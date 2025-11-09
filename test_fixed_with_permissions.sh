#!/bin/bash

echo "========================================="
echo "ARK Server Container Fix Validation Test"
echo "========================================="
echo ""

# Stop any existing test container
echo "[1/6] Cleaning up old test containers..."
docker stop asa-fixed-test 2>/dev/null
docker rm asa-fixed-test 2>/dev/null
docker volume rm asa-fixed-server-files asa-fixed-steam asa-fixed-steamcmd 2>/dev/null

# Create volumes with proper permissions
echo "[2/6] Creating volumes with proper permissions..."
docker volume create asa-fixed-server-files
docker volume create asa-fixed-steam
docker volume create asa-fixed-steamcmd

# Fix permissions using a temporary container
echo "[3/6] Setting volume permissions..."
docker run --rm \
  -v asa-fixed-server-files:/server-files \
  -v asa-fixed-steam:/steam \
  -v asa-fixed-steamcmd:/steamcmd \
  ubuntu:24.04 bash -c "
    chown -R 25000:25000 /server-files /steam /steamcmd
    chmod -R 755 /server-files /steam /steamcmd
  "

# Run the container with our fixes
echo "[4/6] Starting container with fixes..."
docker run -d \
  --name asa-fixed-test \
  -e ASA_START_PARAMS="TheIsland_WP?listen -WinLiveMaxPlayers=70 -Port=7777 -RCONPort=27020 -RCONEnabled=True -log" \
  -e ADMIN_PASSWORD="test123" \
  -v asa-fixed-server-files:/home/gameserver/server-files \
  -v asa-fixed-steam:/home/gameserver/Steam \
  -v asa-fixed-steamcmd:/home/gameserver/steamcmd \
  asa-fixed:latest

echo "[5/6] Container started. Tailing logs for 60 seconds..."
echo "===================================================="
timeout 60 docker logs -f asa-fixed-test 2>&1

echo ""
echo "[6/6] Test complete!"
echo "===================================================="
echo "Container status:"
docker ps -a | grep asa-fixed-test

echo ""
echo "To continue monitoring: docker logs -f asa-fixed-test"
echo "To stop: docker stop asa-fixed-test && docker rm asa-fixed-test"
echo "To clean up volumes: docker volume rm asa-fixed-server-files asa-fixed-steam asa-fixed-steamcmd"