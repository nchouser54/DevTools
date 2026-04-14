#!/bin/bash
set -euo pipefail

# Nemotron 3 SWE GPU User Data Script
# Supports g6.48xlarge (8× L40S), p4d.24xlarge family, and other NVIDIA GPU instances.
# Uses AWS Deep Learning Base GPU AMI (Ubuntu 22.04/24.04) — CUDA and NVIDIA drivers
# are pre-installed on that AMI, so this script only installs nvidia-container-toolkit
# and Docker, then launches vLLM.

MODEL_ID="${model_id}"
VLLM_MAX_MODEL_LEN="${vllm_max_model_len}"
VLLM_MAX_NUM_SEQS="${vllm_max_num_seqs}"
VLLM_GPU_MEMORY_UTIL="${vllm_gpu_memory_util}"
VLLM_EXTRA_ARGS="${vllm_extra_args}"
MODEL_CACHE_MOUNT="${model_cache_mount}"
ENABLE_DETAILED_LOGS="${enable_detailed_logs}"
ENABLE_EFS_CACHE="${enable_efs_cache}"
EFS_DNS_NAME="${efs_dns_name}"
TENSOR_PARALLEL_SIZE="${tensor_parallel_size}"
HF_TOKEN_SSM_PARAMETER="${hf_token_ssm_parameter}"
AWS_REGION="${aws_region}"

LOG_FILE="/var/log/nemotron-init.log"

# Initialize logging
exec 1>>"$LOG_FILE"
exec 2>&1

echo "[$(date)] ==> Starting Nemotron GPU User Data Script"
echo "Model: $MODEL_ID"
echo "vLLM Config: max_model_len=$VLLM_MAX_MODEL_LEN, max_num_seqs=$VLLM_MAX_NUM_SEQS"

# Fetch HuggingFace token from SSM Parameter Store.
# The DL Base AMI ships with AWS CLI pre-installed; no extra install needed.
# If the parameter name is empty, HF_TOKEN stays empty (fine for public models).
HF_TOKEN=""
if [[ -n "$HF_TOKEN_SSM_PARAMETER" ]]; then
  echo "[$(date)] ==> Fetching HF_TOKEN from SSM: $HF_TOKEN_SSM_PARAMETER"
  HF_TOKEN=$(aws ssm get-parameter \
    --name "$HF_TOKEN_SSM_PARAMETER" \
    --with-decryption \
    --query Parameter.Value \
    --output text \
    --region "$AWS_REGION" 2>/dev/null) || {
    echo "[$(date)] ==> WARNING: Failed to fetch HF_TOKEN from SSM — proceeding without token" >&2
    HF_TOKEN=""
  }
  echo "[$(date)] ==> HF_TOKEN fetched successfully"
fi

# Update system
echo "[$(date)] ==> Updating system packages"
apt-get update
apt-get install -y --no-install-recommends \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release \
  jq

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

# Install nvidia-container-toolkit (replaces deprecated nvidia-docker2)
echo "[$(date)] ==> Installing nvidia-container-toolkit"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y --no-install-recommends nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

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

# Create subdirectories
mkdir -p "$MODEL_CACHE_MOUNT/huggingface"
chmod 777 "$MODEL_CACHE_MOUNT"

# Pull latest vLLM image with NVIDIA GPU support
echo "[$(date)] ==> Pulling vLLM Docker image"
docker pull vllm/vllm-openai:latest

# Start vLLM container
echo "[$(date)] ==> Starting vLLM container"
docker run -d \
  --name vllm \
  --gpus all \
  --runtime nvidia \
  --restart unless-stopped \
  -p 8000:8000 \
  -v "$MODEL_CACHE_MOUNT/huggingface:/root/.cache/huggingface" \
  -e HUGGINGFACE_HUB_CACHE="$MODEL_CACHE_MOUNT/huggingface" \
  -e HF_TOKEN="$HF_TOKEN" \
  vllm/vllm-openai:latest \
  --model "$MODEL_ID" \
  --max-model-len $VLLM_MAX_MODEL_LEN \
  --max-num-seqs $VLLM_MAX_NUM_SEQS \
  --gpu-memory-utilization $VLLM_GPU_MEMORY_UTIL \
  --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
  --dtype auto \
  --enable-prefix-caching \
  $VLLM_EXTRA_ARGS \
  --disable-log-requests \
  --port 8000

# Wait for vLLM to be ready (up to 20 minutes for model loading)
echo "[$(date)] ==> Waiting for vLLM to be ready..."
VLLM_READY=false
for i in {1..240}; do
  if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "[$(date)] ==> vLLM is ready!"
    VLLM_READY=true
    break
  fi
  echo "[$(date)] ==> Waiting for vLLM health check ($i/240, $((i*5))s elapsed)..."
  sleep 5
done

if [[ "$VLLM_READY" != "true" ]]; then
  echo "[$(date)] ==> ERROR: vLLM did not become healthy within 20 minutes" >&2
  echo "[$(date)] ==> Docker logs:" >&2
  docker logs vllm 2>&1 | tail -50 >&2
  exit 1
fi

# Create health check script for ELB
mkdir -p /usr/local/bin
cat > /usr/local/bin/health-check.sh << 'HEALTH_EOF'
#!/bin/bash
curl -s http://localhost:8000/health > /dev/null 2>&1 && echo "Health check passed" || echo "Health check failed"
HEALTH_EOF
chmod +x /usr/local/bin/health-check.sh

# Setup CloudWatch agent (optional detailed monitoring)
if [ "$ENABLE_DETAILED_LOGS" = "true" ]; then
  echo "[$(date)] ==> Setting up CloudWatch logging"
  
  cat > /etc/cloudwatch-logs.conf << 'LOGS_EOF'
[/var/log/nemotron-init.log]
log_group_name = /nemotron/init
log_stream_name = {instance_id}
datetime_format = %Y-%m-%d %H:%M:%S
LOGS_EOF
fi

echo "[$(date)] ==> User data script completed successfully!"
echo "[$(date)] ==> vLLM endpoint available at http://localhost:8000"
