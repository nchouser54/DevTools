FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG ENABLE_HELM=false
ARG HELM_VERSION=v3.16.2
ENV ENABLE_HELM=${ENABLE_HELM}
ENV HELM_VERSION=${HELM_VERSION}

WORKDIR /workspace
COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh && rm /tmp/bootstrap.sh
