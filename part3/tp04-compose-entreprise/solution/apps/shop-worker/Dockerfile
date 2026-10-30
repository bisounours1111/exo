# syntax=docker/dockerfile:1.7
# shop-worker: PyPI credentials as a secret mount, pip cache per architecture, multi-arch image.
# Build: docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
# Tests: docker build --secret id=pipconf,src=pip.conf --target test -t worker:test .

ARG PYTHON_IMAGE=python:3.12.16-slim-bookworm@sha256:e697c81897302a4c4333bade000d98038fbb21eb064f8ee1fd42d02ebcd9d337

# ---- base: shared by every stage ----
FROM ${PYTHON_IMAGE} AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/venv/bin:$PATH
WORKDIR /app

# ---- builder: production dependencies in a virtualenv ----
FROM base AS builder
# Set automatically by BuildKit (amd64, arm64...): isolates the pip cache per architecture.
ARG TARGETARCH
COPY requirements.txt ./
# The secret is mounted as tmpfs for this RUN only: it is never written to a layer.
# required=true: the build fails if --secret id=pipconf is missing instead of falling back to the public index.
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    python -m venv /opt/venv \
 && pip install -r requirements.txt

# ---- test: dev dependencies + lint + tests ----
FROM builder AS test
ARG TARGETARCH
COPY requirements-dev.txt ./
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    pip install -r requirements-dev.txt
COPY worker/ ./worker/
COPY tests/ ./tests/
RUN ruff check worker tests \
 && python -m pytest -q \
 && touch /tmp/tests.ok

# ---- runtime: final image ----
FROM base AS runtime
RUN groupadd --system --gid 10001 worker \
 && useradd --system --uid 10001 --gid worker --no-create-home --shell /usr/sbin/nologin worker
COPY --from=builder /opt/venv /opt/venv
COPY worker/ ./worker/
# Makes the test stage mandatory: a failing test prevents the image from being built.
COPY --from=test /tmp/tests.ok /tmp/tests.ok

ARG VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="shop-worker" \
      org.opencontainers.image.description="Shop SAS order processing worker" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="https://github.com/bisounours1111/exo" \
      org.opencontainers.image.vendor="Shop SAS" \
      org.opencontainers.image.base.name="docker.io/library/python:3.12.16-slim-bookworm"

USER 10001:10001
EXPOSE 9100
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --start-interval=1s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9100/metrics', timeout=2)"]
CMD ["python", "-m", "worker.main"]
