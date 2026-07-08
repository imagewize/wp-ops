# Build from the wp-ops repo root:
#   docker build -f mcp-server/Dockerfile -t wp-ops-mcp-server .
#
# The image needs both mcp-server/ and wp-cli/security/ (the scanner scripts the
# security_scan tool wraps), so the build context is the repo root, not mcp-server/.

FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      php-cli \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/mcp-server

COPY mcp-server/package.json mcp-server/package-lock.json* ./
RUN npm install

COPY mcp-server/tsconfig.json ./
COPY mcp-server/src ./src
RUN npm run build && npm prune --omit=dev

COPY wp-cli/security /app/wp-cli/security

ENV WP_OPS_SITES_CONFIG=/config/sites.json

# Default transport is stdio (used when the container is run with `docker run -i`).
# Set MCP_TRANSPORT=http (and WP_OPS_MCP_TOKEN) to run as a standing network service instead.
EXPOSE 3000

ENTRYPOINT ["node", "dist/index.js"]
