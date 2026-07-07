SHELL := /bin/bash

# Pull in KEY=value settings (valid make syntax).
include config/build.env

GPHOME  := $(GPHOME_BASE)/$(GP_NAME)-$(GP_VERSION)
TARBALL := server-build-$(GP_VERSION)-rhel$(EL_VERSION)_$(ARCH).tar.gz
ROOT    := $(shell pwd)

# Environment forwarded into the container (config/ is not mounted there).
ENVS := \
  -e GP_VERSION=$(GP_VERSION) -e RPM_VERSION=$(RPM_VERSION) \
  -e RPM_RELEASE=$(RPM_RELEASE) -e GPHOME_BASE=$(GPHOME_BASE) \
  -e GP_NAME=$(GP_NAME) -e EL_VERSION=$(EL_VERSION) -e ARCH=$(ARCH) \
  -e TARBALL=$(TARBALL) \
  -e PXF_REPO_URL=$(PXF_REPO_URL) -e PXF_REF=$(PXF_REF) -e GO_VERSION=$(GO_VERSION)

# Named volume keeps ccache warm across runs (much faster rebuilds).
DOCKER_RUN := docker run --rm --privileged \
  -v $(ROOT)/output:/work \
  -v $(ROOT)/scripts:/scripts:ro \
  -v $(ROOT)/rpm:/rpm:ro \
  -v whpg-ccache:/root/.ccache \
  $(ENVS) $(IMAGE)

.PHONY: all image source binary rpm rpm-only pxf verify shell clean

## all: image + source + binary tarball + rpm
all: rpm

## image: pull (or locally build) the Rocky 9 toolchain image
image:
	docker pull $(IMAGE) || docker build -t $(IMAGE) -f docker/Dockerfile.rocky9 docker

## source: export the tag into output/src and write the VERSION file
source:
	WHPG_LOCAL_REPO=$(WHPG_LOCAL_REPO) bash scripts/prepare-source.sh

## binary: compile and produce output/artifacts/$(TARBALL)
binary: source
	$(DOCKER_RUN) bash /scripts/build-binary.sh

## rpm: build the binary tarball (if needed) then the RPM
rpm: binary rpm-only

## rpm-only: build only the RPM from an existing tarball (skips compile)
rpm-only:
	$(DOCKER_RUN) bash /scripts/build-rpm.sh

## pxf: build PXF (apache/cloudberry-pxf) against the WHPG tarball -> pxf rpm + tarball
pxf:
	$(DOCKER_RUN) bash /scripts/build-pxf.sh

## verify: extract the tarball in a throwaway container and print the version
verify:
	$(DOCKER_RUN) bash -lc '\
	  mkdir -p /tmp/v && tar xzf /work/artifacts/$(TARBALL) -C /tmp/v && \
	  sed -i "s|GPHOME=.*|GPHOME=/tmp/v|" /tmp/v/greenplum_path.sh && \
	  source /tmp/v/greenplum_path.sh && postgres --gp-version && \
	  (ldd /tmp/v/bin/postgres | grep -i "not found" || echo "all libs resolved")'

## shell: drop into the build container for debugging
shell:
	$(DOCKER_RUN) bash

## clean: remove all build output
clean:
	rm -rf output/*
