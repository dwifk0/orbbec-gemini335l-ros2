#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# usbipd.exe memory watchdog (README, problem 10).
# We saw usbipd.exe grow to 41 GB; Windows ran out of virtual memory, the GPU driver was reset
# and the terminal, WSLg and RViz crashed. In normal 30 fps streaming usbipd stays at ~0.1 GB;
# the leak most likely built up during a storm of USB 2 timeouts / cancelled transfers.
# If it happens again this stops the camera before the PC goes down.
# start.sh launches it in the background. Threshold in GB: first argument (default 3).
LIMIT=${1:-3}
D="$(cd "$(dirname "$0")" && pwd)"
U="/mnt/c/Program Files/usbipd-win/usbipd.exe"
while pgrep -x component_conta >/dev/null || pgrep -f "ros2 launch orbbec_came[r]a" >/dev/null; do
  gb=$(powershell.exe -NoProfile -Command "[math]::Round((Get-Process usbipd -ErrorAction SilentlyContinue).PagedMemorySize64/1GB,1)" 2>/dev/null | tr -d '\r' | tr ',' '.')
  if [ -n "$gb" ] && awk -v g="$gb" -v l="$LIMIT" 'BEGIN{exit !(g>l)}'; then
    echo "!!! WATCHDOG: usbipd.exe uses ${gb} GB (limit ${LIMIT} GB) - stopping the camera."
    echo "!!! To reclaim the memory, in an admin PowerShell:  Restart-Service usbipd"
    "$D/stop.sh"
    "$U" detach --busid "$("$U" list 2>/dev/null | tr -d '\r' | awk -v id="${ORBBEC_ID:-2bc5:0804}" '$2==id{print $1; exit}')" 2>/dev/null
    exit 1
  fi
  sleep 15
done
