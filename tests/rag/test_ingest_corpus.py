import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("ingest", Path(__file__).parents[2] / "scripts/rag/ingest-corpus.py")
ingest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ingest)


class IngestCorpusTests(unittest.TestCase):
    def test_full_contract_checksum_changes_when_schema_changes(self):
        corpus = Path(__file__).parents[2] / "corpus/terraformers-reference/v1"
        original = ingest.validate_contract(corpus)["sha256"]
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "corpus"
            shutil.copytree(corpus, copied)
            schema_path = copied / "index-schema.json"
            schema = json.loads(schema_path.read_text())
            schema["mappings"]["properties"]["checksumProbe"] = {"type": "keyword"}
            schema_path.write_text(json.dumps(schema))
            self.assertNotEqual(original, ingest.validate_contract(copied)["sha256"])

    def test_same_version_different_checksum_is_rejected(self):
        with self.assertRaises(RuntimeError):
            ingest.ensure_version_checksum({"corpus_version": "v1", "checksum": "old"}, "v1", "new")

    def test_sanitized_summary_excludes_document_content(self):
        document = json.loads((Path(__file__).parents[2] / "corpus/terraformers-reference/v1/documents.jsonl").read_text().splitlines()[0])
        summary = {"document_ids": [document["documentId"]], "outcome": "validated"}
        self.assertNotIn(document["content"], json.dumps(summary))


if __name__ == "__main__":
    unittest.main()
