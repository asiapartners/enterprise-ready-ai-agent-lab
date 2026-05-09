# ─── Build stage ───────────────────────────────────────────────────────────────
FROM node:24-alpine AS builder

# Install pnpm (v9+ required by OpenClaw)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Install dependencies first (layer-cache friendly)
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --ignore-scripts

# Copy source and compile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build

# Prune dev dependencies
RUN pnpm prune --prod

# ─── Runtime stage ─────────────────────────────────────────────────────────────
FROM node:24-alpine AS runtime

# Security: run as non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Install iptables for network policy enforcement (NETWORK_MODE=restricted|allowlist)
# Required when container is started with --cap-add=NET_ADMIN
RUN apk add --no-cache iptables

WORKDIR /app

COPY --from=builder /app/dist        ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

# Create OpenClaw home and config dirs; override via volume mount in dev
RUN mkdir -p /app/.openclaw /app/config /app/plugins \
    && chown -R appuser:appgroup /app

# Copy OpenClaw plugin descriptor and channel routing config
COPY openclaw.plugin.json ./openclaw.plugin.json
COPY config/ ./config/

USER appuser

# Bot Framework standard port (A365 / Teams)
EXPOSE 3978

# Health check — used by Container App liveness probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3978/health || exit 1

CMD ["node", "dist/index.js"]
