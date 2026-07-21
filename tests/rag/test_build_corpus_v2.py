import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "build_corpus_v2", ROOT / "scripts/rag/build-corpus-v2.py"
)
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class BuildCorpusV2Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp.name)
        self.provider = self.workspace / "provider"
        docs = self.provider / "website/docs/r"
        docs.mkdir(parents=True)
        (docs / "vpc.html.markdown").write_text(
            """---
page_title: "AWS: aws_vpc"
---
# Resource: aws_vpc

Provides a VPC resource.

## Example Usage

Basic usage:

```terraform
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  password   = "unsafe-example"
}
```

Public usage:

```terraform
resource "aws_vpc" "public" {
  cidr_block = "0.0.0.0/0"
}
```

## Argument Reference

* `cidr_block` - (Optional) VPC CIDR.
""",
            encoding="utf-8",
        )
        self.schema = self.workspace / "schema.json"
        self.schema.write_text(
            json.dumps(
                {
                    "provider_schemas": {
                        build.PROVIDER_ADDRESS: {
                            "resource_schemas": {
                                "aws_vpc": {
                                    "version": 1,
                                    "block": {
                                        "attributes": {
                                            "cidr_block": {
                                                "type": "string",
                                                "optional": True,
                                            },
                                            "id": {
                                                "type": "string",
                                                "computed": True,
                                            },
                                        },
                                        "block_types": {},
                                    },
                                }
                            }
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        self.v1 = self.workspace / "v1"
        self.v1.mkdir()
        (self.v1 / "documents.jsonl").write_text(
            json.dumps(
                {
                    "documentId": "tfref-v1-private-entry",
                    "title": "Private entry",
                    "documentType": "TERRAFORMERS_PATTERN",
                    "content": "CloudFront is the only public entry.",
                    "services": ["cloudfront"],
                    "resourceTypes": ["aws_cloudfront_distribution"],
                    "architecturePattern": "cloudfront-only-public-entry",
                    "securityConsiderations": ["private-origin"],
                    "sourceVersion": "terraformers-reference-v1",
                    "providerVersion": build.PROVIDER_VERSION,
                    "sourcePath": "docs/source-rag-gitops-reuse-plan.md",
                    "corpusVersion": "terraformers-reference-v1",
                }
            )
            + "\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def build_documents(self):
        provider_schema = build.schema_provider(self.schema)
        provider_docs, provider_sources = build.provider_documents(
            self.provider,
            provider_schema,
            "a" * 40,
            ["aws_vpc"],
        )
        project_docs, project_sources = build.project_pattern_documents(
            self.v1,
            "b" * 40,
        )
        return provider_docs + project_docs, provider_sources + project_sources

    def test_preserves_complete_hcl_blocks_and_tags_risky_examples(self):
        documents, _ = self.build_documents()
        examples = [
            document
            for document in documents
            if document["documentType"] == "AWS_PROVIDER_EXAMPLE"
        ]
        self.assertEqual(2, len(examples))
        secret_example = next(
            document for document in examples if "plaintext-secret" in document["riskTags"]
        )
        self.assertIn('password   = "<sensitive-value>"', secret_example["content"])
        self.assertNotIn("unsafe-example", secret_example["content"])
        self.assertEqual(
            secret_example["content"].count("```"),
            2,
            "a generated example must contain one complete fenced HCL block",
        )
        public_example = next(
            document for document in examples if "public-cidr" in document["riskTags"]
        )
        self.assertIn("0.0.0.0/0", public_example["content"])

    def test_generates_schema_and_high_priority_project_documents(self):
        documents, _ = self.build_documents()
        schema_document = next(
            document
            for document in documents
            if document["documentType"] == "AWS_PROVIDER_SCHEMA"
        )
        self.assertEqual("PROVIDER_SCHEMA", schema_document["authority"])
        self.assertIn("`cidr_block`: optional", schema_document["content"])
        project_document = next(
            document
            for document in documents
            if document["documentType"] == "TERRAFORMERS_PATTERN"
        )
        self.assertEqual("PROJECT_DECISION", project_document["authority"])
        self.assertEqual(100, project_document["priority"])
        self.assertEqual(build.CORPUS_VERSION, project_document["sourceVersion"])

    def test_written_v2_corpus_passes_contract_validator(self):
        documents, sources = self.build_documents()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "v2"
            build.write_corpus(output, documents, sources)
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/checks/rag-corpus-contract-verification.py"),
                    "--corpus-dir",
                    str(output),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            manifest = json.loads(
                (output / "corpus-manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(len(documents), manifest["documentCount"])
            mapping = json.loads(
                (output / "index-schema.json").read_text(encoding="utf-8")
            )["mappings"]["properties"]
            self.assertEqual("keyword", mapping["authority"]["type"])
            self.assertEqual("integer", mapping["priority"]["type"])


if __name__ == "__main__":
    unittest.main()
