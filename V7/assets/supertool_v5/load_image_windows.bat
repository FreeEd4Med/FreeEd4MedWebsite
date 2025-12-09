@echo off
echo Loading FreeEd4Med Tool from USB...
docker load -i %~dp0freeed_tool_image.tar
echo Done! You can now run 'run_docker.bat'
PAUSE
