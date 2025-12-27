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
echo "[1/11] Checking juniper.conf..."
if [[ ! -f "$CONF" ]]; then
    echo "ERROR: juniper.conf not found in $WORKDIR"
    exit 1
fi

# 2. Create config.img
echo "[2/11] Creating config.img..."
chmod +x "$MAKE_CONFIG"
cd "$WORKDIR"
sudo ./make-config-25.4R1.12.sh juniper.conf config.img
echo "config.img created."

# 3. Remove old container if exists
echo "[3/11] Removing old container if present..."
docker rm -f "$CID" >/dev/null 2>&1 || true

# 4. Build Docker image
echo "[4/11] Building Docker image..."
docker build -t vjunos-qemu "$WORKDIR"

# 5. Create host bridges
echo "[5/11] Creating host bridges..."
for br in ge-000 ge-001 mgmt-br; do
    #sudo ip link del "$br" >/dev/null 2>&1 || true
    sudo ip link add "$br" type bridge
    sudo ip link set "$br" up
    sudo ip link set "$br" promisc on
done

# 6. Start container
echo "[6/11] Starting vJunos container..."
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
echo "[7/11] Wiring veth interfaces..."

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
echo "[8/11] Bringing interfaces up inside container..."
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

echo "[9/11] Creating docker bridge netwroks from kernel bridges..."

#docker network create \
#  --driver=bridge \
#  --subnet=10.0.0.0/24 \
#  --gateway=10.0.0.1 \
#  --opt com.docker.network.bridge.name=ge-000 \
#  ge-000-docker

#docker network create \
#  --driver=bridge \
#  --subnet=10.0.1.0/24 \
#  --gateway=10.0.1.1 \
#  --opt com.docker.network.bridge.name=ge-001 \
#  ge-001-docker

docker network create -d macvlan \
  --subnet=10.0.0.0/24 \
  --gateway=10.0.0.1 \
  -o parent=ge-000 \
  ge-000-docker

docker network create -d macvlan \
  --subnet=10.0.1.0/24 \
  --gateway=10.0.1.1 \
  -o parent=ge-001 \
  ge-001-docker

#sudo ip route add 10.0.1.0/24 via 10.0.0.1 dev ge-000
#sudo ip route add 10.0.0.0/24 via 10.0.1.1 dev ge-001
#sudo sysctl -w net.ipv4.ip_forward=1

echo "Docker bridge networks created:" 
docker network ls

echo "[10/11] Starting docker compose for hosts..."

docker compose up -d

echo "[11/11] Waiting for containers to settle..."
sleep 2

echo "--------------------------------------------------"
echo " Host are running! "
echo " Wait for the vjunos router and test Connectivity:" 
echo " docker exec -it hostA1 ping 10.0.0.1"
echo "--------------------------------------------------"


