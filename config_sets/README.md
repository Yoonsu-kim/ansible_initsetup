# Config Sets

Fleet deployments can select a complete configuration set per ODIM set.

Each config set mirrors the normal `group_vars` layout:

```text
config_sets/<set_name>/
  all.yml
  role_odim.yml
  role_odil.yml
  role_odic.yml
```

Use `inventory_odim_list.yml` to map a vehicle to a config set:

```yaml
odim_sets:
  car01:
    odim_ip: 10.8.0.11
    config_set: group_vars
  car02:
    odim_ip: 10.8.0.12
    config_set: group_vars2
```

`group_vars/` remains available for the single-set inventory path.
