#!/usr/bin/env python3
"""Build a private External Secrets runtime package from Terraform output JSON.

This command performs no AWS authentication, Helm install, Terraform mutation, or
Kubernetes apply. It prepares:

- backend-runtime-secret-payload.json (non-password runtime values)
- external-secrets-runtime.yaml (ServiceAccount, SecretStore, ExternalSecret)
- managed-secret-source-map.json
- package-summary.txt
- apply-order.txt
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

EXPECTED_NAMESPACE = "terraformers-runtime"
EXPECTED_BACKEND_SECRET = "terraformers-backend-runtime-secrets"
EXPECTED_EXTERNAL_SECRETS_SERVICE_ACCOUNT = "terraformers-external-secrets"
EXPECTED_SECRET_STORE = "terraformers-backend-secretsmanager"
EXPECTED_EXTERNAL_SECRET = "terraformers-backend-runtime"

RUNTIME_CONFIG_KEYS = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "S3_BUCKET_NAME",
    "ANALYSIS_RESULT_BUCKET_NAME",
]


class PackageError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a static External Secrets runtime package from Terraform outputs."
    )
    parser.add_argument("--runtime-outputs-json", required=True)
    parser.add_argument("--stateful-outputs-json", required=True)
    parser.add_argument("--eks-outputs-json", required=True)
    parser.add_argument(
        "--output-dir",
        default="artifacts/external-secrets-runtime-package",
    )
    return parser.parse_args()


def load_outputs(path: str) -> dict[str, Any]:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise PackageError(f"Terraform output JSON must be an object: {path}")
    return value


def output_value(outputs: dict[str, Any], name: str) -> str:
    if name not in outputs:
        raise PackageError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise PackageError(f"Terraform output is empty: {name}")
    if isinstance(value, (dict, list)):
        raise PackageError(f"Terraform output must be scalar: {name}")
    result = str(value)
    if "\n" in result or "\r" in result:
        raise PackageError(f"Terraform output must be single-line: {name}")
    if "<" in result or ">" in result:
        raise PackageError(f"Terraform output must not contain placeholders: {name}")
    return result


def yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def write_private_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o600)


def render_manifest(
    *,
    region: str,
    namespace: str,
    service_account: str,
    role_arn: str,
    runtime_secret_arn: str,
    database_secret_arn: str,
    target_secret_name: str,
) -> str:
    lines = [
        "apiVersion: v1",
        "kind: ServiceAccount",
        "metadata:",
        f"  name: {service_account}",
        f"  namespace: {namespace}",
        "  annotations:",
        f"    eks.amazonaws.com/role-arn: {yaml_string(role_arn)}",
        "---",
        "apiVersion: external-secrets.io/v1",
        "kind: SecretStore",
        "metadata:",
        f"  name: {EXPECTED_SECRET_STORE}",
        f"  namespace: {namespace}",
        "spec:",
        "  provider:",
        "    aws:",
        "      service: SecretsManager",
        f"      region: {region}",
        "      auth:",
        "        jwt:",
        "          serviceAccountRef:",
        f"            name: {service_account}",
        "---",
        "apiVersion: external-secrets.io/v1",
        "kind: ExternalSecret",
        "metadata:",
        f"  name: {EXPECTED_EXTERNAL_SECRET}",
        f"  namespace: {namespace}",
        "spec:",
        "  refreshInterval: 1h0m0s",
        "  secretStoreRef:",
        f"    name: {EXPECTED_SECRET_STORE}",
        "    kind: SecretStore",
        "  target:",
        f"    name: {target_secret_name}",
        "    creationPolicy: Owner",
        "  data:",
    ]
    for key in RUNTIME_CONFIG_KEYS:
        lines.extend(
            [
                f"    - secretKey: {key}",
                "      remoteRef:",
                f"        key: {yaml_string(runtime_secret_arn)}",
                f"        property: {key}",
            ]
        )
    lines.extend(
        [
            "    - secretKey: SPRING_DATASOURCE_PASSWORD",
            "      remoteRef:",
            f"        key: {yaml_string(database_secret_arn)}",
            "        property: password",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    try:
        runtime = load_outputs(args.runtime_outputs_json)
        stateful = load_outputs(args.stateful_outputs_json)
        eks = load_outputs(args.eks_outputs_json)

        namespace = output_value(eks, "backend_namespace")
        service_account = output_value(eks, "external_secrets_service_account_name")
        role_arn = output_value(eks, "external_secrets_irsa_role_arn")
        region = output_value(eks, "aws_region")
        runtime_secret_arn = output_value(runtime, "backend_runtime_secret_arn")
        target_secret_name = output_value(runtime, "kubernetes_runtime_secret_name")
        database_secret_arn = output_value(stateful, "database_master_user_secret_arn")

        if namespace != EXPECTED_NAMESPACE:
            raise PackageError(
                f"backend_namespace must remain {EXPECTED_NAMESPACE}, found: {namespace}"
            )
        if service_account != EXPECTED_EXTERNAL_SECRETS_SERVICE_ACCOUNT:
            raise PackageError(
                "external_secrets_service_account_name must remain "
                f"{EXPECTED_EXTERNAL_SECRETS_SERVICE_ACCOUNT}, found: {service_account}"
            )
        if target_secret_name != EXPECTED_BACKEND_SECRET:
            raise PackageError(
                "kubernetes_runtime_secret_name must remain "
                f"{EXPECTED_BACKEND_SECRET}, found: {target_secret_name}"
            )

        payload = {
            "SPRING_DATASOURCE_URL": output_value(stateful, "spring_datasource_url"),
            "SPRING_DATASOURCE_USERNAME": output_value(stateful, "database_username"),
            "COGNITO_REGION": output_value(stateful, "cognito_region"),
            "COGNITO_USER_POOL_ID": output_value(stateful, "cognito_user_pool_id"),
            "COGNITO_USER_POOL_CLIENT_ID": output_value(
                stateful, "cognito_user_pool_client_id"
            ),
            "COGNITO_JWKS_URL": output_value(stateful, "cognito_jwks_url"),
            "S3_BUCKET_NAME": output_value(runtime, "upload_bucket_name"),
            "ANALYSIS_RESULT_BUCKET_NAME": output_value(runtime, "result_bucket_name"),
        }
        if list(payload) != RUNTIME_CONFIG_KEYS:
            raise PackageError("Internal error: runtime configuration key order drifted.")

        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        output_dir.chmod(0o700)

        payload_path = output_dir / "backend-runtime-secret-payload.json"
        manifest_path = output_dir / "external-secrets-runtime.yaml"
        source_map_path = output_dir / "managed-secret-source-map.json"

        write_private_text(
            payload_path,
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        )
        write_private_text(
            manifest_path,
            render_manifest(
                region=region,
                namespace=namespace,
                service_account=service_account,
                role_arn=role_arn,
                runtime_secret_arn=runtime_secret_arn,
                database_secret_arn=database_secret_arn,
                target_secret_name=target_secret_name,
            ),
        )
        write_private_text(
            source_map_path,
            json.dumps(
                {
                    "provider": "external-secrets-operator",
                    "provider_installation_status": "required-not-performed",
                    "aws_region": region,
                    "backend_runtime_secret_arn": runtime_secret_arn,
                    "database_master_user_secret_arn": database_secret_arn,
                    "database_password_property": "password",
                    "kubernetes_namespace": namespace,
                    "external_secrets_service_account_name": service_account,
                    "external_secrets_irsa_role_arn": role_arn,
                    "kubernetes_runtime_secret_name": target_secret_name,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
        )

        summary = [
            "external_secrets_runtime_package=generated",
            "external_secrets_api_version=external-secrets.io/v1",
            f"runtime_config_key_count={len(payload)}",
            f"target_secret_key_count={len(payload) + 1}",
            "database_password_source=rds-managed-secret/password",
            "database_password_in_payload=false",
            "optional_adapter_setting_count=0",
            "provider_installation=required-not-performed",
            "cluster_contact=none",
        ]
        (output_dir / "package-summary.txt").write_text(
            "\n".join(summary) + "\n", encoding="utf-8"
        )

        apply_order = f"""# Generated managed Secret delivery package
# This file is documentation only. Nothing below was executed by the builder.
# External Secrets Operator installation and all AWS/Kubernetes mutations require explicit approval.

# 1. After approved Terraform apply, write non-password runtime values to the existing container.
aws secretsmanager put-secret-value \\
  --region {region} \\
  --secret-id {runtime_secret_arn} \\
  --secret-string file://{payload_path}

# 2. After the External Secrets Operator CRDs/controller are installed and validated:
kubectl apply -f {manifest_path}

# 3. Validate resource status without printing Secret values:
kubectl get secretstore,externalsecret -n {namespace}
kubectl get secret {target_secret_name} -n {namespace} -o jsonpath='{{.data}}' | jq 'keys'
"""
        (output_dir / "apply-order.txt").write_text(apply_order, encoding="utf-8")
        print("\n".join(summary))
        return 0
    except (OSError, json.JSONDecodeError, PackageError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
