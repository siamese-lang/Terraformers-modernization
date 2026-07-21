import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("ingest", Path(__file__).parents[2] / "scripts/rag/ingest-corpus.py")
ingest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ingest)


class RecordingClient:
    def __init__(self, count=0, hits=None):
        self.count_value = count
        self.hits = hits or []
        self.count_body = None
        self.search_bodies = []

    def count(self, *, index, body):
        self.count_body = body
        return {"count": self.count_value}

    def search(self, *, index, body):
        self.search_bodies.append(body)
        return {"hits": {"hits": self.hits}}


class RecordingIndices:
    def __init__(self, index_name, properties):
        self.index_name = index_name
        self.properties = properties
        self.put_mapping_body = None

    def get_mapping(self, *, index):
        return {
            index: {
                "mappings": {
                    "properties": self.properties,
                }
            }
        }

    def put_mapping(self, *, index, body):
        self.put_mapping_body = body
        self.properties.update(body["properties"])


class MappingClient:
    def __init__(self, index_name, properties):
        self.indices = RecordingIndices(index_name, properties)


class IngestCorpusTests(unittest.TestCase):
    def test_full_contract_checksum_changes_when_schema_changes(self):
        corpus = Path(__file__).parents[2] / "corpus/terraformers-reference/v1"
        original = ingest.validate_contract(corpus)["sha256"]
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "v1"
            shutil.copytree(corpus, copied)
            schema_path = copied / "index-schema.json"
            schema = json.loads(schema_path.read_text())
            schema["mappings"]["properties"]["checksumProbe"] = {"type": "keyword"}
            schema_path.write_text(json.dumps(schema))
            self.assertNotEqual(original, ingest.validate_contract(copied)["sha256"])

    def test_same_version_different_checksum_is_rejected(self):
        with self.assertRaises(RuntimeError):
            ingest.ensure_version_checksum({"corpus_version": "v1", "checksum": "old"}, "v1", "new")

    def test_document_count_is_scoped_to_corpus_version(self):
        client = RecordingClient(count=12)

        count = ingest.wait_for_document_count(
            client,
            "terraformers-reference-v1",
            12,
            "terraformers-reference-v1",
            timeout_seconds=0,
        )

        self.assertEqual(12, count)
        self.assertEqual(
            {"query": {"term": {"corpusVersion": "terraformers-reference-v1"}}},
            client.count_body,
        )

    def test_document_lookup_uses_id_and_corpus_version(self):
        client = RecordingClient(hits=[{"_id": "hit"}])

        exists = ingest.document_exists(
            client,
            "terraformers-reference-v1",
            "tfaws-aws-vpc-overview",
            "terraformers-reference-v2",
        )

        self.assertTrue(exists)
        self.assertEqual(
            [
                {"term": {"documentId": "tfaws-aws-vpc-overview"}},
                {"term": {"corpusVersion": "terraformers-reference-v2"}},
            ],
            client.search_bodies[0]["query"]["bool"]["filter"],
        )

    def test_representative_knn_is_scoped_to_corpus_version(self):
        client = RecordingClient(hits=[{"_id": "hit"}])

        hits = ingest.wait_for_knn_hits(
            client,
            "terraformers-reference-v1",
            "embedding",
            [0.1, 0.2],
            "terraformers-reference-v2",
            timeout_seconds=0,
        )

        self.assertEqual(1, len(hits))
        self.assertEqual(
            {"term": {"corpusVersion": "terraformers-reference-v2"}},
            client.search_bodies[0]["query"]["knn"]["embedding"]["filter"],
        )

    def test_missing_v2_metadata_mapping_is_added_to_existing_index(self):
        index_name = "terraformers-reference-v1"
        client = MappingClient(
            index_name,
            {
                "embedding": {"type": "knn_vector", "dimension": 1024},
                "content": {"type": "text"},
                "title": {"type": "text"},
                "corpusVersion": {"type": "keyword"},
            },
        )
        schema = {
            "mappings": {
                "properties": {
                    "embedding": {"type": "knn_vector", "dimension": 1024},
                    "content": {"type": "text"},
                    "title": {"type": "text"},
                    "corpusVersion": {"type": "keyword"},
                    "authority": {"type": "keyword"},
                    "priority": {"type": "integer"},
                }
            }
        }

        added = ingest.ensure_index_mapping(
            client,
            index_name,
            schema,
            "embedding",
            "content",
            1024,
        )

        self.assertEqual(["authority", "priority"], added)
        self.assertEqual(
            {
                "properties": {
                    "authority": {"type": "keyword"},
                    "priority": {"type": "integer"},
                }
            },
            client.indices.put_mapping_body,
        )

    def test_sanitized_summary_excludes_document_content(self):
        document = json.loads((Path(__file__).parents[2] / "corpus/terraformers-reference/v1/documents.jsonl").read_text().splitlines()[0])
        summary = {"document_ids": [document["documentId"]], "outcome": "validated"}
        self.assertNotIn(document["content"], json.dumps(summary))


if __name__ == "__main__":
    unittest.main()
