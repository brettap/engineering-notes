#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="qemu-guest-agent"
PACKAGE_NAME="qemu-guest-agent"

echo "Checking for ${PACKAGE_NAME}..."

if dpkg -s "$PACKAGE_NAME" >/dev/null 2>&1; then
    echo "${PACKAGE_NAME} is already installed."
else
    echo "${PACKAGE_NAME} is not installed. Installing..."
    sudo apt update
    sudo apt install -y "$PACKAGE_NAME"
fi

echo "Checking service status..."

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "${SERVICE_NAME} is active and running."
else
    echo "${SERVICE_NAME} is not running. Attempting to start it..."
    sudo systemctl start "$SERVICE_NAME"
fi

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "SUCCESS: ${SERVICE_NAME} is running."
else
    echo "ERROR: ${SERVICE_NAME} failed to start."
    sudo systemctl status "$SERVICE_NAME" --no-pager
    exit 1
fi