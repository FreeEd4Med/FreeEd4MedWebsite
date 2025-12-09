@echo off
TITLE FreeEd4Med Media SuperTool Setup (Windows)
COLOR 0A

echo ==================================================
echo      FREEED4MED MEDIA SUPERTOOL SETUP
echo ==================================================
echo.
echo This tool is a powerful Bash script designed for Linux/Unix.
echo To run it on Windows, we use the Windows Subsystem for Linux (WSL).
echo.

:: Legal Acknowledgement
echo ==================================================
echo              LEGAL NOTICE
echo ==================================================
echo By installing this software, you agree to the terms and conditions
echo located in the 'Legal' folder included with this package.
echo.
IF EXIST Legal (
    echo Legal Documents:
    dir /b Legal
) ELSE (
    echo [WARNING] 'Legal' folder not found.
)
echo.
set /p accept="Do you accept the Terms of Use and EULA? (y/N): "
IF /I NOT "%accept%"=="y" (
    COLOR 0C
    echo.
    echo Installation aborted by user.
    PAUSE
    EXIT
)
echo.

:: 1. Check for WSL
wsl --status >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    COLOR 0C
    echo [ERROR] WSL is not installed or not running.
    echo.
    echo Please open PowerShell as Administrator and run:
    echo     wsl --install
    echo.
    echo Then restart your computer and run this installer again.
    PAUSE
    EXIT
)

echo [INFO] WSL is detected.
echo.
echo We will now attempt to set up the environment inside WSL (Ubuntu).
echo This may take a few minutes.
echo.
PAUSE

:: 2. Run setup inside WSL
:: We convert the current directory to a WSL path (e.g., /mnt/c/Users/...)
wsl sudo apt update && wsl sudo apt install -y ffmpeg python3 python3-pip imagemagick && wsl pip3 install -r requirements.txt

echo.
echo ==================================================
echo           SETUP COMPLETE!
echo ==================================================
echo To run the tool, use the 'run_windows.bat' file.
PAUSE
