FROM amazonlinux:2023 AS verify-ssm

# This Dockerfile is a local-testing utility image only.
# In production, the Coder agent is delivered to the EXISTING EC2 instance
# via AWS SSM Run Command — no Docker build step occurs for the target.
#
# Use this image to:
#   1. Verify SSM agent installation steps in a local container.
#   2. Smoke-test the bootstrap.sh against an Amazon Linux 2023 environment.
#   3. Validate that the Coder agent binary downloads and starts correctly
#      before deploying changes to real EC2 instances.

RUN dnf install -y amazon-ssm-agent curl jq bash && \
    dnf clean all

COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh

# Default CMD prints usage rather than running bootstrap, which requires
# the CODER_AGENT_TOKEN environment variable to be set at runtime.
CMD ["/bin/bash", "-c", "echo 'Set CODER_AGENT_TOKEN and run: /tmp/bootstrap.sh'; sleep infinity"]
