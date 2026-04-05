FROM node:20-alpine

# Install system dependencies
RUN apk add --no-cache git jq curl bash

# Install GitHub CLI (multi-arch)
ARG GH_VERSION=2.62.0
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/') \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" | tar xz -C /tmp \
    && mv /tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh_${GH_VERSION}_linux_${ARCH}

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create app user and directories
RUN adduser -D -h /home/agent agent
RUN mkdir -p /data/queue /data/logs /data/sessions /home/agent/.claude /home/agent/.config/gh /home/agent/repos
RUN chown -R agent:agent /home/agent /data

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER agent
WORKDIR /home/agent

ENTRYPOINT ["/entrypoint.sh"]
