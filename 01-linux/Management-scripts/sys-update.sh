#!/bin/bash

# Define log file
LOG_FILE="/var/log/server-autoupdate.log"

# Identify server
HOSTNAME=$(hostname)
EMAIL_TO="support@4techworks.com"
EMAIL_FROM="4techworks@gmail.com"
REPORT_FILE="/tmp/sys-update-report.txt"

echo "=== Update Started: $(date) ===" >> "$LOG_FILE"
echo "Host: $HOSTNAME" >> "$LOG_FILE"

# Do not automatically patch Proxmox hypervisors
if command -v pveversion >/dev/null 2>&1; then
    echo "Proxmox VE detected - automatic updates skipped." >> "$LOG_FILE"
    echo "Update Result: SKIPPED" >> "$LOG_FILE"
    echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    exit 0
fi

# Detect Ubuntu / Debian
if [ -f /etc/debian_version ]; then

    export DEBIAN_FRONTEND=noninteractive

    # Refresh package repositories
    if apt-get update >> "$LOG_FILE" 2>&1; then
        echo "Repository Refresh: SUCCESS" >> "$LOG_FILE"
    else
        echo "Repository Refresh: FAILED" >> "$LOG_FILE"
        echo "Package Upgrade: NOT RUN" >> "$LOG_FILE"
        echo "Update Result: FAILED" >> "$LOG_FILE"
        echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        exit 1
    fi

    # Install available upgrades
    if apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
        echo "Package Upgrade: SUCCESS" >> "$LOG_FILE"
    else
        echo "Package Upgrade: FAILED" >> "$LOG_FILE"
        echo "Update Result: FAILED" >> "$LOG_FILE"
        echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        exit 1
    fi

    # Clean package cache
    if apt-get clean >> "$LOG_FILE" 2>&1; then
        echo "APT Cache Cleanup: SUCCESS" >> "$LOG_FILE"
    else
        echo "APT Cache Cleanup: FAILED" >> "$LOG_FILE"
    fi

else
    echo "Unsupported OS distribution." >> "$LOG_FILE"
    echo "Update Result: FAILED" >> "$LOG_FILE"
    echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    exit 1
fi

# Check whether packages remain upgradeable
UPGRADEABLE_COUNT=$(apt list --upgradeable 2>/dev/null | tail -n +2 | wc -l)

echo "Packages Remaining Upgradeable: $UPGRADEABLE_COUNT" >> "$LOG_FILE"

if [ "$UPGRADEABLE_COUNT" -gt 0 ]; then
    echo "Remaining Upgradeable Packages:" >> "$LOG_FILE"
    apt list --upgradeable 2>/dev/null | tail -n +2 >> "$LOG_FILE"
fi

# Check whether a reboot is required
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED="YES"
    echo "Reboot Required: YES" >> "$LOG_FILE"

    if [ -f /var/run/reboot-required.pkgs ]; then
        echo "Reboot-triggering packages:" >> "$LOG_FILE"
        cat /var/run/reboot-required.pkgs >> "$LOG_FILE"
    fi
else
    REBOOT_REQUIRED="NO"
    echo "Reboot Required: NO" >> "$LOG_FILE"
fi

UPDATE_RESULT="SUCCESS"

echo "Update Result: $UPDATE_RESULT" >> "$LOG_FILE"
echo "=== Update Finished: $(date) ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Build email report
{
    echo "Host: $HOSTNAME"
    echo "Repository Refresh: SUCCESS"
    echo "Package Upgrade: SUCCESS"
    echo "APT Cache Cleanup: SUCCESS"
    echo "Packages Remaining Upgradeable: $UPGRADEABLE_COUNT"
    echo "Reboot Required: $REBOOT_REQUIRED"
    echo "Update Result: $UPDATE_RESULT"

    if [ "$UPGRADEABLE_COUNT" -gt 0 ]; then
        echo ""
        echo "Remaining Upgradeable Packages:"
        apt list --upgradeable 2>/dev/null | tail -n +2
    fi

    if [ "$REBOOT_REQUIRED" = "YES" ] && [ -f /var/run/reboot-required.pkgs ]; then
        echo ""
        echo "Reboot-triggering packages:"
        cat /var/run/reboot-required.pkgs
    fi
} > "$REPORT_FILE"

# Build email subject
if [ "$REBOOT_REQUIRED" = "YES" ]; then
    EMAIL_SUBJECT="[Linux Fleet][$HOSTNAME] Update SUCCESS - REBOOT REQUIRED"
else
    EMAIL_SUBJECT="[Linux Fleet][$HOSTNAME] Update SUCCESS"
fi

# Send email report
{
    echo "Subject: $EMAIL_SUBJECT"
    echo "To: $EMAIL_TO"
    echo "From: $EMAIL_FROM"
    echo ""
    cat "$REPORT_FILE"
} | msmtp "$EMAIL_TO"

rm -f "$REPORT_FILE"

exit 0
