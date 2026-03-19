FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

ARG USERNAME=vscode

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git jq unzip nodejs npm tmux openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir --upgrade pip

COPY bootstrap.sh /usr/local/bin/devtools-bootstrap
RUN chmod +x /usr/local/bin/devtools-bootstrap && /usr/local/bin/devtools-bootstrap

COPY init-workspace.sh /usr/local/bin/devtools-init-workspace
COPY auto-init.sh /usr/local/bin/devtools-auto-init
COPY mcp.servers.template.json /usr/local/share/devtools/mcp.servers.template.json
RUN chmod +x /usr/local/bin/devtools-init-workspace /usr/local/bin/devtools-auto-init

# Run one-time workspace initialization on first shell startup (bash + zsh).
RUN echo '[ -x /usr/local/bin/devtools-auto-init ] && /usr/local/bin/devtools-auto-init' >> /home/${USERNAME}/.bashrc \
    && echo '[ -x /usr/local/bin/devtools-auto-init ] && /usr/local/bin/devtools-auto-init' >> /home/${USERNAME}/.zshrc

USER ${USERNAME}
WORKDIR /workspaces
