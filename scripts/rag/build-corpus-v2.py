#!/usr/bin/env python3
"""Build Terraformers reference corpus v2 from pinned AWS provider sources."""
from __future__ import annotations

import argparse
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "corpus" / "terraformers-reference" / "v2"
DEFAULT_V1 = ROOT / "corpus" / "terraformers-reference" / "v1"
CORPUS_VERSION = "terraformers-reference-v2"
PROVIDER_VERSION = "5.100.0"
PROVIDER_SOURCE_VERSION = f"v{PROVIDER_VERSION}"
PROVIDER_ADDRESS = "registry.terraform.io/hashicorp/aws"
INDEX_NAME = "terraformers-reference-v1"
EMBEDDING_MODEL_ID = "amazon.titan-embed-text-v2:0"
VECTOR_DIMENSION = 1024
VECTOR_FIELD = "embedding"
CONTENT_FIELD = "content"

RESOURCE_SPECS = {
    "aws_vpc": ("website/docs/r/vpc.html.markdown", ["ec2"]),
    "aws_subnet": ("website/docs/r/subnet.html.markdown", ["ec2"]),
    "aws_route_table": ("website/docs/r/route_table.html.markdown", ["ec2"]),
    "aws_route": ("website/docs/r/route.html.markdown", ["ec2"]),
    "aws_internet_gateway": ("website/docs/r/internet_gateway.html.markdown", ["ec2"]),
    "aws_nat_gateway": ("website/docs/r/nat_gateway.html.markdown", ["ec2"]),
    "aws_security_group": ("website/docs/r/security_group.html.markdown", ["ec2"]),
    "aws_vpc_security_group_ingress_rule": (
        "website/docs/r/vpc_security_group_ingress_rule.html.markdown",
        ["ec2"],
    ),
    "aws_eks_cluster": ("website/docs/r/eks_cluster.html.markdown", ["eks"]),
    "aws_eks_node_group": ("website/docs/r/eks_node_group.html.markdown", ["eks"]),
    "aws_lb": ("website/docs/r/lb.html.markdown", ["elbv2"]),
    "aws_lb_listener": ("website/docs/r/lb_listener.html.markdown", ["elbv2"]),
    "aws_lb_target_group": ("website/docs/r/lb_target_group.html.markdown", ["elbv2"]),
    "aws_db_instance": ("website/docs/r/db_instance.html.markdown", ["rds"]),
    "aws_db_subnet_group": ("website/docs/r/db_subnet_group.html.markdown", ["rds"]),
    "aws_s3_bucket": ("website/docs/r/s3_bucket.html.markdown", ["s3"]),
    "aws_s3_bucket_policy": ("website/docs/r/s3_bucket_policy.html.markdown", ["s3"]),
    "aws_sqs_queue": ("website/docs/r/sqs_queue.html.markdown", ["sqs"]),
    "aws_iam_role": ("website/docs/r/iam_role.html.markdown", ["iam"]),
    "aws_iam_policy": ("website/docs/r/iam_policy.html.markdown", ["iam"]),
    "aws_iam_role_policy_attachment": (
        "website/docs/r/iam_role_policy_attachment.html.markdown",
        ["iam"],
    ),
    "aws_ecr_repository": ("website/docs/r/ecr_repository.html.markdown", ["ecr"]),
    "aws_cloudfront_distribution": (
        "website/docs/r/cloudfront_distribution.html.markdown",
        ["cloudfront"],
    ),
    "aws_cloudfront_origin_access_control": (
        "website/docs/r/cloudfront_origin_access_control.html.markdown",
        ["cloudfront"],
    ),
    "aws_cognito_user_pool": (
        "website/docs/r/cognito_user_pool.html.markdown",
        ["cognito-idp"],
    ),
    "aws_cognito_user_pool_client": (
        "website/docs/r/cognito_user_pool_client.html.markdown",
        ["cognito-idp"],
    ),
    "aws_opensearchserverless_collection": (
        "website/docs/r/opensearchserverless_collection.html.markdown",
        ["opensearchserverless"],
    ),
    "aws_opensearchserverless_access_policy": (
        "website/docs/r/opensearchserverless_access_policy.html.markdown",
        ["opensearchserverless"],
    ),
    "aws_cloudwatch_log_group": (
        "website/docs/r/cloudwatch_log_group.html.markdown",
        ["cloudwatch"],
    ),
    "aws_cloudwatch_metric_alarm": (
        "website/docs/r/cloudwatch_metric_alarm.html.markdown",
        ["cloudwatch"],
    ),
}

FRONT_MATTER = re.compile(r"\A---\s*\n.*?\n---\s*\n", re.DOTALL)
FENCE = re.compile(r"```(?:terraform|hcl)\s*\n.*?```", re.DOTALL | re.IGNORECASE)
MARKDOWN_LINK = re.compile(r"\[([^\]]+)\]\([^)]+\)")
ACCOUNT_ID = re.compile(r"(?<!\d)\d{12}(?!\d)")
ACCESS_KEY = re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")
ARN = re.compile(r"\barn:aws[a-z-]*:[^\s\"'`]+")
AWS_ENDPOINT = re.compile(r"https?://[^\s\"'`]*amazonaws\.com[^\s\"'`]*", re.IGNORECASE)
SECRET_ASSIGNMENT = re.compile(
    r'(?im)^(\s*(?:password|secret|token|access_key|secret_key)\s*=\s*)'
    r'(?:"[^"]*"|\'[^\']*\')'
)
PUBLIC_CIDR = re.compile(r'(?:"0\.0\.0\.0/0"|"::/0")')
PUBLIC_ACCESS = re.compile(
    r"(?im)^\s*(?:publicly_accessible|map_public_ip_on_launch)\s*=\s*true\b"
)
RECOVERY_RISK = re.compile(
    r"(?im)^\s*(?:skip_final_snapshot\s*=\s*true|deletion_protection\s*=\s*false)\b"
)
WILDCARD_IAM = re.compile(
    r'(?is)(?:actions?|resources?)\s*=\s*\[[^\]]*"\*"[^\]]*\]|'
    r'"(?:Action|Resource)"\s*:\s*"\*"'
)
PROVIDER_BLOCK = re.compile(r'(?m)^\s*provider\s+"aws"\s*\{')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build corpus v2 from terraform-provider-aws v5.100.0 docs and schema."
    )
    parser.add_argument("--provider-source-dir", type=Path, required=True)
    parser.add_argument("--provider-schema-json", type=Path, required=True)
    parser.add_argument("--provider-source-commit", required=True)
    parser.add_argument("--project-source-commit", required=True)
    parser.add_argument("--v1-corpus-dir", type=Path, default=DEFAULT_V1)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--resource",
        action="append",
        choices=sorted(RESOURCE_SPECS),
        help="Build only the named curated resource. Repeat as needed.",
    )
    return parser.parse_args()


def require_commit(value: str, label: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError(f"{label} must be a full lowercase 40-character commit SHA")
    return value


def normalize_text(value: str) -> str:
    value = MARKDOWN_LINK.sub(r"\1", value)
    value = re.sub(r"[ \t]+\n", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def risk_tags(value: str) -> list[str]:
    tags: list[str] = []
    checks = (
        ("plaintext-secret", SECRET_ASSIGNMENT),
        ("public-cidr", PUBLIC_CIDR),
        ("public-access", PUBLIC_ACCESS),
        ("recovery-risk", RECOVERY_RISK),
        ("wildcard-iam", WILDCARD_IAM),
        ("provider-block", PROVIDER_BLOCK),
    )
    for tag, pattern in checks:
        if pattern.search(value):
            tags.append(tag)
    return tags


def sanitize(value: str) -> str:
    value = SECRET_ASSIGNMENT.sub(r'\1"<sensitive-value>"', value)
    value = ACCESS_KEY.sub("<aws-access-key>", value)
    value = ARN.sub("<aws-arn>", value)
    value = AWS_ENDPOINT.sub("<aws-endpoint>", value)
    value = ACCOUNT_ID.sub("<aws-account-id>", value)
    return normalize_text(value)


def slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return result[:60] or "example"


def section(text: str, heading: str) -> str:
    pattern = re.compile(rf"(?ms)^## {re.escape(heading)}\s*$\n(.*?)(?=^## |\Z)")
    match = pattern.search(text)
    return match.group(1).strip() if match else ""


def resource_overview(text: str) -> str:
    body = FRONT_MATTER.sub("", text)
    match = re.search(r"(?ms)^# Resource:[^\n]*\n(.*?)(?=^## |\Z)", body)
    if not match:
        return ""
    return normalize_text(match.group(1))


def example_chunks(text: str) -> list[tuple[str, str]]:
    example_section = section(FRONT_MATTER.sub("", text), "Example Usage")
    if not example_section:
        return []
    chunks: list[tuple[str, str]] = []
    cursor = 0
    for number, match in enumerate(FENCE.finditer(example_section), 1):
        prose = example_section[cursor:match.start()].strip()
        prose_lines = [line.strip() for line in prose.splitlines() if line.strip()]
        label = prose_lines[-1].rstrip(":") if prose_lines else f"Example {number}"
        immediate = "\n".join(prose_lines[-3:])
        content = f"{immediate}\n\n{match.group(0)}".strip()
        chunks.append((label, content))
        cursor = match.end()
    return chunks


def schema_provider(schema_path: Path) -> dict[str, object]:
    payload = json.loads(schema_path.read_text(encoding="utf-8"))
    providers = payload.get("provider_schemas")
    if not isinstance(providers, dict) or PROVIDER_ADDRESS not in providers:
        raise ValueError(f"schema JSON does not contain {PROVIDER_ADDRESS}")
    provider = providers[PROVIDER_ADDRESS]
    if not isinstance(provider, dict):
        raise ValueError("AWS provider schema entry must be an object")
    return provider


def format_type(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def summarize_block(block: dict[str, object], indent: int = 0) -> list[str]:
    prefix = "  " * indent
    lines: list[str] = []
    attributes = block.get("attributes", {})
    if isinstance(attributes, dict):
        for name in sorted(attributes):
            attribute = attributes[name]
            if not isinstance(attribute, dict):
                continue
            flags = [
                key
                for key in ("required", "optional", "computed", "sensitive")
                if attribute.get(key) is True
            ]
            lines.append(
                f"{prefix}- `{name}`: {', '.join(flags) or 'unspecified'}; "
                f"type={format_type(attribute.get('type'))}"
            )
    block_types = block.get("block_types", {})
    if isinstance(block_types, dict):
        for name in sorted(block_types):
            nested = block_types[name]
            if not isinstance(nested, dict):
                continue
            limits = []
            for key in ("min_items", "max_items"):
                if key in nested:
                    limits.append(f"{key}={nested[key]}")
            suffix = f"; {', '.join(limits)}" if limits else ""
            lines.append(
                f"{prefix}- nested block `{name}`: "
                f"nesting_mode={nested.get('nesting_mode', 'unknown')}{suffix}"
            )
            child = nested.get("block")
            if isinstance(child, dict):
                lines.extend(summarize_block(child, indent + 1))
    return lines


def make_provider_document(
    *,
    document_id: str,
    title: str,
    document_type: str,
    authority: str,
    priority: int,
    section_type: str,
    content: str,
    services: list[str],
    resource_type: str,
    source_path: str,
    source_commit: str,
    architecture_pattern: str,
) -> dict[str, object]:
    tags = risk_tags(content)
    safe_content = sanitize(content)
    return {
        "documentId": document_id,
        "title": title,
        "documentType": document_type,
        "authority": authority,
        "priority": priority,
        "sectionType": section_type,
        "riskTags": tags,
        "content": safe_content,
        "services": services,
        "resourceTypes": [resource_type],
        "architecturePattern": architecture_pattern,
        "securityConsiderations": tags,
        "sourceVersion": PROVIDER_SOURCE_VERSION,
        "providerVersion": PROVIDER_VERSION,
        "sourcePath": source_path,
        "sourceCommit": source_commit,
        "corpusVersion": CORPUS_VERSION,
    }


def provider_documents(
    provider_source_dir: Path,
    provider_schema: dict[str, object],
    provider_commit: str,
    resource_types: Iterable[str],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    resource_schemas = provider_schema.get("resource_schemas")
    if not isinstance(resource_schemas, dict):
        raise ValueError("AWS provider schema does not contain resource_schemas")

    documents: list[dict[str, object]] = []
    sources: list[dict[str, object]] = []
    for resource_type in resource_types:
        source_path, services = RESOURCE_SPECS[resource_type]
        doc_path = provider_source_dir / source_path
        if not doc_path.is_file():
            raise FileNotFoundError(f"missing provider document: {source_path}")
        resource_schema = resource_schemas.get(resource_type)
        if not isinstance(resource_schema, dict) or not isinstance(resource_schema.get("block"), dict):
            raise ValueError(f"provider schema does not contain {resource_type}")

        raw = doc_path.read_text(encoding="utf-8")
        overview = resource_overview(raw)
        if overview:
            documents.append(
                make_provider_document(
                    document_id=f"tfaws-{PROVIDER_VERSION}-{resource_type}-overview",
                    title=f"{resource_type} - overview",
                    document_type="AWS_PROVIDER_DOC",
                    authority="PROVIDER_DOCUMENTATION",
                    priority=60,
                    section_type="overview",
                    content=overview,
                    services=services,
                    resource_type=resource_type,
                    source_path=source_path,
                    source_commit=provider_commit,
                    architecture_pattern="provider-resource-overview",
                )
            )
            sources.append(
                {
                    "sourceType": "AWS_PROVIDER_DOC",
                    "sourceVersion": PROVIDER_SOURCE_VERSION,
                    "sourcePath": source_path,
                    "sourceCommit": provider_commit,
                }
            )

        examples = example_chunks(raw)
        if examples:
            sources.append(
                {
                    "sourceType": "AWS_PROVIDER_EXAMPLE",
                    "sourceVersion": PROVIDER_SOURCE_VERSION,
                    "sourcePath": source_path,
                    "sourceCommit": provider_commit,
                }
            )
        for number, (label, content) in enumerate(examples, 1):
            documents.append(
                make_provider_document(
                    document_id=(
                        f"tfaws-{PROVIDER_VERSION}-{resource_type}-"
                        f"example-{number}-{slug(label)}"
                    ),
                    title=f"{resource_type} - {label}",
                    document_type="AWS_PROVIDER_EXAMPLE",
                    authority="PROVIDER_DOCUMENTATION",
                    priority=60,
                    section_type="example",
                    content=content,
                    services=services,
                    resource_type=resource_type,
                    source_path=source_path,
                    source_commit=provider_commit,
                    architecture_pattern="provider-resource-example",
                )
            )

        schema_path = f"terraform providers schema -json#resource_schemas.{resource_type}"
        schema_lines = summarize_block(resource_schema["block"])
        if not schema_lines:
            raise ValueError(f"provider schema summary is empty for {resource_type}")
        documents.append(
            make_provider_document(
                document_id=f"tfaws-{PROVIDER_VERSION}-{resource_type}-schema",
                title=f"{resource_type} - provider schema",
                document_type="AWS_PROVIDER_SCHEMA",
                authority="PROVIDER_SCHEMA",
                priority=70,
                section_type="schema",
                content=(
                    f"Provider {PROVIDER_VERSION} schema for `{resource_type}`.\n\n"
                    + "\n".join(schema_lines)
                ),
                services=services,
                resource_type=resource_type,
                source_path=schema_path,
                source_commit=provider_commit,
                architecture_pattern="provider-schema-contract",
            )
        )
        sources.append(
            {
                "sourceType": "AWS_PROVIDER_SCHEMA",
                "sourceVersion": PROVIDER_SOURCE_VERSION,
                "sourcePath": schema_path,
                "sourceCommit": provider_commit,
            }
        )
    return documents, sources


def project_pattern_documents(
    v1_corpus_dir: Path, project_commit: str
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    documents: list[dict[str, object]] = []
    sources: list[dict[str, object]] = []
    for line in (v1_corpus_dir / "documents.jsonl").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        original = json.loads(line)
        if original.get("documentType") != "TERRAFORMERS_PATTERN":
            continue
        risk = list(original.get("securityConsiderations", []))
        document = {
            **original,
            "documentId": str(original["documentId"]).replace("tfref-v1-", "tfref-v2-"),
            "authority": "PROJECT_DECISION",
            "priority": 100,
            "sectionType": "project-pattern",
            "riskTags": risk,
            "sourceVersion": CORPUS_VERSION,
            "sourceCommit": project_commit,
            "corpusVersion": CORPUS_VERSION,
        }
        documents.append(document)
        sources.append(
            {
                "sourceType": "TERRAFORMERS_PATTERN",
                "sourceVersion": CORPUS_VERSION,
                "sourcePath": document["sourcePath"],
                "sourceCommit": project_commit,
            }
        )
    if not documents:
        raise ValueError("v1 corpus contains no Terraformers project patterns")
    return documents, sources


def dedupe_sources(sources: Iterable[dict[str, object]]) -> list[dict[str, object]]:
    unique = {
        (
            str(source["sourceType"]),
            str(source["sourceVersion"]),
            str(source["sourcePath"]),
            str(source["sourceCommit"]),
        ): source
        for source in sources
    }
    return [unique[key] for key in sorted(unique)]


def index_schema() -> dict[str, object]:
    keyword_fields = [
        "documentId",
        "documentType",
        "authority",
        "sectionType",
        "riskTags",
        "sourceVersion",
        "sourcePath",
        "sourceCommit",
        "corpusVersion",
        "services",
        "resourceTypes",
        "architecturePattern",
        "securityConsiderations",
        "providerVersion",
    ]
    properties: dict[str, object] = {
        VECTOR_FIELD: {
            "type": "knn_vector",
            "dimension": VECTOR_DIMENSION,
            "method": {
                "name": "hnsw",
                "engine": "faiss",
                "space_type": "cosinesimil",
                "parameters": {},
            },
        },
        "title": {"type": "text"},
        CONTENT_FIELD: {"type": "text"},
        "priority": {"type": "integer"},
    }
    properties.update({field: {"type": "keyword"} for field in keyword_fields})
    return {
        "settings": {"index": {"knn": True}},
        "mappings": {"properties": properties},
    }


def write_corpus(
    output_dir: Path,
    documents: list[dict[str, object]],
    sources: list[dict[str, object]],
) -> None:
    documents = sorted(documents, key=lambda item: str(item["documentId"]))
    ids = [str(document["documentId"]) for document in documents]
    if len(ids) != len(set(ids)):
        raise ValueError("generated corpus contains duplicate document IDs")

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="terraformers-reference-v2-", dir=output_dir.parent))
    try:
        manifest = {
            "corpusVersion": CORPUS_VERSION,
            "awsProviderVersion": PROVIDER_VERSION,
            "embeddingModelId": EMBEDDING_MODEL_ID,
            "vectorDimension": VECTOR_DIMENSION,
            "indexName": INDEX_NAME,
            "vectorField": VECTOR_FIELD,
            "contentField": CONTENT_FIELD,
            "documentCount": len(documents),
            "chunkCount": len(documents),
            "checksumAlgorithm": "SHA-256",
        }
        (staging / "corpus-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "source-manifest.json").write_text(
            json.dumps({"sources": dedupe_sources(sources)}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "index-schema.json").write_text(
            json.dumps(index_schema(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "documents.jsonl").write_text(
            "".join(
                json.dumps(document, sort_keys=True, ensure_ascii=False) + "\n"
                for document in documents
            ),
            encoding="utf-8",
        )
        if output_dir.exists():
            shutil.rmtree(output_dir)
        staging.replace(output_dir)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def main() -> None:
    args = parse_args()
    provider_commit = require_commit(args.provider_source_commit, "provider-source-commit")
    project_commit = require_commit(args.project_source_commit, "project-source-commit")
    resources = args.resource or list(RESOURCE_SPECS)
    provider_schema = schema_provider(args.provider_schema_json)
    provider_docs, provider_sources = provider_documents(
        args.provider_source_dir.resolve(),
        provider_schema,
        provider_commit,
        resources,
    )
    project_docs, project_sources = project_pattern_documents(
        args.v1_corpus_dir.resolve(),
        project_commit,
    )
    documents = provider_docs + project_docs
    sources = provider_sources + project_sources
    write_corpus(args.output_dir.resolve(), documents, sources)
    print(
        f"Built {CORPUS_VERSION}: resources={len(resources)} "
        f"documents={len(documents)} output={args.output_dir.resolve()}"
    )


if __name__ == "__main__":
    main()
