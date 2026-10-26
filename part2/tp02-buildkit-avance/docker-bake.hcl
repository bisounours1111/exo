# Builds the whole Shop SAS stack (TP01 API + worker) with a single command.
# Run from part2/tp02-buildkit-avance: relative paths are resolved from the current directory.
#
#   docker buildx bake --print
#   VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake worker-test
#   VERSION=1.0 docker buildx bake --set *.platform=linux/amd64 --load
#   VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake --push

variable "REGISTRY" {
  default = "localhost:5000"
}

variable "VERSION" {
  default = "dev"
}

variable "GIT_SHA" {
  default = "unknown"
}

group "default" {
  targets = ["api", "worker"]
}

# Abstract target: never built on its own, only inherited.
target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
  labels = {
    "org.opencontainers.image.version"  = VERSION
    "org.opencontainers.image.revision" = GIT_SHA
    "org.opencontainers.image.source"   = "https://github.com/bisounours1111/exo"
    "org.opencontainers.image.vendor"   = "Shop SAS"
  }
  # Every image reads the cache of the whole stack; writing (cache-to) is per image,
  # otherwise both targets would overwrite the same reference in parallel.
  cache-from = [for name in ["api", "worker"] : "type=registry,ref=${REGISTRY}/cache:${name}"]
}

target "api" {
  inherits = ["_common"]
  context  = "../tp01-optimisation-image/starter/shopapi"
  target   = "runtime"
  args = {
    APP_VERSION = VERSION
    GIT_SHA     = GIT_SHA
  }
  tags     = ["${REGISTRY}/shopapi:${VERSION}"]
  cache-to = ["type=registry,ref=${REGISTRY}/cache:api,mode=max"]
}

target "worker" {
  inherits = ["_common"]
  context  = "starter/shop-worker"
  target   = "runtime"
  args = {
    VERSION = VERSION
    GIT_SHA = GIT_SHA
  }
  secret   = ["id=pipconf,src=starter/shop-worker/pip.conf"]
  tags     = ["${REGISTRY}/shop-worker:${VERSION}"]
  cache-to = ["type=registry,ref=${REGISTRY}/cache:worker,mode=max"]
}

# Runs only the test stage (ruff + pytest) on every platform, without producing an image.
target "worker-test" {
  inherits = ["worker"]
  target   = "test"
  tags     = []
  output   = ["type=cacheonly"]
  cache-to = []
}
