# ==============================================================================
# Multi-stage Dockerfile for NGO Management System Fastify Backend
# ==============================================================================

# Stage 1: Build stage
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependency manifests
COPY package*.json tsconfig.json ./

# Install all dependencies including devDependencies for build
RUN npm ci

# Copy source code and migrations
COPY src ./src
COPY migrations ./migrations

# Compile TypeScript
RUN npm run build

# Stage 2: Production runtime stage
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
ENV HOST=0.0.0.0

# Install production dependencies only
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy compiled artifacts from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/migrations ./migrations

# Use non-root node user provided by the base image
USER node

EXPOSE 8080

# Built-in readiness healthcheck probing /ready (verifies PostgreSQL connectivity)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 8080) + '/ready').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

# Apply pending upgrades on every start, including databases with existing data.
CMD ["sh", "-c", "node dist/db/migrate.js up && exec node dist/server.js"]
