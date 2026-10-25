# Router2NVR: Turn Your Opkg-Supported Router into a Lightweight NVR

Transform your Opkg/Entware-supported router (tested on **Keenetic Hopper DSL AX1800**) into a 24/7 low-power Network Video Recorder (NVR). This project records RTSP streams directly to an EXT4 USB drive attached to your router using `ffmpeg` (copy mode, zero CPU encoding overhead), manages local storage automatically, and syncs completed recordings to a Windows backup server.

---

## Table of Contents
1. [System Architecture & Features](#-system-architecture--features)
2. [Step 1: Keenetic Router Preparation & Storage Setup](#step-1-keenetic-router-preparation--storage-setup)
3. [Step 2: SSH Access & OPKG Initialization](#step-2-ssh-access--opkg-initialization)
4. [Step 3: Installing FFmpeg & MIPS / MIPSEL Notes](#step-3-installing-ffmpeg--mips--mipsel-notes)
5. [Step 4: Creating & Deploying Router Scripts](#step-4-creating--deploying-router-scripts)
6. [Step 5: Verifying the Setup](#step-5-verifying-the-setup)
7. [Step 6: Automated Windows Archiving Script](#step-6-automated-windows-archiving-script)
8. [License & Attribution](#-license--attribution)

---

## System Architecture & Features

- **Headless & Low-Power:** Captures RTSP streams directly on the router using stream copying (`-c copy`), keeping CPU usage minimal.
- **Smart Local Storage Management:** Automated background script (`auto_clean.sh`) triggers at **95%** disk capacity and purges the oldest daily directories (`YYYY-MM-DD`) until usage drops below **85%**.
- **Seamless Local Archiving:** Windows batch script moves completed hourly `.mkv` files over SMB share while preserving current active recordings, with local PC drive cleanup (90% to 80%).

---

## Step 1: Keenetic Router Preparation & Storage Setup

Before deploying scripts, prepare your Keenetic router to support package management and Linux file systems.

1. **Install Essential Components:**
   * Access your Keenetic web interface.
   * Go to **Management** -> **General System Settings** -> **Component options** (*Sistem ayarları -> Bileşenler*).
   * Check and install: **OPKG package manager**, **SSH server support**, and **Ext file system support**.
   * Reboot your router to apply changes.

2. **Format USB Drive to EXT4:**
   * Plug your USB flash drive into the router.
   * Go to **Management** -> **System Information** or **Storages and Devices** (*Depolama ve Cihazlar*).
   * Format your USB drive to **EXT4** using the router's built-in utility (EXT4 is required for proper Linux permissions and symbolic links).

---

## Step 2: SSH Access & OPKG Initialization

1. **Connect via SSH:**
   * Open Terminal, PowerShell, or PuTTY and run:
     ```bash
     ssh admin@192.168.1.1
     ```
     *(Replace `192.168.1.1` with your router IP if different).*
   * Enter your router admin password when prompted. *(Note: Characters will not be visible while typing).*

2. **Update Package Manager:**
   ```bash
   opkg update
   ```

---

## Step 3: Installing FFmpeg & MIPS / MIPSEL Notes

1. **Architecture & Repository Notes:**
   * Keenetic Hopper DSL uses a MIPS/MIPSEL CPU architecture.
   * If `opkg install ffmpeg` fails due to target architecture mismatches, verify your architecture via `uname -m` or `opkg print-architecture`.
   * Configure the correct repository feed URL in `/opt/etc/opkg.conf` or manually fetch the `.ipk` package built for your router's specific MIPS variant.

2. **Install FFmpeg:**
   ```bash
   opkg install ffmpeg
   ```

3. **Verify Installation:**
   ```bash
   ffmpeg -version
   ```

---

## Step 4: Creating & Deploying Router Scripts

All router-side execution scripts are located under `/opt/bin/`, and auto-start init scripts are placed in `/opt/etc/init.d/`.

### 1. Recording Script (`/opt/bin/record.sh`)

Create the recording script:
```bash
nano /opt/bin/record.sh
```

Paste the following logic (replace RTSP credentials and camera IPs with your actual details):

```bash
#!/bin/sh

mkdir -p /opt/records/camera1 /opt/records/camera2

# Camera 1 Loop
(
  while true; do
    DATE_STR=$(date +%Y-%m-%d)
    TIME_STR=$(date +%H-%M)
    
    TARGET_DIR="/opt/records/camera1/$DATE_STR"
    mkdir -p "$TARGET_DIR"

    ffmpeg -y -loglevel error \
           -use_wallclock_as_timestamps 1 \
           -rtsp_transport tcp \
           -i "rtsp://YOUR_USERNAME:YOUR_PASSWORD@192.168.1.100:554/stream1" \
           -fflags +genpts \
           -c copy \
           -t 3600 \
           "$TARGET_DIR/$TIME_STR.mkv" >> /tmp/cam1.log 2>&1

    sleep 2
  done
) &

# Camera 2 Loop
(
  while true; do
    DATE_STR=$(date +%Y-%m-%d)
    TIME_STR=$(date +%H-%M)
    
    TARGET_DIR="/opt/records/camera2/$DATE_STR"
    mkdir -p "$TARGET_DIR"

    ffmpeg -y -loglevel error \
           -use_wallclock_as_timestamps 1 \
           -rtsp_transport tcp \
           -i "rtsp://YOUR_USERNAME:YOUR_PASSWORD@192.168.1.101:554/stream1" \
           -fflags +genpts \
           -c copy \
           -t 3600 \
           "$TARGET_DIR/$TIME_STR.mkv" >> /tmp/cam2.log 2>&1

    sleep 2
  done
) &

/opt/bin/auto_clean.sh &
```

### 2. Auto-Cleanup Script (`/opt/bin/auto_clean.sh`)

Create the automated space monitoring script:
```bash
nano /opt/bin/auto_clean.sh
```

Paste the following monitoring script:

```bash
#!/bin/sh

TARGET_DIR="/opt/records"
MAX_USAGE=95  # Trigger cleanup at 95% usage
MIN_USAGE=85  # Stop cleanup once usage drops below 85%

while true; do
    CURRENT_USAGE=$(df -h "$TARGET_DIR" | awk 'NR==2 {print $5}' | tr -d '%')

    if [ -n "$CURRENT_USAGE" ] && [ "$CURRENT_USAGE" -ge "$MAX_USAGE" ]; then
        echo "[$(date)] Disk usage at ${CURRENT_USAGE}%. Starting cleanup..." >> /tmp/cleaner.log
        
        while [ "$CURRENT_USAGE" -gt "$MIN_USAGE" ]; do
            OLDEST_DIR=$(find "$TARGET_DIR" -mindepth 2 -maxdepth 2 -type d -name "20*" 2>/dev/null | sort | head -n 1)

            if [ -n "$OLDEST_DIR" ] && [ -d "$OLDEST_DIR" ]; then
                rm -rf "$OLDEST_DIR"
                echo "[$(date)] Removed daily folder: $OLDEST_DIR" >> /tmp/cleaner.log
                CURRENT_USAGE=$(df -h "$TARGET_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
            else
                echo "[$(date)] No eligible date folder found to delete!" >> /tmp/cleaner.log
                break
            fi
        done
    fi

    sleep 300
done
```

### 3. Auto-Start Init Script (`/opt/etc/init.d/S99nvr`)

To ensure the recording service automatically starts whenever the router boots up or reboots, create an init script inside `/opt/etc/init.d/` (Entware automatically runs scripts starting with `S` on boot):

```bash
nano /opt/etc/init.d/S99nvr
```

Paste the following service initialization script:

```bash
#!/bin/sh

case "$1" in
  start)
    echo "Starting RTSP NVR recording service..."
    killall -9 ffmpeg >/dev/null 2>&1
    /opt/bin/record.sh
    ;;
  stop)
    echo "Stopping RTSP NVR recording service..."
    killall -9 ffmpeg record.sh >/dev/null 2>&1
    ;;
  restart)
    $0 stop
    sleep 2
    $0 start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
exit 0
```

### 4. Execution Permissions & Launch

Grant execution permissions to all scripts:
```bash
chmod +x /opt/bin/record.sh
chmod +x /opt/bin/auto_clean.sh
chmod +x /opt/etc/init.d/S99nvr
```

Start or manage the service anytime using the init script:
```bash
/opt/etc/init.d/S99nvr start
```

---

## Step 5: Verifying the Setup

1. **Check Active FFmpeg Processes:**
   ```bash
   ps | grep ffmpeg
   ```
   *Expected Output:*
   ```text
   1234 admin     2450 S   ffmpeg -y -loglevel error -use_wallclock_as_timestamps 1 -rtsp_transport tcp -i rtsp://...
   5678 admin     2450 S   ffmpeg -y -loglevel error -use_wallclock_as_timestamps 1 -rtsp_transport tcp -i rtsp://...
   ```

2. **Inspect Logs & Video Storage:**
   * Monitor output via `cat /tmp/cam1.log` or `cat /tmp/cleaner.log`.
   * Files appear under `/opt/records/cameraX/YYYY-MM-DD/HH-mm.mkv`.

---

## Step 6: Automated Windows Archiving Script

On your local Windows machine, save the following script as `transfer_records.bat` to sync completed files from the router SMB share to your archival hard drive (`J:`):

```bat
@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

title Camera Transfer and Organization System

set "MODEM1=\\KEENETIC-5440\EXT4-0lWozds0\records\camera1"
set "MODEM2=\\KEENETIC-5440\EXT4-0lWozds0\records\camera2"
set "YEREL_DEPO=J:\KameraKayitlari"

echo ===================================================
echo [%date% %time%] Camera transfer process started...
echo ===================================================

:: 1. LOCAL DISK CLEANUP (90% -> 80%)
echo [1/3] Checking local disk capacity (J:)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq 'J:'; if ($d) { $p = [math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 1); Write-Host 'Current Usage:' $p'%%'; if ($p -gt 90) { Get-ChildItem -Path 'J:\KameraKayitlari' -Recurse -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object CreationTime | ForEach-Object { $cur = Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq 'J:'; $cp = (($cur.Size - $cur.FreeSpace)/$cur.Size)*100; if ($cp -le 80) { break }; Remove-Item -Path $_.FullName -Recurse -Force } } }"

:: 2. TRANSFER COMPLETED RECORDINGS
echo [2/3] Transferring completed records from router...
if exist "%MODEM1%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$src = '%MODEM1%'; $dest = '%YEREL_DEPO%\Kamera-1'; if (Test-Path $src) { $folders = Get-ChildItem -Path $src -Directory; foreach ($fld in $folders) { $tDir = Join-Path $dest $fld.Name; if (-not (Test-Path $tDir)) { New-Item -ItemType Directory -Path $tDir -Force | Out-Null }; $isToday = ($fld.Name -eq (Get-Date).ToString('yyyy-MM-dd')); $files = Get-ChildItem -Path $fld.FullName -Filter '*.mkv' | Sort-Object Name; if ($files.Count -gt 0) { $toMove = if ($isToday) { if ($files.Count -gt 1) { $files | Select-Object -First ($files.Count - 1) } else { @() } } else { $files }; foreach ($file in $toMove) { Move-Item -Path $file.FullName -Destination (Join-Path $tDir $file.Name) -Force }; Write-Host ('Camera 1 (' + $fld.Name + '): ' + $toMove.Count + ' files transferred.') }; if (-not $isToday -and (Get-ChildItem -Path $fld.FullName).Count -eq 0) { Remove-Item -Path $fld.FullName -Force } } }"
)

if exist "%MODEM2%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$src = '%MODEM2%'; $dest = '%YEREL_DEPO%\Kamera-2'; if (Test-Path $src) { $folders = Get-ChildItem -Path $src -Directory; foreach ($fld in $folders) { $tDir = Join-Path $dest $fld.Name; if (-not (Test-Path $tDir)) { New-Item -ItemType Directory -Path $tDir -Force | Out-Null }; $isToday = ($fld.Name -eq (Get-Date).ToString('yyyy-MM-dd')); $files = Get-ChildItem -Path $fld.FullName -Filter '*.mkv' | Sort-Object Name; if ($files.Count -gt 0) { $toMove = if ($isToday) { if ($files.Count -gt 1) { $files | Select-Object -First ($files.Count - 1) } else { @() } } else { $files }; foreach ($file in $toMove) { Move-Item -Path $file.FullName -Destination (Join-Path $tDir $file.Name) -Force }; Write-Host ('Camera 2 (' + $fld.Name + '): ' + $toMove.Count + ' files transferred.') }; if (-not $isToday -and (Get-ChildItem -Path $fld.FullName).Count -eq 0) { Remove-Item -Path $fld.FullName -Force } } }"
)

:: 3. CLEANUP EMPTY DIRECTORIES
echo [3/3] Cleaning empty directories...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path 'J:\KameraKayitlari' -Recurse -Directory | Where-Object { (Get-ChildItem -Path $_.FullName -Recurse -File).Count -eq 0 } | Sort-Object FullName -Descending | ForEach-Object { Remove-Item -Path $_.FullName -Force -Recurse }"

echo Process completed!
pause
```
