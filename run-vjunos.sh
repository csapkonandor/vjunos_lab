#!/bin/bash
set -e

DISK_IMAGE=/vjunos/vjunos-rtr1-live.qcow2
CONFIG_DISK=/vjunos/config.img

MEM_MB=5120
CPUS=4

echo "run-vjunos.sh: waiting for veth interfaces..."

# Wait for veth-TAP interfaces created by setup.sh
while ! ip link show mgmt-c >/dev/null 2>&1; do sleep 0.2; done
while ! ip link show ge0-c  >/dev/null 2>&1; do sleep 0.2; done
while ! ip link show ge1-c  >/dev/null 2>&1; do sleep 0.2; done

for br in ge-000-dckr ge-001-dckr mgmt-br-dckr; do
    ip link del "$br" >/dev/null 2>&1 || true
    ip link add "$br" type bridge
    ip link set "$br" up
    ip link set "$br" promisc on
done

# mgmt
ip tuntap add dev tap-mgmt mode tap
ip link set tap-mgmt up
ip link set tap-mgmt master mgmt-br-dckr
ip link set mgmt-c up
ip link set mgmt-c master mgmt-br-dckr

# ge0
ip tuntap add dev tap-ge0 mode tap
ip link set tap-ge0 up
ip link set tap-ge0 master ge-000-dckr
ip link set ge0-c up
ip link set ge0-c master ge-000-dckr

# ge1
ip tuntap add dev tap-ge1 mode tap
ip link set tap-ge1 up
ip link set tap-ge1 master ge-001-dckr
ip link set ge1-c up
ip link set ge1-c master ge-001-dckr

sysctl -w net.bridge.bridge-nf-call-iptables=0 || true
sysctl -w net.bridge.bridge-nf-call-arptables=0 || true
sysctl -w net.bridge.bridge-nf-call-ip6tables=0 || true

echo "run-vjunos.sh: veth interfaces detected, brideges and TAP interfaces created, starting QEMU..."

exec qemu-system-x86_64 \
  -nographic \
  -enable-kvm \
  -machine accel=kvm,type=pc \
  -cpu IvyBridge,+vmx \
  -smp ${CPUS} \
  -m ${MEM_MB}M \
  \
  -drive file=${DISK_IMAGE},if=virtio,cache=writeback,format=qcow2 \
  -drive file=${CONFIG_DISK},if=none,format=raw,id=cfgdisk \
  -device usb-ehci,id=ehci \
  -device usb-storage,drive=cfgdisk,removable=on \
  \
  -serial tcp:0.0.0.0:8610,server,nowait \
  \
  -netdev tap,id=mgmt,ifname=tap-mgmt,script=no,downscript=no \
  -device virtio-net-pci,netdev=mgmt,mac=52:54:00:00:00:10 \
  \
  -netdev tap,id=ge0,ifname=tap-ge0,script=no,downscript=no \
  -device virtio-net-pci,netdev=ge0,mac=52:54:00:00:00:11 \
  \
  -netdev tap,id=ge1,ifname=tap-ge1,script=no,downscript=no \
  -device virtio-net-pci,netdev=ge1,mac=52:54:00:00:00:12 \
  \
  -monitor unix:/tmp/qmp-sock,server,nowait

