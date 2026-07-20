import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC=importlib.util.spec_from_file_location('ingest',Path(__file__).parents[2]/'scripts/rag/ingest-corpus.py')
ingest=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(ingest)
class IngestCorpusTests(unittest.TestCase):
 def test_stable_document_ids_and_sanitized_summary(self):
  corpus=Path(__file__).parents[2]/'corpus/terraformers-reference/v1'
  data=ingest.validate(corpus)
  self.assertEqual(12,len({d['documentId'] for d in data['documents']}))
  summary={'document_ids':[data['documents'][0]['documentId']],'outcome':'validated'}
  self.assertNotIn(data['documents'][0]['content'],json.dumps(summary))
 def test_same_version_different_checksum_is_rejected(self):
  with self.assertRaises(RuntimeError): ingest.ensure_version_checksum({'corpus_version':'v1','checksum':'old'},'v1','new')
if __name__=='__main__': unittest.main()
