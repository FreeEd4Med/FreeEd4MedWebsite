#!/bin/bash

echo -e "\033[1;35m--- FreeEd4Med Media SuperTool Installer (macOS) ---\033[0m"

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

# 1. Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew is already installed."
fi

# 2. Install System Dependencies
echo "Installing system dependencies (ffmpeg, python, imagemagick, sdl2)..."
brew install ffmpeg python imagemagick sdl2 portaudio

# 3. Install Python Dependencies
echo "Installing Python libraries..."
pip3 install -r requirements.txt

echo -e "\033[1;32mInstallation Complete!\033[0m"
echo "You can now run the tool with: ./freeed_media_super_tool.sh"
