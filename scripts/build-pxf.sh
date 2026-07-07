#!/usr/bin/env bash
# Build PXF (Platform Extension Framework) against the WHPG GPHOME and package it
# as an RPM + binary tarball. Runs INSIDE the Rocky 9 build container.
#
# Source: greenplum-db/pxf-archive (PXF 6.x, PostgreSQL 12 / GPDB 7 lineage) — the
# API-compatible match for WHPG 7. (apache/cloudberry-pxf expects PG14 headers.)
# Requires: the WHPG server tarball already in /work/artifacts (run build-binary first),
#           a JDK (in the image) and Go.
set -euxo pipefail
source "$(dirname "$0")/common.sh"

ART=/work/artifacts
PXF_SRC=/work/pxf-src
: "${PXF_REPO_URL:=https://github.com/greenplum-db/pxf-archive.git}"
: "${PXF_REF:=main}"
: "${GO_VERSION:=system}"

# 1. Install the WHPG GPHOME from our tarball so PXF's C extensions can compile
#    against its headers and detect the GP major version.
[[ -f "${ART}/${TARBALL}" ]] || {
    echo "ERROR: ${ART}/${TARBALL} not found. Run build-binary.sh first." >&2
    exit 1
}
rm -rf "$GPHOME"
mkdir -p "$GPHOME"
tar xzf "${ART}/${TARBALL}" -C "$GPHOME"
# shellcheck disable=SC1090
source "${GPHOME}/greenplum_path.sh"
log "GPHOME=${GPHOME}  ($(pg_config --version 2>/dev/null || postgres --gp-version))"

# 2. Toolchain.
# PXF's Gradle wrapper predates Java 17; the image's default javac is 17, so pin
# to JDK 11 (works for both the old server Gradle and the extensions/CLI).
if [[ -z "${JAVA_HOME:-}" ]]; then
    for j in /usr/lib/jvm/java-11-openjdk /usr/lib/jvm/java-11; do
        [[ -x "$j/bin/javac" ]] && { JAVA_HOME="$(readlink -f "$j")"; break; }
    done
    JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
fi
export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${PATH}"
log "JAVA_HOME=${JAVA_HOME} ($("${JAVA_HOME}/bin/javac" -version 2>&1))"
if [[ "${GO_VERSION}" == "system" ]]; then
    command -v go >/dev/null 2>&1 || { log "Installing distro golang"; dnf install -y golang >/dev/null; }
else
    if ! command -v go >/dev/null 2>&1 || [[ "$(go version 2>/dev/null)" != *"go${GO_VERSION}"* ]]; then
        log "Installing Go ${GO_VERSION}"
        curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz
    fi
fi
export PATH="/usr/local/go/bin:${PATH}"
export GOPATH="${GOPATH:-/root/go}"
export PATH="${PATH}:${GOPATH}/bin"
export GOFLAGS=-mod=mod
go version

# 3. Fetch PXF source (keep .git — the stage target records the commit sha).
#    PXF_REF may be a commit SHA, tag, or branch, so clone then checkout.
rm -rf "$PXF_SRC"
git clone "$PXF_REPO_URL" "$PXF_SRC"
git -C "$PXF_SRC" checkout --quiet "$PXF_REF"
cd "$PXF_SRC"
export PXF_HOME="${GPHOME}/pxf"

# 4. Build extensions (external-table/fdw) + CLI (Go) + server (Gradle), then package.
make -j"$(nproc)"
make rpm
make tar

# 5. Collect artifacts.
find build/rpmbuild/RPMS -name '*.rpm' -exec cp -v {} "$ART/" \;
find build/dist          -name '*.tar.gz' -exec cp -v {} "$ART/" \;
( cd "$ART" && for f in *pxf*.rpm *pxf*.tar.gz; do [[ -e "$f" ]] && sha256sum "$f" > "${f}.sha256"; done ) || true

log "PXF artifacts:"
ls -lh "$ART"/*pxf* 2>/dev/null || ls -lh "$ART"/*cloudberry-pxf* 2>/dev/null
