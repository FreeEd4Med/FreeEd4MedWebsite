#!/bin/bash

echo -e "\033[1;35m--- FreeEd4Med Media SuperTool Installer (Linux/Debian) ---\033[0m"

# Legal Acknowledgement
echo
echo -e "\033[1;33mIMPORTANT: LEGAL NOTICE\033[0m"
echo "By installing this software, you agree to the terms and conditions"
echo "located in the 'Legal' folder included with this package."
echo
if [ -d "Legal" ]; then
    echo "Legal Documents:"
    ls -1 Legal
else
    echo "Warning: 'Legal' folder not found in current directory."
fi
echo
read -p "Do you accept the Terms of Use and EULA? (y/N): " accept
if [[ "$accept" != "y" && "$accept" != "Y" ]]; then
    echo -e "\033[0;31mInstallation aborted by user.\033[0m"
    exit 1
fi
echo

# 1. Update Package List
echo "[1/3] Updating package lists..."
sudo apt-get update

# 2. Install System Dependencies
echo "[2/3] Installing system dependencies (ffmpeg, python3, imagemagick)..."
# python3-venv is often needed for proper pip usage on modern Debian/Ubuntu
sudo apt-get install -y ffmpeg python3 python3-pip python3-venv imagemagick

# 3. Install Python Dependencies
echo "[3/3] Installing Python libraries..."
# Use --break-system-packages if on newer Debian/Ubuntu versions that enforce PEP 668, 
# or suggest venv. For simplicity in this "SuperTool" context, we'll try standard pip 
# and fallback or warn.
pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt

echo -e "\033[1;32mInstallation Complete!\033[0m"
echo "You can now run the tool with: ./freeed_media_super_tool.sh"
