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
  - Currently contain only:
    ```yaml
    initial_setup_overrides: {}
    ```
  - Role-specific ODIM/ODIL/ODIC differences should be added here.

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

- `ansible.cfg`
  - Sets Ansible temp dirs to `/tmp` because the environment could not write to `/home/blackpanther/.ansible/tmp`.

- `README.md`
  - User-facing usage guide.

## Verified

Commands that passed:

```bash
ansible-playbook -i inventory.ini deploy_initial_setup.yml --syntax-check
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
- Lists are avoided for overlay-sensitive settings because Ansible list variables are replaced wholesale.
- `ptp.use_exec` defaults to `false`.
  - The original script used two `exec /usr/local/sbin/ptp4l ... &` lines.
  - The inspector warns about multiple enabled `exec ptp4l` lines because the first `exec` can replace the shell.

## Example Override

For the ODIL role, changing VLAN IPs and disabling PTP:

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
2. For fleet work, copy `inventory_fleet.example.ini` to `inventory_fleet.ini` and add each ODIM set with unique aliases.
3. Ask which settings differ per role, then fill in `group_vars/role_odim.yml`, `group_vars/role_odil.yml`, and `group_vars/role_odic.yml`.
4. Run:
   ```bash
   ansible-playbook -i inventory.ini deploy_initial_setup.yml -e odim_vpn_ip=10.8.0.11 -e ssh_pass=dev --check --diff
   ```
5. If the diff is correct, apply:
   ```bash
   ansible-playbook -i inventory.ini deploy_initial_setup.yml -e odim_vpn_ip=10.8.0.11 -e ssh_pass=dev
   ```
6. Optionally verify rendered remote scripts with:
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
