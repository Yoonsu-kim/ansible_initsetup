# Handoff Notes

This repository is being shaped into an Ansible-based generator/deployer for `initial_setup.sh`.

The user wants to manage different `initial_setup.sh` settings for ODIM, ODIL, and ODIC roles without maintaining three separate shell scripts. The selected design is:

- Store common defaults in `group_vars/all.yml`.
- Store role differences in `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, and `group_vars/role_odic.yml`.
- Merge defaults plus host overrides with Ansible `combine(..., recursive=True)`.
- Render `templates/initial_setup.sh.j2` to `initial_setup_dest`.
- Use `--check --diff` when the user wants confirmation only.
- Use `inspect_initial_setup.sh` to read and summarize a generated or existing script without executing it.

## Current Files

- `initial_setup.sh`
  - Original/manual script kept in place.
  - It is no longer the source of truth for generated output.

- `inspect_initial_setup.sh`
  - Read-only shell/awk inspector.
  - It parses a target script and prints sections for CAN pinmux command presence, module `modprobe` command presence, CAN interfaces, IRQ affinity, ethtool, VLAN/IP, route/firewall, and PTP.
  - It does not execute the target script.

- `group_vars/all.yml`
  - Main default configuration.
  - Contains `initial_setup_dest` and `initial_setup_defaults`.
  - Current configurable defaults reflect the current `initial_setup.sh` settings, with one intentional fix: generated PTP commands default to no `exec`.
  - CAN pinmux and kernel module commands are intentionally fixed in the template instead of exposed as variables.

- `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, `group_vars/role_odic.yml`
  - Contain only role-specific differences under `initial_setup_overrides`.
  - They are intentionally not complete final configs; unchanged leaf values are inherited from `initial_setup_defaults`.
  - VLAN 2 keeps common description/default gateway in `group_vars/all.yml`, while each role sets its own IP.

- `templates/initial_setup.sh.j2`
  - Generates the actual shell script from merged `initial_setup`.
  - Generates CAN-FD or classic CAN based on `can.fd`.
  - Comments out disabled IRQ affinity and PTP items.
  - Fixes the typo from the original script: `SESNOR_INTERFACE` becomes `SENSOR_INTERFACE`.

- `deploy_initial_setup.yml`
  - Renders `templates/initial_setup.sh.j2` to `initial_setup_dest`.
  - Uses:
    ```yaml
    initial_setup: "{{ initial_setup_defaults | combine(initial_setup_overrides | default({}), recursive=True) }}"
    ```

- `inventory.ini`
  - Single-set inventory. The operator passes the selected ODIM VPN IP and SSH password at runtime with `-e odim_vpn_ip=... -e ssh_pass=...`.
  - ODIL/ODIC use fixed internal IPs and SSH through ODIM with `ProxyCommand + sshpass`.
  - Hosts:
    ```ini
    [initial_setup_targets:children]
    role_odim
    role_odil
    role_odic
    ```

- `inventory_fleet.example.ini`
  - Example for deploying to many ODIM sets at once.
  - Uses unique aliases such as `car01_odim`, `car01_odil`, and `car01_odic`.
  - ODIL/ODIC keep fixed internal IPs, but each line uses the matching ODIM VPN IP through `ProxyCommand + sshpass`.

- `inventory_odim_list.example.yml`
  - Preferred fleet example when only ODIM VPN IP changes per set.
  - Operators copy this to `inventory_odim_list.yml` and list only:
    ```yaml
    odim_sets:
      car01: 10.8.0.11
      car02: 10.8.0.12
    ```
  - `odil_inner_ip` and `odic_inner_ip` are shared across sets.

- `deploy_fleet_from_odim_list.yml`
  - First play runs on localhost and creates runtime hosts with `add_host`.
  - For each `odim_sets` entry it creates `<set>_odim`, `<set>_odil`, and `<set>_odic`.
  - ODIL/ODIC use the matching ODIM VPN IP as the `ProxyCommand` jump target.
  - Imports `deploy_initial_setup.yml` after runtime hosts are created.
  - Supports `-e fleet_set=car02` or `-e fleet_set=car01,car03` to build only selected sets. This is preferred over `--limit` because the dynamic hosts do not exist before the first play runs.

- `ansible.cfg`
  - Sets Ansible temp dirs to `/tmp` because the environment could not write to `/home/blackpanther/.ansible/tmp`.

- `README.md`
  - User-facing usage guide.

## Verified

Commands that passed:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --syntax-check
ansible-playbook -i inventory_odim_list.example.yml deploy_fleet_from_odim_list.yml --syntax-check
bash -n inspect_initial_setup.sh
```

Local render test was also performed successfully:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml \
  --limit odim \
  -e odim_vpn_ip=10.8.0.11 \
  -e ssh_pass=dev \
  -e ansible_connection=local \
  -e initial_setup_dest=/tmp/initial_setup.odim.sh
```

Then:

```bash
bash -n /tmp/initial_setup.odim.sh
./inspect_initial_setup.sh /tmp/initial_setup.odim.sh
```

The generated `/tmp/initial_setup.odim.sh` inspected cleanly with no warnings.

## Important Behavioral Notes

- `--check --diff` is the intended command for "confirmation only".
- Running the playbook without `--check` writes `initial_setup_dest` on the remote host.
- Dicts are used for `can_interfaces`, `irq_affinity`, `vlans`, and `ptp.configs` so host overrides can replace only specific keys.
- Role files should override only values that differ from `group_vars/all.yml`; avoid repeating inherited defaults.
- Lists are avoided for overlay-sensitive settings because Ansible list variables are replaced wholesale.
- `ptp.use_exec` defaults to `false`.
  - The original script used two `exec /usr/local/sbin/ptp4l ... &` lines.
  - The inspector warns about multiple enabled `exec ptp4l` lines because the first `exec` can replace the shell.

## Example Override

For the ODIL role, changing the Internet VLAN IP and disabling PTP:

```yaml
initial_setup_overrides:
  vlans:
    "2":
      enabled: true
      ip: "192.168.9.102/24"

  ptp:
    enabled: false
```

For the ODIC role, changing parent interface and disabling `can1`:

```yaml
initial_setup_overrides:
  sensor_interface: "eth0"

  can_interfaces:
    can1:
      enabled: false
```

## Likely Next Steps

1. For single-set work, pass the selected ODIM VPN IP and SSH password with `-e odim_vpn_ip=... -e ssh_pass=...`.
2. For fleet work where only ODIM VPN IP differs per set, copy `inventory_odim_list.example.yml` to `inventory_odim_list.yml` and add each set under `odim_sets`.
3. For fleet work where internal IPs or jump behavior differ per set, copy `inventory_fleet.example.ini` to `inventory_fleet.ini` and add each ODIM/ODIL/ODIC alias explicitly.
4. Ask which settings differ per role, then add only those differences to `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, and `group_vars/role_odic.yml`.
5. Run for a single set:
   ```bash
   ansible-playbook -i inventory.ini deploy_initial_setup.yml -e odim_vpn_ip=10.8.0.11 -e ssh_pass=dev --check --diff
   ```
6. Or run for an ODIM IP list:
   ```bash
   ansible-playbook -i inventory_odim_list.yml deploy_fleet_from_odim_list.yml -e ssh_pass=dev --check --diff
   ```
7. If the diff is correct, apply:
   ```bash
   ansible-playbook -i inventory.ini deploy_initial_setup.yml -e odim_vpn_ip=10.8.0.11 -e ssh_pass=dev
   ```
8. Optionally verify rendered remote scripts with:
   ```bash
   ssh odim 'bash -s -- /home/odin/initial_setup.sh' < inspect_initial_setup.sh
   ```

## Caveats

- This directory did not behave as a normal Git repository during earlier checks:
  ```text
  fatal: not a git repository (or any of the parent directories): .git
  ```
  Do not assume normal Git commands work here.
- Remote connectivity has not been tested because actual odim/odil/odic connection information is not yet configured.
- The original `initial_setup.sh` remains unchanged; generated output is driven by YAML plus Jinja.
