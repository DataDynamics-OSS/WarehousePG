# WarehousePG Build & Install Tooling

> 한국어 문서: [README.ko.md](README.ko.md)
>
> This repository is **not** the WarehousePG database source code. It is a set of
> tools that builds, packages, and installs WarehousePG. The database itself lives
> upstream at [warehouse-pg/warehouse-pg](https://github.com/warehouse-pg/warehouse-pg).

This repository takes **a single WarehousePG source tag and reproducibly turns it
into a server binary tarball (tar.gz), an installable RPM, and a PXF (Platform
Extension Framework) package for Rocky Linux 9**. Point it at a tag, run `make`,
and it downloads the source, compiles it inside an isolated Rocky 9 container,
and packages the result into distributable form — end to end, automatically.

The overall flow: prepare the source (`prepare-source`), compile it in a
container into a tar.gz (`build-binary`), then repackage that tar.gz as an RPM
(`build-rpm`). If you need PXF, it is built separately against a WarehousePG
installation unpacked as GPHOME (`build-pxf`).

## Repository layout

All key configuration lives in one place: `config/build.env`. That is where you
set the target tag, version strings, install paths, the container image to use,
and the PXF source. The actual work is divided among the scripts under
`scripts/`: `prepare-source.sh` exports the tag into `output/src` and plants a
version file; `build-binary.sh` runs configure/make/install and produces a
tar.gz with bundled libraries; `build-rpm.sh` turns that tar.gz into an RPM
using the `rpm/warehouse-pg.spec.in` template; and `build-pxf.sh` builds PXF
against the installed GPHOME, producing its own RPM and tar.gz. The Rocky 9
toolchain is defined in `docker/Dockerfile.rocky9`, though by default a
pre-built image is pulled. The top-level `Makefile` orchestrates everything,
and all artifacts land in `output/` (excluded from git).

An Ansible playbook that installs the built RPMs onto an actual cluster lives
in `install/` and is documented separately in
[install/README.md](install/README.md).

## Prerequisites

Docker and `git` are required. You need access to `ghcr.io` to pull the
container image and access to the WarehousePG source repository. For offline
builds, set `WHPG_LOCAL_REPO` to a local clone path to skip the network clone.
If the pre-built image cannot be pulled in your environment, `make image`
builds it locally from `docker/Dockerfile.rocky9`.

## Usage

The simplest path is `make all`, which builds both the server tar.gz and the
RPM for the tag configured in `config/build.env`. To run the steps
individually:

```bash
make image        # prepare the Rocky 9 toolchain image (pull or local build)
make binary       # -> output/artifacts/server-build-7.6.1-WHPG-rhel9_x86_64.tar.gz
make rpm          # -> output/artifacts/warehouse-pg-7.6.1-1.el9.x86_64.rpm
make verify       # unpack the tar.gz, check gp-version and library resolution
make pxf          # -> output/artifacts/pxf-gp7-6.10.1-SNAPSHOT.el9.x86_64.rpm (+ tar.gz)
```

PXF requires the WarehousePG tar.gz produced by `make binary`. To build without
network access from a local checkout, pass the path as
`make all WHPG_LOCAL_REPO=/path/to/warehouse-pg`. To repackage an RPM from an
already-built tar.gz, use `make rpm-only`. Every artifact is accompanied by a
`.sha256` checksum file in `output/artifacts/`.

## Design notes

### Why the install path drops `-devel`

Development builds conventionally install into `/usr/local/greenplum-db-devel`,
but the releases this repository produces follow the standard Greenplum/GPDB
layout: a **versioned directory plus an unversioned symlink**. The actual
install goes to `/usr/local/greenplum-db-7.6.1-WHPG`, and the RPM maintains a
`/usr/local/greenplum-db` symlink pointing at it. Users always activate with
`source /usr/local/greenplum-db/greenplum_path.sh`, and multiple versions can
sit side by side with only the symlink switching between them. The path scheme
is configurable via `GP_NAME` and `GPHOME_BASE` in `config/build.env`.

### Making sure the right version is baked into the binary

`getversion` reads the tag via `git describe` **only when `.git` is a
directory**. In a source tree exported as an archive that condition does not
hold, so configure falls back to its default (`7.0.0-beta.0`). Therefore
`prepare-source.sh` exports the tag without `.git` and plants a `VERSION` file
(`7.6.1-WHPG build commit:<sha>`) directly. This is the same official mechanism
used for release tarballs, and it makes `postgres --gp-version` report the real
tag accurately. Always build from a clean source tree — leftovers from a
previous build can bake in the wrong version.

### From tar.gz to RPM

`build-binary.sh` compiles with the versioned GPHOME as `--prefix` and then
tars up that whole tree. `build-rpm.sh` feeds the tar.gz to
`rpm/warehouse-pg.spec.in`; the spec is relocatable (`Prefix:`) and manages the
`greenplum-db` symlink in `%post`/`%postun`. Since RPM's `Version` field cannot
contain a hyphen, the numeric version (`7.6.1`) goes into the RPM field while
the full version (`7.6.1-WHPG`) is used for the install directory and the
binary version string.

### Bundled extensions

`build-binary.sh` enables `--enable-gpcloud`, so the tar.gz and RPM include the
S3 external table protocol (`s3://`, `gpcloud.so`/`gps3ext.so`, `gpcheckcloud`)
alongside the standard extensions: gp_toolkit, orafce, pg_hint_plan,
postgres_fdw, dblink, pgcrypto, plpython3u, plperl, gp_exttable_fdw, gpfdist,
plus the ORCA optimizer and IC Proxy. Note that gpperfmon was removed upstream
in WarehousePG/GPDB 7, so there is nothing to enable.

### PXF

`make pxf` builds PXF from **greenplum-db/pxf-archive** (PXF 6.x). WarehousePG 7
is PostgreSQL 12 based, and pxf-archive targets exactly that lineage (GPDB 7),
so the headers match as-is. The actively maintained `apache/cloudberry-pxf` was
tried first, but Cloudberry has moved to PostgreSQL 14 and requires PG14
headers (`common/jsonapi.h`), so it does not compile against WarehousePG 7.
pxf-archive is a frozen archive with no release tags (version 6.10.1-SNAPSHOT),
so for reproducibility the build pins the final commit SHA rather than a moving
branch.

The build installs the WarehousePG tar.gz as GPHOME, then compiles the external
table and FDW extensions (C), the CLI (Go), and the server (Java, Gradle) on
top of it. The server Gradle must run under **JDK 11** — the image's default
`javac` is 17, which the older Gradle refuses. The resulting PXF RPM
(`pxf-gp7-*.rpm`) is relocatable and installs to the standalone path
`/usr/local/pxf-gp7`, not inside GPHOME. After installation, run
`pxf cluster register` as `gpadmin` to register the extension files into the
running cluster's GPHOME, then activate with `CREATE EXTENSION pxf;` or
`CREATE EXTENSION pxf_fdw;`.

### Signing (optional)

The image includes `rpm-sign`. To sign, import your key, add
`%_gpg_name <key>` to `~/.rpmmacros`, and run
`rpm --addsign output/artifacts/*.rpm` (e.g. inside the container via
`make shell`).

## Building other tags or EL versions

To build a different tag, change `WHPG_TAG`, `GP_VERSION`, and `RPM_VERSION` in
`config/build.env` or override them on the command line, e.g.
`make all WHPG_TAG=7.4.1-WHPG GP_VERSION=7.4.1-WHPG RPM_VERSION=7.4.1`. An EL8
toolchain works the same way: specify an el8 image and `EL_VERSION=8`.

## License

The tooling in this repository is distributed under the
[Apache License 2.0](LICENSE). WarehousePG and PXF themselves are covered by
their own upstream licenses.
