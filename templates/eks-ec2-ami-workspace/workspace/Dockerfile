FROM amazonlinux:2023 AS verify-userdata

# Local testing utility image — simulates the AMI bootstrap environment.
# The actual workspace runs on an EC2 instance, not in a Docker container.
#
# Use this image to:
#   1. Smoke-test workspace/bootstrap.sh against Amazon Linux 2023.
#   2. Verify the Coder agent binary downloads and starts inside a container
#      before deploying to real EC2 instances.
#   3. Test your extra user-data commands locally.

RUN dnf install -y \
    curl \
    jq \
    git \
    tmux \
    ca-certificates \
    util-linux \
    shadow-utils && \
    dnf clean all

COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh

CMD ["/bin/bash", "-c", \
  "echo 'Set CODER_AGENT_TOKEN and CODER_SERVER_URL, then run: /tmp/bootstrap.sh'; sleep infinity"]
