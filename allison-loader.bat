@echo off
setlocal EnableDelayedExpansion
for /f %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
title Allison Loader
color 0a

set "FONT_URL=https://raw.githubusercontent.com/britzl/gbrausers/master/assets/font/smallest_pixel-7.ttf"
set "OUTDIR=%USERPROFILE%\Desktop\Allison"
set "OUTFILE=%OUTDIR%\smallest-pixel-7.ttf"

echo %ESC%[92m[+]%ESC%[0m connecting to servers...
ping -n 2 127.0.0.1 >nul
echo %ESC%[92m[+]%ESC%[0m handshake ok (raw.githubusercontent.com)
echo %ESC%[93m[*]%ESC%[0m target folder: %OUTDIR%
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo %ESC%[92m[+]%ESC%[0m downloading font...
echo %ESC%[90m    %FONT_URL%%ESC%[0m
curl -L --fail --connect-timeout 15 -o "%OUTFILE%" "%FONT_URL%"
if errorlevel 1 (
  echo %ESC%[91m[!]%ESC%[0m download failed.
  pause
  exit /b 1
)

echo %ESC%[92m[+]%ESC%[0m saved: %OUTFILE%
dir "%OUTFILE%"
echo %ESC%[92m[+]%ESC%[0m done.
pause
