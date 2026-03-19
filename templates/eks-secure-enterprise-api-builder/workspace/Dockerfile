FROM python:3.12-slim-bookworm

ARG USERNAME=appuser
ARG UID=1001

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		curl \
		git \
		jq \
		tmux \
		openssh-client \
		unzip \
		ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (arm64 + amd64 via TARGETARCH)
ARG TARGETARCH=amd64
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
	  AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"; \
	else \
	  AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
	fi \
	&& curl -fsSL "${AWSCLI_URL}" -o /tmp/awscli.zip \
	&& unzip -q /tmp/awscli.zip -d /tmp \
	&& /tmp/aws/install \
	&& rm -rf /tmp/aws /tmp/awscli.zip

# Install kubectl
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" \
		-o /usr/local/bin/kubectl \
	&& chmod +x /usr/local/bin/kubectl

WORKDIR /workspace
COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh && rm /tmp/bootstrap.sh

RUN useradd -u ${UID} -m ${USERNAME}

USER ${USERNAME}
WORKDIR /app
