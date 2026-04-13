#!/bin/bash
set -euo pipefail

# Nemotron 3 SWE GPU User Data Script (g4dn.xlarge, p3.2xlarge)
# Runs vLLM with NVIDIA GPU support

MODEL_ID="${model_id}"
VLLM_MAX_MODEL_LEN="${vllm_max_model_len}"
VLLM_MAX_NUM_SEQS="${vllm_max_num_seqs}"
VLLM_GPU_MEMORY_UTIL="${vllm_gpu_memory_util}"
MODEL_CACHE_MOUNT="${model_cache_mount}"
ENABLE_DETAILED_LOGS="${enable_detailed_logs}"

LOG_FILE="/var/log/nemotron-init.log"

# Initialize logging
exec 1>>"$LOG_FILE"
exec 2>&1

echo "[$(date)] ==> Starting Nemotron GPU User Data Script"
echo "Model: $MODEL_ID"
echo "vLLM Config: max_model_len=$VLLM_MAX_MODEL_LEN, max_num_seqs=$VLLM_MAX_NUM_SEQS"

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

# Install NVIDIA Docker runtime
echo "[$(date)] ==> Installing NVIDIA Docker Runtime"
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null
apt-get update
apt-get install -y --no-install-recommends nvidia-docker2
systemctl restart docker

# Mount model cache volume
echo "[$(date)] ==> Setting up model cache volume"
mkdir -p "$MODEL_CACHE_MOUNT"

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
    if ! sudo blkid "$DEVICE"; then
      sudo mkfs.ext4 -F "$DEVICE"
    fi
    sudo mount "$DEVICE" "$MODEL_CACHE_MOUNT"
    sudo chown -R nobody:nogroup "$MODEL_CACHE_MOUNT"
    echo "$DEVICE $MODEL_CACHE_MOUNT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
  fi
fi

# Create directories
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
  -p 8000:8000 \
  -v "$MODEL_CACHE_MOUNT/huggingface:/root/.cache/huggingface" \
  -e HUGGINGFACE_HUB_CACHE="$MODEL_CACHE_MOUNT/huggingface" \
  -e HF_TOKEN="" \
  vllm/vllm-openai:latest \
  --model "$MODEL_ID" \
  --max-model-len $VLLM_MAX_MODEL_LEN \
  --max-num-seqs $VLLM_MAX_NUM_SEQS \
  --gpu-memory-utilization $VLLM_GPU_MEMORY_UTIL \
  --dtype auto \
  --disable-log-requests \
  --port 8000

# Wait for vLLM to be ready (up to 20 minutes for model loading)
echo "[$(date)] ==> Waiting for vLLM to be ready..."
for i in {1..240}; do
  if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "[$(date)] ==> vLLM is ready!"
    break
  fi
  echo "[$(date)] ==> Waiting for vLLM health check ($i/240, $((i*5))s elapsed)..."
  sleep 5
done

# Create health check script for ELB
cat > /local/health-check.sh << 'HEALTH_EOF'
#!/bin/bash
curl -s http://localhost:8000/health > /dev/null 2>&1 && echo "Health check passed" || echo "Health check failed"
HEALTH_EOF
chmod +x /local/health-check.sh

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
