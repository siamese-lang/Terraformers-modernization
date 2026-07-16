#!/usr/bin/env python3
"""Build public frontend production inputs from Terraform output JSON.

The generated bundle contains only browser-public Cognito identifiers and
frontend delivery destinations. It performs no AWS authentication, S3 sync,
CloudFront invalidation, Terraform mutation, or deployment.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


class BundleError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build same-origin React delivery inputs from Terraform outputs."
    )
    parser.add_argument("--stateful-outputs-json", required=True)
    parser.add_argument("--frontend-outputs-json", required=True)
    parser.add_argument(
        "--output-dir",
        default="artifacts/frontend-delivery-input-bundle",
    )
    return parser.parse_args()


def load_outputs(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def output_value(outputs: dict[str, Any], name: str) -> str:
    if name not in outputs:
        raise BundleError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise BundleError(f"Terraform output is empty: {name}")
    if isinstance(value, (dict, list)):
        raise BundleError(f"Terraform output must be scalar: {name}")
    text = str(value)
    if "<" in text or ">" in text:
        raise BundleError(f"Terraform output contains a placeholder: {name}")
    return text


def write_env(path: Path, values: dict[str, str]) -> None:
    lines: list[str] = []
    for key, value in values.items():
        if "\n" in value or "\r" in value:
            raise BundleError(f"{key} must be a single-line value.")
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o600)


def main() -> int:
    args = parse_args()
    stateful = load_outputs(args.stateful_outputs_json)
    frontend = load_outputs(args.frontend_outputs_json)

    cloudfront_domain = output_value(frontend, "cloudfront_distribution_domain_name")
    bucket_name = output_value(frontend, "frontend_bucket_name")
    distribution_id = output_value(frontend, "cloudfront_distribution_id")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir.chmod(0o700)

    build_env = {
        "REACT_APP_API_BASE_URL": "",
        "REACT_APP_AWS_REGION": output_value(stateful, "cognito_region"),
        "REACT_APP_COGNITO_USER_POOL_ID": output_value(
            stateful, "cognito_user_pool_id"
        ),
        "REACT_APP_COGNITO_USER_POOL_CLIENT_ID": output_value(
            stateful, "cognito_user_pool_client_id"
        ),
    }
    write_env(output_dir / "frontend-build.env", build_env)

    source_map = {
        "frontend_bucket_name": bucket_name,
        "cloudfront_distribution_id": distribution_id,
        "cloudfront_distribution_domain_name": cloudfront_domain,
        "frontend_base_url": f"https://{cloudfront_domain}",
        "api_base_mode": "same-origin-relative",
        "api_path_prefix": "/api/",
        "cognito_values": "browser-public-terraform-outputs",
        "mutable_cache_control": "no-cache,no-store,must-revalidate",
        "static_cache_control": "public,max-age=31536000,immutable",
        "invalidation_scope": "mutable-entrypoints-only",
        "aws_mutation": "not-performed",
    }
    (output_dir / "delivery-source-map.json").write_text(
        json.dumps(source_map, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    summary = [
        "frontend_delivery_input_bundle=generated",
        "frontend_build_variable_count=4",
        "api_base_mode=same-origin-relative",
        "api_path_prefix=/api/*",
        "cognito_source=terraform-output",
        "frontend_bucket_source=terraform-output",
        "cloudfront_distribution_source=terraform-output",
        "mutable_cache_control=no-cache",
        "static_cache_control=immutable-one-year",
        "invalidation_scope=mutable-entrypoints-only",
        "invalidation_wait=required",
        "aws_mutation=none",
    ]
    (output_dir / "bundle-summary.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8"
    )

    invalidation_file = output_dir / "frontend-invalidation.json"
    apply_order = f"""# Generated frontend delivery sequence
# This file is a manual deployment boundary. The bundle generator did not run these commands.

set -a
. {output_dir / 'frontend-build.env'}
set +a

npm --prefix frontend ci --legacy-peer-deps --no-audit --no-fund
npm --prefix frontend run build

aws s3 sync frontend/build s3://{bucket_name} \\
  --delete \\
  --exclude 'static/*' \\
  --cache-control 'no-cache,no-store,must-revalidate' \\
  --only-show-errors

aws s3 sync frontend/build/static s3://{bucket_name}/static \\
  --delete \\
  --cache-control 'public,max-age=31536000,immutable' \\
  --only-show-errors

aws cloudfront create-invalidation \\
  --distribution-id {distribution_id} \\
  --paths '/' '/index.html' '/asset-manifest.json' '/manifest.json' \\
  > {invalidation_file}

INVALIDATION_ID="$(python3 -c 'import json; print(json.load(open(\"{invalidation_file}\"))[\"Invalidation\"][\"Id\"])')"
aws cloudfront wait invalidation-completed \\
  --distribution-id {distribution_id} \\
  --id "$INVALIDATION_ID"

# Browser smoke target
# https://{cloudfront_domain}
# https://{cloudfront_domain}/api/public-projects
"""
    (output_dir / "apply-order.txt").write_text(apply_order, encoding="utf-8")

    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BundleError, OSError, json.JSONDecodeError) as exc:
        print(str(exc), file=__import__("sys").stderr)
        raise SystemExit(1)
