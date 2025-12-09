@echo off
TITLE FreeEd4Med Media SuperTool
:: Convert current path to WSL path
:: This assumes the drive letter is C: -> /mnt/c/
:: A more robust solution would use `wslpath` but this is a quick starter.

echo Launching SuperTool in WSL...
wsl bash -c "cd \"$(wslpath '%CD%')\" && ./freeed_media_super_tool.sh"
PAUSE
