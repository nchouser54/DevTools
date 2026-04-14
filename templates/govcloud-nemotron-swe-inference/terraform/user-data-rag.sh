#!/bin/bash
set -euo pipefail

# RAG Proxy User Data Script
# Runs a stateless FastAPI service that retrieves context from OpenSearch Serverless
# and forwards augmented prompts to the vLLM inference endpoint on the same ALB.
# Designed for CPU instances (c6i family). Safe on Spot — all state lives in OpenSearch.

MODEL_ID="${model_id}"
MODEL_CACHE_MOUNT="${model_cache_mount}"
ENABLE_DETAILED_LOGS="${enable_detailed_logs}"
ENABLE_EFS_CACHE="${enable_efs_cache}"
EFS_DNS_NAME="${efs_dns_name}"
OPENSEARCH_ENDPOINT="${opensearch_endpoint}"
RAG_INDEX_NAME="${rag_index_name}"
ALB_DNS="${alb_dns_name}"
RAG_INFERENCE_MODEL="${rag_inference_model}"
AWS_REGION_VAL="${aws_region}"

LOG_FILE="/var/log/rag-proxy-init.log"
exec 1>>"$LOG_FILE"
exec 2>&1

echo "[$(date)] ==> Starting RAG Proxy User Data Script"
echo "[$(date)] ==> OpenSearch: $OPENSEARCH_ENDPOINT | Index: $RAG_INDEX_NAME | ALB: $ALB_DNS"

# Update system
echo "[$(date)] ==> Updating system packages"
apt-get update
apt-get install -y --no-install-recommends \
  curl wget ca-certificates jq python3 python3-pip python3-venv lsb-release

# Mount model/embedding cache — EFS shared or per-instance EBS
echo "[$(date)] ==> Setting up cache storage"
mkdir -p "$MODEL_CACHE_MOUNT"

if [[ "$ENABLE_EFS_CACHE" == "true" ]]; then
  echo "[$(date)] ==> EFS shared cache enabled: $EFS_DNS_NAME"
  apt-get install -y --no-install-recommends nfs-common

  MOUNTED=false
  for i in {1..30}; do
    if mount -t nfs4 \
        -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
        "$EFS_DNS_NAME:/" "$MODEL_CACHE_MOUNT"; then
      echo "[$(date)] ==> EFS mount successful"
      echo "$EFS_DNS_NAME:/ $MODEL_CACHE_MOUNT nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" | tee -a /etc/fstab > /dev/null
      MOUNTED=true
      break
    fi
    echo "[$(date)] ==> EFS mount attempt $i/30 failed, retrying in 5s..."
    sleep 5
  done

  if [[ "$MOUNTED" != "true" ]]; then
    echo "[$(date)] ==> ERROR: Failed to mount EFS after 30 attempts" >&2
    exit 1
  fi
else
  for i in {1..60}; do
    if [ -b /dev/nvme1n1 ] || [ -b /dev/sdf ]; then
      echo "[$(date)] ==> Found EBS volume"
      break
    fi
    echo "[$(date)] ==> Waiting for EBS volume ($i/60)..."
    sleep 1
  done

  if ! mountpoint -q "$MODEL_CACHE_MOUNT"; then
    DEVICE=""
    [ -b /dev/nvme1n1 ] && DEVICE="/dev/nvme1n1" || { [ -b /dev/sdf ] && DEVICE="/dev/sdf"; }
    if [ -n "$DEVICE" ]; then
      if ! blkid "$DEVICE"; then mkfs.ext4 -F "$DEVICE"; fi
      mount "$DEVICE" "$MODEL_CACHE_MOUNT"
      chown -R nobody:nogroup "$MODEL_CACHE_MOUNT"
      echo "$DEVICE $MODEL_CACHE_MOUNT ext4 defaults,nofail 0 2" | tee -a /etc/fstab > /dev/null
    fi
  fi
fi

mkdir -p "$MODEL_CACHE_MOUNT/fastembed"
chmod 777 "$MODEL_CACHE_MOUNT"

# Install Python dependencies in a venv (PEP 668 safe)
echo "[$(date)] ==> Installing Python dependencies"
python3 -m venv /opt/rag-venv
/opt/rag-venv/bin/pip install --quiet --upgrade pip
# fastembed downloads ~250 MB bge-small-en-v1.5 on first run; cached to EFS thereafter.
/opt/rag-venv/bin/pip install --quiet \
  "fastapi==0.115.0" \
  "uvicorn[standard]==0.30.6" \
  "httpx==0.27.0" \
  "opensearch-py==2.7.1" \
  "requests-aws4auth==1.3.1" \
  "boto3>=1.34" \
  "fastembed==0.4.1"

# Write the RAG proxy application
cat > /opt/rag-proxy.py << 'RAG_EOF'
#!/usr/bin/env python3
"""
RAG proxy — OpenAI-compatible chat completions with retrieval augmentation.

Endpoints:
  POST /v1/chat/completions  — Retrieve top-K context chunks, augment prompt, call vLLM
  POST /v1/documents         — Chunk, embed, and index a document into the knowledge base
  DELETE /v1/documents/{id}  — Remove all chunks for a document by doc_id
  GET  /health               — Health check (verifies OpenSearch connectivity)
"""

import json
import logging
import os
import uuid
from typing import Optional

import boto3
import httpx
from fastapi import FastAPI, HTTPException
from fastembed import TextEmbedding
from opensearchpy import AWSV4SignerAsyncAuth, OpenSearch, RequestsHttpConnection
from pydantic import BaseModel
from requests_aws4auth import AWS4Auth

# ─── Configuration (injected via environment) ────────────────────────────────
OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"].replace("https://", "")
INDEX_NAME          = os.environ.get("INDEX_NAME", "knowledge-base")
ALB_DNS             = os.environ["ALB_DNS"]
INFERENCE_MODEL     = os.environ.get("INFERENCE_MODEL", "nemotron")
AWS_REGION          = os.environ.get("AWS_REGION", "us-gov-west-1")
EMBED_CACHE_DIR     = os.environ.get("FASTEMBED_CACHE_PATH", "/mnt/model-cache/fastembed")
TOP_K               = int(os.environ.get("RAG_TOP_K", "5"))
CHUNK_SIZE          = int(os.environ.get("RAG_CHUNK_SIZE", "400"))   # words
CHUNK_OVERLAP       = int(os.environ.get("RAG_CHUNK_OVERLAP", "50")) # words
EMBED_DIM           = 384  # matches BAAI/bge-small-en-v1.5

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("rag-proxy")

app = FastAPI(title="RAG Proxy", version="1.0.0")

# ─── OpenSearch client (AWS SigV4, aoss service) ─────────────────────────────
_session     = boto3.Session()
_credentials = _session.get_credentials()
_awsauth     = AWS4Auth(
    refreshable_credentials=_credentials,
    region=AWS_REGION,
    service="aoss",
)

os_client = OpenSearch(
    hosts=[{"host": OPENSEARCH_ENDPOINT, "port": 443}],
    http_auth=_awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    pool_maxsize=20,
)

# ─── Embedding model (CPU, cached to EFS) ────────────────────────────────────
embed_model = TextEmbedding(
    model_name="BAAI/bge-small-en-v1.5",
    cache_dir=EMBED_CACHE_DIR,
)

# ─── httpx client for upstream vLLM calls ────────────────────────────────────
http = httpx.Client(timeout=180.0)


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _ensure_index():
    """Create the kNN vector index if it does not exist."""
    if os_client.indices.exists(INDEX_NAME):
        return
    logger.info("Creating index %s", INDEX_NAME)
    os_client.indices.create(
        INDEX_NAME,
        body={
            "settings": {
                "index": {
                    "knn": True,
                    "knn.algo_param.ef_search": 100,
                }
            },
            "mappings": {
                "properties": {
                    "embedding": {
                        "type": "knn_vector",
                        "dimension": EMBED_DIM,
                        "method": {
                            "name": "hnsw",
                            "engine": "faiss",
                            "parameters": {"ef_construction": 128, "m": 16},
                        },
                    },
                    "text":     {"type": "text"},
                    "doc_id":   {"type": "keyword"},
                    "metadata": {"type": "object", "enabled": False},
                }
            },
        },
    )
    logger.info("Index %s created", INDEX_NAME)


def _embed(texts: list) -> list:
    return [v.tolist() for v in embed_model.embed(texts)]


def _chunk(text: str) -> list:
    words   = text.split()
    chunks  = []
    i = 0
    while i < len(words):
        chunks.append(" ".join(words[i : i + CHUNK_SIZE]))
        i += CHUNK_SIZE - CHUNK_OVERLAP
    return chunks


def _retrieve(query: str, top_k: int = TOP_K) -> list:
    q_vec = _embed([query])[0]
    resp  = os_client.search(
        index=INDEX_NAME,
        body={
            "size": top_k,
            "query": {"knn": {"embedding": {"vector": q_vec, "k": top_k}}},
            "_source": ["text", "doc_id", "metadata"],
        },
    )
    return [h["_source"] for h in resp["hits"]["hits"]]


# ─── Pydantic models ─────────────────────────────────────────────────────────

class Message(BaseModel):
    role:    str
    content: str

class ChatRequest(BaseModel):
    model:       Optional[str]   = None
    messages:    list
    max_tokens:  Optional[int]   = 1024
    temperature: Optional[float] = 0.7
    stream:      Optional[bool]  = False

class DocumentRequest(BaseModel):
    text:     str
    doc_id:   Optional[str]  = None
    metadata: Optional[dict] = {}


# ─── Startup ─────────────────────────────────────────────────────────────────

@app.on_event("startup")
def startup():
    # Retry until OpenSearch collection is active (can take up to 15 min after first apply).
    import time
    for attempt in range(1, 60):
        try:
            _ensure_index()
            logger.info("OpenSearch ready")
            return
        except Exception as exc:
            logger.warning("OpenSearch not ready (attempt %d/60): %s", attempt, exc)
            time.sleep(15)
    raise RuntimeError("OpenSearch collection did not become ready within 15 minutes")


# ─── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    try:
        os_client.cat.indices(index=INDEX_NAME, h="index")
        return {"status": "ok"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc))


@app.post("/v1/documents")
def ingest(req: DocumentRequest):
    """Chunk, embed, and index a document. Returns the doc_id and chunk count."""
    doc_id = req.doc_id or str(uuid.uuid4())
    chunks = _chunk(req.text)
    if not chunks:
        raise HTTPException(status_code=400, detail="Empty document")

    vectors = _embed(chunks)
    bulk_body: list = []
    for i, (chunk, vec) in enumerate(zip(chunks, vectors)):
        bulk_body.append({"index": {"_index": INDEX_NAME, "_id": f"{doc_id}-{i}"}})
        bulk_body.append({
            "doc_id":    doc_id,
            "text":      chunk,
            "embedding": vec,
            "metadata":  req.metadata or {},
        })

    resp = os_client.bulk(body=bulk_body, refresh=True)
    if resp.get("errors"):
        raise HTTPException(status_code=500, detail="Bulk index error")

    logger.info("Indexed doc_id=%s chunks=%d", doc_id, len(chunks))
    return {"doc_id": doc_id, "chunks_indexed": len(chunks)}


@app.delete("/v1/documents/{doc_id}")
def delete_document(doc_id: str):
    """Delete all indexed chunks for a document."""
    resp = os_client.delete_by_query(
        index=INDEX_NAME,
        body={"query": {"term": {"doc_id": doc_id}}},
        refresh=True,
    )
    deleted = resp.get("deleted", 0)
    logger.info("Deleted doc_id=%s chunks=%d", doc_id, deleted)
    return {"doc_id": doc_id, "chunks_deleted": deleted}


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest):
    """Retrieve top-K context chunks and forward an augmented prompt to vLLM."""
    user_msgs = [m for m in req.messages if (isinstance(m, dict) and m.get("role") == "user") or
                 (hasattr(m, "role") and m.role == "user")]
    if not user_msgs:
        raise HTTPException(status_code=400, detail="No user message found")

    query = user_msgs[-1]["content"] if isinstance(user_msgs[-1], dict) else user_msgs[-1].content
    hits  = _retrieve(query)

    context = "\n\n".join(f"[{i+1}] {h['text']}" for i, h in enumerate(hits))
    augmented = [
        {"role": "system", "content": f"Answer using only the context below:\n\n{context}"},
        *([m if isinstance(m, dict) else m.dict() for m in req.messages]),
    ]

    payload = {
        "model":       req.model or INFERENCE_MODEL,
        "messages":    augmented,
        "max_tokens":  req.max_tokens,
        "temperature": req.temperature,
        "stream":      False,
    }

    upstream = http.post(f"http://{ALB_DNS}/v1/chat/completions", json=payload)
    if upstream.status_code != 200:
        logger.error("vLLM error %d: %s", upstream.status_code, upstream.text[:500])
        raise HTTPException(status_code=502, detail="Upstream inference error")

    return upstream.json()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
RAG_EOF

chmod +x /opt/rag-proxy.py

# Set FASTEMBED_CACHE_PATH so the embedding model is stored on EFS and shared
# across Spot replacements (same caching benefit as model weights).
cat > /etc/systemd/system/rag-proxy.service << 'SERVICE_EOF'
[Unit]
Description=RAG Proxy — OpenAI-compat chat with OpenSearch retrieval
After=network.target
Wants=network-online.target

[Service]
Type=simple
Environment=FASTEMBED_CACHE_PATH=/mnt/model-cache/fastembed
EnvironmentFile=-/etc/rag-proxy.env
ExecStart=/opt/rag-venv/bin/python3 /opt/rag-proxy.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/rag-proxy.log
StandardError=append:/var/log/rag-proxy.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Write runtime environment — injected by Terraform templatefile
cat > /etc/rag-proxy.env << ENVEOF
OPENSEARCH_ENDPOINT=${opensearch_endpoint}
INDEX_NAME=${rag_index_name}
ALB_DNS=${alb_dns_name}
INFERENCE_MODEL=${rag_inference_model}
AWS_REGION=${aws_region}
FASTEMBED_CACHE_PATH=${model_cache_mount}/fastembed
ENVEOF
chmod 600 /etc/rag-proxy.env

echo "[$(date)] ==> Starting RAG proxy service"
systemctl daemon-reload
systemctl enable rag-proxy
systemctl start rag-proxy

# Wait for the proxy to respond (OpenSearch collection may still be activating;
# the proxy retries internally for up to 15 minutes).
echo "[$(date)] ==> Waiting for RAG proxy health check..."
for i in {1..60}; do
  if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "[$(date)] ==> RAG proxy is ready!"
    break
  fi
  echo "[$(date)] ==> Waiting ($i/60)..."
  sleep 10
done

echo "[$(date)] ==> RAG proxy init complete"
echo "[$(date)] ==> Endpoints: POST /v1/chat/completions | POST /v1/documents | GET /health"
