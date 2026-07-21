import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "curate_corpus_v2", ROOT / "scripts/rag/curate-corpus-v2.py"
)
curate_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(curate_module)


class CurateCorpusV2Tests(unittest.TestCase):
    def test_removes_irrelevant_examples_and_tags_service_wildcards(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / "v2"
            corpus.mkdir()
            documents = [
                self.document(
                    "basic",
                    "aws_db_instance - Basic Usage",
                    "aws_db_instance",
                    'resource "aws_db_instance" "main" {}',
                    "website/docs/r/db_instance.html.markdown",
                ),
                self.document(
                    "custom",
                    "aws_db_instance - RDS Custom for Oracle Usage with Replica",
                    "aws_db_instance",
                    'resource "aws_db_instance" "custom" {}',
                    "website/docs/r/db_instance.html.markdown",
                ),
                self.document(
                    "aoss",
                    "aws_opensearchserverless_access_policy - Grant all collection and index permissions",
                    "aws_opensearchserverless_access_policy",
                    'Permission = ["aoss:*"]',
                    "website/docs/r/opensearchserverless_access_policy.html.markdown",
                ),
            ]
            (corpus / "corpus-manifest.json").write_text(
                json.dumps(
                    {
                        "corpusVersion": curate_module.CORPUS_VERSION,
                        "documentCount": 3,
                        "chunkCount": 3,
                    }
                )
            )
            (corpus / "documents.jsonl").write_text(
                "".join(json.dumps(document) + "\n" for document in documents)
            )
            (corpus / "source-manifest.json").write_text(
                json.dumps(
                    {
                        "sources": [
                            {
                                "sourceType": "AWS_PROVIDER_EXAMPLE",
                                "sourceVersion": "v5.100.0",
                                "sourcePath": path,
                                "sourceCommit": "a" * 40,
                            }
                            for path in sorted({document["sourcePath"] for document in documents})
                        ]
                    }
                )
            )
            (corpus / "index-schema.json").write_text("{}")

            summary = curate_module.curate(corpus)

            retained = [
                json.loads(line)
                for line in (corpus / "documents.jsonl").read_text().splitlines()
            ]
            self.assertEqual({"before": 3, "after": 2, "removed": 1}, summary)
            self.assertEqual({"basic", "aoss"}, {document["documentId"] for document in retained})
            aoss = next(document for document in retained if document["documentId"] == "aoss")
            self.assertIn("wildcard-iam", aoss["riskTags"])
            manifest = json.loads((corpus / "corpus-manifest.json").read_text())
            self.assertEqual(2, manifest["documentCount"])

    @staticmethod
    def document(document_id, title, resource_type, content, source_path):
        return {
            "documentId": document_id,
            "title": title,
            "documentType": "AWS_PROVIDER_EXAMPLE",
            "content": content,
            "resourceTypes": [resource_type],
            "riskTags": [],
            "securityConsiderations": [],
            "sourceVersion": "v5.100.0",
            "sourcePath": source_path,
            "sourceCommit": "a" * 40,
        }


if __name__ == "__main__":
    unittest.main()
