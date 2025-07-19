FROM alpine:3.22.0

# Install dependencies
RUN apk update && \
    apk add --no-cache curl bash && \
    curl -sSf https://cli.nexus.xyz/ -o install.sh && \
    chmod +x install.sh && \
    NONINTERACTIVE=1 ./install.sh && \
    rm -f install.sh

# Create nexus user for better security
RUN adduser -D -s /bin/bash nexus && \
    mkdir -p /home/nexus/.nexus && \
    chown -R nexus:nexus /home/nexus

USER nexus
WORKDIR /home/nexus

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep nexus-cli || exit 1

ENTRYPOINT ["/root/.nexus/bin/nexus-cli"]
