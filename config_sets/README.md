# Config Sets

Deployments select a complete configuration set per ODIM set.

Each config set has one default file and one role override file per device role:

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
    config_set: v6_5
  car02:
    odim_ip: 10.8.0.12
    config_set: v6_5
```
