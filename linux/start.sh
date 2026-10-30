#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# Start the camera driver in the background on native Linux (Jetson / Raspberry Pi).
# Default: depth + color 848x480 @ 30, MJPG color — the setting measured as right for a Pi 5 on USB 3.
#
#   linux/start.sh                 USB 3 default
#   USB2=1 linux/start.sh          USB 2 preset: depth 848x480 @ 10, color 640x480 @ 15
#   PC=true linux/start.sh         also publish the point cloud
#   DW DH DF / CW CH CF CFMT       override depth / color width, height, fps and color format
#
# Extra arguments go to the launch file. Log: /tmp/orbbec_camera.log. Stop with wsl/stop.sh.
DISTRO=${ROS_DISTRO:-$(ls /opt/ros | head -1)}
source "/opt/ros/$DISTRO/setup.bash"
if [ "${USB2:-0}" = 1 ]; then DF=${DF:-10}; CW=${CW:-640}; CH=${CH:-480}; CF=${CF:-15}; fi

"$(dirname "$0")/../wsl/stop.sh"
LOG=/tmp/orbbec_camera.log
nohup ros2 launch orbbec_camera gemini_330_series.launch.py \
  depth_width:=${DW:-848} depth_height:=${DH:-480} depth_fps:=${DF:-30} \
  color_width:=${CW:-848} color_height:=${CH:-480} color_fps:=${CF:-30} color_format:=${CFMT:-MJPG} \
  enable_point_cloud:=${PC:-false} enable_colored_point_cloud:=false \
  point_cloud_decimation_filter_factor:=2 \
  enable_hardware_noise_removal_filter:=true enable_noise_removal_filter:=false "$@" \
  > "$LOG" 2>&1 &
sleep 15
if grep -q "No matched video stream profile" "$LOG"; then
  echo "No matched video stream profile — on a USB 2 link? (lsusb -t shows 480M) Try: USB2=1 $0"
fi
grep -i -E "error|warn|firmware|version|serial" "$LOG" | head -15
