#!/bin/bash
set -euo pipefail

# Nemotron 3 SWE CPU User Data Script (c6i.4xlarge)
# Runs inference using CPU with llama.cpp or Ollama (MUCH slower than GPU)

MODEL_ID="${model_id}"
VLLM_MAX_MODEL_LEN="${vllm_max_model_len}"
VLLM_MAX_NUM_SEQS="${vllm_max_num_seqs}"
MODEL_CACHE_MOUNT="${model_cache_mount}"
ENABLE_DETAILED_LOGS="${enable_detailed_logs}"
ENABLE_EFS_CACHE="${enable_efs_cache}"
EFS_DNS_NAME="${efs_dns_name}"

LOG_FILE="/var/log/nemotron-init.log"

# Initialize logging
exec 1>>"$LOG_FILE"
exec 2>&1

echo "[$(date)] ==> Starting Nemotron CPU User Data Script"
echo "[$(date)] ==> WARNING: CPU inference is 5-10× slower than GPU!"
echo "Model: $MODEL_ID"

# Update system
echo "[$(date)] ==> Updating system packages"
apt-get update
apt-get install -y --no-install-recommends \
  curl \
  wget \
  ca-certificates \
  build-essential \
  cmake \
  jq \
  htop

# Install Docker
echo "[$(date)] ==> Installing Docker"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

# Start Docker
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Mount model cache — EFS shared (persists across Spot replacements) or per-instance EBS
echo "[$(date)] ==> Setting up model cache storage"
mkdir -p "$MODEL_CACHE_MOUNT"

if [[ "$ENABLE_EFS_CACHE" == "true" ]]; then
  echo "[$(date)] ==> EFS shared cache enabled: $EFS_DNS_NAME"
  apt-get install -y --no-install-recommends nfs-common

  # Retry NFS mount — network + EFS mount targets may need a few seconds
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
  # Wait for EBS volume to attach (up to 60 sec)
  for i in {1..60}; do
    if [ -b /dev/nvme1n1 ] || [ -b /dev/sdf ]; then
      echo "[$(date)] ==> Found EBS volume"
      break
    fi
    echo "[$(date)] ==> Waiting for EBS volume ($i/60)..."
    sleep 1
  done

  # Format and mount if not already mounted
  if ! mountpoint -q "$MODEL_CACHE_MOUNT"; then
    DEVICE=""
    if [ -b /dev/nvme1n1 ]; then
      DEVICE="/dev/nvme1n1"
    elif [ -b /dev/sdf ]; then
      DEVICE="/dev/sdf"
    fi

    if [ -n "$DEVICE" ]; then
      echo "[$(date)] ==> Formatting and mounting $DEVICE"
      if ! blkid "$DEVICE"; then
        mkfs.ext4 -F "$DEVICE"
      fi
      mount "$DEVICE" "$MODEL_CACHE_MOUNT"
      chown -R nobody:nogroup "$MODEL_CACHE_MOUNT"
      echo "$DEVICE $MODEL_CACHE_MOUNT ext4 defaults,nofail 0 2" | tee -a /etc/fstab > /dev/null
    fi
  fi
fi

mkdir -p "$MODEL_CACHE_MOUNT/models"
chmod 777 "$MODEL_CACHE_MOUNT"

# Use Ollama for CPU-based inference
# Ollama is simpler and more lightweight than vLLM on CPU
echo "[$(date)] ==> Installing Ollama"
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
echo "[$(date)] ==> Starting Ollama service"
systemctl enable ollama
systemctl restart ollama

# Wait for Ollama to be ready
echo "[$(date)] ==> Waiting for Ollama to start..."
sleep 10

# Pull configured model for CPU runtime.
# Note: this runtime expects an Ollama-compatible model identifier.
echo "[$(date)] ==> Pulling CPU model: $MODEL_ID"
ollama pull "$MODEL_ID"

# Create a simple wrapper API that mimics vLLM's OpenAI-compatible interface
cat > /opt/api-wrapper.py << 'WRAPPER_EOF'
#!/usr/bin/env python3
"""
Simple API wrapper for Ollama that mimics vLLM's OpenAI-compatible interface.
Provides /v1/completions and /health endpoints.
"""

import flask
import requests
import json
import logging
from datetime import datetime

app = flask.Flask(__name__)
logging.basicConfig(level=logging.INFO)

OLLAMA_URL = "http://localhost:11434"
MODEL = "${model_id}"

@app.route("/health", methods=["GET"])
def health():
    try:
        requests.get(f"{OLLAMA_URL}/api/tags")
        return {"status": "ok"}, 200
    except:
        return {"status": "unhealthy"}, 503

@app.route("/v1/completions", methods=["POST"])
def completions():
    data = flask.request.json

    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": MODEL,
                "prompt": data.get("prompt", ""),
                "stream": False,
                "num_predict": data.get("max_tokens", 512),
                "temperature": data.get("temperature", 0.7),
            }
        )

        if response.status_code != 200:
            return {"error": "Ollama error"}, 500

        result = response.json()

        return {
            "id": "ollama-cpu",
            "object": "text_completion",
            "created": int(datetime.now().timestamp()),
            "model": MODEL,
            "choices": [
                {
                    "text": result.get("response", ""),
                    "index": 0,
                    "finish_reason": "stop"
                }
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        }, 200

    except Exception as e:
        logging.error(f"Error: {e}")
        return {"error": str(e)}, 500


@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """OpenAI chat completions endpoint — converts to Ollama /api/chat."""
    data = flask.request.json
    messages = data.get("messages", [])

    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": MODEL,
                "messages": messages,
                "stream": False,
                "options": {
                    "num_predict": data.get("max_tokens", 512),
                    "temperature": data.get("temperature", 0.7),
                },
            }
        )

        if response.status_code != 200:
            return {"error": "Ollama error"}, 500

        result = response.json()
        assistant_msg = result.get("message", {})

        return {
            "id": "ollama-cpu",
            "object": "chat.completion",
            "created": int(datetime.now().timestamp()),
            "model": MODEL,
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": assistant_msg.get("role", "assistant"),
                        "content": assistant_msg.get("content", ""),
                    },
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        }, 200

    except Exception as e:
        logging.error(f"Error: {e}")
        return {"error": str(e)}, 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)

WRAPPER_EOF

chmod +x /opt/api-wrapper.py

# Install Python dependencies in a venv to avoid PEP 668 "externally-managed-environment"
# errors that forbid system-wide pip installs on Ubuntu 22.04.3+.
apt-get install -y python3 python3-pip python3-venv
python3 -m venv /opt/api-venv
/opt/api-venv/bin/pip install --quiet flask requests

# Install API wrapper as a systemd service so it restarts on reboot / Spot replacement.
cat > /etc/systemd/system/api-wrapper.service << 'SERVICE_EOF'
[Unit]
Description=Ollama OpenAI-compatible API Wrapper
After=network.target ollama.service
Requires=ollama.service

[Service]
Type=simple
ExecStart=/opt/api-venv/bin/python3 /opt/api-wrapper.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/api-wrapper.log
StandardError=append:/var/log/api-wrapper.log

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "[$(date)] ==> Starting API wrapper service on port 8000"
systemctl daemon-reload
systemctl enable api-wrapper
systemctl start api-wrapper

# Wait for API to be ready
echo "[$(date)] ==> Waiting for API wrapper to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "[$(date)] ==> API is ready!"
    break
  fi
  echo "[$(date)] ==> Waiting for API health check ($i/30)..."
  sleep 2
done

echo "[$(date)] ==> User data script completed!"
echo "[$(date)] ==> WARNING: CPU inference is 5-10× slower than GPU"
echo "[$(date)] ==> API endpoint available at http://localhost:8000"
