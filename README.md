# WarehousePG-build

Reproducible build tooling that turns a **WarehousePG source tag** into a
**Rocky Linux 9** server tarball **and** an installable **RPM**.

```
Source tag ──► prepare-source ──► build-binary ──► tar.gz ──► build-rpm ──► .rpm
 7.5.0-WHPG      (VERSION file)      (in container)             (in container)
```

## Layout

| Path | Purpose |
|------|---------|
| `config/build.env` | All tunables (tag, version, install path, image). |
| `scripts/prepare-source.sh` | Export the tag to `output/src` + write the `VERSION` file. |
| `scripts/build-binary.sh` | `configure`/`make`/`make install`, vendor libs, produce the tarball. |
| `scripts/build-rpm.sh` | Render the spec and `rpmbuild` the tarball into an RPM. |
| `scripts/build-pxf.sh` | Build PXF against the WHPG GPHOME -> PXF rpm + tarball. |
| `rpm/warehouse-pg.spec.in` | RPM spec template (placeholders filled at build time). |
| `docker/Dockerfile.rocky9` | The Rocky 9 toolchain (Makefile pulls the prebuilt image by default). |
| `Makefile` | Orchestrator. |
| `output/` | Generated source + artifacts (git-ignored). |

## Prerequisites

- Docker
- `git`
- Network access to `ghcr.io` (prebuilt image) and to the WarehousePG source
  repo — or set `WHPG_LOCAL_REPO` to build offline from a local clone.

## Usage

```bash
# Build everything (tarball + rpm) for the tag in config/build.env
make all

# Or step by step
make image        # pull/build the Rocky 9 toolchain
make binary       # -> output/artifacts/server-build-7.5.0-WHPG-rhel9_x86_64.tar.gz
make rpm          # -> output/artifacts/warehouse-pg-7.5.0-2.el9.x86_64.rpm
make verify       # extract tarball, print `postgres --gp-version`, check libs

# Build PXF (needs the WHPG tarball from `make binary` first):
make pxf          # -> output/artifacts/pxf-gp7-6.10.1-SNAPSHOT.el9.x86_64.rpm (+ tarball)

# Offline build from a local checkout (no clone):
make all WHPG_LOCAL_REPO=/path/to/warehouse-pg

# Rebuild just the RPM from an existing tarball:
make rpm-only
```

Artifacts (with `.sha256` sidecars) land in `output/artifacts/`.

## Design notes

### Install path: `-devel` is gone
Development builds install to `/usr/local/greenplum-db-devel`. Releases here use
a **versioned** directory plus a **version-less symlink**, which is the standard
Greenplum/GPDB RPM layout:

```
/usr/local/greenplum-db-7.5.0-WHPG      <- real install (GPHOME, baked into binary)
/usr/local/greenplum-db  ->  greenplum-db-7.5.0-WHPG   <- symlink, managed by the RPM
```

Users always `source /usr/local/greenplum-db/greenplum_path.sh`, and multiple
versions can coexist. Change `GP_NAME` / `GPHOME_BASE` in `config/build.env` to
adjust (e.g. `GP_NAME=warehouse-pg`).

### Correct version gets baked in
`getversion` only consults `git describe` when `.git` is a **directory**; from an
archived export it falls back to configure's `PACKAGE_VERSION` (`7.0.0-beta.0`).
`prepare-source.sh` therefore exports the tag **without** `.git` and writes a
`VERSION` file (`7.5.0-WHPG build commit:<sha>`) — the documented release-tarball
mechanism — so `postgres --gp-version` reports the real tag. Always build from a
clean source export; a stale tree can bake the wrong version.

### tar.gz → RPM
`build-binary.sh` compiles with `--prefix=<versioned GPHOME>` and tars the tree.
`build-rpm.sh` feeds that tarball to `rpmbuild` via `rpm/warehouse-pg.spec.in`,
which is **relocatable** (`Prefix:`), fixes `GPHOME` in `greenplum_path.sh`, and
manages the `greenplum-db` symlink in `%post`/`%postun`. RPM `Version` cannot
contain `-`, so the numeric `RPM_VERSION` (`7.5.0`) is used for the RPM field
while the full `GP_VERSION` (`7.5.0-WHPG`) names the install dir and the binary.

### Bundled extensions
`build-binary.sh` enables `--enable-gpcloud`, so the tarball/RPM include the S3
external-table protocol (`s3://`, `gpcloud.so`/`gps3ext.so`, `gpcheckcloud`) on
top of the standard set (`gp_toolkit`, `orafce`, `pg_hint_plan`, `postgres_fdw`,
`dblink`, `pgcrypto`, `plpython3u`, `plperl`, `gp_exttable_fdw`, `gpfdist`,
ORCA, IC Proxy, …). Note `gpperfmon` was **removed upstream in WHPG/GPDB 7**, so
there is nothing to enable for it.

### PXF (Platform Extension Framework)
`make pxf` builds PXF from **greenplum-db/pxf-archive** (PXF 6.x). WHPG 7 is
PostgreSQL-12-based, and pxf-archive targets exactly that lineage — `apache/cloudberry-pxf`
was tried first but expects PG14 headers (`common/jsonapi.h`) because Cloudberry
has moved to PG14, so it does **not** compile against WHPG 7. The build installs
the WHPG tarball as GPHOME, then compiles the external-table + FDW C extensions
against it, the Go CLI, and the Java server (Gradle, pinned to **JDK 11** — the
image's default `javac` is 17, which the older Gradle rejects).

The PXF RPM (`pxf-gp7-*.rpm`) is relocatable and installs to `/usr/local/pxf-gp7`
(standalone, not inside GPHOME). After install, register the extensions into the
running cluster's GPHOME with `pxf cluster register` (run as `gpadmin`); then
`CREATE EXTENSION pxf;` / `CREATE EXTENSION pxf_fdw;`.

### Signing (optional)
The image includes `rpm-sign`. To sign, import your key and add
`%_gpg_name <key>` to `~/.rpmmacros`, then `rpm --addsign output/artifacts/*.rpm`
(e.g. via `make shell`).

## Building other tags / EL versions
Edit `config/build.env` (`WHPG_TAG`, `GP_VERSION`, `RPM_VERSION`) or override on
the command line: `make all WHPG_TAG=7.4.1-WHPG GP_VERSION=7.4.1-WHPG RPM_VERSION=7.4.1`.
An `EL8` toolchain works the same way with an el8 image and `EL_VERSION=8`.
