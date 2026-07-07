# WarehousePG · PXF 설치 플레이북

이 디렉터리는 앞서 빌드한 WarehousePG 서버 RPM과 PXF RPM을 여러 노드에 설치하기 위한 Ansible 플레이북입니다. 운영체제를 준비하고 `gpadmin` 계정과 노드 간 무암호 SSH를 구성한 뒤, WarehousePG와 PXF 패키지를 설치하는 것까지를 한 번에 처리합니다. 필요하다면 `gpinitsystem`으로 클러스터를 초기화하고 PXF를 등록·기동하는 단계까지 선택적으로 이어서 실행할 수 있습니다.

## 구성

전체를 엮는 진입점은 `site.yml`이고, 실제 작업은 `roles/` 아래 일곱 개의 역할이 나눠 맡습니다. `common`은 SELinux 비활성화와 커널 파라미터(`sysctl`), 리소스 한계(`limits`) 같은 운영체제 준비를 담당하고, `chrony`는 모든 노드의 시각을 NTP로 맞추고 타임존을 설정합니다. `firewall`은 firewalld에서 클러스터 노드 간 트래픽을 허용하고 클라이언트 포트를 개방합니다. `gpadmin`은 전용 계정과 sudo 권한을 만들고, `ssh_exchange`는 모든 노드에서 gpadmin 키를 만들어 서로의 공개키를 교차 등록하는 방식으로 노드 간 무암호 SSH를 구성합니다. `warehouse_pg`와 `pxf`는 각각 서버와 PXF RPM을 설치하고 소유권·환경변수를 정리하며, 마지막 `cluster_init`은 선택 단계로 클러스터 초기화와 PXF 등록을 수행합니다. 설치에 사용할 값들은 모두 `group_vars/all.yml` 한 곳에 모여 있습니다.

시간 동기화는 세그먼트 간 시계 오차가 운영에 문제를 일으킬 수 있어 별도 역할로 두었고, 기본 NTP 서버와 타임존은 `group_vars/all.yml`에서 바꿀 수 있습니다. 방화벽은 인터커넥트가 동적 UDP 포트를 쓰는 특성상 포트를 일일이 여는 대신 클러스터 노드 소스에 대해 전체 트래픽을 허용하는 방식을 택했으며, 여기에 더해 클라이언트용으로 코디네이터 포트(5432)와 PXF 서비스 포트(5888)를 개방합니다. 클러스터 노드를 자동으로 신뢰 소스로 잡을 때는 인벤토리의 `ansible_host` 값을 사용하므로, 그 값이 호스트명이라면 `firewall_extra_sources`에 대역(CIDR)을 직접 지정하는 편이 안전합니다. 방화벽이나 시간 동기화를 건너뛰려면 `configure_firewall`, `configure_chrony`를 각각 꺼 두면 됩니다.

## 사전 준비

제어 노드(플레이북을 실행하는 곳)에는 Ansible과, 비밀번호 해시 생성을 위한 `passlib`가 필요합니다. 필요한 컬렉션은 `ansible-galaxy collection install -r requirements.yml`로 설치합니다. 설치할 RPM 두 개는 `files/` 디렉터리에 두고, 파일명을 `group_vars/all.yml`의 `whpg_rpm_file`, `pxf_rpm_file`과 맞추면 됩니다. 사내 저장소나 릴리스에서 내려받아 설치하려면 파일 대신 `whpg_rpm_url`, `pxf_rpm_url`에 다운로드 주소를 지정할 수도 있으며, 이 경우 URL이 파일보다 우선합니다.

대상 노드는 `inventory/hosts.ini`에 정의합니다. 예시에는 코디네이터 한 대, 대기 코디네이터 한 대, 세그먼트 두 대가 들어 있으며, 모든 노드가 `whpg_cluster` 그룹으로 묶여 공통 준비와 설치의 대상이 됩니다. 클러스터 내부에서 노드끼리 서로를 부르는 이름은 `/etc/hosts`나 DNS로 해석되도록 미리 맞춰 두는 것이 좋습니다.

## 실행

가장 기본은 전체 플레이북을 그대로 실행하는 것입니다.

```bash
cd install
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml
```

부분만 실행하고 싶을 때는 태그를 활용합니다. 운영체제 준비와 계정·SSH 구성만 하려면 `--tags os`, 패키지 설치만 하려면 `--tags install`을 지정합니다. PXF를 빼고 서버만 설치하려면 `-e install_pxf=false`로 끌 수 있습니다.

```bash
ansible-playbook site.yml --tags os        # OS 준비 + 시간동기화 + 방화벽 + gpadmin + SSH
ansible-playbook site.yml --tags time      # chrony(시간 동기화)만
ansible-playbook site.yml --tags firewall  # 방화벽 포트 개방만
ansible-playbook site.yml --tags install   # WarehousePG + PXF 설치
ansible-playbook site.yml -e install_pxf=false
```

## 설치 결과

플레이북이 끝나면 모든 노드에 WarehousePG가 `/usr/local/greenplum-db-7.5.0-WHPG`로 설치되고 `/usr/local/greenplum-db` 심링크가 걸립니다. gpadmin 로그인 셸에서는 `greenplum_path.sh`가 자동으로 로드되어 `postgres --gp-version`으로 버전을 확인할 수 있습니다. PXF는 `/usr/local/pxf-gp7`에 설치되고 gpadmin 환경에 `PXF_HOME`, `PXF_BASE`, `PATH`가 설정되어 `pxf version`이 동작합니다. 다만 이 시점까지는 패키지 설치만 이뤄진 상태이며, 데이터베이스 클러스터는 아직 초기화되지 않았습니다.

## 클러스터 초기화(선택)

`gpinitsystem`은 데이터 디렉터리를 만들고 세그먼트를 배치하는 파괴적인 작업이므로 기본적으로 꺼져 있습니다. `group_vars/all.yml`에서 코디네이터·세그먼트의 데이터 디렉터리와 포트, 미러 사용 여부를 검토한 뒤, 준비가 되면 다음처럼 초기화 단계를 켜서 실행합니다.

```bash
ansible-playbook site.yml -e init_cluster=true
```

이 단계는 코디네이터 노드에서 `gpinitsystem`을 실행해 클러스터를 만들고, PXF가 설치되어 있으면 이어서 `pxf cluster register`로 확장을 GPHOME에 배포한 뒤 `pxf cluster prepare`와 `pxf cluster start`로 PXF를 기동합니다. 초기화가 끝나면 psql에 접속해 `CREATE EXTENSION pxf;` 또는 `CREATE EXTENSION pxf_fdw;`로 확장을 활성화하면 됩니다.

## 주의

예시의 gpadmin 초기 비밀번호(`changeme`)는 설치 후 반드시 변경하세요. 커널 파라미터의 `vm.overcommit_ratio`는 스왑 구성에 따라 조정이 필요할 수 있고, `sysctl`의 공유메모리 값은 호스트 전체 메모리에서 자동으로 계산됩니다. 운영 환경에 적용하기 전에 테스트 노드에서 한 번 검증할 것을 권장합니다.
