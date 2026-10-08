#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ahmet Efe Nezli
#
# Stop everything start.sh opened (RViz, the launch, the camera container).
# Call it on its own line: `pkill -f` patterns also match a shell whose command line
# contains the same text, which would kill your own shell (exit 144).
pkill -x rviz2
pkill -x component_conta
for p in $(pgrep -f "ros2 launch orbbec_camera"); do [ "$p" != "$$" ] && kill "$p"; done 2>/dev/null
sleep 2
pkill -9 -x rviz2; pkill -9 -x component_conta
exit 0
