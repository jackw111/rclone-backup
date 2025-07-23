#!/bin/bash

# ==============================================================================
# Rclone Uninstaller Script
#
# This script uninstalls rclone that was installed via the official script.
# It performs the following actions:
# 1. Checks for root (sudo) privileges.
# 2. Finds and removes the rclone binary.
# 3. Finds and removes the rclone man page.
# 4. Asks the user if they want to remove the rclone configuration directory.
# 5. Verifies the uninstallation.
#
# Usage:
# 1. Save this code as "uninstall_rclone.sh".
# 2. Make it executable: chmod +x uninstall_rclone.sh
# 3. Run it with sudo:   sudo ./uninstall_rclone.sh
# ==============================================================================

# --- Colors for output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Rclone Uninstaller ---${NC}"

# --- Step 1: Check for root privileges ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run with sudo.${NC}"
   echo "Please run it like this: sudo ./uninstall_rclone.sh"
   exit 1
fi

echo "Running with sudo privileges..."

# --- Step 2: Find and remove the rclone binary ---
RCLONE_BIN=$(which rclone)

if [ -n "$RCLONE_BIN" ]; then
    echo "Found rclone binary at: $RCLONE_BIN"
    echo "Removing rclone binary..."
    rm -f "$RCLONE_BIN"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully removed rclone binary.${NC}"
    else
        echo -e "${RED}Failed to remove rclone binary.${NC}"
    fi
else
    echo -e "${YELLOW}rclone binary not found in PATH. It might already be uninstalled.${NC}"
fi

# --- Step 3: Find and remove the rclone man page ---
MAN_PAGE="/usr/local/share/man/man1/rclone.1"
if [ -f "$MAN_PAGE" ]; then
    echo "Found man page at: $MAN_PAGE"
    echo "Removing rclone man page..."
    rm -f "$MAN_PAGE"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully removed man page.${NC}"
    else
        echo -e "${RED}Failed to remove man page.${NC}"
    fi
else
    echo -e "${YELLOW}rclone man page not found.${NC}"
fi

# --- Step 4: Ask to remove configuration ---
# The config is in the user's home directory, not the root's.
# We need to use $SUDO_USER to find the correct home directory.
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    # Construct the path to the user's config directory
    # Handles both /home/user and /Users/user (for macOS)
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    CONFIG_DIR="$USER_HOME/.config/rclone"

    if [ -d "$CONFIG_DIR" ]; then
        echo -e "\n${YELLOW}WARNING: Found rclone configuration directory at: ${CONFIG_DIR}${NC}"
        echo "This directory contains all your remote connection settings."
        read -p "Do you want to PERMANENTLY DELETE this configuration directory? (y/N): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "Removing configuration directory..."
            rm -rf "$CONFIG_DIR"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Configuration directory successfully removed.${NC}"
            else
                echo -e "${RED}Failed to remove configuration directory.${NC}"
            fi
        else
            echo "Skipping removal of configuration directory."
        fi
    else
        echo "No rclone configuration directory found for user '$SUDO_USER'."
    fi
else
    echo -e "\n${YELLOW}Could not determine the original user. Skipping check for configuration files.${NC}"
    echo "You may need to manually remove ~/.config/rclone"
fi

# --- Step 5: Verification ---
echo -e "\n--- Verifying Uninstallation ---"
if ! command -v rclone &> /dev/null; then
    echo -e "${GREEN}Success! Rclone seems to be successfully uninstalled.${NC}"
    echo "You can double-check by running 'rclone --version'. It should say 'command not found'."
else
    echo -e "${RED}Verification failed. 'rclone' command is still found at: $(which rclone)${NC}"
    echo "This might happen if rclone was installed in multiple locations or by a package manager."
fi

echo -e "\n${GREEN}Uninstallation process finished.${NC}"

