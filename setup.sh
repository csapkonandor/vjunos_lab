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
echo "[1/14] Checking juniper.conf..."
if [[ ! -f "$CONF" ]]; then
    echo "ERROR: juniper.conf not found in $WORKDIR"
    exit 1
fi

# 2. Create config.img
echo "[2/14] Creating config.img..."
chmod +x "$MAKE_CONFIG"
cd "$WORKDIR"
sudo ./make-config-25.4R1.12.sh juniper.conf config.img
echo "config.img created."

# 3. Remove old container if exists
echo "[3/14] Removing old container if present..."
docker rm -f "$CID" >/dev/null 2>&1 || true

# 4. Build Docker image
echo "[4/14] Building Docker image..."
docker build -t vjunos-qemu "$WORKDIR"

# 5. Create host bridges
echo "[5/14] Creating host bridges..."
for br in ge-000 ge-001 mgmt-br; do
    sudo ip link del "$br" >/dev/null 2>&1 || true
    sudo ip link add "$br" type bridge
    sudo ip link set "$br" up
done

# 6. Start container
echo "[6/14] Starting vJunos container..."
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

# 7. Create veth interfaces and move them into container
echo "[7/14] Wiring veth interfaces..."

# Clean leftovers
for t in tap-mgmt tap-ge0 tap-ge1; do
    sudo ip link del "$t" >/dev/null 2>&1 || true
done

# mgmt
sudo ip link add mgmt type veth peer name mgmt-c
sudo ip link set mgmt up
sudo ip link set mgmt master mgmt-br
sudo ip link set mgmt-c netns "$PID"

# ge0
sudo ip link add ge0 type veth peer name ge0-c
sudo ip link set ge0 up
sudo ip link set ge0 master ge-000
sudo ip link set ge0-c netns "$PID"

# ge1

sudo ip link add ge1 type veth peer name ge1-c
sudo ip link set ge1 up
sudo ip link set ge1 master ge-001
sudo ip link set ge1-c netns "$PID"


# 8. Bring interfaces up inside container
echo "[8/14] Bringing interfaces up inside container..."
sudo nsenter -t "$PID" -n bash <<EOF
ip link set lo up
ip link set mgmt-c up
ip link set ge0-c up
ip link set ge1-c up
EOF

echo "--------------------------------------------------"
echo " vJunos router is starting!"
echo " Connect via:  telnet localhost 8610"
echo "--------------------------------------------------"

#exit 0

#################################################
# Hosts                                         #
#################################################

echo "[9/14] Starting docker compose for hosts..."
docker compose up -d

echo "[10/14] Waiting for containers to settle..."
sleep 2

# Helper: get stable Docker network namespace path
get_ns() {
    docker inspect -f '{{.NetworkSettings.SandboxKey}}' "$1"
}

# Helper: move container-side veth into container namespace
move_veth() {
    HOST_IF=$1
    CONT_IF=$2
    CONT=$3
    NS=$(get_ns "$CONT")

    echo "  - Moving $CONT_IF into $CONT (ns: $NS)"
    sudo ip link set "$CONT_IF" netns "$NS"
}


echo "[11/14] Creating veth pairs..."

# Host interfaces
sudo ip link add hA1 type veth peer name hA1-c
sudo ip link add hA2 type veth peer name hA2-c
sudo ip link add hB1 type veth peer name hB1-c
sudo ip link add hB2 type veth peer name hB2-c

echo "[12/14] Attaching host ends to bridges..."

sudo ip link set hA1 master ge-000
sudo ip link set hA2 master ge-000

sudo ip link set hB1 master ge-001
sudo ip link set hB2 master ge-001

sudo ip link set hA1 up
sudo ip link set hA2 up
sudo ip link set hB1 up
sudo ip link set hB2 up

echo "[13/14] Moving container ends into namespaces..."

move_veth hA1 hA1-c hostA1
move_veth hA2 hA2-c hostA2
move_veth hB1 hB1-c hostB1
move_veth hB2 hB2-c hostB2

echo "[14/14] Configuring hosts..."

# LAN A hosts
for H in hostA1 hostA2; do
    NS=$(get_ns "$H")
    IF=$(echo "$H" | sed 's/hostA/hA/')
    IP_SUFFIX=$(echo "$H" | sed 's/hostA//')
    IP=$((10 + IP_SUFFIX))

    sudo nsenter --net="$NS" ip link set ${IF}-c name eth0
    sudo nsenter --net="$NS" ip link set eth0 up
    sudo nsenter --net="$NS" ip addr add 10.0.0.$IP/24 dev eth0
    sudo nsenter --net="$NS" ip route add default via 10.0.0.1
done

# LAN B hosts
for H in hostB1 hostB2; do
    NS=$(get_ns "$H")
    IF=$(echo "$H" | sed 's/hostB/hB/')
    IP_SUFFIX=$(echo "$H" | sed 's/hostB//')
    IP=$((20 + IP_SUFFIX))

    sudo nsenter --net="$NS" ip link set ${IF}-c name eth0
    sudo nsenter --net="$NS" ip link set eth0 up
    sudo nsenter --net="$NS" ip addr add 10.0.1.$IP/24 dev eth0
    sudo nsenter --net="$NS" ip route add default via 10.0.1.1
done

echo "[14/14] Setup complete!"
echo "--------------------------------------------------"
echo " Host are running! "
echo " Wait for the vjunos router and test Connectivity:" 
echo " docker exec -it hostA1 ping 10.0.0.1"
echo "--------------------------------------------------"


