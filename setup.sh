#!/bin/bash
set -euo pipefail

WORKDIR="$(pwd)"
CID="vjunos-rtr1"
CONF="$WORKDIR/juniper.conf"
CONFIG_IMG="$WORKDIR/config.img"
MAKE_CONFIG="$WORKDIR/make-config-25.4R1.12.sh"

echo "--------------------------------------------------"
echo " vJunos Router Setup (TAP-based wiring)"
echo "--------------------------------------------------"

# 1. Validate config file
echo "[1/8] Checking juniper.conf..."
if [[ ! -f "$CONF" ]]; then
    echo "ERROR: juniper.conf not found in $WORKDIR"
    exit 1
fi

# 2. Create config.img
echo "[2/8] Creating config.img..."
chmod +x "$MAKE_CONFIG"
cd "$WORKDIR"
sudo ./make-config-25.4R1.12.sh juniper.conf config.img
echo "config.img created."

# 3. Remove old container if exists
echo "[3/8] Removing old container if present..."
docker rm -f "$CID" >/dev/null 2>&1 || true

# 4. Build Docker image
echo "[4/8] Building Docker image..."
docker build -t vjunos-qemu "$WORKDIR"

# 5. Create host bridges
echo "[5/8] Creating host bridges..."
for br in ge-000 ge-001 mgmt-br; do
    sudo ip link del "$br" >/dev/null 2>&1 || true
    sudo ip link add "$br" type bridge
    sudo ip link set "$br" up
done

# 6. Start container
echo "[6/8] Starting vJunos container..."
docker run -d --name "$CID" \
  --privileged \
  --device /dev/kvm \
  -p 8610:8610 \
  -v "$WORKDIR/vjunos-rtr1-live.qcow2:/vjunos/vjunos-rtr1-live.qcow2" \
  -v "$WORKDIR/config.img:/vjunos/config.img" \
  vjunos-qemu

sleep 1

echo "[DEBUG] Checking container state..."
STATE=$(docker inspect -f '{{.State.Status}}' "$CID")
echo "Container state: $STATE"

if [[ "$STATE" != "running" ]]; then
    echo "ERROR: Container is not running. Dumping logs:"
    docker logs "$CID"
    exit 1
fi

PID=$(docker inspect -f '{{.State.Pid}}' "$CID")
echo "Container PID = $PID"

# 7. Create TAP interfaces and move them into container
echo "[7/8] Wiring TAP interfaces..."

# Clean leftovers
for t in tap-mgmt tap-ge0 tap-ge1; do
    sudo ip link del "$t" >/dev/null 2>&1 || true
done

# mgmt
sudo ip tuntap add dev tap-mgmt mode tap
sudo ip link set tap-mgmt up
sudo ip link set tap-mgmt master mgmt-br
sudo ip link set tap-mgmt netns "$PID"

# ge0
sudo ip tuntap add dev tap-ge0 mode tap
sudo ip link set tap-ge0 up
sudo ip link set tap-ge0 master ge-000
sudo ip link set tap-ge0 netns "$PID"

# ge1
sudo ip tuntap add dev tap-ge1 mode tap
sudo ip link set tap-ge1 up
sudo ip link set tap-ge1 master ge-001
sudo ip link set tap-ge1 netns "$PID"

# 8. Bring interfaces up inside container
echo "[8/8] Bringing interfaces up inside container..."
sudo nsenter -t "$PID" -n bash <<EOF
ip link set lo up
ip link set tap-mgmt up
ip link set tap-ge0 up
ip link set tap-ge1 up
EOF

echo "--------------------------------------------------"
echo " vJunos router is starting!"
echo " Connect via:  telnet localhost 8610"
echo "--------------------------------------------------"

