FROM node:22-alpine AS base

# Required for network capability perimeters (iptables rules)
RUN apk add --no-cache iptables ip6tables bash curl

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Install dependencies
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --prod=false

# Copy source
COPY . .

# Compile TypeScript
RUN pnpm build || true

# Runtime data directory for conversation references and session state
RUN mkdir -p /root/.openclaw

EXPOSE 3978

# Entrypoint applies network policy before starting the agent
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["pnpm", "openclaw", "gateway"]
