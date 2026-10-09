@echo off
set "NODE=C:\Program Files\nodejs\node.exe"
if not exist "%NODE%" set "NODE=node"
title DeepSeek Harness live wallpaper
"%NODE%" "%~dp0wallpaper-server.mjs" %*
if errorlevel 1 (
  echo.
  echo Server exited with an error. Press any key to close.
  pause >nul
)
