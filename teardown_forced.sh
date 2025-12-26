#!/bin/bash
set -euo pipefail

CID="vjunos-rtr1"

echo "--------------------------------------------------"
echo " Graceful teardown of vJunos Router"
echo "--------------------------------------------------"

# 1. Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CID}$"; then
    echo "Container $CID does not exist. Nothing to tear down."
fi

# 2. Gracefully shut down QEMU (PID 1 inside container)
echo "[1/4] Sending SIGTERM to QEMU inside container..."
docker exec "$CID" kill -SIGTERM 1 2>/dev/null || true

# 3. Wait for container to exit cleanly
echo "[2/4] Waiting for Junos to shut down..."
docker wait "$CID" >/dev/null 2>&1 || true

# 4. Remove container normally (no -f!)
echo "[3/4] Removing container..."
docker rm "$CID" >/dev/null 2>&1 || true
docker compose down

# 5. Clean up TAP interfaces and bridges
echo "[4/4] Cleaning up TAP interfaces and bridges..."

for t in tap-mgmt tap-ge0 tap-ge1 hA1 hA1-c hA2 hA2-c hB1 hB1-c hB2 hB2-c; do
    sudo ip link del "$t" >/dev/null 2>&1 || true
done

for br in mgmt-br ge-000 ge-001; do
    sudo ip link del "$br" >/dev/null 2>&1 || true
done

echo "--------------------------------------------------"
echo " Teardown complete. qcow2 image is safe."
echo "--------------------------------------------------"
