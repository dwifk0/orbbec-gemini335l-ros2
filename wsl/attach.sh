#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# (Re)attach the Orbbec camera to WSL2 with usbipd-win and make sure libusb can open it.
# Run before every camera start: over usbip, after the camera process is killed the next
# start receives no frames; detach + attach resets it (README, problem 9).
# One-time prerequisite (admin PowerShell):  usbipd bind --busid <BUSID>
#
# ORBBEC_ID selects the device (default 2bc5:0804 = Gemini 335L; see `usbipd list`).
ID=${ORBBEC_ID:-2bc5:0804}
U="/mnt/c/Program Files/usbipd-win/usbipd.exe"
[ -x "$U" ] || { echo "usbipd-win not found: winget install --exact dorssel.usbipd-win"; exit 1; }
B=$("$U" list 2>/dev/null | tr -d '\r' | awk -v id="$ID" '$2==id{print $1; exit}')
[ -z "$B" ] && { echo "Camera $ID not visible in Windows (plugged in?)"; exit 1; }
"$U" list 2>/dev/null | tr -d '\r' | awk -v id="$ID" '$2==id' | grep -q 'Not shared' && {
  echo "Camera is not shared yet. In an admin PowerShell:  usbipd bind --busid $B"; exit 1; }

timeout 20 "$U" detach --busid "$B" >/dev/null 2>&1
sleep 5
# The first attach right after a detach often does not stick (Windows is re-enumerating) -> retry
for try in 1 2 3; do
  timeout 60 "$U" attach --wsl --busid "$B" >/dev/null 2>&1
  for i in $(seq 1 15); do
    f=$(grep -l "${ID%%:*}" /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1); [ -n "$f" ] && break 2; sleep 1
  done
  sleep 3
done
[ -z "$f" ] && { echo "Camera did not appear in WSL"; exit 1; }
sleep 2; d=$(dirname "$f")
# On USB 3 the udev rule (99-obsensor-libusb.rules) sets the permission itself; fall back to chmod
n="/dev/bus/usb/$(printf %03d "$(cat "$d/busnum")")/$(printf %03d "$(cat "$d/devnum")")"
[ -w "$n" ] || sudo chmod 666 "$n"
echo "Attached: busid $B, speed $(cat "$d/speed") Mbps"
[ "$(cat "$d/speed")" -lt 5000 ] && echo "WARNING: not USB 3 - replace the cable (README, problem 1)"
exit 0
