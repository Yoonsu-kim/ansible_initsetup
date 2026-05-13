# ansible_initialsetup

`initial_setup.sh`를 장비별로 생성하고 배포하기 위한 Ansible 구성입니다.

기본 설정은 `group_vars/all.yml`에 두고, A/B/C 장비별 차이는 `host_vars/<host>.yml`의 `initial_setup_overrides`에 필요한 값만 overlay합니다.

## 파일 구조

```text
ansible.cfg
inventory.ini
deploy_initial_setup.yml
group_vars/all.yml
host_vars/A.yml
host_vars/B.yml
host_vars/C.yml
templates/initial_setup.sh.j2
inspect_initial_setup.sh
initial_setup.sh
```

- `group_vars/all.yml`: 모든 장비에 적용되는 기본 설정
- `host_vars/A.yml`, `host_vars/B.yml`, `host_vars/C.yml`: 장비별 override 설정
- `templates/initial_setup.sh.j2`: `initial_setup.sh` 생성 템플릿
- `deploy_initial_setup.yml`: 원격 장비에 `initial_setup.sh`를 생성/배포하는 playbook
- `inspect_initial_setup.sh`: 생성된 `initial_setup.sh`를 실행하지 않고 읽기 전용으로 검사하는 스크립트
- `initial_setup.sh`: 기존 수동 스크립트

## Inventory 설정

`inventory.ini`의 A/B/C를 실제 접속 정보에 맞게 수정합니다.

```ini
[initial_setup_targets]
A ansible_host=192.168.0.10 ansible_user=odin
B ansible_host=192.168.0.11 ansible_user=odin
C ansible_host=192.168.0.12 ansible_user=odin
```

SSH key를 쓰지 않고 비밀번호를 입력해야 하면 실행 시 `--ask-pass`를 붙입니다.

## 기본 설정 수정

공통 기본값은 `group_vars/all.yml`에서 수정합니다.

주요 항목:

- `initial_setup_dest`: 원격 장비에 생성할 스크립트 경로
- `can_pinmux`: CAN pinmux `busybox devmem` 설정
- `kernel_modules`: `modprobe` 대상
- `can_interfaces`: CAN/CAN-FD 인터페이스 설정
- `irq_affinity`: interrupt CPU affinity 설정
- `ethtool`: local network throughput 설정
- `sensor_interface`: VLAN parent interface
- `vlans`: VLAN ID, IP, gateway, firewall rule
- `ptp`: PTP 실행 여부와 `ptp4l` config/log 경로

## 장비별 Override

장비별로 다른 값만 `host_vars/<host>.yml`에 적습니다.

예: B 장비의 일부 VLAN IP만 변경하고 PTP를 끄는 경우

```yaml
initial_setup_overrides:
  vlans:
    "30":
      ip: "10.30.1.208/24"
    "31":
      ip: "10.31.1.208/24"

  ptp:
    enabled: false
```

예: C 장비에서 sensor interface를 `eth0`로 바꾸고 `can1`을 비활성화하는 경우

```yaml
initial_setup_overrides:
  sensor_interface: "eth0"

  can_interfaces:
    can1:
      enabled: false
```

`initial_setup_overrides`는 `initial_setup_defaults` 위에 recursive merge됩니다.

## 변경 사항 확인만 하기

실제 원격 파일을 바꾸지 않고 어떤 차이가 날지 확인합니다.

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --check --diff
```

특정 장비만 확인하려면:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --limit A --check --diff
```

## 실제 적용

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml
```

특정 장비만 적용:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --limit B
```

비밀번호 인증이 필요하면:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --ask-pass
```

## 로컬 렌더링 테스트

원격 장비에 배포하지 않고 A 설정 기준으로 `/tmp`에 생성해 볼 수 있습니다.

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit A \
  -e ansible_connection=local \
  -e initial_setup_dest=/tmp/initial_setup.A.sh
```

문법 확인:

```bash
bash -n /tmp/initial_setup.A.sh
```

읽기 전용 설정 검사:

```bash
./inspect_initial_setup.sh /tmp/initial_setup.A.sh
```

## 기존 스크립트 검사

기존 `initial_setup.sh`를 실행하지 않고 설정만 확인합니다.

```bash
./inspect_initial_setup.sh initial_setup.sh
```

검사 항목:

- CAN pinmux 설정
- kernel module 설정
- CAN/CAN-FD interface 설정
- interrupt CPU affinity 설정
- ethtool 설정
- VLAN ID와 interface별 IP
- route/firewall 설정
- PTP 실행 여부
- 중복 CAN 설정이나 `exec ptp4l` 사용 같은 warning

## 원격 스크립트 검사

원격 A 장비의 기존 스크립트를 실행하지 않고 검사하려면:

```bash
ssh A 'bash -s -- /home/odin/initial_setup.sh' < inspect_initial_setup.sh
```

A에서 B/C로만 접근 가능한 구조라면 A를 통해 검사합니다.

```bash
ssh A 'ssh B "bash -s -- /home/odin/initial_setup.sh" < ./inspect_initial_setup.sh'
ssh A 'ssh C "bash -s -- /home/odin/initial_setup.sh" < ./inspect_initial_setup.sh'
```

## 주의 사항

- `--check --diff`는 확인용이며 실제 파일을 변경하지 않습니다.
- `deploy_initial_setup.yml`을 `--check` 없이 실행하면 `initial_setup_dest` 경로의 파일을 생성 또는 갱신합니다.
- list 형태 변수는 부분 overlay가 어렵기 때문에 VLAN, CAN, PTP 설정은 dict 형태로 관리합니다.
- PTP는 기본값에서 `exec`를 사용하지 않도록 생성합니다. `exec ... &`를 여러 줄 쓰면 첫 번째 `exec`가 shell을 대체할 수 있어 의도와 다르게 동작할 수 있습니다.
