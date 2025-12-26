#!/bin/bash
set -euo pipefail

CID="vjunos-rtr1"

echo "--------------------------------------------------"
echo " Graceful teardown of vJunos Router"
echo "--------------------------------------------------"

# 1. Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CID}$"; then
    echo "Container $CID does not exist. Nothing to tear down."
    #exit 0
fi

# 2. Trigger ACPI shutdown via QEMU monitor
echo "[1/4] Sending ACPI shutdown to QEMU..."
#docker exec "$CID" sh -c 'echo "system_powerdown" | nc -U /tmp/qmp-sock' 2>/dev/null || true
docker exec "$CID" sh -c 'echo "system_powerdown" | nc -U /tmp/qmp-sock >/dev/null 2>&1 &' || true

# 3. Wait for Junos/QEMU to exit cleanly
echo "[2/4] Waiting for Junos to shut down..."
docker wait "$CID" >/dev/null 2>&1 || true

# 4. Remove containers normally
echo "[3/4] Removing containers..."
docker rm "$CID" >/dev/null 2>&1 || true
docker compose down

# 5. Clean up veth interfaces and bridges
echo "[4/4] Cleaning up veth interfaces and bridges..."

for t in mgmt mgmt-c ge0 ge0-c ge1 ge1-c hA1 hA1-c hA2 hA2-c hB1 hB1-c hB2 hB2-c; do
    sudo ip link del "$t" >/dev/null 2>&1 || true
done

docker network rm ge-000-docker
docker network rm ge-001-docker

for br in mgmt-br ge-000 ge-001; do
    sudo ip link del "$br" >/dev/null 2>&1 || true
done

echo "--------------------------------------------------"
echo " Teardown complete. qcow2 image is cleanly unmounted."
echo "--------------------------------------------------"
