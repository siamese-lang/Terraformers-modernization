#!/usr/bin/env python3
"""Offline validation for the versioned, project-owned Terraform reference corpus."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "corpus" / "terraformers-reference" / "v1"
REQUIRED_MANIFEST = {"corpusVersion", "awsProviderVersion", "embeddingModelId", "vectorDimension", "indexName", "vectorField", "contentField", "documentCount", "chunkCount", "checksumAlgorithm"}
REQUIRED_DOCUMENT = {"documentId", "title", "documentType", "content", "services", "resourceTypes", "architecturePattern", "securityConsiderations", "sourceVersion", "providerVersion", "sourcePath", "corpusVersion"}
TYPES = {"AWS_PROVIDER_DOC", "AWS_PROVIDER_SCHEMA", "MODULE_EXAMPLE", "TERRAFORMERS_PATTERN"}
FIXED = {"corpusVersion": "terraformers-reference-v1", "awsProviderVersion": "5.100.0", "embeddingModelId": "amazon.titan-embed-text-v2:0", "vectorDimension": 1024, "indexName": "terraformers-reference-v1", "vectorField": "embedding", "contentField": "content"}
FORBIDDEN = [
    (re.compile(r"(?<!\d)\d{12}(?!\d)"), "account-like identifier"),
    (re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"), "access key"),
    (re.compile(r"\barn:aws[a-z-]*:"), "live ARN"),
    (re.compile(r"https?://[^\s\"']+"), "live endpoint"),
    (re.compile(r"(?i)\.tfstate\b"), "tfstate reference"),
    (re.compile(r'(?i)(?:password|secret|credential)(?:=|:|_)'), "secret-like payload"),
]
def fail(message):
    print(f"RAG corpus contract failure: {message}", file=sys.stderr)
    sys.exit(1)
def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot parse {path.relative_to(ROOT)}: {exc}")
def main():
    manifest = load_json(CORPUS / "corpus-manifest.json")
    if set(manifest) < REQUIRED_MANIFEST: fail("corpus manifest is missing required fields")
    for key, value in FIXED.items():
        if manifest.get(key) != value: fail(f"manifest {key} must be {value!r}")
    if manifest["checksumAlgorithm"] != "SHA-256": fail("checksumAlgorithm must be SHA-256")
    sources = load_json(CORPUS / "source-manifest.json").get("sources")
    if not isinstance(sources, list) or not sources: fail("source manifest must contain sources")
    for source in sources:
        if source.get("sourceType") not in TYPES or not source.get("sourceVersion") or not source.get("sourcePath"):
            fail("each source manifest entry needs a supported type, version, and path")
        if source["sourceType"].startswith("AWS_PROVIDER") and source["sourceVersion"] != "v5.100.0": fail("AWS provider sources must use tag v5.100.0")
    documents = []
    try:
        for line_no, line in enumerate((CORPUS / "documents.jsonl").read_text(encoding="utf-8").splitlines(), 1):
            if line.strip(): documents.append(json.loads(line))
    except json.JSONDecodeError as exc: fail(f"documents.jsonl line {line_no}: {exc}")
    ids = set()
    for doc in documents:
        if set(doc) < REQUIRED_DOCUMENT: fail("document is missing required fields")
        if doc["documentType"] not in TYPES: fail(f"unsupported document type for {doc.get('documentId')}")
        if not isinstance(doc["content"], str) or not doc["content"].strip(): fail(f"blank content for {doc['documentId']}")
        if not doc["sourceVersion"] or not doc["providerVersion"] or not doc["corpusVersion"]: fail(f"source/corpus version missing for {doc['documentId']}")
        if doc["corpusVersion"] != FIXED["corpusVersion"]: fail(f"wrong corpus version for {doc['documentId']}")
        if doc["documentId"] in ids: fail(f"duplicate document ID {doc['documentId']}")
        ids.add(doc["documentId"])
    if manifest["documentCount"] != len(documents) or manifest["chunkCount"] != len(documents): fail("manifest documentCount and chunkCount must equal JSONL chunk count")
    schema = load_json(CORPUS / "index-schema.json")
    props = schema.get("mappings", {}).get("properties", {})
    vector = props.get(manifest["vectorField"], {})
    if schema.get("settings", {}).get("index", {}).get("knn") is not True or vector.get("type") != "knn_vector" or vector.get("dimension") != manifest["vectorDimension"]: fail("index vector settings do not match manifest")
    if vector.get("method", {}).get("name") != "hnsw" or vector.get("method", {}).get("engine") != "faiss" or vector.get("method", {}).get("space_type") != "cosinesimil": fail("index must use Faiss HNSW cosine similarity")
    if props.get(manifest["contentField"], {}).get("type") != "text" or props.get("title", {}).get("type") != "text": fail("title and content must be text fields")
    serialized = "\n".join(json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=True) for doc in documents)
    for regex, label in FORBIDDEN:
        if regex.search(serialized): fail(f"{label} is not permitted in corpus documents")
    digest = hashlib.sha256(serialized.encode("utf-8")).hexdigest()
    print(f"RAG corpus contract passed: corpusVersion={manifest['corpusVersion']} documents={len(documents)} chunks={len(documents)} sha256={digest}")
if __name__ == "__main__": main()
