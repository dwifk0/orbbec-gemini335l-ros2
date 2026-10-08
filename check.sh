#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# Diagnostics for an Orbbec Gemini 330-series camera: checks the known pitfalls one by one,
# prints OK / WARN / FAIL for each. Works on WSL2, Jetson and Raspberry Pi.
# The camera must be plugged in (on WSL: attached to WSL). Each item maps to a README problem number.
T=0; U=0; H=0
ok(){   echo "  OK    $*"; T=$((T+1)); }
warn(){ echo "  WARN  $*"; U=$((U+1)); }
fail(){ echo "  FAIL  $*"; H=$((H+1)); }
WSL=0; grep -qi microsoft /proc/version && WSL=1
echo "== Environment: $( [ $WSL = 1 ] && echo WSL || echo 'direct Linux') | $(lsb_release -ds 2>/dev/null) | $(uname -m)"

# ROS package
DISTRO=${ROS_DISTRO:-$(ls /opt/ros 2>/dev/null | head -1)}
if [ -n "$DISTRO" ] && [ -d "/opt/ros/$DISTRO/share/orbbec_camera" ]; then
  ok "ros-$DISTRO-orbbec-camera installed"
else
  fail "Orbbec ROS package missing -> sudo apt install ros-<distro>-orbbec-camera"
fi

# Problem 1: is the camera on USB, at what speed
f=$(grep -l 2bc5 /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1)
if [ -z "$f" ]; then
  fail "Camera not on USB$( [ $WSL = 1 ] && echo ' (WSL: attached with usbipd? -> wsl/attach.sh)')"
else
  d=$(dirname "$f"); hiz=$(cat "$d/speed")
  if [ "$hiz" -ge 5000 ]; then ok "Camera at USB 3 speed ($hiz Mbps)"
  else fail "Camera at USB 2 speed ($hiz Mbps) -> REPLACE THE CABLE (USB 3 cable), use a blue/SS port"; fi
  # Problem 4: access permission
  n="/dev/bus/usb/$(printf %03d "$(cat "$d/busnum")")/$(printf %03d "$(cat "$d/devnum")")"
  if [ -w "$n" ]; then ok "Device node writable ($n)"
  else fail "No permission on device node ($n) -> udev rule installed? (linux/setup.sh / sudo chmod 666 $n)"; fi
fi

# Problem 3: on WSL, uvcvideo grabs the camera
if [ $WSL = 1 ]; then
  if lsmod | grep -q '^uvcvideo'; then
    warn "uvcvideo loaded -> on WSL it grabs the camera and times out (blacklist: README)"
  else ok "uvcvideo not loaded (WSL)"; fi
fi

# Problem 7: DDS UDP buffer
r=$(sysctl -n net.core.rmem_max)
if [ "$r" -ge 10485760 ]; then ok "UDP receive buffer large enough ($r)"
else warn "UDP receive buffer small ($r) -> large messages freeze; see linux/setup.sh step 3"; fi

# Problem 8: clock jumps
atla=$(python3 - <<'EOF'
import time
p = time.time() - time.monotonic(); n = 0
for _ in range(16):
    time.sleep(0.5); o = time.time() - time.monotonic()
    if abs(o - p) > 0.05: n += 1
    p = o
print(n)
EOF
)
if [ "$atla" = 0 ]; then ok "System clock did not jump in 8 s"
else fail "System clock jumped $atla times in 8 s -> two time syncs are fighting (README)"; fi
if [ $WSL = 1 ] && systemctl is-active -q systemd-timesyncd 2>/dev/null; then
  warn "systemd-timesyncd active on WSL -> may fight the Windows time sync (sudo systemctl disable --now systemd-timesyncd)"
fi

# Problem 10: usbipd memory leak (WSL)
if [ $WSL = 1 ] && command -v powershell.exe >/dev/null; then
  gb=$(powershell.exe -NoProfile -Command "[math]::Round((Get-Process usbipd -ErrorAction SilentlyContinue).PagedMemorySize64/1GB,2)" 2>/dev/null | tr -d '\r' | tr ',' '.')
  if [ -z "$gb" ]; then warn "could not read the usbipd process"
  elif awk -v g="$gb" 'BEGIN{exit !(g>2)}'; then fail "usbipd.exe uses $gb GB -> admin PowerShell: Restart-Service usbipd"
  else ok "usbipd.exe memory normal ($gb GB)"; fi
fi

# Problem 11: does RViz render on the GPU
if command -v glxinfo >/dev/null; then
  # on WSL, wsl/start.sh opens RViz with d3d12 (GPU); test that path
  [ $WSL = 1 ] && export GALLIUM_DRIVER=d3d12
  r=$(glxinfo -B 2>/dev/null | awk -F': ' '/renderer string/{print $2}')
  case "$r" in
    *llvmpipe*) warn "OpenGL in software ($r) -> RViz burns CPU$( [ $WSL = 1 ] && echo '; WSL: GALLIUM_DRIVER=d3d12')";;
    "") ;;
    *) ok "OpenGL in hardware ($r)";;
  esac
fi

echo "== Result: $T ok, $U warnings, $H failures"
[ "$H" = 0 ]
