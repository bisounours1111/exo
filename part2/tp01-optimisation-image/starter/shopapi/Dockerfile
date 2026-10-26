# syntax=docker/dockerfile:1.7
# shopapi image following the Shop SAS image standards (see ../../RAPPORT.md).
# Build: docker build --build-arg APP_VERSION=1.4.2 --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t shopapi:1.4.2 .
# Tests: docker build --target test -t shopapi:test .

# Official image pinned by exact tag AND digest (a tag alone is mutable).
ARG NODE_IMAGE=node:20.20.2-alpine3.23@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293

# ---- base: shared by every stage ----
FROM ${NODE_IMAGE} AS base
WORKDIR /app

# ---- deps: production dependencies only ----
# Only the manifests are copied: a change in src/ does not rerun npm ci.
FROM base AS deps
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --no-audit --no-fund

# ---- test: full dependencies + lint + tests ----
FROM base AS test
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund
COPY src/ ./src/
COPY test/ ./test/
RUN npm run lint \
 && npm test \
 && touch /tmp/tests.ok

# ---- runtime: final image ----
FROM base AS runtime
ENV NODE_ENV=production \
    PORT=3000
# Files are owned by root and cannot be modified by the node user.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src/ ./src/
# Explicit dependency on the test stage: if a test fails, the final image is not built.
COPY --from=test /tmp/tests.ok /tmp/tests.ok

# Metadata at the end: it changes on every build without invalidating the layers above.
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.title="shopapi" \
      org.opencontainers.image.description="Shop SAS product catalog API" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="https://github.com/bisounours1111/exo" \
      org.opencontainers.image.vendor="Shop SAS" \
      org.opencontainers.image.base.name="docker.io/library/node:20.20.2-alpine3.23"

# Numeric UID of the node user: verifiable by Kubernetes runAsNonRoot.
USER 1000:1000
EXPOSE 3000
# wget comes from busybox in the alpine image: no extra package needed.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --start-interval=1s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:3000/health"]
# Exec form: node is PID 1 and receives SIGTERM directly (shutdown() handler in server.js).
CMD ["node", "src/server.js"]
