#!/bin/bash

# -----------------------------
# Global Variables
# -----------------------------

FAIL_COUNT=0
WARN_COUNT=0

FAIL_MESSAGES=""
WARN_MESSAGES=""

HOSTNAME=$(hostname)

# -----------------------------
# Thresholds
# -----------------------------

DISK_WARNING=80
DISK_CRITICAL=90

MEMORY_WARNING=80
MEMORY_CRITICAL=90

# -----------------------------
# Email Configuration
# -----------------------------

EMAIL_TO="support@4techworks.com"
EMAIL_FROM="4techworks@gmail.com"
REPORT_FILE="/tmp/fleet-healthcheck-report.txt"

# -----------------------------
# Service Check Function
# -----------------------------

check_service() {
    SERVICE="$1"

    if systemctl is-active --quiet "$SERVICE"; then
        echo "PASS: Service $SERVICE is active"
    else
        MESSAGE="FAIL: Service $SERVICE is not active"
        echo "$MESSAGE"
        FAIL_MESSAGES+="$MESSAGE"$'\n'
        ((FAIL_COUNT++))
    fi
}

# -----------------------------
# Port Check Function
# -----------------------------

check_port() {
    PORT="$1"

    if ss -ltn | grep -q ":$PORT"; then
        echo "PASS: TCP port $PORT is listening"
    else
        MESSAGE="FAIL: TCP port $PORT is not listening"
        echo "$MESSAGE"
        FAIL_MESSAGES+="$MESSAGE"$'\n'
        ((FAIL_COUNT++))
    fi
}

# -----------------------------
# Disk Check Function
# -----------------------------

check_disk() {
    USAGE=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')

    if [ "$USAGE" -ge "$DISK_CRITICAL" ]; then
        MESSAGE="FAIL: Root filesystem utilization is ${USAGE}%"
        echo "$MESSAGE"
        FAIL_MESSAGES+="$MESSAGE"$'\n'
        ((FAIL_COUNT++))

    elif [ "$USAGE" -ge "$DISK_WARNING" ]; then
        MESSAGE="WARN: Root filesystem utilization is ${USAGE}%"
        echo "$MESSAGE"
        WARN_MESSAGES+="$MESSAGE"$'\n'
        ((WARN_COUNT++))

    else
        echo "PASS: Root filesystem utilization is ${USAGE}%"
    fi
}

# -----------------------------
# Memory Check Function
# -----------------------------

check_memory() {
    MEMORY_USED_PERCENT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

    if [ "$MEMORY_USED_PERCENT" -ge "$MEMORY_CRITICAL" ]; then
        MESSAGE="FAIL: Memory utilization is ${MEMORY_USED_PERCENT}%"
        echo "$MESSAGE"
        FAIL_MESSAGES+="$MESSAGE"$'\n'
        ((FAIL_COUNT++))

    elif [ "$MEMORY_USED_PERCENT" -ge "$MEMORY_WARNING" ]; then
        MESSAGE="WARN: Memory utilization is ${MEMORY_USED_PERCENT}%"
        echo "$MESSAGE"
        WARN_MESSAGES+="$MESSAGE"$'\n'
        ((WARN_COUNT++))

    else
        echo "PASS: Memory utilization is ${MEMORY_USED_PERCENT}%"
    fi
}

# -----------------------------
# Pending Update Check Function
# -----------------------------

check_updates() {
    UPGRADEABLE_COUNT=$(apt list --upgradeable 2>/dev/null | tail -n +2 | wc -l)

    if [ "$UPGRADEABLE_COUNT" -gt 0 ]; then
        MESSAGE="WARN: $UPGRADEABLE_COUNT package(s) pending upgrade"
        echo "$MESSAGE"
        WARN_MESSAGES+="$MESSAGE"$'\n'
        ((WARN_COUNT++))
    else
        echo "PASS: No packages pending upgrade"
    fi
}

# -----------------------------
# Health Check Header
# -----------------------------

echo "=== Fleet Health Check: $(date) ==="
echo "Host: $HOSTNAME"
echo ""

# -----------------------------
# Service Checks
# -----------------------------

check_service ssh
check_service nginx
check_service noc-app
check_service docker
check_service containerd
check_service qemu-guest-agent

# -----------------------------
# Port Checks
# -----------------------------

echo ""

check_port 22
check_port 80
check_port 9100

# -----------------------------
# Disk Check
# -----------------------------

echo ""

check_disk

# -----------------------------
# Memory Check
# -----------------------------

echo ""

check_memory

# -----------------------------
# Pending Update Check
# -----------------------------

echo ""

check_updates

# -----------------------------
# Overall Health Evaluation
# -----------------------------

echo ""
echo "Warnings Detected: $WARN_COUNT"
echo "Failures Detected: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    OVERALL_STATUS="CRITICAL"
    EXIT_CODE=1

elif [ "$WARN_COUNT" -gt 0 ]; then
    OVERALL_STATUS="WARNING"
    EXIT_CODE=2

else
    OVERALL_STATUS="HEALTHY"
    EXIT_CODE=0
fi

echo "Overall Status: $OVERALL_STATUS"

# -----------------------------
# Email Handler
# -----------------------------

if [ "$OVERALL_STATUS" != "HEALTHY" ]; then

    {
        echo "Host: $HOSTNAME"
        echo "Overall Status: $OVERALL_STATUS"
        echo "Warnings Detected: $WARN_COUNT"
        echo "Failures Detected: $FAIL_COUNT"

        if [ -n "$FAIL_MESSAGES" ]; then
            echo ""
            echo "FAILED CHECKS:"
            echo ""
            printf "%s" "$FAIL_MESSAGES"
        fi

        if [ -n "$WARN_MESSAGES" ]; then
            echo ""
            echo "WARNING CHECKS:"
            echo ""
            printf "%s" "$WARN_MESSAGES"
        fi

    } > "$REPORT_FILE"

    {
        echo "Subject: [Linux Fleet][$HOSTNAME][$OVERALL_STATUS] Health Check"
        echo "To: $EMAIL_TO"
        echo "From: $EMAIL_FROM"
        echo ""
        cat "$REPORT_FILE"

    } | msmtp "$EMAIL_TO"

    rm -f "$REPORT_FILE"
fi

# -----------------------------
# Exit Handler
# -----------------------------

exit "$EXIT_CODE"