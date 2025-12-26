#!/bin/bash
set -e

DISK_IMAGE=/vjunos/vjunos-rtr1-live.qcow2
CONFIG_DISK=/vjunos/config.img

MEM_MB=5120
CPUS=4

echo "run-vjunos.sh: waiting for TAP interfaces..."

# Wait for TAP interfaces created by setup.sh
while ! ip link show tap-mgmt >/dev/null 2>&1; do sleep 0.2; done
while ! ip link show tap-ge0  >/dev/null 2>&1; do sleep 0.2; done
while ! ip link show tap-ge1  >/dev/null 2>&1; do sleep 0.2; done

echo "run-vjunos.sh: TAP interfaces detected, starting QEMU..."

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

