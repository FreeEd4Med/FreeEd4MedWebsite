@echo off
TITLE Ardour Fixer Setup
COLOR 0A

echo ==================================================
echo      ARDOUR MASTERING ASSISTANT SETUP
echo ==================================================
echo.

:: 1. Check for Python
python --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    COLOR 0C
    echo [ERROR] Python is not installed.
    echo Please install Python 3 from python.org or the Microsoft Store.
    PAUSE
    EXIT
)

:: 2. Install Colorama
echo [INFO] Installing required libraries...
pip install -r requirements.txt

:: 3. Check for FFmpeg
where ffmpeg >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    COLOR 0E
    echo.
    echo [WARNING] FFmpeg is missing!
    echo Attempting to install via Winget...
    winget install Gyan.FFmpeg
    echo.
    echo IMPORTANT: You may need to restart your computer after this.
) ELSE (
    echo [INFO] FFmpeg is already installed.
)

echo.
echo ==================================================
echo           SETUP COMPLETE!
echo ==================================================
echo To run the tool, type: python ardour_fixer.py
PAUSE
