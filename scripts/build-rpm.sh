#!/usr/bin/env bash
# Turn the binary tarball into an installable RPM.
# Runs INSIDE the Rocky 9 build container (rpm-build/rpmdevtools are preinstalled).
# Expects /work/artifacts/${TARBALL} to already exist (run build-binary.sh first).
set -euxo pipefail
source "$(dirname "$0")/common.sh"

ART=/work/artifacts
TOP=/root/rpmbuild

[[ -f "${ART}/${TARBALL}" ]] || {
    echo "ERROR: ${ART}/${TARBALL} not found. Run build-binary.sh first." >&2
    exit 1
}

rm -rf "$TOP"
mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp "${ART}/${TARBALL}" "${TOP}/SOURCES/"

# Render the spec from the template.
sed -e "s|@GP_NAME@|${GP_NAME}|g" \
    -e "s|@GP_VERSION@|${GP_VERSION}|g" \
    -e "s|@GPHOME_BASE@|${GPHOME_BASE}|g" \
    -e "s|@RPM_VERSION@|${RPM_VERSION}|g" \
    -e "s|@RPM_RELEASE@|${RPM_RELEASE}|g" \
    -e "s|@ARCH@|${ARCH}|g" \
    -e "s|@TARBALL_NAME@|${TARBALL}|g" \
    /rpm/warehouse-pg.spec.in > "${TOP}/SPECS/warehouse-pg.spec"

rpmbuild -bb --define "_topdir ${TOP}" "${TOP}/SPECS/warehouse-pg.spec"

cp "${TOP}/RPMS/${ARCH}/"*.rpm "$ART/"
( cd "$ART" && for f in *.rpm; do sha256sum "$f" > "${f}.sha256"; done )

log "RPM(s) built:"
ls -1 "${ART}/"*.rpm
