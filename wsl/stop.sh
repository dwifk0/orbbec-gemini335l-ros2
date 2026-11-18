#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# Stop everything start.sh opened (RViz, the launch, the camera container) - and ONLY that.
# Earlier versions used `pkill -x component_conta` / `pkill rviz2`; the process name is cut to
# 15 characters, so that matched every ROS 2 component container on the machine (Nav2 and
# friends on a Jetson) and every RViz window. Now each pattern names this repo's processes:
#   - the container the orbbec launch file creates (node name camera_container)
#   - RViz opened with this repo's config file
#   - the `ros2 launch orbbec_camera ...` process itself
# Each PID is picked by its process NAME first (component_conta / rviz2 / ros2), then its
# command line is checked, so a shell whose command line merely contains the same text is
# never hit (plain `pkill -f` would kill it - exit 144).
# Another camera_container on the machine? Set ORBBEC_CONTAINER to its node name.
NODE=${ORBBEC_CONTAINER:-camera_container}
find_pids() {  # find_pids <process name> <text in command line>
  local pid
  for pid in $(pgrep -x "$1"); do
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$2" && echo "$pid"
  done
}
all_pids() { find_pids component_conta "__node:=$NODE"; find_pids rviz2 gemini335l.rviz; find_pids ros2 "launch orbbec_camera"; }
P=$(all_pids); [ -n "$P" ] && kill $P 2>/dev/null
sleep 2
P=$(all_pids); [ -n "$P" ] && kill -9 $P 2>/dev/null
exit 0
