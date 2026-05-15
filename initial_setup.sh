#!/bin/bash
#---------------------------------#
# Runtime pinmux setting for CAN
busybox devmem 0x0c303018 w 0xc458
busybox devmem 0x0c303010 w 0xc400
busybox devmem 0x0c303008 w 0xc458
busybox devmem 0x0c303000 w 0xc400
#---------------------------------#

#---------------------------------#
# Load kenel modules
# CAN modules
modprobe can
modprobe can-raw
modprobe mttcan
# VLAN modules
modprobe 8021q
#---------------------------------#

#---------------------------------#
# CAN inteface setup
# when use can-fd
ip link set can0 up type can bitrate 500 sample-point 0.8 sjw 3 dbitrate 2000000 dsample-point 0.8 dsjw 3 berr-reporting on fd on restart-ms 100
ip link set can1 up type can bitrate 500000 sample-point 0.8 sjw 3 dbitrate 2000000 dsample-point 0.8 dsjw 3 berr-reporting on fd on restart-ms 100
# when use can
#ip link set can0 up type can bitrate 500000 sample-point 0.8 sjw 3 berr-reporting on fd off restart-ms 100
#ip link set can1 up type can bitrate 500000 sample-point 0.8 sjw 3 berr-reporting on fd off restart-ms 100
#---------------------------------#

#---------------------------------#
sleep 1
# Interrupt CPU affinity
# usb interrupt
# echo 2 > /proc/irq/236/smp_affinity
# can0, can1
echo 2 > /proc/irq/14/smp_affinity
echo 2 > /proc/irq/15/smp_affinity
#---------------------------------#

#---------------------------------#
# Local network throughput setting
TARGET_PREFIX="192.168.31."
INTERFACE=""

echo "Searching '${TARGET_PREFIX}' IP ..."
while true; do
    INTERFACE=$(ip -o addr show | awk -v pat="^$TARGET_PREFIX" '$4 ~ pat {print $2; exit}')

    if [ -n "$INTERFACE" ]; then
        echo "Success: Interface name is '$INTERFACE'"
        break
    fi

    sleep 1
done
ethtool -s $INTERFACE speed 2500 duplex full autoneg on
ethtool -s $INTERFACE advertise 0x800000000000
#---------------------------------#

#---------------------------------#
# VLAN setting (Phy. eth0)
# ID List
# 11 : Pandar64
# 12 : XT32
# 19 : ARS_540
export SENSOR_INTERFACE="veth0"

while true; do
  if ip link show "$SENSOR_INTERFACE" | grep -q "state UP"; then
    echo "$SENSOR_INTERFACE is up"
    break;
  else
    echo "Waiting for $SESNOR_INTERFACE"
    sleep 1
  fi
done

# Up Internet interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.2 type vlan id 2
ip addr add 192.168.9.102/24 dev $SENSOR_INTERFACE.2
ip link set dev $SENSOR_INTERFACE.2 up
ip route add default via 192.168.9.1 dev $SENSOR_INTERFACE.2

# Up Pandar64_0 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.30 type vlan id 30
ip addr add 10.30.1.207/24 dev $SENSOR_INTERFACE.30
ip link set dev $SENSOR_INTERFACE.30 up

# Up Pandar64_1 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.31 type vlan id 31
ip addr add 10.31.1.207/24 dev $SENSOR_INTERFACE.31
ip link set dev $SENSOR_INTERFACE.31 up

# Up XT32_0 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.34 type vlan id 34
ip addr add 10.34.1.207/24 dev $SENSOR_INTERFACE.34
ip link set dev $SENSOR_INTERFACE.34 up

# Up XT32_1 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.35 type vlan id 35
ip addr add 10.35.1.207/24 dev $SENSOR_INTERFACE.35
ip link set dev $SENSOR_INTERFACE.35 up

# Up XT32_2 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.36 type vlan id 36
ip addr add 10.36.1.207/24 dev $SENSOR_INTERFACE.36
ip link set dev $SENSOR_INTERFACE.36 up

# Up XT32_3 interface
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.37 type vlan id 37
ip addr add 10.37.1.207/24 dev $SENSOR_INTERFACE.37
ip link set dev $SENSOR_INTERFACE.37 up

# Up ARS540 interface
iptables -I INPUT 1 -p udp --dport 42102 -j ACCEPT
ip link add link $SENSOR_INTERFACE name $SENSOR_INTERFACE.19 type vlan id 19
ip addr add 10.13.1.166/24 dev $SENSOR_INTERFACE.19
ip link set dev $SENSOR_INTERFACE.19 up
#---------------------------------#

# PTP setting
exec /usr/local/sbin/ptp4l -S -i veth0 -m -f /home/odin/ptp4l_veth0_hesai.cfg > /var/log/ptp4l_veth0_hesai.log &
exec /usr/local/sbin/ptp4l -S -i veth0 -m -f /home/odin/ptp4l_veth0_ars.cfg > /var/log/ptp4l_veth0_ars.log &
