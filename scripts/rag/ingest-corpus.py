#!/usr/bin/env python3
"""CodeBuild-only utility for guarded private RAG corpus ingestion."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise RuntimeError(message)


def log(**values: object) -> None:
    print(json.dumps(values, sort_keys=True))


def corpus_dir(package: Path) -> Path:
    if package.is_dir():
        return package
    target = Path(tempfile.mkdtemp(prefix="rag-corpus-"))
    with zipfile.ZipFile(package) as archive:
        for item in archive.infolist():
            if not str((target / item.filename).resolve()).startswith(str(target.resolve())):
                fail("unsafe package path")
        archive.extractall(target)
    manifests = list(target.rglob("corpus-manifest.json"))
    if len(manifests) != 1:
        fail("package must contain exactly one corpus-manifest.json")
    return manifests[0].parent


def validate_contract(corpus: Path) -> dict[str, object]:
    summary = Path(tempfile.mkstemp(prefix="rag-contract-", suffix=".json")[1])
    try:
        subprocess.run(
            [sys.executable, str(ROOT / "scripts/checks/rag-corpus-contract-verification.py"), "--corpus-dir", str(corpus), "--summary-json", str(summary)],
            check=True,
        )
        return json.loads(summary.read_text(encoding="utf-8"))
    finally:
        summary.unlink(missing_ok=True)


def ensure_version_checksum(receipt: dict[str, object] | None, corpus_version: str, checksum: str) -> None:
    if receipt and receipt.get("corpus_version") == corpus_version and receipt.get("checksum") != checksum:
        fail("corpus version checksum changed; bump corpus version")


def wait_for_document_count(client: object, index_name: str, expected: int, timeout_seconds: int = 180) -> int:
    deadline = time.monotonic() + timeout_seconds
    while True:
        count = int(client.count(index=index_name)["count"])
        if count == expected:
            return count
        if count > expected:
            fail("target index document count exceeds expected document count")
        if time.monotonic() >= deadline:
            fail("target index document count did not converge before timeout")
        time.sleep(10)


def wait_for_knn_hits(client: object, index_name: str, vector_field: str, vector: list[float], timeout_seconds: int = 120) -> list[dict[str, object]]:
    deadline = time.monotonic() + timeout_seconds
    while True:
        hits = client.search(index=index_name, body={"size": 3, "query": {"knn": {vector_field: {"vector": vector, "k": 3}}}})["hits"]["hits"]
        if hits:
            return hits
        if time.monotonic() >= deadline:
            fail("representative k-NN query returned no hits before timeout")
        time.sleep(10)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, default=ROOT / "corpus/terraformers-reference/v1")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--collection-endpoint", default=os.getenv("COLLECTION_ENDPOINT", ""))
    parser.add_argument("--index-name", default=os.getenv("INDEX_NAME", ""))
    parser.add_argument("--vector-field", default=os.getenv("VECTOR_FIELD", ""))
    parser.add_argument("--content-field", default=os.getenv("CONTENT_FIELD", ""))
    parser.add_argument("--embedding-model-id", default=os.getenv("EMBEDDING_MODEL_ID", ""))
    parser.add_argument("--vector-dimension", type=int, default=int(os.getenv("VECTOR_DIMENSION", "1024")))
    parser.add_argument("--expected-checksum", default=os.getenv("EXPECTED_CHECKSUM", ""))
    parser.add_argument("--expected-document-count", type=int, default=int(os.getenv("EXPECTED_DOCUMENT_COUNT", "0")))
    parser.add_argument("--receipt-bucket", default=os.getenv("CORPUS_BUCKET", ""))
    parser.add_argument("--receipt-key", default=os.getenv("RECEIPT_KEY", ""))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    started = time.monotonic()
    corpus = corpus_dir(args.package)
    contract = validate_contract(corpus)
    manifest = json.loads((corpus / "corpus-manifest.json").read_text(encoding="utf-8"))
    checksum = str(contract["sha256"])
    document_count = int(contract["documentCount"])
    if args.expected_checksum and checksum != args.expected_checksum:
        fail("package checksum does not match expected full corpus contract checksum")
    if args.expected_document_count and document_count != args.expected_document_count:
        fail("package document count does not match expected document count")
    summary = {"corpus_version": manifest["corpusVersion"], "checksum": checksum, "document_count": document_count, "index_name": args.index_name or manifest["indexName"], "embedding_model_id": args.embedding_model_id or manifest["embeddingModelId"], "vector_dimension": args.vector_dimension, "outcome": "validated", "elapsed_seconds": round(time.monotonic() - started, 3)}
    if args.validate_only:
        log(**summary)
        return
    if not all([args.collection_endpoint, args.index_name, args.vector_field, args.content_field, args.embedding_model_id, args.receipt_bucket, args.receipt_key]):
        fail("deployment inputs are required")
    import boto3
    from opensearchpy import OpenSearch, RequestsHttpConnection
    from requests_aws4auth import AWS4Auth

    s3 = boto3.client("s3")
    receipt = None
    try:
        receipt = json.loads(s3.get_object(Bucket=args.receipt_bucket, Key=args.receipt_key)["Body"].read())
    except s3.exceptions.NoSuchKey:
        pass
    ensure_version_checksum(receipt, manifest["corpusVersion"], checksum)
    if receipt and receipt.get("corpus_version") != manifest["corpusVersion"]:
        fail("receipt corpus version does not match target index version")
    host = args.collection_endpoint.removeprefix("https://").split("/")[0]
    region = os.environ.get("AWS_REGION") or boto3.session.Session().region_name
    credentials = boto3.Session().get_credentials()
    auth = AWS4Auth(credentials.access_key, credentials.secret_key, region, "aoss", session_token=credentials.token)
    client = OpenSearch(hosts=[{"host": host, "port": 443}], http_auth=auth, use_ssl=True, verify_certs=True, connection_class=RequestsHttpConnection)
    schema = json.loads((corpus / "index-schema.json").read_text(encoding="utf-8"))
    if not client.indices.exists(args.index_name):
        if receipt:
            fail("receipt exists but target index is missing")
        client.indices.create(args.index_name, body=schema)
    mapping = client.indices.get_mapping(index=args.index_name)[args.index_name]["mappings"]["properties"]
    vector = mapping.get(args.vector_field, {})
    if vector.get("type") != "knn_vector" or vector.get("dimension") != args.vector_dimension or mapping.get(args.content_field, {}).get("type") != "text":
        fail("existing index field contract differs")
    documents = [json.loads(line) for line in (corpus / "documents.jsonl").read_text(encoding="utf-8").splitlines() if line]
    bedrock = boto3.client("bedrock-runtime")
    if not receipt:
        for document in documents:
            existing = client.search(
                index=args.index_name,
                body={"size": 1, "_source": False, "query": {"term": {"documentId": document["documentId"]}}},
            )["hits"]["hits"]
            if existing:
                continue
            embedding = json.loads(bedrock.invoke_model(modelId=args.embedding_model_id, body=json.dumps({"inputText": document[args.content_field]}))["body"].read())["embedding"]
            client.index(index=args.index_name, body={**document, args.vector_field: embedding})
    count = wait_for_document_count(client, args.index_name, document_count)
    query_embedding = json.loads(bedrock.invoke_model(modelId=args.embedding_model_id, body=json.dumps({"inputText": documents[0][args.content_field]}))["body"].read())["embedding"]
    hits = wait_for_knn_hits(client, args.index_name, args.vector_field, query_embedding)
    receipt = {"corpus_version": manifest["corpusVersion"], "checksum": checksum, "document_count": count, "index_name": args.index_name, "embedding_model_id": args.embedding_model_id, "vector_dimension": args.vector_dimension, "hit_count": len(hits), "document_ids": [str(hit.get("_source", {}).get("documentId", hit.get("_id", ""))) for hit in hits], "outcome": "already-ingested" if receipt else "ingested", "elapsed_seconds": round(time.monotonic() - started, 3)}
    s3.put_object(Bucket=args.receipt_bucket, Key=args.receipt_key, Body=json.dumps(receipt, sort_keys=True).encode(), ContentType="application/json")
    log(**receipt)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log(outcome="failed", error_class=exc.__class__.__name__)
        print(str(exc), file=sys.stderr)
        sys.exit(1)
