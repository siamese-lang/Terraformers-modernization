#!/usr/bin/env python3
"""CodeBuild-only utility for guarded private RAG corpus ingestion."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, sys, tempfile, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
def digest(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for part in iter(lambda:f.read(1024*1024),b''): h.update(part)
    return h.hexdigest()
def log(**values): print(json.dumps(values, sort_keys=True))
def fail(message): raise RuntimeError(message)
def corpus_dir(package: Path) -> Path:
    if package.is_dir(): return package
    target=Path(tempfile.mkdtemp(prefix='rag-corpus-'))
    with zipfile.ZipFile(package) as z:
        for item in z.infolist():
            destination=(target/item.filename).resolve()
            if not str(destination).startswith(str(target.resolve())): fail('unsafe package path')
        z.extractall(target)
    candidates=list(target.rglob('corpus-manifest.json'))
    if len(candidates)!=1: fail('package must contain exactly one corpus-manifest.json')
    return candidates[0].parent
def validate(path: Path) -> dict:
    required=['corpus-manifest.json','documents.jsonl','index-schema.json','source-manifest.json']
    if any(not (path/x).is_file() for x in required): fail('package is missing corpus contract files')
    manifest=json.loads((path/'corpus-manifest.json').read_text())
    docs=[json.loads(x) for x in (path/'documents.jsonl').read_text().splitlines() if x.strip()]
    ids=[x.get('documentId') for x in docs]
    if not all(isinstance(x,str) and x for x in ids) or len(ids)!=len(set(ids)): fail('documents must have unique stable documentId values')
    if manifest.get('documentCount') != len(docs): fail('expected document count differs from corpus manifest')
    return {'manifest':manifest,'documents':docs,'schema':json.loads((path/'index-schema.json').read_text())}
def ensure_version_checksum(receipt, corpus_version, checksum):
 if receipt and receipt.get('corpus_version') == corpus_version and receipt.get('checksum') != checksum: fail('corpus version checksum changed; bump corpus version')

def args():
 p=argparse.ArgumentParser(); p.add_argument('--package',type=Path,default=ROOT/'corpus/terraformers-reference/v1'); p.add_argument('--validate-only',action='store_true'); p.add_argument('--collection-endpoint',default=os.getenv('COLLECTION_ENDPOINT','')); p.add_argument('--index-name',default=os.getenv('INDEX_NAME','')); p.add_argument('--vector-field',default=os.getenv('VECTOR_FIELD','')); p.add_argument('--content-field',default=os.getenv('CONTENT_FIELD','')); p.add_argument('--embedding-model-id',default=os.getenv('EMBEDDING_MODEL_ID','')); p.add_argument('--vector-dimension',type=int,default=int(os.getenv('VECTOR_DIMENSION','1024'))); p.add_argument('--expected-checksum',default=os.getenv('EXPECTED_CHECKSUM','')); p.add_argument('--expected-document-count',type=int,default=int(os.getenv('EXPECTED_DOCUMENT_COUNT','0'))); p.add_argument('--receipt-bucket',default=os.getenv('CORPUS_BUCKET','')); p.add_argument('--receipt-key',default=os.getenv('RECEIPT_KEY','')); return p.parse_args()
def main():
 a=args(); started=time.monotonic(); cdir=corpus_dir(a.package)
 validator = ROOT / 'scripts/checks/rag-corpus-contract-verification.py'
 if validator.is_file() and a.package.is_dir(): subprocess.run([sys.executable, str(validator)], check=True)
 data=validate(cdir); m=data['manifest']; checksum=digest(a.package/'documents.jsonl' if a.package.is_dir() else a.package)
 if a.expected_checksum and checksum != a.expected_checksum: fail('package checksum does not match expected checksum')
 if a.expected_document_count and len(data['documents']) != a.expected_document_count: fail('package document count does not match expected document count')
 summary={'corpus_version':m['corpusVersion'],'checksum':checksum,'document_count':len(data['documents']),'index_name':a.index_name or m['indexName'],'embedding_model_id':a.embedding_model_id or m['embeddingModelId'],'vector_dimension':a.vector_dimension,'outcome':'validated','elapsed_seconds':round(time.monotonic()-started,3)}
 if a.validate_only: log(**summary); return
 if not all([a.collection_endpoint,a.index_name,a.vector_field,a.content_field,a.embedding_model_id,a.receipt_bucket,a.receipt_key]): fail('deployment inputs are required')
 import boto3
 from opensearchpy import OpenSearch, RequestsHttpConnection
 from requests_aws4auth import AWS4Auth
 host=a.collection_endpoint.removeprefix('https://').split('/')[0]; region=os.environ.get('AWS_REGION') or boto3.session.Session().region_name
 credentials=boto3.Session().get_credentials(); auth=AWS4Auth(credentials.access_key,credentials.secret_key,region,'aoss',session_token=credentials.token)
 client=OpenSearch(hosts=[{'host':host,'port':443}],http_auth=auth,use_ssl=True,verify_certs=True,connection_class=RequestsHttpConnection)
 schema=data['schema']; existing=client.indices.exists(a.index_name)
 if not existing: client.indices.create(a.index_name,body=schema)
 else:
  props=client.indices.get_mapping(index=a.index_name)[a.index_name]['mappings']['properties']; vector=props.get(a.vector_field,{})
  if vector.get('dimension') != a.vector_dimension or props.get(a.content_field,{}).get('type') != 'text': fail('existing index field contract differs')
 s3=boto3.client('s3'); receipt=None
 try: receipt=json.loads(s3.get_object(Bucket=a.receipt_bucket,Key=a.receipt_key)['Body'].read())
 except s3.exceptions.NoSuchKey: pass
 ensure_version_checksum(receipt, m['corpusVersion'], checksum)
 bedrock=boto3.client('bedrock-runtime'); indexed=[]
 for doc in data['documents']:
  vector=json.loads(bedrock.invoke_model(modelId=a.embedding_model_id,body=json.dumps({'inputText':doc[a.content_field]}))['body'].read())['embedding']
  client.index(index=a.index_name,id=doc['documentId'],body={**doc,a.vector_field:vector}); indexed.append(doc['documentId'])
 client.indices.refresh(index=a.index_name); count=client.count(index=a.index_name)['count']
 query_vector=json.loads(bedrock.invoke_model(modelId=a.embedding_model_id,body=json.dumps({'inputText':data['documents'][0][a.content_field]}))['body'].read())['embedding']
 hits=client.search(index=a.index_name,body={'size':3,'query':{'knn':{a.vector_field:{'vector':query_vector,'k':3}}}})['hits']['hits']
 receipt={'corpus_version':m['corpusVersion'],'checksum':checksum,'document_count':count,'index_name':a.index_name,'embedding_model_id':a.embedding_model_id,'vector_dimension':a.vector_dimension,'hit_count':len(hits),'document_ids':[h['_id'] for h in hits],'outcome':'already-ingested' if receipt else 'ingested','elapsed_seconds':round(time.monotonic()-started,3)}
 s3.put_object(Bucket=a.receipt_bucket,Key=a.receipt_key,Body=json.dumps(receipt,sort_keys=True).encode(),ContentType='application/json'); log(**receipt)
if __name__=='__main__':
 try: main()
 except Exception as exc: log(outcome='failed',error_class=exc.__class__.__name__); print(str(exc),file=sys.stderr); sys.exit(1)
