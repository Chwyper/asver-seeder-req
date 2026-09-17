#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# File to track the installation state across reboots
STATE_FILE="/etc/hailo_install_state"

# Function to handle errors
trap 'echo "An error occurred during execution. Please check the logs."' ERR

# Determine current state
if [ ! -f "$STATE_FILE" ]; then
    echo "=== Step 1: System Update & EEPROM Upgrade ==="
    sudo apt update
    sudo apt full-upgrade -y
    sudo rpi-eeprom-update -a
    
    echo "=== System needs to reboot for updates and EEPROM ==="
    echo "The script will automatically resume after the reboot."
    
    # Mark state for the next run
    echo "STAGE_2" | sudo tee "$STATE_FILE" > /dev/null
    
    sudo reboot
elif [ "$(cat "$STATE_FILE")" = "STAGE_2" ]; then
    echo "=== Step 2: Installing DKMS and Hailo Packages ==="
    sudo apt install dkms -y
    sudo apt install hailo-all -y
    
    echo "=== System needs to reboot to load Hailo drivers ==="
    echo "The script will automatically resume after the reboot."
    
    # Mark state for the final run
    echo "STAGE_3" | sudo tee "$STATE_FILE" > /dev/null
    
    sudo reboot
elif [ "$(cat "$STATE_FILE")" = "STAGE_3" ]; then
    echo "=== Step 3: Verifying Installation & Installing Camera Apps ==="
    
    # Clean up the state file
    sudo rm -f "$STATE_FILE"
    
    echo "Running Hailo firmware identification..."
    hailortcli fw-control identify || echo "Warning: hailortcli check failed or device not fully initialized."
    
    echo "Updating and installing rpicam-apps..."
    sudo apt update
    sudo apt install rpicam-apps -y
    
    echo "=========================================="
    echo " Setup complete successfully! "
    echo "=========================================="
fi