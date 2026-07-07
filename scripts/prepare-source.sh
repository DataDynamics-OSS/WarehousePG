#!/usr/bin/env bash
# Prepare the WarehousePG source tree for the tag, WITHOUT a .git directory,
# and drop in a VERSION file so `getversion` reports the WHPG tag deterministically.
#
# Why no .git + explicit VERSION file:
#   getversion uses `git describe` only when `.git` is a *directory*. From a
#   worktree or an archived export that check fails and it silently falls back
#   to configure's PACKAGE_VERSION (e.g. 7.0.0-beta.0). Shipping a VERSION file
#   (the documented release-tarball mechanism) makes the baked-in version exact
#   regardless of clone depth or whether the tag is annotated/lightweight.
set -euo pipefail
source "$(dirname "$0")/common.sh"

SRC="$(cd "$(dirname "$0")/.." && pwd)/output/src"
rm -rf "$SRC"
mkdir -p "$SRC"

if [[ -n "${WHPG_LOCAL_REPO:-}" ]]; then
    log "Exporting ${WHPG_TAG} from local repo ${WHPG_LOCAL_REPO}"
    SHA="$(git -C "$WHPG_LOCAL_REPO" rev-list -n1 "$WHPG_TAG")"
    git -C "$WHPG_LOCAL_REPO" archive --format=tar "$WHPG_TAG" | tar -x -C "$SRC"
else
    log "Cloning ${WHPG_TAG} from ${WHPG_REPO_URL}"
    git clone --depth 1 --branch "$WHPG_TAG" "$WHPG_REPO_URL" "$SRC"
    SHA="$(git -C "$SRC" rev-parse HEAD)"
    rm -rf "$SRC/.git"
fi

printf '%s build commit:%s\n' "$GP_VERSION" "$SHA" > "$SRC/VERSION"
log "Source ready at ${SRC}"
log "VERSION -> $(cat "$SRC/VERSION")"
