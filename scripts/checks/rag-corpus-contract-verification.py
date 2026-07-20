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
PROVIDER_TYPES = {"AWS_PROVIDER_DOC", "AWS_PROVIDER_SCHEMA"}
FIXED = {"corpusVersion": "terraformers-reference-v1", "awsProviderVersion": "5.100.0", "embeddingModelId": "amazon.titan-embed-text-v2:0", "vectorDimension": 1024, "indexName": "terraformers-reference-v1", "vectorField": "embedding", "contentField": "content"}
FORBIDDEN = [(re.compile(r"(?<!\d)\d{12}(?!\d)"), "account-like identifier"), (re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"), "access key"), (re.compile(r"\barn:aws[a-z-]*:"), "live ARN"), (re.compile(r"https?://[^\s\"']+"), "live endpoint"), (re.compile(r"(?i)\.tfstate\b"), "tfstate reference"), (re.compile(r'(?i)(?:password|secret|credential)(?:=|:|_)'), "secret-like payload")]

def fail(message):
    print(f"RAG corpus contract failure: {message}", file=sys.stderr)
    sys.exit(1)

def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot parse {path.relative_to(ROOT)}: {exc}")

def require_nonblank_string(value, label):
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a nonblank string")

def require_nonblank_list(value, label, nonempty=True):
    if not isinstance(value, list) or (nonempty and not value) or any(not isinstance(item, str) or not item.strip() for item in value):
        fail(f"{label} must be {'a non-empty ' if nonempty else 'a '}list of nonblank strings")

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)

def reject_forbidden(value, label):
    text = canonical(value)
    for regex, kind in FORBIDDEN:
        if regex.search(text):
            fail(f"{kind} is not permitted in {label}")

def main():
    manifest = load_json(CORPUS / "corpus-manifest.json")
    missing = sorted(REQUIRED_MANIFEST - set(manifest))
    if missing:
        fail(f"corpus manifest is missing required fields: {', '.join(missing)}")
    for key, value in FIXED.items():
        if manifest.get(key) != value:
            fail(f"manifest {key} must be {value!r}")
    if manifest["checksumAlgorithm"] != "SHA-256":
        fail("checksumAlgorithm must be SHA-256")

    source_manifest = load_json(CORPUS / "source-manifest.json")
    sources = source_manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        fail("source manifest must contain sources")
    source_tuples = set()
    for source in sources:
        if not isinstance(source, dict):
            fail("source manifest entries must be objects")
        source_type, version, path = source.get("sourceType"), source.get("sourceVersion"), source.get("sourcePath")
        if source_type not in TYPES:
            fail("source manifest contains an unsupported source type")
        require_nonblank_string(version, "source manifest sourceVersion")
        require_nonblank_string(path, "source manifest sourcePath")
        item = (source_type, version, path)
        if item in source_tuples:
            fail(f"duplicate source tuple: {item}")
        source_tuples.add(item)
        if source_type in PROVIDER_TYPES and version != "v5.100.0":
            fail("AWS provider sources must use tag v5.100.0")
        reject_forbidden(source, "source manifest")

    documents = []
    try:
        for line_no, line in enumerate((CORPUS / "documents.jsonl").read_text(encoding="utf-8").splitlines(), 1):
            if line.strip():
                documents.append(json.loads(line))
    except json.JSONDecodeError as exc:
        fail(f"documents.jsonl line {line_no}: {exc}")

    ids = set()
    for doc in documents:
        if not isinstance(doc, dict):
            fail("documents must be JSON objects")
        missing = sorted(REQUIRED_DOCUMENT - set(doc))
        if missing:
            fail(f"document is missing required fields: {', '.join(missing)}")
        require_nonblank_string(doc["documentId"], "documentId")
        require_nonblank_string(doc["title"], "title")
        require_nonblank_string(doc["content"], "content")
        require_nonblank_string(doc["architecturePattern"], "architecturePattern")
        require_nonblank_string(doc["sourcePath"], "sourcePath")
        require_nonblank_list(doc["services"], "services")
        require_nonblank_list(doc["resourceTypes"], "resourceTypes")
        require_nonblank_list(doc["securityConsiderations"], "securityConsiderations", nonempty=False)
        if doc["documentType"] not in TYPES:
            fail(f"unsupported document type for {doc['documentId']}")
        require_nonblank_string(doc["sourceVersion"], "sourceVersion")
        require_nonblank_string(doc["providerVersion"], "providerVersion")
        require_nonblank_string(doc["corpusVersion"], "corpusVersion")
        if doc["documentType"] in PROVIDER_TYPES:
            if doc["providerVersion"] != "5.100.0" or doc["sourceVersion"] != "v5.100.0":
                fail(f"provider document {doc['documentId']} must use providerVersion 5.100.0 and sourceVersion v5.100.0")
        elif doc["sourceVersion"] != "terraformers-reference-v1":
            fail(f"project-owned document {doc['documentId']} must use sourceVersion terraformers-reference-v1")
        if doc["corpusVersion"] != FIXED["corpusVersion"]:
            fail(f"wrong corpus version for {doc['documentId']}")
        if doc["documentId"] in ids:
            fail(f"duplicate document ID {doc['documentId']}")
        if (doc["documentType"], doc["sourceVersion"], doc["sourcePath"]) not in source_tuples:
            fail(f"document {doc['documentId']} does not have a matching source manifest tuple")
        ids.add(doc["documentId"])
        reject_forbidden(doc, "corpus documents")

    if manifest["documentCount"] != len(documents) or manifest["chunkCount"] != len(documents):
        fail("manifest documentCount and chunkCount must equal JSONL chunk count")
    schema = load_json(CORPUS / "index-schema.json")
    props = schema.get("mappings", {}).get("properties", {})
    vector = props.get(manifest["vectorField"], {})
    if schema.get("settings", {}).get("index", {}).get("knn") is not True or vector.get("type") != "knn_vector" or vector.get("dimension") != manifest["vectorDimension"]:
        fail("index vector settings do not match manifest")
    if vector.get("method", {}).get("name") != "hnsw" or vector.get("method", {}).get("engine") != "faiss" or vector.get("method", {}).get("space_type") != "cosinesimil":
        fail("index must use Faiss HNSW cosine similarity")
    if props.get(manifest["contentField"], {}).get("type") != "text" or props.get("title", {}).get("type") != "text":
        fail("title and content must be text fields")
    checksum_input = {"corpusManifest": manifest, "sourceManifest": source_manifest, "indexSchema": schema, "documents": documents}
    digest = hashlib.sha256(canonical(checksum_input).encode("utf-8")).hexdigest()
    print(f"RAG corpus contract passed: corpusVersion={manifest['corpusVersion']} documents={len(documents)} chunks={len(documents)} sources={len(sources)} sha256={digest}")

if __name__ == "__main__":
    main()
