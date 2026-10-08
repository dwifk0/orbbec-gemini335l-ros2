#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# Gemini 335L on WSL2 + ROS 2: attach the camera, start the usbipd watchdog, the driver and RViz.
# Measured (firmware 1.8.10): color + depth + point cloud at 30 Hz, camera node ~20 % CPU.
#  - Uncolored point cloud (/camera/depth/points), RViz colors it by distance; no alignment.
#    Colored cloud: depth_registration:=true align_mode:=HW enable_colored_point_cloud:=true
#    (color and depth must have the same size for hardware D2C - README, problem 6).
#  - Point cloud decimated 2x (~100k points).
#  - RViz is pointed at the GPU (d3d12); WSLg defaults to llvmpipe (README, problem 11).
# Usage: ./start.sh              camera + RViz
#        ./start.sh no_rviz      camera only
#        extra launch arguments are passed through, e.g. ./start.sh depth_fps:=15
# Stop:  ./stop.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="$D/../config"
"$D/attach.sh" || exit 1
DISTRO=${ROS_DISTRO:-$(ls /opt/ros | head -1)}
source "/opt/ros/$DISTRO/setup.bash"
[ "${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}" = rmw_cyclonedds_cpp ] && export CYCLONEDDS_URI="file://$C/cyclonedds.xml"
(sleep 20; exec "$D/usbipd_watchdog.sh") &
if [ "$1" = "no_rviz" ]; then
  shift
else
  (sleep 5; GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME="${MESA_D3D12_DEFAULT_ADAPTER_NAME:-NVIDIA}" \
     exec rviz2 -d "$C/gemini335l.rviz") &
fi
exec ros2 launch orbbec_camera gemini_330_series.launch.py \
  depth_width:=848 depth_height:=480 depth_fps:=30 \
  color_width:=848 color_height:=480 color_fps:=30 \
  depth_registration:=false \
  enable_point_cloud:=true enable_colored_point_cloud:=false \
  point_cloud_decimation_filter_factor:=2 "$@"
