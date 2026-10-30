# WarehousePG 빌드·설치 도구

> English documentation: [README.md](README.md)
>
> 이 저장소는 WarehousePG **데이터베이스 본체의 소스가 아니라**, 그 빌드·패키징·설치를
> 자동화하는 도구 모음입니다. 데이터베이스 소스는 업스트림
> [warehouse-pg/warehouse-pg](https://github.com/warehouse-pg/warehouse-pg)에 있습니다.

이 저장소는 **WarehousePG 소스 태그 하나를 받아 Rocky Linux 9용 서버 바이너리(tar.gz)와 설치용 RPM, 그리고 PXF(Platform Extension Framework) 패키지까지 재현 가능하게 만들어 내는 빌드 도구 모음**입니다. 태그를 지정하고 `make`를 실행하면, 격리된 Rocky 9 컨테이너 안에서 소스를 내려받아 컴파일하고, 그 결과물을 배포 가능한 형태로 포장하는 전 과정을 자동으로 수행합니다.

전체 흐름은 다음과 같습니다. 먼저 소스를 준비하고(`prepare-source`), 컨테이너 안에서 컴파일하여 tar.gz를 만든 뒤(`build-binary`), 그 tar.gz를 다시 RPM으로 포장합니다(`build-rpm`). PXF가 필요하면 앞서 만든 WarehousePG를 GPHOME으로 설치한 상태에서 별도로 빌드합니다(`build-pxf`).

## 저장소 구성

핵심 설정은 모두 `config/build.env` 한 곳에 모여 있습니다. 여기서 대상 태그, 버전 문자열, 설치 경로, 사용할 컨테이너 이미지, PXF 소스 등을 조정합니다. 실제 작업은 `scripts/` 아래 스크립트들이 나눠 맡습니다. `prepare-source.sh`는 태그를 `output/src`로 내보내면서 버전 파일을 심고, `build-binary.sh`는 configure·make·install을 거쳐 라이브러리를 번들링한 tar.gz를 만듭니다. `build-rpm.sh`는 그 tar.gz를 `rpm/warehouse-pg.spec.in` 템플릿으로 RPM화하며, `build-pxf.sh`는 설치된 GPHOME을 기준으로 PXF를 빌드해 별도의 RPM과 tar.gz를 만들어 냅니다. Rocky 9 툴체인은 `docker/Dockerfile.rocky9`로 정의되어 있으나, 기본적으로는 미리 만들어진 이미지를 내려받아 사용합니다. 전체를 엮는 오케스트레이터는 최상위 `Makefile`이며, 생성물은 모두 `output/`(git 추적 제외)에 쌓입니다.

빌드된 RPM을 실제 클러스터에 설치하는 Ansible 플레이북은 `install/` 디렉터리에 있으며, 별도의 [install/README.md](install/README.md)에서 설명합니다.

## 사전 준비

Docker와 `git`이 필요합니다. 컨테이너 이미지를 받기 위한 `ghcr.io` 접근과 WarehousePG 소스 저장소 접근이 가능해야 하며, 오프라인으로 빌드하려면 `WHPG_LOCAL_REPO`에 로컬 클론 경로를 지정해 네트워크 클론을 건너뛸 수 있습니다. 이미지를 내려받을 수 없는 환경이라면 `make image`가 `docker/Dockerfile.rocky9`로 이미지를 직접 빌드합니다.

## 사용법

가장 간단하게는 `config/build.env`에 적힌 태그에 대해 서버 tar.gz와 RPM을 한 번에 만드는 `make all`을 실행하면 됩니다. 단계별로 나눠 실행하고 싶다면 아래처럼 각 타깃을 개별 호출할 수 있습니다.

```bash
make image        # Rocky 9 툴체인 이미지 준비(pull 또는 로컬 build)
make binary       # -> output/artifacts/server-build-7.6.1-WHPG-rhel9_x86_64.tar.gz
make rpm          # -> output/artifacts/warehouse-pg-7.6.1-1.el9.x86_64.rpm
make verify       # tar.gz를 풀어 gp-version과 라이브러리 해석 여부 확인
make pxf          # -> output/artifacts/pxf-gp7-6.10.1-SNAPSHOT.el9.x86_64.rpm (+ tar.gz)
```

PXF는 `make binary`로 만든 WarehousePG tar.gz가 있어야 빌드할 수 있습니다. 네트워크 없이 로컬 체크아웃에서 빌드하려면 `make all WHPG_LOCAL_REPO=/path/to/warehouse-pg`처럼 경로를 넘기고, 이미 만들어 둔 tar.gz에서 RPM만 다시 포장하려면 `make rpm-only`를 사용합니다. 모든 산출물에는 `.sha256` 체크섬 파일이 함께 생성되어 `output/artifacts/`에 놓입니다.

## 설계 노트

### 설치 경로에서 `-devel`을 뗀 이유

개발용 빌드는 관례적으로 `/usr/local/greenplum-db-devel`에 설치되지만, 이 저장소가 만드는 릴리스는 **버전이 박힌 디렉터리와 버전 없는 심링크**를 함께 두는 Greenplum/GPDB 표준 배치를 따릅니다. 즉 실제 설치는 `/usr/local/greenplum-db-7.6.1-WHPG`에 이뤄지고, RPM이 `/usr/local/greenplum-db`라는 심링크를 그 디렉터리로 걸어 줍니다. 사용자는 항상 `source /usr/local/greenplum-db/greenplum_path.sh`로 활성화하면 되고, 여러 버전을 나란히 두고 심링크만 바꿔 전환할 수 있습니다. 경로 규칙은 `config/build.env`의 `GP_NAME`, `GPHOME_BASE`로 바꿀 수 있습니다.

### 올바른 버전이 바이너리에 새겨지도록

`getversion`은 `.git`이 **디렉터리일 때만** `git describe`로 태그를 읽습니다. 아카이브로 내보낸 소스 트리에서는 이 조건이 성립하지 않아 configure의 기본값(`7.0.0-beta.0`)으로 후퇴합니다. 그래서 `prepare-source.sh`는 태그를 `.git` 없이 내보낸 뒤 `VERSION` 파일(`7.6.1-WHPG build commit:<sha>`)을 직접 심습니다. 이는 릴리스 tarball을 만들 때 쓰는 정식 방식이며, 덕분에 `postgres --gp-version`이 실제 태그를 정확히 보고합니다. 반드시 깨끗한 소스에서 빌드해야 하며, 이전 빌드 산물이 남은 트리에서는 엉뚱한 버전이 박힐 수 있습니다.

### tar.gz에서 RPM으로

`build-binary.sh`는 버전이 박힌 GPHOME을 `--prefix`로 삼아 컴파일한 뒤 그 트리를 통째로 tar.gz로 묶습니다. `build-rpm.sh`는 이 tar.gz를 `rpm/warehouse-pg.spec.in`에 넘겨 RPM으로 만드는데, 이 스펙은 재배치 가능(`Prefix:`)하며 `%post`/`%postun`에서 `greenplum-db` 심링크를 관리합니다. RPM의 `Version` 필드에는 하이픈을 넣을 수 없으므로, 숫자 버전(`7.6.1`)을 RPM 필드에 쓰고 전체 버전(`7.6.1-WHPG`)은 설치 디렉터리와 바이너리 버전 문자열에 사용합니다.

### 함께 담기는 확장

`build-binary.sh`는 `--enable-gpcloud`를 켜므로, tar.gz와 RPM에는 S3 외부 테이블 프로토콜(`s3://`, `gpcloud.so`/`gps3ext.so`, `gpcheckcloud`)이 표준 확장들과 함께 담깁니다. 표준 확장에는 gp_toolkit, orafce, pg_hint_plan, postgres_fdw, dblink, pgcrypto, plpython3u, plperl, gp_exttable_fdw, gpfdist를 비롯해 ORCA 옵티마이저와 IC Proxy가 포함됩니다. 참고로 gpperfmon은 WarehousePG/GPDB 7에서 업스트림 차원에서 제거되었으므로 켤 대상 자체가 없습니다.

### PXF

`make pxf`는 **greenplum-db/pxf-archive**(PXF 6.x)에서 PXF를 빌드합니다. WarehousePG 7은 PostgreSQL 12 기반이고 pxf-archive가 바로 그 계열(GPDB 7)을 대상으로 하기 때문에 헤더가 그대로 맞습니다. 처음에는 활발히 유지보수되는 `apache/cloudberry-pxf`를 시도했으나, Cloudberry가 PostgreSQL 14로 올라가면서 PG14 헤더(`common/jsonapi.h`)를 요구해 WarehousePG 7에서는 컴파일되지 않았습니다. 이 pxf-archive는 릴리스 태그가 하나도 없는 동결 아카이브(버전 6.10.1-SNAPSHOT)이므로, 재현성을 위해 움직이는 브랜치 대신 마지막 커밋 SHA에 고정해 빌드합니다.

빌드 과정에서는 WarehousePG tar.gz를 GPHOME으로 설치한 다음, 그 위에서 외부 테이블 확장과 FDW 확장(C), CLI(Go), 서버(Java, Gradle)를 컴파일합니다. 이때 서버 Gradle은 반드시 **JDK 11**로 실행해야 합니다. 이미지의 기본 `javac`가 17이라 구 버전 Gradle이 이를 거부하기 때문입니다. 산출되는 PXF RPM(`pxf-gp7-*.rpm`)은 재배치 가능하며 GPHOME 안이 아니라 독립 경로 `/usr/local/pxf-gp7`에 설치됩니다. 설치 후에는 `gpadmin` 계정으로 `pxf cluster register`를 실행해 확장 파일을 실행 중인 클러스터의 GPHOME에 등록하고, `CREATE EXTENSION pxf;` 또는 `CREATE EXTENSION pxf_fdw;`로 활성화합니다.

### 서명(선택)

이미지에는 `rpm-sign`이 포함되어 있습니다. 서명하려면 키를 임포트하고 `~/.rpmmacros`에 `%_gpg_name <key>`를 추가한 뒤 `rpm --addsign output/artifacts/*.rpm`을 실행하면 됩니다(예: `make shell`로 컨테이너에 진입).

## 다른 태그나 EL 버전으로 빌드하기

다른 태그를 빌드하려면 `config/build.env`의 `WHPG_TAG`, `GP_VERSION`, `RPM_VERSION`을 바꾸거나 명령줄에서 덮어쓰면 됩니다. 예를 들어 `make all WHPG_TAG=7.4.1-WHPG GP_VERSION=7.4.1-WHPG RPM_VERSION=7.4.1`처럼 지정할 수 있습니다. EL8 툴체인도 같은 방식으로, el8 이미지와 `EL_VERSION=8`을 지정하면 동작합니다.

## 라이선스

이 저장소의 도구는 [Apache License 2.0](LICENSE)으로 배포됩니다. WarehousePG와 PXF 본체는 각자의 업스트림 라이선스를 따릅니다.
