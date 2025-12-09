#!/bin/bash
echo "=================================================="
echo "      LAUNCHING IN DOCKER"
echo "=================================================="

if ! command -v docker &> /dev/null; then
    echo "[ERROR] Docker is not installed."
    exit 1
fi

echo "[INFO] Building container..."
docker build -t freeed-media-tool .

echo "[INFO] Starting Tool..."
echo "NOTE: Your current folder is mounted at /data"
# Run interactive, remove on exit, mount current dir to /data
docker run -it --rm -v "$(pwd)":/data freeed-media-tool
