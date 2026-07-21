#!/usr/bin/env python3
"""Remove provider examples that do not serve Terraformers generation quality."""
from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path

CORPUS_VERSION = "terraformers-reference-v2"
EXCLUDED_TITLE_PATTERNS = {
    "aws_cognito_user_pool_client": (
        r"no SRP authentication",
        r"pinpoint analytics",
    ),
    "aws_db_instance": (
        r"RDS Custom for Oracle",
        r"RDS Custom for SQL Server",
        r"RDS Db2",
    ),
    "aws_eks_cluster": (
        r"EKS Auto Mode",
        r"EKS Hybrid Nodes",
        r"AWS Outpost",
    ),
    "aws_iam_role": (
        r"out-of-band",
        r"appears to be empty",
        r"empty `managed_policy_arns`",
    ),
    "aws_lb": (r"Specifying Elastic IPs",),
    "aws_lb_listener": (
        r"To a NLB",
        r"Authenticate-OIDC",
        r"Gateway Load Balancer",
        r"Mutual TLS",
    ),
    "aws_lb_target_group": (
        r"Lambda Target Group",
        r"ALB Target Group",
        r"unhealthy connection termination",
    ),
    "aws_nat_gateway": (r"Secondary Private IP Addresses",),
    "aws_route_table": (
        r"remove all managed routes",
        r"adopt an existing",
        r"update the target",
    ),
    "aws_security_group": (
        r"replace_triggered_by",
        r"takes a long time",
        r"local provisioners",
    ),
}
SERVICE_WILDCARD = re.compile(r'"[a-z0-9-]+:\*"', re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Curate generated Terraformers corpus v2.")
    parser.add_argument("--corpus-dir", type=Path, required=True)
    return parser.parse_args()


def excluded(document: dict[str, object]) -> bool:
    if document.get("documentType") != "AWS_PROVIDER_EXAMPLE":
        return False
    resource_types = document.get("resourceTypes")
    if not isinstance(resource_types, list) or len(resource_types) != 1:
        return False
    patterns = EXCLUDED_TITLE_PATTERNS.get(str(resource_types[0]), ())
    title = str(document.get("title", ""))
    return any(re.search(pattern, title, re.IGNORECASE) for pattern in patterns)


def add_risk_metadata(document: dict[str, object]) -> None:
    if not SERVICE_WILDCARD.search(str(document.get("content", ""))):
        return
    for key in ("riskTags", "securityConsiderations"):
        values = document.get(key)
        if not isinstance(values, list):
            values = []
        if "wildcard-iam" not in values:
            values.append("wildcard-iam")
        document[key] = sorted(str(value) for value in values)


def source_key(value: dict[str, object]) -> tuple[str, str, str, str]:
    return (
        str(value.get("sourceType") or value.get("documentType")),
        str(value.get("sourceVersion")),
        str(value.get("sourcePath")),
        str(value.get("sourceCommit")),
    )


def curate(corpus_dir: Path) -> dict[str, int]:
    manifest_path = corpus_dir / "corpus-manifest.json"
    documents_path = corpus_dir / "documents.jsonl"
    sources_path = corpus_dir / "source-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("corpusVersion") != CORPUS_VERSION:
        raise ValueError(f"curation requires {CORPUS_VERSION}")

    documents = [
        json.loads(line)
        for line in documents_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    retained = []
    for document in documents:
        if excluded(document):
            continue
        add_risk_metadata(document)
        retained.append(document)

    source_manifest = json.loads(sources_path.read_text(encoding="utf-8"))
    referenced = {source_key(document) for document in retained}
    sources = [
        source
        for source in source_manifest.get("sources", [])
        if source_key(source) in referenced
    ]

    manifest["documentCount"] = len(retained)
    manifest["chunkCount"] = len(retained)
    staging = Path(tempfile.mkdtemp(prefix="curated-corpus-v2-", dir=corpus_dir.parent))
    try:
        (staging / "corpus-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        (staging / "documents.jsonl").write_text(
            "".join(json.dumps(document, sort_keys=True, ensure_ascii=False) + "\n" for document in retained),
            encoding="utf-8",
        )
        (staging / "source-manifest.json").write_text(
            json.dumps({"sources": sources}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "index-schema.json").write_text(
            (corpus_dir / "index-schema.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        for path in corpus_dir.iterdir():
            path.unlink()
        for path in staging.iterdir():
            path.replace(corpus_dir / path.name)
        staging.rmdir()
    except Exception:
        for path in staging.glob("*"):
            path.unlink(missing_ok=True)
        staging.rmdir()
        raise

    return {"before": len(documents), "after": len(retained), "removed": len(documents) - len(retained)}


def main() -> None:
    summary = curate(parse_args().corpus_dir.resolve())
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
