@echo off
TITLE FreeEd4Med Media SuperTool (Docker)
echo ==================================================
echo      LAUNCHING IN DOCKER
echo ==================================================
echo.
echo This will run the tool inside a container.
echo Your current folder is mounted to /data inside the tool.
echo.

:: Check for Docker
docker --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker is not installed or not running.
    echo Please install Docker Desktop for Windows.
    PAUSE
    EXIT
)

:: Build (only needs to happen once, but fast if cached)
echo [INFO] Building/Checking container image...
docker build -t freeed-media-tool .

:: Run
echo [INFO] Starting Tool...
echo NOTE: All your files are available in the /data folder.
echo.
docker run -it --rm -v "%CD%":/data freeed-media-tool

PAUSE
