#!/bin/sh

mkdir -p /opt/records/camera1 /opt/records/camera2

# camera 1 loop
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

# camera 2 loop
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