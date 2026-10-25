#!/bin/sh

TARGET_DIR="/opt/records"
MAX_USAGE=95  # Cleanup starts if disk usage reaches 95%
MIN_USAGE=85  # Deletes until disk usage drops below 85%

while true; do
    # Get current disk usage percentage
    CURRENT_USAGE=$(df -h "$TARGET_DIR" | awk 'NR==2 {print $5}' | tr -d '%')

    if [ -n "$CURRENT_USAGE" ] && [ "$CURRENT_USAGE" -ge "$MAX_USAGE" ]; then
        echo "[$(date)] Disk usage at ${CURRENT_USAGE}% (Threshold: ${MAX_USAGE}%). Starting cleanup..." >> /tmp/cleaner.log
        
        # Delete oldest date folders until disk usage falls below MIN_USAGE (85%)
        while [ "$CURRENT_USAGE" -gt "$MIN_USAGE" ]; do
            # Find the oldest YYYY-MM-DD folder inside camera directories
            # (Alphabetical sorting matches chronological order for YYYY-MM-DD format)
            OLDEST_DIR=$(find "$TARGET_DIR" -mindepth 2 -maxdepth 2 -type d -name "20*" 2>/dev/null | sort | head -n 1)

            if [ -n "$OLDEST_DIR" ] && [ -d "$OLDEST_DIR" ]; then
                rm -rf "$OLDEST_DIR"
                echo "[$(date)] Removed (Daily Folder): $OLDEST_DIR" >> /tmp/cleaner.log
                
                # Re-check current disk usage
                CURRENT_USAGE=$(df -h "$TARGET_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
            else
                echo "[$(date)] No eligible date folder found to delete!" >> /tmp/cleaner.log
                break
            fi
        done
    fi

    # Check disk usage every 5 minutes
    sleep 300
done