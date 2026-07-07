#!/usr/bin/env bash
# Build the WarehousePG server and package it as a relocatable tarball.
# Runs INSIDE the Rocky 9 build container. Expects:
#   /work/src        - prepared source tree (from prepare-source.sh, contains VERSION)
#   /work/artifacts  - output directory (created here)
set -euxo pipefail
source "$(dirname "$0")/common.sh"

SRC=/work/src
ART=/work/artifacts
mkdir -p "$ART"
rm -rf "$GPHOME"

# Some build steps expect /usr/bin/pytest
if [[ ! -e /usr/bin/pytest && -e /usr/bin/pytest-3 ]]; then
    ln -s /usr/bin/pytest-3 /usr/bin/pytest || true
fi

cd "$SRC"
log "Building $(cat VERSION 2>/dev/null || echo "${GP_VERSION}") -> ${GPHOME}"

# Configure flags mirror the upstream CI (.github/workflows/whpg-ci.yml),
# minus test-only options. Prefix is the FINAL, versioned GPHOME.
CC='ccache gcc -m64' \
CFLAGS='-O2 -g3' LDFLAGS='-Wl,--enable-new-dtags -Wl,--export-dynamic' \
./configure --disable-gpperfmon --with-gssapi --enable-mapreduce --enable-orafce \
            --enable-ic-proxy --enable-orca --with-libxml --with-uuid=e2fs \
            --with-pgport=5432 --with-llvm --with-perl --with-python --with-openssl \
            --with-pam --with-ldap --with-includes="" --with-libraries="" \
            --disable-rpath \
            --prefix="$GPHOME" --mandir="$GPHOME/man"

make -j"$(nproc)"
make -j"$(nproc)" install

# Vendor shared libs (xerces-c, LLVM) so the tree is self-contained.
declare -a library_search_path vendored_libs
library_search_path+=($(cat /etc/ld.so.conf.d/*.conf 2>/dev/null | grep -v '#' || true))
library_search_path+=(/lib64 /usr/lib64 /lib /usr/lib)
vendored_libs=(libxerces-c{,-3.1,-3.2}.so libLLVM{,-15,-15.0.7,-16,-17}.so)
mkdir -p "${GPHOME}/lib"
for path in "${library_search_path[@]}"; do
    [[ -d "$path" ]] || continue
    for lib in "${vendored_libs[@]}"; do
        find -L "$path" -name "$lib" -exec cp -avn '{}' "${GPHOME}/lib" \; 2>/dev/null || true
    done
done

# Package: tar the CONTENTS of GPHOME (./bin ./lib ...), matching upstream's
# compile_gpdb.bash export_gpdb.
cd "$GPHOME"
chmod -R 755 .
find . -type f \( -iname '*.pyc' -o -iname '*.pyo' \) -delete
tar -czf "${ART}/${TARBALL}" ./*
cp "${ART}/${TARBALL}" "${ART}/bin_gpdb.tar.gz"
( cd "$ART" && sha256sum "$TARBALL" > "${TARBALL}.sha256" )

log "Binary tarball: ${ART}/${TARBALL}"
"${GPHOME}/bin/postgres" --gp-version || true
ls -lh "$ART"
