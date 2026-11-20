#!/usr/bin/env bash
# Builds the tarball of the release of Rescord for a server with no Docker
# (ADR 0044), into dist/:
#
#   scripts/release-tarball.sh            # for this machine
#   scripts/release-tarball.sh amd64 arm64
#
# Each tarball holds the Erlang runtime. It is built on Debian bookworm, so it
# runs on a system with glibc 2.36 or later and OpenSSL 3: Debian 12 and later,
# Ubuntu 24.04 and later, and Fedora 37 and later. An architecture that is
# not the one of this machine needs QEMU for Docker (binfmt).
#
# Behind a proxy that inspects TLS, set EXTRA_CA to the file of its
# certificate. DOCKERFILE names another Dockerfile, and DOCKER_BUILD_FLAGS adds flags
# to `docker buildx build`.
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
debian="${DEBIAN_VERSION:-bookworm-20261104-slim}"
dockerfile="${DOCKERFILE:-$root/platform/Dockerfile}"
archs=("$@")
if [ "${#archs[@]}" -eq 0 ]; then
  case "$(uname -m)" in
    x86_64) archs=(amd64) ;;
    aarch64 | arm64) archs=(arm64) ;;
    *) echo "Give the architecture: amd64 or arm64" >&2; exit 2 ;;
  esac
fi

secret=()
if [ -n "${EXTRA_CA:-}" ]; then
  secret=(--secret "id=extra_ca,src=${EXTRA_CA}")
fi

mkdir -p "$root/dist"
for arch in "${archs[@]}"; do
  echo "Building the tarball for linux/${arch} on Debian ${debian}"
  docker buildx build \
    --platform "linux/${arch}" \
    --build-arg "DEBIAN_VERSION=${debian}" \
    "${secret[@]}" \
    ${DOCKER_BUILD_FLAGS:-} \
    --file "$dockerfile" \
    --target tarball \
    --output "type=local,dest=${root}/dist" \
    "$root/platform"
done

(cd "$root/dist" && sha256sum rescord-linux-*.tar.gz > SHA256SUMS)
echo "The tarballs and their checksums are in ${root}/dist"
