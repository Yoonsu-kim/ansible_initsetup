# Handoff Notes

This repository generates and deploys `initial_setup.sh` from Ansible-managed config sets.

The current design uses `config_sets/<set_name>/` as the only configuration source of truth:

- Store common defaults in `config_sets/<set_name>/all.yml`.
- Store role differences in `config_sets/<set_name>/role_odim.yml`, `role_odil.yml`, and `role_odic.yml`.
- Merge defaults plus role overrides with Ansible `combine(..., recursive=True)`.
- Render `templates/initial_setup.sh.j2` to `initial_setup_dest`.
- Use `--check --diff` when the operator wants confirmation only.
- Use `inspect_initial_setup.sh` to read and summarize a generated or existing script without executing it.

Ansible automatic `group_vars/` and `host_vars/` configuration paths have been removed to avoid drift with `config_sets/`.

## Current Files

- `initial_setup.sh`
  - Original/manual script kept in place.
  - It is no longer the source of truth for generated output.

- `inspect_initial_setup.sh`
  - Read-only shell/awk inspector.
  - It parses a target script and prints sections for CAN pinmux command presence, module `modprobe` command presence, CAN interfaces, IRQ affinity, ethtool, VLAN/IP, route/firewall, and PTP.
  - It does not execute the target script.

- `config_sets/<set_name>/all.yml`
  - Main default configuration for a config set.
  - Contains `initial_setup_dest` and `initial_setup_defaults`.

- `config_sets/<set_name>/role_odim.yml`, `role_odil.yml`, `role_odic.yml`
  - Contain only role-specific differences under `initial_setup_overrides`.
  - They are intentionally not complete final configs; unchanged leaf values are inherited from `initial_setup_defaults`.

- `templates/initial_setup.sh.j2`
  - Generates the actual shell script from merged `initial_setup`.
  - Generates CAN-FD or classic CAN based on `can.fd`.
  - Comments out disabled IRQ affinity and PTP items.

- `deploy_initial_setup.yml`
  - Requires `initial_setup_config_set` and `initial_setup_config_role`.
  - Loads:
    ```text
    config_sets/{{ initial_setup_config_set }}/all.yml
    config_sets/{{ initial_setup_config_set }}/{{ initial_setup_config_role }}.yml
    ```
  - Then uses:
    ```yaml
    initial_setup: "{{ initial_setup_defaults | combine(initial_setup_overrides | default({}), recursive=True) }}"
    ```

- `inventory.ini`
  - Single-set inventory. The operator passes the selected ODIM VPN IP, SSH password, and config set at runtime.
  - ODIL/ODIC use fixed internal IPs and SSH through ODIM with `ProxyCommand + sshpass`.
  - Role groups define `initial_setup_config_role`.

- `inventory_odim_list.yml`
  - Preferred fleet inventory when only ODIM VPN IP changes per target.
  - Each `odim_sets` item provides `odim_ip` and `config_set`.

- `deploy_fleet_from_odim_list.yml`
  - First play runs on localhost and creates runtime hosts with `add_host`.
  - For each `odim_sets` entry it creates `<set>_odim`, `<set>_odil`, and `<set>_odic`.
  - ODIL/ODIC use the matching ODIM VPN IP as the `ProxyCommand` jump target.
  - Each generated host receives `initial_setup_config_set` and `initial_setup_config_role`.
  - Validates `fleet_set` names before generating hosts.
  - Imports `deploy_initial_setup.yml` after runtime hosts are created.

- `ansible.cfg`
  - Sets Ansible temp dirs to `/tmp`.

- `README.md`
  - User-facing usage guide.

## Verified

Commands that should pass after this cleanup:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --syntax-check
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml --syntax-check
ansible-playbook -i inventory_odim_list.example.yml deploy_fleet_from_odim_list.yml --syntax-check
bash -n inspect_initial_setup.sh
```

Local render test pattern:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit odim \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  -e initial_setup_config_set=v6_5 \
  -e ansible_connection=local \
  -e initial_setup_dest=/tmp/initial_setup.odim.sh
```

Then:

```bash
bash -n /tmp/initial_setup.odim.sh
./inspect_initial_setup.sh /tmp/initial_setup.odim.sh
```

## Important Behavioral Notes

- `--check --diff` is the intended command for confirmation only.
- Running the playbook without `--check` writes `initial_setup_dest` on the remote host.
- Dicts are used for `can_interfaces`, `irq_affinity`, `vlans`, and `ptp.configs` so role overrides can replace only specific keys.
- Role files should override only values that differ from `config_sets/<set_name>/all.yml`; avoid repeating inherited defaults.
- Lists are avoided for overlay-sensitive settings because Ansible list variables are replaced wholesale.
- `ptp.use_exec` defaults to `false`.

## Common Commands

Single target set through `inventory.ini`:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  -e initial_setup_config_set=v6_5 \
  --check --diff
```

Fleet target selection:

```bash
ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml \
  -e ssh_pass=dev \
  -e fleet_set=target01 \
  --check --diff
```

## Caveats

- Remote connectivity has not been tested unless noted in the current session.
- The original `initial_setup.sh` remains unchanged; generated output is driven by YAML plus Jinja.
