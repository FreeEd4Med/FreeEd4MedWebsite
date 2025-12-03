#!/bin/bash

echo "=================================================="
echo "      ARDOUR MASTERING ASSISTANT SETUP"
echo "=================================================="

# 1. Check Python
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python 3 is not installed."
    exit 1
fi

# 2. Install Colorama
echo "[INFO] Installing Python requirements..."
pip3 install -r requirements.txt

# 3. Check FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "[WARNING] FFmpeg is missing!"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Please run: brew install ffmpeg"
    else
        echo "Please run: sudo apt install ffmpeg"
    fi
else
    echo "[INFO] FFmpeg is found."
fi

echo ""
echo "Setup Complete. Run with: python3 ardour_fixer.py"
