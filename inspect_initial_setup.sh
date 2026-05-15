#!/usr/bin/env bash
set -euo pipefail

script_path="${1:-initial_setup.sh}"

if [[ ! -f "$script_path" ]]; then
  echo "ERROR: script not found: $script_path" >&2
  exit 1
fi

awk '
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function is_commented(line) {
  return line ~ /^[[:space:]]*#/
}

function command_text(line) {
  line = trim(line)
  sub(/^#[[:space:]]*/, "", line)
  return line
}

function status(line) {
  return is_commented(line) ? "disabled" : "enabled"
}

function warn(msg) {
  warnings[++warning_count] = msg
}

function field_after(text, key,    n, parts, i) {
  n = split(text, parts, /[[:space:]]+/)
  for (i = 1; i < n; i++) {
    if (parts[i] == key) return parts[i + 1]
  }
  return ""
}

function vlan_suffix(iface,    n, parts) {
  n = split(iface, parts, ".")
  return parts[n]
}

BEGIN {
  print "Inspecting: " ARGV[1]
  print ""
}

/^[[:space:]]*#[[:space:]]*Runtime pinmux setting for CAN/ {
  section = "can_pinmux"
  next
}

/^[[:space:]]*#[[:space:]]*Load kenel modules/ || /^[[:space:]]*#[[:space:]]*Load kernel modules/ {
  section = "modules"
  next
}

/^[[:space:]]*#[[:space:]]*CAN inteface setup/ || /^[[:space:]]*#[[:space:]]*CAN interface setup/ {
  section = "can"
  next
}

/^[[:space:]]*#[[:space:]]*Interrupt CPU affinity/ {
  section = "irq"
  next
}

/^[[:space:]]*#[[:space:]]*Local network throughput setting/ {
  section = "ethtool"
  next
}

/^[[:space:]]*#[[:space:]]*VLAN setting/ {
  section = "vlan"
  next
}

/^[[:space:]]*#[[:space:]]*PTP setting/ {
  section = "ptp"
  next
}

section == "can_pinmux" && /^[[:space:]]*#?-?[[:space:]]*busybox[[:space:]]+devmem/ {
  can_pinmux_count++
  if (status($0) == "enabled") enabled_can_pinmux_count++
}

section == "modules" && /^[[:space:]]*#?[[:space:]]*modprobe[[:space:]]+/ {
  module_count++
  if (status($0) == "enabled") enabled_module_count++
}

section == "can" && /^[[:space:]]*#?[[:space:]]*ip[[:space:]]+link[[:space:]]+set[[:space:]]+can[0-9]+[[:space:]]+/ {
  cmd = command_text($0)
  can_lines[++can_count] = status($0) " | " cmd
  if (status($0) == "enabled") {
    split(cmd, parts, /[[:space:]]+/)
    iface = parts[4]
    enabled_can[iface]++
    if (cmd ~ / fd on /) can_mode[iface] = "can-fd"
    else if (cmd ~ / fd off /) can_mode[iface] = "classic-can"
    else can_mode[iface] = "unknown"
  }
}

section == "irq" && /^[[:space:]]*#?[[:space:]]*echo[[:space:]]+[0-9a-fA-F]+[[:space:]]*>[[:space:]]*\/proc\/irq\/[0-9]+\/smp_affinity/ {
  line = command_text($0)
  irq_lines[++irq_count] = status($0) " | " line
}

section == "ethtool" && /^[[:space:]]*#?[[:space:]]*TARGET_PREFIX=/ {
  target_prefix = command_text($0)
  sub(/^TARGET_PREFIX=/, "", target_prefix)
  gsub(/"/, "", target_prefix)
}

section == "ethtool" && /^[[:space:]]*#?[[:space:]]*ethtool[[:space:]]+/ {
  ethtool_lines[++ethtool_count] = status($0) " | " command_text($0)
}

section == "vlan" && /^[[:space:]]*#?[[:space:]]*export[[:space:]]+SENSOR_INTERFACE=/ {
  sensor_interface = command_text($0)
  sub(/^export[[:space:]]+SENSOR_INTERFACE=/, "", sensor_interface)
  gsub(/"/, "", sensor_interface)
}

section == "vlan" && /^[[:space:]]*#?[[:space:]]*ip[[:space:]]+link[[:space:]]+add[[:space:]]+link[[:space:]]+/ {
  cmd = command_text($0)
  vlan_status[++vlan_count] = status($0)
  vlan_cmd[vlan_count] = cmd
  vlan_name[vlan_count] = vlan_suffix(field_after(cmd, "name"))
  vlan_id[vlan_count] = field_after(cmd, "id")
}

section == "vlan" && /^[[:space:]]*#?[[:space:]]*ip[[:space:]]+addr[[:space:]]+add[[:space:]]+/ {
  cmd = command_text($0)
  addr_status[++addr_count] = status($0)
  addr_cmd[addr_count] = cmd
  addr_ip[addr_count] = field_after(cmd, "add")
  addr_vlan[addr_count] = vlan_suffix(field_after(cmd, "dev"))
}

section == "vlan" && /^[[:space:]]*#?[[:space:]]*ip[[:space:]]+route[[:space:]]+add[[:space:]]+/ {
  route_lines[++route_count] = status($0) " | " command_text($0)
}

section == "vlan" && /^[[:space:]]*#?[[:space:]]*iptables[[:space:]]+/ {
  firewall_lines[++firewall_count] = status($0) " | " command_text($0)
}

section == "ptp" && /^[[:space:]]*#?[[:space:]]*(exec[[:space:]]+)?\/usr\/local\/sbin\/ptp4l[[:space:]]+/ {
  ptp_lines[++ptp_count] = status($0) " | " command_text($0)
  if (!is_commented($0) && command_text($0) ~ /^exec[[:space:]]+/) {
    enabled_exec_ptp++
  }
}

END {
  print "[CAN pinmux]"
  if (can_pinmux_count) print "  present=yes devmem_count=" can_pinmux_count " enabled_count=" enabled_can_pinmux_count
  else print "  present=no"
  print ""

  print "[Kernel modules]"
  if (module_count) print "  present=yes modprobe_count=" module_count " enabled_count=" enabled_module_count
  else print "  present=no"
  print ""

  print "[CAN interfaces]"
  if (!can_count) print "  none"
  for (i = 1; i <= can_count; i++) print "  " can_lines[i]
  for (iface in enabled_can) {
    print "  summary | " iface " enabled_count=" enabled_can[iface] " mode=" can_mode[iface]
    if (enabled_can[iface] > 1) warn(iface " has duplicated enabled CAN setup lines")
  }
  if (!("can1" in enabled_can)) warn("can1 has no enabled CAN setup line")
  print ""

  print "[Interrupt CPU affinity]"
  if (!irq_count) print "  none"
  for (i = 1; i <= irq_count; i++) print "  " irq_lines[i]
  print ""

  print "[ethtool]"
  print "  TARGET_PREFIX=" (target_prefix ? target_prefix : "not found")
  if (!ethtool_count) print "  none"
  for (i = 1; i <= ethtool_count; i++) print "  " ethtool_lines[i]
  print ""

  print "[VLAN/IP]"
  print "  SENSOR_INTERFACE=" (sensor_interface ? sensor_interface : "not found")
  if (!vlan_count) print "  none"
  for (i = 1; i <= vlan_count; i++) {
    ip = "no ip found"
    for (j = 1; j <= addr_count; j++) {
      if (addr_vlan[j] == vlan_name[i]) ip = addr_ip[j]
    }
    print "  " vlan_status[i] " | vlan_id=" vlan_id[i] " iface_vlan=" vlan_name[i] " ip=" ip
    if (vlan_name[i] != vlan_id[i]) warn("VLAN interface suffix " vlan_name[i] " differs from vlan id " vlan_id[i])
    if (ip == "no ip found") warn("VLAN " vlan_id[i] " has no matching ip addr add line")
  }
  for (i = 1; i <= route_count; i++) print "  route | " route_lines[i]
  for (i = 1; i <= firewall_count; i++) print "  firewall | " firewall_lines[i]
  print ""

  print "[PTP]"
  if (!ptp_count) print "  none"
  for (i = 1; i <= ptp_count; i++) print "  " ptp_lines[i]
  if (enabled_exec_ptp > 1) warn("multiple enabled ptp4l lines use exec; the first exec can replace the shell")
  print ""

  print "[Warnings]"
  if (!warning_count) print "  none"
  for (i = 1; i <= warning_count; i++) print "  WARN: " warnings[i]
}
' "$script_path"
