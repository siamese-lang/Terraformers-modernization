#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts/deploy/live-aws-prerequisite-inventory.py"
EVIDENCE_DIR = REPO_ROOT / "artifacts/live-aws-prerequisite-inventory"


def load_inventory_module():
    spec = importlib.util.spec_from_file_location("live_aws_prerequisite_inventory", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    module = load_inventory_module()

    assert module.decode_process_output("✓ authenticated".encode("utf-8")) == "✓ authenticated"
    assert module.decode_process_output("인증 실패".encode("cp949")) == "인증 실패"
    assert module.decode_process_output(None) == ""

    original_run = module.subprocess.run
    try:
        module.subprocess.run = lambda *args, **kwargs: SimpleNamespace(
            returncode=1,
            stdout=None,
            stderr="✓ gh auth failed".encode("utf-8"),
        )
        code, stdout, stderr = module.run("gh", "auth", "status")
    finally:
        module.subprocess.run = original_run

    assert code == 1
    assert stdout == ""
    assert stderr == "✓ gh auth failed"

    with tempfile.TemporaryDirectory() as temporary_directory:
        output_dir = Path(temporary_directory)
        stale_inventory = output_dir / "prerequisite-inventory.json"
        stale_summary = output_dir / "prerequisite-summary.txt"
        retained_console = output_dir / "console-output.txt"
        stale_inventory.write_text("stale", encoding="utf-8")
        stale_summary.write_text("stale", encoding="utf-8")
        retained_console.write_text("retain", encoding="utf-8")

        module.clear_generated_reports(output_dir)

        assert not stale_inventory.exists()
        assert not stale_summary.exists()
        assert retained_console.read_text(encoding="utf-8") == "retain"

    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    summary = [
        "live_aws_prerequisite_windows_portability=passed",
        "subprocess_capture_mode=bytes",
        "utf8_output_decode=passed",
        "cp949_output_decode=passed",
        "none_output_decode=passed",
        "stale_report_cleanup=passed",
        "console_evidence_preserved=true",
    ]
    (EVIDENCE_DIR / "windows-portability-summary.txt").write_text(
        "\n".join(summary) + "\n",
        encoding="utf-8",
    )
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
