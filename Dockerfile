# NanoClaw Orchestrator — runs the main Node.js process in K3s
# The orchestrator spawns agent containers via Docker socket (DinD sidecar)

FROM node:22-slim AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

# ──────────────────────────────────────────────────────────────────
FROM node:22-slim AS runtime

# curl for health checks and simple HTTP calls
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled output
COPY --from=builder /app/dist ./dist

# Groups directory — mounted as PVC in K3s
RUN mkdir -p /app/groups

ENV NODE_ENV=production
# Docker socket path — DinD sidecar exposes on tcp:2375 in K3s
ENV DOCKER_HOST=tcp://localhost:2375

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3001/health 2>/dev/null || pgrep -f "node dist/index.js" > /dev/null

CMD ["node", "dist/index.js"]
