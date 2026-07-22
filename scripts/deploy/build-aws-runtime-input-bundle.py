#!/usr/bin/env python3
"""Build private AWS runtime deployment inputs from Terraform output JSON.

This script performs no AWS authentication, Terraform apply, image push, or
Kubernetes mutation. It converts existing Terraform outputs plus a privately
supplied database password and immutable backend image URI into:

- backend-runtime-secret.env
- aws-runtime-manifest.env
- deployment-source-map.json
- bundle-summary.txt
- apply-order.txt
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUNTIME_DIR = REPO_ROOT / "infra/terraform/envs/backend-runtime-dependencies"
DEFAULT_STATEFUL_DIR = REPO_ROOT / "infra/terraform/envs/backend-stateful-dependencies"
DEFAULT_EKS_DIR = REPO_ROOT / "infra/terraform/envs/eks-runtime"

EXPECTED_NAMESPACE = "terraformers-runtime"
EXPECTED_SERVICE_ACCOUNT = "terraformers-backend"
EXPECTED_RUNTIME_SECRET = "terraformers-backend-runtime-secrets"

BASE_SECRET_KEYS = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "S3_BUCKET_NAME",
]


class BundleError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build AWS runtime deployment inputs from existing Terraform outputs."
    )
    parser.add_argument(
        "--runtime-outputs-json",
        help="Path to backend-runtime-dependencies terraform output -json.",
    )
    parser.add_argument(
        "--stateful-outputs-json",
        help="Path to backend-stateful-dependencies terraform output -json.",
    )
    parser.add_argument(
        "--eks-outputs-json",
        help="Path to eks-runtime terraform output -json.",
    )
    parser.add_argument(
        "--runtime-dir",
        default=str(DEFAULT_RUNTIME_DIR),
        help="Terraform directory for backend runtime dependencies.",
    )
    parser.add_argument(
        "--stateful-dir",
        default=str(DEFAULT_STATEFUL_DIR),
        help="Terraform directory for backend stateful dependencies.",
    )
    parser.add_argument(
        "--eks-dir",
        default=str(DEFAULT_EKS_DIR),
        help="Terraform directory for EKS runtime.",
    )
    parser.add_argument(
        "--database-password",
        default=os.environ.get("SPRING_DATASOURCE_PASSWORD", ""),
        help="Database password supplied privately through an argument or environment variable.",
    )
    parser.add_argument(
        "--image-uri",
        default=os.environ.get("BACKEND_IMAGE_URI", ""),
        help="Immutable backend image URI belonging to backend_image_repository_url.",
    )
    parser.add_argument(
        "--output-dir",
        default="artifacts/aws-runtime-input-bundle",
        help="Directory where private generated input files are written.",
    )
    return parser.parse_args()


def run_terraform_output(terraform_dir: Path) -> dict[str, Any]:
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


def load_outputs(path: str | None, terraform_dir: str) -> dict[str, Any]:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    return run_terraform_output(Path(terraform_dir))


def output_value(outputs: dict[str, Any], name: str) -> str:
    if name not in outputs:
        raise BundleError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise BundleError(f"Terraform output is empty: {name}")
    if isinstance(value, (dict, list)):
        raise BundleError(f"Terraform output must be scalar: {name}")
    return str(value)


def optional_output_value(outputs: dict[str, Any], name: str) -> str | None:
    if name not in outputs:
        return None
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        return None
    if isinstance(value, (dict, list)):
        raise BundleError(f"Terraform output must be scalar: {name}")
    return str(value)


def reject_placeholder(name: str, value: str) -> None:
    if not value:
        raise BundleError(f"{name} is required.")
    if "<" in value or ">" in value:
        raise BundleError(f"{name} must not contain angle-bracket placeholders.")
    lowered = value.lower()
    if "adapter-disabled" in lowered or "disabled.example" in lowered:
        raise BundleError(f"{name} must not use a disabled-adapter placeholder value.")


def validate_image_uri(image_uri: str, repository_url: str) -> None:
    reject_placeholder("BACKEND_IMAGE_URI", image_uri)
    reject_placeholder("backend_image_repository_url", repository_url)

    tag_prefix = repository_url + ":"
    digest_prefix = repository_url + "@sha256:"
    if image_uri.startswith(tag_prefix):
        tag = image_uri[len(tag_prefix):]
        if not tag:
            raise BundleError("BACKEND_IMAGE_URI tag must not be empty.")
        if tag == "latest":
            raise BundleError("BACKEND_IMAGE_URI must not use the mutable latest tag.")
        return

    if image_uri.startswith(digest_prefix):
        digest = image_uri[len(digest_prefix):]
        if len(digest) != 64 or any(
            character not in "0123456789abcdefABCDEF" for character in digest
        ):
            raise BundleError(
                "BACKEND_IMAGE_URI sha256 digest must contain exactly 64 hexadecimal characters."
            )
        return

    raise BundleError(
        "BACKEND_IMAGE_URI must belong to Terraform output backend_image_repository_url "
        "and use an immutable tag or sha256 digest."
    )


def write_env_file(path: Path, values: dict[str, str]) -> None:
    lines: list[str] = []
    for key, value in values.items():
        reject_placeholder(key, value)
        if "\n" in value or "\r" in value:
            raise BundleError(f"{key} must be a single-line value.")
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o600)


def write_json_file(path: Path, value: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    path.chmod(0o600)


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)

    try:
        runtime = load_outputs(args.runtime_outputs_json, args.runtime_dir)
        stateful = load_outputs(args.stateful_outputs_json, args.stateful_dir)
        eks = load_outputs(args.eks_outputs_json, args.eks_dir)

        repository_url = output_value(runtime, "backend_image_repository_url")
        validate_image_uri(args.image_uri, repository_url)
        reject_placeholder("SPRING_DATASOURCE_PASSWORD", args.database_password)

        namespace = output_value(eks, "backend_namespace")
        service_account = output_value(eks, "backend_service_account_name")
        irsa_role_arn = output_value(eks, "backend_irsa_role_arn")
        runtime_secret_name = output_value(runtime, "kubernetes_runtime_secret_name")

        if namespace != EXPECTED_NAMESPACE:
            raise BundleError(
                f"backend_namespace must remain {EXPECTED_NAMESPACE}, found: {namespace}"
            )
        if service_account != EXPECTED_SERVICE_ACCOUNT:
            raise BundleError(
                "backend_service_account_name must remain "
                f"{EXPECTED_SERVICE_ACCOUNT}, found: {service_account}"
            )
        if runtime_secret_name != EXPECTED_RUNTIME_SECRET:
            raise BundleError(
                "kubernetes_runtime_secret_name must remain "
                f"{EXPECTED_RUNTIME_SECRET}, found: {runtime_secret_name}"
            )

        secret_env = {
            "SPRING_DATASOURCE_URL": output_value(stateful, "spring_datasource_url"),
            "SPRING_DATASOURCE_USERNAME": output_value(stateful, "database_username"),
            "SPRING_DATASOURCE_PASSWORD": args.database_password,
            "COGNITO_REGION": output_value(stateful, "cognito_region"),
            "COGNITO_USER_POOL_ID": output_value(stateful, "cognito_user_pool_id"),
            "COGNITO_USER_POOL_CLIENT_ID": output_value(
                stateful, "cognito_user_pool_client_id"
            ),
            "COGNITO_JWKS_URL": output_value(stateful, "cognito_jwks_url"),
            "S3_BUCKET_NAME": output_value(runtime, "upload_bucket_name"),
            "ANALYSIS_RESULT_BUCKET_NAME": output_value(runtime, "result_bucket_name"),
        }
        if list(secret_env)[: len(BASE_SECRET_KEYS)] != BASE_SECRET_KEYS:
            raise BundleError("Internal error: base runtime Secret key order drifted.")

        manifest_env = {
            "BACKEND_IMAGE_URI": args.image_uri,
            "BACKEND_IRSA_ROLE_ARN": irsa_role_arn,
            "KUBERNETES_NAMESPACE": namespace,
        }
        source_map = {
            "backend_image_repository_url": repository_url,
            "backend_runtime_secret_arn": output_value(
                runtime, "backend_runtime_secret_arn"
            ),
            "kubernetes_runtime_secret_name": runtime_secret_name,
            "database_master_user_secret_arn": optional_output_value(
                stateful, "database_master_user_secret_arn"
            ),
            "cluster_name": output_value(eks, "cluster_name"),
            "backend_namespace": namespace,
            "backend_service_account_name": service_account,
            "backend_irsa_role_arn": irsa_role_arn,
            "upload_bucket_name": output_value(runtime, "upload_bucket_name"),
            "result_bucket_name": output_value(runtime, "result_bucket_name"),
            "runtime_secret_provider_status": "unresolved",
            "database_password_delivery_status": "private-input-required",
        }

        output_dir.mkdir(parents=True, exist_ok=True)
        output_dir.chmod(0o700)
        secret_env_path = output_dir / "backend-runtime-secret.env"
        manifest_env_path = output_dir / "aws-runtime-manifest.env"
        source_map_path = output_dir / "deployment-source-map.json"

        write_env_file(secret_env_path, secret_env)
        write_env_file(manifest_env_path, manifest_env)
        write_json_file(source_map_path, source_map)

        summary_lines = [
            "aws_runtime_input_bundle=generated",
            f"base_required_key_count={len(BASE_SECRET_KEYS)}",
            f"runtime_secret_key_count={len(secret_env)}",
            "optional_result_bucket_key=present",
            "optional_adapter_setting_count=0",
            "backend_image_repository_match=true",
            f"kubernetes_namespace={namespace}",
            f"service_account_name={service_account}",
            f"kubernetes_runtime_secret_name={runtime_secret_name}",
            "runtime_secret_provider=unresolved",
            "database_password_source=private-input",
        ]
        (output_dir / "bundle-summary.txt").write_text(
            "\n".join(summary_lines) + "\n", encoding="utf-8"
        )

        apply_order = f"""# Generated AWS runtime input bundle
# This file stops at manifest rendering and preflight. It does not apply resources.
# Private files:
# - {secret_env_path}
# - {manifest_env_path}
# - {source_map_path}

set -a
. {manifest_env_path}
set +a

bash scripts/deploy/render-backend-runtime-secret.sh \\
  --env-file {secret_env_path} \\
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
  --cluster-check false \\
  --server-dry-run false
"""
        (output_dir / "apply-order.txt").write_text(apply_order, encoding="utf-8")

        print(f"Generated AWS runtime input bundle: {output_dir}")
        print("- backend-runtime-secret.env")
        print("- aws-runtime-manifest.env")
        print("- deployment-source-map.json")
        print("- bundle-summary.txt")
        print("- apply-order.txt")
        return 0
    except BundleError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
