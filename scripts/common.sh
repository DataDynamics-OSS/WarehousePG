#!/usr/bin/env bash
# Shared configuration + helpers.
# Safe to source on the host (reads config/build.env) or inside the build
# container (values arrive via `docker run -e ...`).
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# On the host, config/build.env sits next to scripts/. Inside the container the
# scripts are mounted at /scripts and the values come from the environment.
# Load build.env as defaults only: values already present in the environment
# (passed by the Makefile or on the command line) take precedence, so
# `make all WHPG_TAG=...` and `WHPG_LOCAL_REPO=...` overrides actually win.
_env_file="${_here}/../config/build.env"
if [[ -f "$_env_file" ]]; then
    while IFS='=' read -r _k _v; do
        [[ "$_k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue   # skip comments/blanks
        [[ -n "${!_k+x}" ]] && continue                       # keep existing env value
        export "${_k}=${_v}"
    done < "$_env_file"
fi

: "${GPHOME_BASE:=/usr/local}"
: "${GP_NAME:=greenplum-db}"
: "${GP_VERSION:?GP_VERSION is required}"
: "${EL_VERSION:=9}"
: "${ARCH:=x86_64}"
: "${RPM_VERSION:=${GP_VERSION%%-*}}"
: "${RPM_RELEASE:=1}"

# Derived, exported so child scripts see them.
export GPHOME="${GPHOME_BASE}/${GP_NAME}-${GP_VERSION}"
export TARBALL="${TARBALL:-server-build-${GP_VERSION}-rhel${EL_VERSION}_${ARCH}.tar.gz}"

log() { printf '\033[1;34m[whpg-build]\033[0m %s\n' "$*"; }
