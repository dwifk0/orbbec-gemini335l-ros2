#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# One-time setup for an Orbbec Gemini 330-series camera on Linux with a direct USB connection:
# Jetson (JetPack 6 / Ubuntu 22.04 / Humble) and Raspberry Pi 5 (Ubuntu 24.04 / Jazzy).
# NOT for WSL - there the camera arrives through usbipd, see README "WSL2".
#   1) ros-$ROS_DISTRO-orbbec-camera (apt, official ROS repository)
#   2) udev rule -> the camera opens without root
#   3) sysctl -> large DDS messages (images, point clouds) are not dropped as fragments
# Does NOT touch uvcvideo: other USB webcams on a Jetson need it.
set -e
[ -f /.dockerenv ] && echo "Note: inside Docker; apply udev and sysctl on the HOST."
grep -qi microsoft /proc/version && { echo "This is WSL - this script is for direct-USB Linux. See README."; exit 1; }

DISTRO=${ROS_DISTRO:-$(ls /opt/ros 2>/dev/null | head -1)}
[ -z "$DISTRO" ] && { echo "ROS 2 not found (/opt/ros is empty). Install ROS 2 first."; exit 1; }
echo "== ROS 2 distro: $DISTRO ($(lsb_release -ds 2>/dev/null), $(uname -m))"

echo "== 1/3 Orbbec ROS 2 package"
sudo apt-get update -qq
sudo apt-get install -y "ros-$DISTRO-orbbec-camera" "ros-$DISTRO-orbbec-description"

echo "== 2/3 udev rule"
sudo cp "/opt/ros/$DISTRO/share/orbbec_camera/udev/99-obsensor-libusb.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=2bc5 || true
echo "   If the camera is plugged in, unplug and replug it once."

echo "== 3/3 DDS buffer settings (/etc/sysctl.d/60-ros2-dds.conf)"
sudo tee /etc/sysctl.d/60-ros2-dds.conf >/dev/null <<'EOF'
# ROS 2 / DDS large messages (camera images, point clouds). With the default 208 KB buffer the UDP
# fragments of 1-10 MB messages are dropped and the image freezes.
net.core.rmem_max=2147483647
net.core.wmem_max=2147483647
net.ipv4.ipfrag_time=3
net.ipv4.ipfrag_high_thresh=134217728
EOF
sudo sysctl -p /etc/sysctl.d/60-ros2-dds.conf >/dev/null

echo
echo "Done. Next: ../check.sh   (with the camera plugged in)"
echo "Launch example: README, section 'Jetson / Raspberry Pi'."
