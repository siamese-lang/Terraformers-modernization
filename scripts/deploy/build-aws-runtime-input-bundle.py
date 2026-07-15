#!/usr/bin/env python3
"""Build deployment input files from Terraform output JSON.

The script does not contact AWS and does not apply Kubernetes manifests. It converts
Terraform outputs into:

- backend-runtime-secret.env for render-backend-runtime-secret.sh
- aws-runtime-manifest.env for render-aws-runtime-manifest.sh
- apply-order.txt with the next manual commands

It can read either existing `terraform output -json` files or run `terraform output
-json` in the known Terraform environment directories.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUNTIME_DIR = REPO_ROOT / "infra/terraform/envs/backend-runtime-dependencies"
DEFAULT_STATEFUL_DIR = REPO_ROOT / "infra/terraform/envs/backend-stateful-dependencies"
DEFAULT_EKS_DIR = REPO_ROOT / "infra/terraform/envs/eks-runtime"

DEFAULT_BEDROCK_MODEL_ID = "adapter-disabled-bedrock-model"
DEFAULT_BEDROCK_EMBEDDING_MODEL_ID = "adapter-disabled-bedrock-embedding-model"
DEFAULT_OPENSEARCH_ENDPOINT = "https://opensearch-disabled.example.internal"
DEFAULT_INDEX_NAME = "terraformers-reference"
DEFAULT_VECTOR_FIELD_NAME = "embedding"
DEFAULT_CONTENT_FIELD_NAME = "content"


class BundleError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build AWS runtime deployment input files from Terraform outputs."
    )
    parser.add_argument("--runtime-outputs-json", help="Path to backend-runtime-dependencies terraform output -json.")
    parser.add_argument("--stateful-outputs-json", help="Path to backend-stateful-dependencies terraform output -json.")
    parser.add_argument("--eks-outputs-json", help="Path to eks-runtime terraform output -json.")
    parser.add_argument("--runtime-dir", default=str(DEFAULT_RUNTIME_DIR), help="Terraform directory for backend runtime dependencies.")
    parser.add_argument("--stateful-dir", default=str(DEFAULT_STATEFUL_DIR), help="Terraform directory for backend stateful dependencies.")
    parser.add_argument("--eks-dir", default=str(DEFAULT_EKS_DIR), help="Terraform directory for EKS runtime.")
    parser.add_argument("--database-password", default=os.environ.get("SPRING_DATASOURCE_PASSWORD", ""), help="Database password. Prefer passing through environment variables or a private shell history-safe wrapper.")
    parser.add_argument("--image-uri", default=os.environ.get("BACKEND_IMAGE_URI", ""), help="Immutable backend image URI pushed to ECR or another registry.")
    parser.add_argument("--namespace", default="", help="Override Kubernetes namespace. Defaults to EKS Terraform output backend_namespace.")
    parser.add_argument("--output-dir", default="artifacts/aws-runtime-input-bundle", help="Directory where generated input files are written.")
    parser.add_argument("--bedrock-model-id", default=os.environ.get("BEDROCK_MODEL_ID", DEFAULT_BEDROCK_MODEL_ID))
    parser.add_argument("--bedrock-embedding-model-id", default=os.environ.get("BEDROCK_EMBEDDING_MODEL_ID", DEFAULT_BEDROCK_EMBEDDING_MODEL_ID))
    parser.add_argument("--opensearch-endpoint", default=os.environ.get("OPENSEARCH_ENDPOINT", DEFAULT_OPENSEARCH_ENDPOINT))
    parser.add_argument("--index-name", default=os.environ.get("INDEX_NAME", DEFAULT_INDEX_NAME))
    parser.add_argument("--vector-field-name", default=os.environ.get("VECTOR_FIELD_NAME", DEFAULT_VECTOR_FIELD_NAME))
    parser.add_argument("--content-field-name", default=os.environ.get("CONTENT_FIELD_NAME", DEFAULT_CONTENT_FIELD_NAME))
    parser.add_argument("--allow-latest-image-tag", action="store_true", help="Allow image URI ending in :latest. Disabled by default.")
    return parser.parse_args()


def run_terraform_output(terraform_dir: Path) -> Dict[str, Any]:
    if not terraform_dir.exists():
        raise BundleError(f"Terraform directory not found: {terraform_dir}")
    try:
        completed = subprocess.run(
            ["terraform", "-chdir=" + str(terraform_dir), "output", "-json"],
            check=True,
            text=True,
            capture_output=True,
        )
    except FileNotFoundError as exc:
        raise BundleError("Required command not found: terraform") from exc
    except subprocess.CalledProcessError as exc:
        raise BundleError(
            f"terraform output -json failed in {terraform_dir}:\n{exc.stderr.strip()}"
        ) from exc
    return json.loads(completed.stdout)


def load_outputs(path: str | None, terraform_dir: str) -> Dict[str, Any]:
    if path:
        return json.loads(Path(path).read_text())
    return run_terraform_output(Path(terraform_dir))


def output_value(outputs: Dict[str, Any], name: str) -> str:
    if name not in outputs:
        raise BundleError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise BundleError(f"Terraform output is empty: {name}")
    if isinstance(value, (dict, list)):
        raise BundleError(f"Terraform output must be scalar: {name}")
    return str(value)


def reject_placeholder(name: str, value: str) -> None:
    if not value:
        raise BundleError(f"{name} is required.")
    if "<" in value or ">" in value:
        raise BundleError(f"{name} must not contain angle-bracket placeholders.")


def validate_image_uri(image_uri: str, allow_latest: bool) -> None:
    reject_placeholder("BACKEND_IMAGE_URI", image_uri)
    if ":" not in image_uri:
        raise BundleError("BACKEND_IMAGE_URI must include an immutable tag.")
    tag = image_uri.rsplit(":", 1)[1]
    if not tag:
        raise BundleError("BACKEND_IMAGE_URI tag must not be empty.")
    if tag == "latest" and not allow_latest:
        raise BundleError("BACKEND_IMAGE_URI must not use latest unless --allow-latest-image-tag is set.")


def write_env_file(path: Path, values: Dict[str, str]) -> None:
    lines = []
    for key, value in values.items():
        reject_placeholder(key, value)
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        runtime = load_outputs(args.runtime_outputs_json, args.runtime_dir)
        stateful = load_outputs(args.stateful_outputs_json, args.stateful_dir)
        eks = load_outputs(args.eks_outputs_json, args.eks_dir)

        validate_image_uri(args.image_uri, args.allow_latest_image_tag)
        reject_placeholder("SPRING_DATASOURCE_PASSWORD", args.database_password)

        namespace = args.namespace or output_value(eks, "backend_namespace")
        irsa_role_arn = output_value(eks, "backend_irsa_role_arn")
        reject_placeholder("KUBERNETES_NAMESPACE", namespace)
        reject_placeholder("BACKEND_IRSA_ROLE_ARN", irsa_role_arn)

        secret_env = {
            "SPRING_DATASOURCE_URL": output_value(stateful, "spring_datasource_url"),
            "SPRING_DATASOURCE_USERNAME": output_value(stateful, "database_username"),
            "SPRING_DATASOURCE_PASSWORD": args.database_password,
            "COGNITO_REGION": output_value(stateful, "cognito_region"),
            "COGNITO_USER_POOL_ID": output_value(stateful, "cognito_user_pool_id"),
            "COGNITO_USER_POOL_CLIENT_ID": output_value(stateful, "cognito_user_pool_client_id"),
            "COGNITO_JWKS_URL": output_value(stateful, "cognito_jwks_url"),
            "S3_BUCKET_NAME": output_value(runtime, "upload_bucket_name"),
            "ANALYSIS_RESULT_BUCKET_NAME": output_value(runtime, "result_bucket_name"),
            "AI_LOG_QUEUE_URL": output_value(runtime, "ai_log_queue_url"),
            "TERRAFORM_LOG_QUEUE_URL": output_value(runtime, "terraform_log_queue_url"),
            "BEDROCK_MODEL_ID": args.bedrock_model_id,
            "BEDROCK_EMBEDDING_MODEL_ID": args.bedrock_embedding_model_id,
            "OPENSEARCH_ENDPOINT": args.opensearch_endpoint,
            "INDEX_NAME": args.index_name,
            "VECTOR_FIELD_NAME": args.vector_field_name,
            "CONTENT_FIELD_NAME": args.content_field_name,
        }

        manifest_env = {
            "BACKEND_IMAGE_URI": args.image_uri,
            "BACKEND_IRSA_ROLE_ARN": irsa_role_arn,
            "KUBERNETES_NAMESPACE": namespace,
        }

        write_env_file(output_dir / "backend-runtime-secret.env", secret_env)
        write_env_file(output_dir / "aws-runtime-manifest.env", manifest_env)

        apply_order = f"""# Generated AWS runtime input bundle
# Files:
# - backend-runtime-secret.env
# - aws-runtime-manifest.env

set -a
. {output_dir / 'aws-runtime-manifest.env'}
set +a

bash scripts/deploy/render-backend-runtime-secret.sh \\
  --env-file {output_dir / 'backend-runtime-secret.env'} \\
  --namespace \"$KUBERNETES_NAMESPACE\" \\
  --output /tmp/terraformers-backend-runtime-secret.yaml

bash scripts/deploy/render-aws-runtime-manifest.sh \\
  --image-uri \"$BACKEND_IMAGE_URI\" \\
  --irsa-role-arn \"$BACKEND_IRSA_ROLE_ARN\" \\
  --namespace \"$KUBERNETES_NAMESPACE\" \\
  --output /tmp/terraformers-aws-runtime.yaml

bash scripts/deploy/aws-runtime-deploy-preflight.sh \\
  --runtime-manifest /tmp/terraformers-aws-runtime.yaml \\
  --secret-manifest /tmp/terraformers-backend-runtime-secret.yaml \\
  --namespace \"$KUBERNETES_NAMESPACE\" \\
  --cluster-check true \\
  --server-dry-run true
"""
        (output_dir / "apply-order.txt").write_text(apply_order)

        print(f"Generated AWS runtime input bundle: {output_dir}")
        print("- backend-runtime-secret.env")
        print("- aws-runtime-manifest.env")
        print("- apply-order.txt")
        return 0
    except BundleError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
