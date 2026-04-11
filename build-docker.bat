@echo off
setlocal

if "%GIMP_VERSION%"=="" set "GIMP_VERSION=2"

docker build --build-arg GIMP_VERSION=%GIMP_VERSION% -t switchwave-builder .
if errorlevel 1 exit /b %errorlevel%

docker run --rm --name devkitpro-switchwave ^
    -v "%cd%:/mnt/" ^
    switchwave-builder ^
    bash -c "set -e; git config --global --add safe.directory '*'; cd /mnt/; make clean; make configure-ffmpeg; make build-ffmpeg -j$(nproc); make configure-uam; make build-uam; make configure-mpv; make build-mpv; make dist -j$(nproc)"

exit /b %errorlevel%
