# Orbbec Gemini 335L with ROS 2 + RViz — WSL2, Jetson and Raspberry Pi

**[Türkçe](README.tr.md)**

Field notes from getting a brand-new **Orbbec Gemini 335L** stereo depth camera from the box to a
smooth 30 Hz point cloud in RViz on **Windows 11 + WSL2 (Ubuntu 24.04, ROS 2 Jazzy)** — every problem
we hit, its *real* cause, and the fix, plus setup notes for **Jetson** and **Raspberry Pi**.

Most of the problems were not the camera at all: they came from the layers in between — a cable,
usbip, the system clock, DDS buffers, the graphics driver. Every item below was verified by
measurement; the numbers are given.

> Applies to the whole Gemini 330 series (330 / 335 / 335L / 336 / 336L …) with small changes
> (USB product ID, resolutions). Tested with camera firmware 1.2.81 → 1.8.10,
> `ros-jazzy-orbbec-camera` 2.9.3, OrbbecSDK v2.10.6, usbipd-win 5.3.0, WSL 2.7.3. October 2026.

![Working: point cloud at 30 Hz, colored by distance](images/05_final_with_tools.png)

**End result (WSL2):** color 848×480 + depth 848×480 + point cloud at **30 Hz**, camera node ~20 % CPU,
RViz on the GPU, zero gaps longer than 0.3 s over a 40 s measurement.

---

## Contents

1. [Files](#files)
2. [Quick start — WSL2](#quick-start--wsl2)
3. [Quick start — Jetson / Raspberry Pi](#quick-start--jetson--raspberry-pi)
4. [Problem → cause → fix](#problem--cause--fix) ← the useful part
5. [Updating the camera firmware](#updating-the-camera-firmware)
6. [Settings and why](#settings-and-why)
7. [Using RViz](#using-rviz)

---

## Files

| File | What it does | Where |
|---|---|---|
| `wsl/start.sh` | Attaches the camera, starts the usbipd watchdog, the driver and RViz | WSL |
| `wsl/stop.sh` | Stops RViz, the launch and the camera node | WSL / Linux |
| `wsl/attach.sh` | **Re**-attaches the camera to WSL with usbipd (detach → attach, retries) | WSL |
| `wsl/usbipd_watchdog.sh` | Watches `usbipd.exe` memory every 15 s, stops the camera above 3 GB | WSL |
| `linux/setup.sh` | ROS package + udev rule + sysctl, one time | Jetson / Pi |
| `check.sh` | Checks the pitfalls below one by one: OK / WARN / FAIL | everywhere |
| `config/gemini335l.rviz` | Point cloud (colored by distance) + color + depth images + tool bar | everywhere |
| `config/cyclonedds.xml` | CycloneDDS receive buffer ≥ 10 MB | everywhere (if you use Cyclone) |

---

## Quick start — WSL2

**One time:**

1. Windows: `winget install --exact dorssel.usbipd-win` (a UAC prompt appears).
2. WSL: `sudo apt install ros-jazzy-orbbec-camera ros-jazzy-orbbec-description`
3. WSL, udev rule:
   `sudo cp /opt/ros/jazzy/share/orbbec_camera/udev/99-obsensor-libusb.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules`
4. WSL, keep `uvcvideo` away from the camera ([problem 3](#3--wsl-sdk-hangs-in-usb_remove_ep_devs-dmesg-failed-to-query-uvc-control--110)):
   `echo "blacklist uvcvideo" | sudo tee /etc/modprobe.d/orbbec-uvcvideo-off.conf && sudo modprobe -r uvcvideo`
5. WSL, DDS buffers ([problem 7](#7--rviz-images-come-and-go-point-cloud-frozen)): apply the `60-ros2-dds.conf` block from `linux/setup.sh` by hand.
6. WSL, clock fight ([problem 8](#8--everything-freezes-for-a-few-seconds-then-recovers--the-clock)): `sudo systemctl disable --now systemd-timesyncd`
7. Plug the camera in **with a USB 3 cable** ([problem 1](#1--camera-always-on-usb-2-480-mbps-everything-times-out-on-wsl--the-cable)). In an admin PowerShell:
   `usbipd list` → note the camera's BUSID → `usbipd bind --busid <BUSID>`
8. If the firmware is old, [update it](#updating-the-camera-firmware). With 1.2.81 the stock launch file does not start ([problem 5](#5--stock-launch-file-fails-failed-to-set-2052--device-response-with-error-errorcode-2)).

**Every time:**

```bash
wsl/start.sh              # attach + camera + RViz      (camera only: wsl/start.sh no_rviz)
wsl/stop.sh               # stop
./check.sh                # if anything looks wrong, run this first
```

To use the camera in Windows again: `usbipd detach --busid <BUSID>`.
**A different USB port gives a different BUSID** → `bind` once more for that port (UAC).
For another camera of the series set `ORBBEC_ID` (e.g. `ORBBEC_ID=2bc5:0800 wsl/start.sh`; see `usbipd list`).

---

## Quick start — Jetson / Raspberry Pi

With a direct USB connection the WSL-specific problems (2, 3, 9, 10) **do not exist**. What remains:
USB 3 cable (1), firmware (5), DDS buffers (7), clock (8), CPU load (6).

| Platform | Ubuntu / ROS 2 | Binary package (Oct 2026) |
|---|---|---|
| Jetson Orin (JetPack 6) | 22.04 / Humble | `ros-humble-orbbec-camera` 2.9.3 arm64 ✔ |
| Raspberry Pi 5 | 24.04 / Jazzy | `ros-jazzy-orbbec-camera` 2.9.3 arm64 ✔ |
| Raspberry Pi 5 | Raspberry Pi OS | **no** ROS 2 binaries → Ubuntu/ROS in Docker, or build OrbbecSDK_v2 from source |

```bash
linux/setup.sh            # package + udev + sysctl (once)
# unplug and replug the camera, then:
./check.sh
source /opt/ros/$ROS_DISTRO/setup.bash
ros2 launch orbbec_camera gemini_330_series.launch.py \
  depth_width:=848 depth_height:=480 depth_fps:=30 \
  color_width:=848 color_height:=480 color_fps:=30 \
  enable_point_cloud:=true enable_colored_point_cloud:=false \
  point_cloud_decimation_filter_factor:=2 \
  enable_hardware_noise_removal_filter:=true enable_noise_removal_filter:=false
```

The last line moves the noise-removal filter from software into the camera — that is the only
difference of Orbbec's own `_low_cpu` launch file, and it matters on an ARM CPU.

### Jetson specifics

- **Do NOT blacklist `uvcvideo`.** The WSL fix (problem 3) would kill every other USB webcam on the
  Jetson. On native Linux libusb detaches uvcvideo from the camera by itself; no problem there.
- **Clock:** without an RTC battery the clock starts in the past and jumps when the network comes up.
  The jump can stall DDS (problem 8). Start the driver after `timedatectl` reports
  `System clock synchronized: yes`, and look at the clock line of `check.sh`.
- **Power:** the Orin Nano devkit's USB 3 ports power the camera fine (335L peak ≈ 6 W). Behind a hub,
  use a **powered** hub.
- In Docker, udev and sysctl must be applied **on the host**; the container needs
  `--privileged -v /dev/bus/usb:/dev/bus/usb`.

### Raspberry Pi 5 specifics

- **USB current limit:** with the official 5 A supply the Pi 5 gives all USB ports **1.6 A** in total,
  with other supplies **0.6 A**. The 335L draws ~1.2 A at peak → the official supply is required. With
  other USB devices (a LiDAR, …) add them up, or use a powered hub.
- Use a blue (USB 3) port; `check.sh` reports the speed.
- CPU: 30 fps plus a point cloud is heavy for a Pi. Start with `depth_fps:=15`, enable the point cloud only if needed.
- Run RViz on a PC on the network, not on the Pi (same `ROS_DOMAIN_ID`). Raw images over Wi-Fi are
  heavy; for viewing use `/camera/color/image_raw/compressed`.

---

## Problem → cause → fix

In the order we hit them. The matching `check.sh` item is noted where there is one.

### 1 · Camera always on USB 2 (480 Mbps), everything times out on WSL — **the cable**

- **Symptom:** `Connection: USB2.1` in the SDK log; `/sys/bus/usb/devices/*/speed` = 480; same on two
  different ports. On WSL every USB request takes a 5 s timeout and the SDK hangs; in Orbbec Viewer
  `no matching stream profile found`.
- **Cause:** the USB-C cable only carried USB 2. A USB 3 device that falls back reports `bcdUSB` 2.10,
  and the 335L cannot open most stream profiles in that mode.
- **Fix:** a USB 3 cable. Immediately `USB3.2` / 5000 Mbps, and **all** WSL timeouts disappeared.
  Phone charging cables are often USB 2 only.
- `check.sh`: USB speed. **Check this before anything else** — it triggered some of the problems below.

### 2 · usbipd warning: `Unknown USB filter 'nxusbf'`

- **Cause:** `nxusbf` is **NoMachine**'s USB filter driver (it stays installed even with the service off).
- **Fix:** with the USB 3 cable a normal `bind` was enough. If you have trouble:
  `usbipd bind --force --busid <id>` (Windows can then no longer use the camera; `usbipd unbind` to give it back).

### 3 · WSL: SDK hangs in `usb_remove_ep_devs`, dmesg `Failed to query (GET_INFO) UVC control … -110`

- **Cause:** the WSL kernel ships `uvcvideo`, which grabs the camera before the Orbbec SDK; over usbip
  each of its control queries times out.
- **Fix (WSL only):** `blacklist uvcvideo` (quick start step 4). The Orbbec SDK talks to the camera
  through libusb (`uvc_backend:=libuvc`, the default) and does not need uvcvideo.
  Cost: no other webcam works in WSL either — delete the file to undo.
- `check.sh`: uvcvideo.

### 4 · `openUsbDevice failed! status:113`

- **Cause:** the device node is `crw------- root` — the udev rule was not applied (during the USB 2
  phase even `udevadm trigger` hung on timeouts).
- **Fix:** the udev rule. On USB 3 it applies **by itself** (`root video`, 0666). If not:
  `sudo chmod 666 /dev/bus/usb/<bus>/<dev>` (`wsl/attach.sh` does this for you).
- `check.sh`: device node permission.

### 5 · Stock launch file fails: `Failed to set 2052 … device response with error, errorCode: 2`

- **Cause:** property 2052 is `OB_PROP_DEPTH_AUTO_EXPOSURE_PRIORITY_INT`. The driver only writes it
  when the parameter is *provided* — but the stock launch file provides **every** parameter with its
  default, so it is always written. The factory firmware **1.2.81** does not know this property →
  three attempts, exit.
- **Fix:** update the firmware to **1.8.10** (recommended by Orbbec for SDK 2.9/2.10). After that the
  stock launch works; start-up 6.6 s → 1.2 s, depth 4–6 fps → 30 fps.
- Workaround without updating: skip the launch file and run
  `ros2 run orbbec_camera orbbec_camera_node --ros-args -p …` with only the parameters you need
  (parameters not given are not written).

### 6 · `Current stream profile is not support hardware d2c` / node at 100 % CPU, depth 7 fps

![Colored point cloud with software alignment: 8 fps](images/02_colored_cloud_sw_align_8fps.png)

- **Cause:** depth-to-color alignment (D2C) of 848×480 depth with 1280×720/800 color is **not
  supported in hardware**. `align_mode:=SW` starts, but alignment + MJPEG decoding + point cloud
  saturate one core and depth drops to 7 fps.
- **Fix:** color and depth at the **same size** (848×480) → `align_mode:=HW` → 30 Hz, node at 20 %.
  If you do not need a colored point cloud, do not align at all (`depth_registration:=false`,
  `enable_colored_point_cloud:=false`) — that is the current setup.

### 7 · RViz: images come and go, point cloud frozen

![RViz with no image](images/01_rviz_no_image.png)

- **Cause:** `net.core.rmem_max` was **208 KB**; one colored point cloud message is ~10 MB, one color
  image 2.7 MB. UDP fragments do not fit in the buffer, get dropped, the message never completes.
- **Fix:** `/etc/sysctl.d/60-ros2-dds.conf` (rmem/wmem 2 GB, ipfrag) + for CycloneDDS
  `config/cyclonedds.xml` (`SocketReceiveBufferSize min="10MB"`, via `CYCLONEDDS_URI`). Decimating the
  point cloud 2× (`point_cloud_decimation_filter_factor:=2`) brings a message down to 1.4–1.7 MB.
- `check.sh`: UDP buffer.

### 8 · Everything freezes for a few seconds, then recovers — **the clock**

- **Symptom:** the camera produces a steady 30 fps, yet all three topics stop **at the same time** for
  5–20 s (in our measurement: multiples of 5.3 s). `dmesg`:
  `systemd-journald: Time jumped backwards, rotating.` — **exactly every 5 s**.
- **Cause:** the WSL clock was synced both from Windows and by `systemd-timesyncd` (NTP) inside WSL.
  The Windows clock was ~5 s off NTP, so the two fought: the clock jumped **−500 ms every 5 s**. DDS
  timers follow the wall clock, so publishing stalls.
- **Fix:** `sudo systemctl disable --now systemd-timesyncd` (WSL already takes its time from Windows).
  The clock jumped once by +5.3 s and settled; afterwards **zero** gaps over 0.3 s in 40 s.
  If the Windows clock itself is wrong, fix it there (Settings → Time → Sync now).
- On a Jetson the equivalent is the battery-less RTC: a big jump when NTP arrives.
- `check.sh`: clock jumps. **This looks like "the network / USB stutters" — check the clock first.**

### 9 · WSL: after the camera process is stopped, the next start gets no frames

- **Symptom:** the launch starts, `Start streams done!`, but `STARTING → STREAMING` never appears.
- **Cause:** usbip; when the process is killed mid-stream the camera side is left half-open.
- **Fix:** detach → attach before every start. `wsl/attach.sh` does it; the first attach right after
  a detach often does not stick, so it retries three times.

### 10 · 🔴 WSL: the PC fell over — terminal, browser, RViz closed — **usbipd memory leak**

![usbipd.exe at 6.2 GB in Task Manager](images/04_usbipd_memory_6gb.png)

- **Symptom:** the terminal and RViz closed by themselves. Windows event log: `Resource-Exhaustion-
  Detector 2004` (low virtual memory) ×4, then `LiveKernelEvent 141/119/193` (GPU driver hung and was
  reset), `msrdc.exe` (the program that shows WSLg windows) and the browser "not responding".
- **Cause:** `usbipd.exe` had grown to **41 GB** of committed memory (on a 15 GB RAM machine) →
  Windows ran out of virtual memory.
- **Measurement:** after restarting the service: 0.01 GB. Then, streaming 30 fps for a minute: steady
  **0.1 GB**; a stop/attach cycle did not grow it either. So normal use does not leak; the trigger was
  most likely the storm of USB 2 timeouts / cancelled transfers from problem 1. Not isolated for sure.
- **Fix:** admin PowerShell → `Restart-Service usbipd`. `wsl/usbipd_watchdog.sh` watches it and
  **stops the camera above 3 GB**, before the PC goes down.
- `check.sh`: usbipd memory.

### 11 · RViz at 500 % CPU, stuttering

- **Cause:** under WSLg OpenGL defaults to **llvmpipe** (software).
- **Fix:** `GALLIUM_DRIVER=d3d12` (+ with two GPUs `MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA`) → 50–70 %.
  `wsl/start.sh` starts RViz this way. `check.sh`: OpenGL renderer.

### 12 · RViz: the view does not rotate with the mouse

- **Cause:** if the `.rviz` file has no `Tools:` section, the tool bar only shows `+ −`; the
  **Interact** tool that moves the view is not loaded.
- **Fix:** a `Tools:` list in the `.rviz` (Interact, MoveCamera, Select, FocusCamera, Measure) —
  `config/gemini335l.rviz` has it.

### Small notes

- Running `pkill -f "…launch.py"` in the same shell line as other commands that contain that text
  **kills your own shell** too (exit 144). Call `wsl/stop.sh` on its own.
- `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST` together with `ROS_STATIC_PEERS` made the stock launch
  unable to load the node into its container here; removing the variable fixed it.
- Leftover `ros2 launch` processes from earlier attempts confuse discovery; `wsl/stop.sh` cleans them up.
- Extracting the Windows Orbbec Viewer zip on Linux with Python's `zipfile` turns sub-folders into flat
  files named `config\x.ini` (the zip uses backslashes) → plugins do not load. Extract it on Windows.
- `lsusb -v` can hang on the camera over usbip; read `/sys/bus/usb/devices/*/speed` for the speed.

---

## Updating the camera firmware

Do it in Windows, with the camera **attached to Windows** (if it is attached to WSL, `usbipd detach` first).
If the connection drops while writing over usbip the camera can be bricked — hence directly.

1. Package: Orbbec's Gemini 330 firmware page (`orbbec.com/docs/g330-firmware-release`); as of
   October 2026 the recommended version is **1.8.10** (`Gemini330_Release_1.8.10.zip`). Verify it
   against the `_md5.txt` inside the zip.
2. Tool: `bin/ob_device_firmware_update.exe` from the OrbbecSDK_v2 Windows release:
   ```
   ob_device_firmware_update.exe -l                         # lists the device and its version
   ob_device_firmware_update.exe -f <...>\Gemini330_Release_1.8.10.bin -s <serial_number>
   ```
3. The tool verifies and writes the app, `335L_cfg`, depth table, post-filter and ISP parts one by
   one; the camera reboots by itself (~2 min). Confirm with `-l`: `Firmware version: 1.8.10`.

Do not touch the cable or let the PC sleep until it finishes. On Linux the same tool exists
(`/opt/ros/<distro>/lib/orbbec_camera/firmware_update_tool`, or the SDK example).

---

## Settings and why

| Setting | Value | Why |
|---|---|---|
| Depth | 848×480 @ 30 | Native depth resolution of the 335L; `640×480` falls into the 4:3 group and narrows the FOV from 90° to 81° |
| Color | 848×480 @ 30 | Same size as depth → hardware D2C possible (problem 6) |
| Point cloud | uncolored, decimated 2× | A colored cloud needs alignment and is ~2× larger; decimation gives ~100k points |
| RViz coloring | AxisColor on X (forward), 0.3–5 m | Depth cue for free; no RGB needed |
| UDP buffer | 2 GB max, Cyclone 10 MB | Problem 7 |
| Alignment | off (`HW` if you need a colored cloud) | Problem 6 |

![Point cloud of the room](images/03_point_cloud_working.png)

---

## Using RViz

In the 3D view, with the **Interact** tool selected:

| Action | Mouse |
|---|---|
| Rotate | Left button + drag |
| Zoom | Wheel (or right button + drag up/down) |
| Pan | Middle button + drag (or Shift + left button) |
| Measure a distance | **Measure** in the tool bar, click two points |
| Back to the start view | **Reset**, bottom left |

---

## License

[MIT](LICENSE) — use, copy and modify freely; keep the copyright notice.
Orbbec, Gemini, Jetson, Raspberry Pi and other names are trademarks of their owners; this project is
not affiliated with them.
