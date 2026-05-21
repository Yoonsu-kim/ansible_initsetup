# ansible_initialsetup

`initial_setup.sh`를 장비별로 생성하고 배포하기 위한 Ansible 구성입니다.

기본 설정은 `group_vars/all.yml`에 두고, ODIM/ODIL/ODIC 역할별 차이는 `group_vars/role_<role>.yml`의 `initial_setup_overrides`에 필요한 값만 overlay합니다. 역할별 파일은 최종 설정 전체가 아니라 공통값과 다른 부분만 담습니다.

## 파일 구조

```text
ansible.cfg
inventory.ini
inventory_fleet.example.ini
inventory_odim_list.example.yml
deploy_initial_setup.yml
deploy_fleet_from_odim_list.yml
group_vars/all.yml
group_vars/role_odim.yml
group_vars/role_odil.yml
group_vars/role_odic.yml
templates/initial_setup.sh.j2
inspect_initial_setup.sh
initial_setup.sh
```

- `group_vars/all.yml`: 모든 장비에 적용되는 기본 설정
- `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, `group_vars/role_odic.yml`: ODIM/ODIL/ODIC 역할별 override 설정
- `inventory.ini`: ODIM VPN IP 하나를 넘겨 한 세트만 작업하는 inventory
- `inventory_odim_list.example.yml`: ODIM IP 목록만으로 여러 세트를 작업하는 inventory 예시
- `inventory_fleet.example.ini`: host alias를 직접 나열하는 fleet inventory 예시
- `templates/initial_setup.sh.j2`: `initial_setup.sh` 생성 템플릿
- `deploy_initial_setup.yml`: 원격 장비에 `initial_setup.sh`를 생성/배포하는 playbook
- `deploy_fleet_from_odim_list.yml`: ODIM IP 목록에서 ODIM/ODIL/ODIC host를 생성한 뒤 배포하는 playbook
- `inspect_initial_setup.sh`: 생성된 `initial_setup.sh`를 실행하지 않고 읽기 전용으로 검사하는 스크립트
- `initial_setup.sh`: 기존 수동 스크립트

## Inventory 설정

두 가지 방식을 같이 지원합니다.

### 한 세트만 작업

`inventory.ini`는 ODIM VPN IP와 SSH 비밀번호를 실행 시 넘기는 방식입니다. ODIL/ODIC은 ODIM을 jump host로 타고 접속하며, `ProxyCommand + sshpass`로 비밀번호 인증을 처리합니다.

```ini
[initial_setup_targets:children]
role_odim
role_odil
role_odic

[role_odim]
odim ansible_host="{{ odim_vpn_ip | mandatory }}" ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}"

[role_odil]
odil ansible_host=192.168.0.21 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null odin@{{ odim_vpn_ip | mandatory }}"'

[role_odic]
odic ansible_host=192.168.0.22 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null odin@{{ odim_vpn_ip | mandatory }}"'
```

실행할 때 대상 ODIM VPN IP와 SSH 비밀번호를 지정합니다.

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev
```

### ODIM IP 목록으로 여러 세트 작업

ODIM의 VPN IP만 세트별로 다르고, ODIM에 접속한 뒤 ODIL/ODIC으로 들어가는 내부 IP가 모든 세트에서 같다면 이 방식을 사용합니다.

`inventory_odim_list.example.yml`을 복사해서 실제 목록을 만듭니다.

```bash
cp inventory_odim_list.example.yml inventory_odim_list.yml
```

예:

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
  children:
    initial_setup_targets:
      children:
        role_odim:
        role_odil:
        role_odic:
  vars:
    odil_inner_ip: 192.168.31.7
    odic_inner_ip: 192.168.31.8

    odim_sets:
      car01: 10.8.0.11
      car02: 10.8.0.12
      car03: 10.8.0.13
```

전체 세트 확인:

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev \
  --check --diff
```

전체 세트 적용:

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev
```

특정 세트만 확인하거나 적용하려면 `fleet_set`에 세트 이름을 지정합니다.

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev \
  -e fleet_set=car02 \
  --check --diff
```

여러 세트만 선택할 수도 있습니다.

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev \
  -e fleet_set=car01,car03
```

이 playbook은 실행 중에 다음 host를 생성합니다.

```text
car01_odim -> 10.8.0.11
car01_odil -> 192.168.31.7 via car01 ODIM
car01_odic -> 192.168.31.8 via car01 ODIM
```

역할별 설정은 기존처럼 `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, `group_vars/role_odic.yml`가 적용됩니다.

제어 PC에 `sshpass`가 설치되어 있어야 합니다. ODIM/ODIL/ODIC의 SSH 비밀번호가 같다는 전제로 `ssh_pass` 하나를 사용합니다.

### Host alias를 직접 나열하는 fleet inventory

세트별로 ODIL/ODIC 내부 IP나 접속 방식까지 다르면 `inventory_fleet.example.ini`를 복사해서 차량별 alias를 직접 추가할 수 있습니다.

```ini
[initial_setup_targets:children]
role_odim
role_odil
role_odic

[role_odim]
car01_odim ansible_host=10.8.0.11 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}"
car02_odim ansible_host=10.8.0.12 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}"

[role_odil]
car01_odil ansible_host=192.168.0.21 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p odin@10.8.0.11"'
car02_odil ansible_host=192.168.0.21 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p odin@10.8.0.12"'

[role_odic]
car01_odic ansible_host=192.168.0.22 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p odin@10.8.0.11"'
car02_odic ansible_host=192.168.0.22 ansible_user=odin ansible_password="{{ ssh_pass | mandatory }}" ansible_ssh_common_args='-o ProxyCommand="sshpass -p {{ ssh_pass | mandatory }} ssh -W %h:%p odin@10.8.0.12"'
```

## 기본 설정 수정

공통 기본값은 `group_vars/all.yml`에서 수정합니다.

주요 항목:

- `initial_setup_dest`: 원격 장비에 생성할 스크립트 경로
- `can_interfaces`: CAN/CAN-FD 인터페이스 설정
- `irq_affinity`: interrupt CPU affinity 설정
- `ethtool`: local network throughput 설정
- `sensor_interface`: VLAN parent interface
- `vlans`: VLAN ID, IP, gateway, firewall rule
- `ptp`: PTP 실행 여부와 `ptp4l` config/log 경로

## 장비별 Override

ODIM/ODIL/ODIC 역할별로 다른 값은 `group_vars/role_<role>.yml`에 적습니다. 이 방식은 단일 세트 inventory와 fleet inventory에서 같은 override를 공유합니다.

`initial_setup_overrides`는 `initial_setup_defaults` 위에 recursive merge됩니다. 따라서 role 파일에는 바꾸려는 leaf 값만 적습니다. 예를 들어 VLAN 2의 description/default gateway는 공통값을 상속하고, 역할별 파일에는 장비별 IP만 둡니다.

예: odil 장비의 Internet VLAN IP만 변경하고 일부 VLAN과 PTP를 끄는 경우

```yaml
initial_setup_overrides:
  vlans:
    "2":
      enabled: true
      ip: "192.168.9.102/24"
    "31":
      enabled: false

  ptp:
    enabled: false
```

예: odic 장비에서 sensor interface를 `eth0`로 바꾸고 `can1`을 비활성화하는 경우

```yaml
initial_setup_overrides:
  sensor_interface: "eth0"

  can_interfaces:
    can1:
      enabled: false
```

fleet inventory에서 특정 차량 하나만 다른 설정이 필요하면 `host_vars/car01_odil.yml`처럼 alias와 같은 이름의 host_vars 파일을 추가합니다.

## 변경 사항 확인만 하기

실제 원격 파일을 바꾸지 않고 어떤 차이가 날지 확인합니다.

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  --check --diff
```

특정 장비만 확인하려면:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit odim \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  --check --diff
```

ODIM IP 목록 inventory에서 특정 세트만 확인하려면:

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev \
  -e fleet_set=car01 \
  --check --diff
```

## 실제 적용

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev
```

특정 장비만 적용:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit odil \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev
```

ODIM IP 목록 inventory 전체 적용:

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev
```

## 로컬 렌더링 테스트

원격 장비에 배포하지 않고 odim 설정 기준으로 `/tmp`에 생성해 볼 수 있습니다.

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit odim \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  -e ansible_connection=local \
  -e initial_setup_dest=/tmp/initial_setup.odim.sh
```

문법 확인:

```bash
bash -n /tmp/initial_setup.odim.sh
```

읽기 전용 설정 검사:

```bash
./inspect_initial_setup.sh /tmp/initial_setup.odim.sh
```

## 기존 스크립트 검사

기존 `initial_setup.sh`를 실행하지 않고 설정만 확인합니다.

```bash
./inspect_initial_setup.sh initial_setup.sh
```

검사 항목:

- CAN pinmux 명령 존재 여부
- kernel module `modprobe` 명령 존재 여부
- CAN/CAN-FD interface 설정
- interrupt CPU affinity 설정
- ethtool 설정
- VLAN ID와 interface별 IP
- route/firewall 설정
- PTP 실행 여부
- 중복 CAN 설정이나 `exec ptp4l` 사용 같은 warning

## 원격 스크립트 검사

원격 odim 장비의 기존 스크립트를 실행하지 않고 검사하려면:

```bash
ssh odim 'bash -s -- /home/odin/initial_setup.sh' < inspect_initial_setup.sh
```

odim에서 odil/odic로만 접근 가능한 구조라면 odim을 통해 검사합니다.

```bash
ssh odim 'ssh odil "bash -s -- /home/odin/initial_setup.sh" < ./inspect_initial_setup.sh'
ssh odim 'ssh odic "bash -s -- /home/odin/initial_setup.sh" < ./inspect_initial_setup.sh'
```

## 주의 사항

- `--check --diff`는 확인용이며 실제 파일을 변경하지 않습니다.
- `deploy_initial_setup.yml`을 `--check` 없이 실행하면 `initial_setup_dest` 경로의 파일을 생성 또는 갱신합니다.
- list 형태 변수는 부분 overlay가 어렵기 때문에 VLAN, CAN, PTP 설정은 dict 형태로 관리합니다.
- PTP는 기본값에서 `exec`를 사용하지 않도록 생성합니다. `exec ... &`를 여러 줄 쓰면 첫 번째 `exec`가 shell을 대체할 수 있어 의도와 다르게 동작할 수 있습니다.
