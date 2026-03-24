#!/bin/bash

# Ventoy USB Setup for Unraid Recovery
# This script sets up a Ventoy USB with SystemRescue ISO and recovery scripts.
# NEW: Automatically downloads and installs Ventoy if not already present.
# Includes version tracking and upgrade support.

set -e

VERSION="1.1.7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration file
INI_FILE="${SCRIPT_DIR}/setup_ventoy.ini"
if [[ ! -f "$INI_FILE" ]]; then
    echo "❌ ERROR: setup_ventoy.ini not found in $SCRIPT_DIR"
    echo "   Expected location: $INI_FILE"
    exit 1
fi
source "$INI_FILE"

# Argument parsing
UPGRADE_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -upgrade)
            UPGRADE_MODE=true
            shift
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Usage: $0 [-upgrade]"
            exit 1
            ;;
    esac
done

# Global variables
VENTOY_DEVICE=""
VENTOY_MOUNT=""
IS_UNRAID=false
VENTOY_FRESH_INSTALL=false

printf "╔════════════════════════════════════════════════════╗\n"
printf "║  Ventoy USB Setup for Unraid Recovery              ║\n"
printf "║  Version: %-41s║\n" "$VERSION"
printf "╚════════════════════════════════════════════════════╝\n"
printf "\n"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function to prompt for yes/no with validation and default
# Usage: ask_yes_no "prompt text" "default_value"
# Returns: 0 for yes, 1 for no
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response

    # Format the prompt with default indicator
    if [ "$default" = "yes" ]; then
        prompt="$prompt (YES/no): "
    elif [ "$default" = "no" ]; then
        prompt="$prompt (yes/NO): "
    else
        prompt="$prompt (yes/no): "
    fi

    while true; do
        read -p "$prompt" response

        # If empty response, use default
        if [ -z "$response" ]; then
            if [ -n "$default" ]; then
                response="$default"
            else
                echo "Please enter yes or no."
                continue
            fi
        fi

        # Check for valid yes/no response (case insensitive)
        case "${response,,}" in
            yes|y)
                return 0
                ;;
            no|n)
                return 1
                ;;
            *)
                echo "Invalid input. Please enter 'yes' or 'no'."
                ;;
        esac
    done
}

# Function to verify SHA512 hash
verify_sha512() {
    local iso_file="$1"
    local sha_file="$2"

    echo "Verifying SHA512 hash..."

    # Check if sha512sum command is available
    if ! command -v sha512sum &> /dev/null; then
        echo "❌ ERROR: sha512sum command not found!"
        echo "   Please install coreutils package."
        return 1
    fi

    # Compute the hash of the ISO
    echo "  Computing hash of ISO file..."
    COMPUTED_HASH=$(sha512sum "$iso_file" | awk '{print $1}')

    # Read the expected hash from the .sha512 file
    # The file format is: HASH  FILENAME
    EXPECTED_HASH=$(awk '{print $1}' "$sha_file")

    echo "  Comparing hashes..."
    if [ "$COMPUTED_HASH" = "$EXPECTED_HASH" ]; then
        echo "  ✅ SHA512 verification PASSED!"
        echo "  Hash: ${COMPUTED_HASH:0:16}...${COMPUTED_HASH: -16}"
        return 0
    else
        echo "  ❌ SHA512 verification FAILED!"
        echo "  Expected: ${EXPECTED_HASH:0:16}...${EXPECTED_HASH: -16}"
        echo "  Computed: ${COMPUTED_HASH:0:16}...${COMPUTED_HASH: -16}"
        echo
        echo "  ⚠️  CRITICAL ERROR: Hash mismatch detected!"
        echo "  The ISO file may be corrupted or tampered with."
        echo "  Please re-download the ISO and try again."
        return 1
    fi
}

# Function to verify SHA256 hash
verify_sha256() {
    local file="$1"
    local sha_file="$2"

    echo "Verifying SHA256 hash..."

    if ! command -v sha256sum &> /dev/null; then
        echo "❌ ERROR: sha256sum command not found!"
        return 1
    fi

    local filename=$(basename "$file")

    # Extract expected hash from sha256.txt
    local expected_hash=$(grep "$filename" "$sha_file" 2>/dev/null | awk '{print $1}')
    if [ -z "$expected_hash" ]; then
        echo "❌ ERROR: Could not find hash for $filename in sha256.txt"
        return 1
    fi

    # Compute actual hash
    local computed_hash=$(sha256sum "$file" | awk '{print $1}')

    echo "  Filename: $filename"
    echo "  Comparing hashes..."

    if [ "$computed_hash" = "$expected_hash" ]; then
        echo "  ✅ SHA256 verification PASSED!"
        echo "  Hash: ${computed_hash:0:16}...${computed_hash: -16}"
        return 0
    else
        echo "  ❌ SHA256 verification FAILED!"
        echo "  Expected: ${expected_hash:0:16}...${expected_hash: -16}"
        echo "  Computed: ${computed_hash:0:16}...${computed_hash: -16}"
        return 1
    fi
}

# Version comparison helpers
version_gt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]
}

version_eq() {
    [ "$1" = "$2" ]
}

# ============================================================================
# MAIN SETUP FUNCTIONS
# ============================================================================

# Function to scan for Ventoy USB or available USB for Ventoy installation
check_ventoy_origin() {
    echo "Checking for Ventoy USB..."
    local ventoy_info

    # Check if we're running on Unraid
    local kernel_info=$(uname -a)
    if echo "$kernel_info" | grep -q "Unraid"; then
        IS_UNRAID=true
    fi

    # Use lsblk to find Ventoy partition on USB
    ventoy_info=$(lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN 2>/dev/null | grep 'LABEL="Ventoy"' | head -1)

    if [ -n "$ventoy_info" ]; then
        VENTOY_DEVICE_NAME=$(echo "$ventoy_info" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
        VENTOY_DEVICE="/dev/$VENTOY_DEVICE_NAME"

        echo "✅ Found existing Ventoy USB: $VENTOY_DEVICE"
        VENTOY_FRESH_INSTALL=false
        return 0
    fi

    echo "⚠️  No existing Ventoy USB found."
    echo
    echo "Scanning for available USB drives to set up Ventoy..."

    # Scan for available USB drives
    declare -a usb_devices
    declare -a usb_models
    declare -a usb_sizes
    declare -a usb_labels

    # Get all lsblk data
    local lsblk_data
    lsblk_data=$(lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN 2>/dev/null)

    # Find all USB devices (not partitions) that are ≥ 2GB
    # Then check their partitions for any UNRAID/UNRAID_DR labels to exclude
    declare -A excluded_devices

    # First, mark any devices that have UNRAID or UNRAID_DR partitions as excluded
    while IFS= read -r line; do
        local name=$(echo "$line" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
        local label=$(echo "$line" | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)

        # Check if this partition is UNRAID or UNRAID_DR
        if [[ "$label" == "UNRAID" || "$label" == "UNRAID_DR" ]]; then
            # Mark the parent device as excluded
            local parent_device=$(echo "$name" | sed 's/[0-9]*$//' | sed 's/p$//')
            excluded_devices[$parent_device]=1
        fi
    done <<< "$lsblk_data"

    # Now find all USB devices (not partitions) that meet requirements
    while IFS= read -r line; do
        local name=$(echo "$line" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
        local size=$(echo "$line" | grep -o 'SIZE="[^"]*"' | cut -d'"' -f2)
        local tran=$(echo "$line" | grep -o 'TRAN="[^"]*"' | cut -d'"' -f2)

        # Check if this is a device (not a partition - doesn't end with number)
        if [[ ! "$name" =~ [0-9]$ ]] && [ "$tran" = "usb" ] && [ "$size" -ge 2000000000 ]; then
            # Skip if this device or any of its partitions are UNRAID/UNRAID_DR
            if [ -n "${excluded_devices[$name]}" ]; then
                continue
            fi

            # Get device model
            local model=$(lsblk -n -d -o MODEL "/dev/$name" 2>/dev/null | xargs)
            [ -z "$model" ] && model="Unknown"

            # Get the device's current label (if any partition has one)
            local device_label=""
            while IFS= read -r pline; do
                local pname=$(echo "$pline" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
                local plabel=$(echo "$pline" | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)

                # Check if this partition belongs to our device
                if [[ "$pname" =~ ^${name}[0-9] ]] && [ -n "$plabel" ]; then
                    device_label="$plabel"
                    break
                fi
            done <<< "$lsblk_data"

            [ -z "$device_label" ] && device_label="(no label)"

            usb_devices+=("$name")
            usb_models+=("$model")
            usb_sizes+=("$size")
            usb_labels+=("$device_label")
        fi
    done <<< "$lsblk_data"

    if [ ${#usb_devices[@]} -eq 0 ]; then
        echo "❌ ERROR: No suitable USB drives found!"
        echo "   Requirements:"
        echo "     - USB transport (not internal disk)"
        echo "     - Size ≥ 2GB"
        echo "     - Not labeled UNRAID or UNRAID_DR (reserved for boot/backup)"
        echo "   Did you plug in a USB drive?"
        exit 1
    fi

    echo "Found ${#usb_devices[@]} available USB drive(s):"
    echo

    for i in "${!usb_devices[@]}"; do
        local size_gb=$(awk "BEGIN {printf \"%.2f\", ${usb_sizes[$i]} / 1024 / 1024 / 1024}")
        echo "  [$((i+1))] Device: ${usb_devices[$i]}"
        echo "      Model:  ${usb_models[$i]}"
        echo "      Size:   ${size_gb} GB"
        echo "      Label:  ${usb_labels[$i]}"
        echo
    done

    # Build list of valid choices for the prompt
    local device_count=${#usb_devices[@]}
    local valid_choices=""
    local i
    for ((i=1; i<=device_count; i++)); do
        if [ $i -gt 1 ]; then
            valid_choices="$valid_choices,$i"
        else
            valid_choices="$i"
        fi
    done

    # Build grammatically correct error message suffix
    local choice_prompt
    if [ "$device_count" -eq 1 ]; then
        choice_prompt="Only option is 1"
    else
        choice_prompt="Please choose between $valid_choices"
    fi

    # Get device selection from user by index
    local selected_index=""
    local selected_device=""
    local attempt=0
    local max_attempts=2

    while true; do
        # Show prompt with available choices
        printf "Select USB drive by index number (%s): " "$valid_choices"
        read -r selected_index || selected_index=""

        # Special case: if only one device and user pressed Enter, auto-select it
        if [ -z "$selected_index" ] && [ "$device_count" -eq 1 ]; then
            selected_index="1"
        fi

        # Check if user entered anything
        if [ -z "$selected_index" ]; then
            ((attempt++)) || true
            printf "❌ Please enter a valid choice (%s)\n" "$valid_choices"
            if [ "$attempt" -ge "$max_attempts" ]; then
                printf "❌ Maximum attempts reached. Exiting.\n"
                exit 1
            fi
            continue
        fi

        # Validate that input is a number
        if ! printf '%d' "$selected_index" >/dev/null 2>&1; then
            ((attempt++)) || true
            printf "❌ Invalid input '%s'. Please enter a number from: %s\n" "$selected_index" "$valid_choices"
            if [ "$attempt" -ge "$max_attempts" ]; then
                printf "❌ Maximum attempts reached. Exiting.\n"
                exit 1
            fi
            continue
        fi

        # Validate that index is in valid range (1 to count of devices)
        if [ "$selected_index" -lt 1 ] || [ "$selected_index" -gt "$device_count" ]; then
            ((attempt++)) || true
            printf "❌ Invalid selection '%s'. %s\n" "$selected_index" "$choice_prompt"
            if [ "$attempt" -ge "$max_attempts" ]; then
                printf "❌ Maximum attempts reached. Exiting.\n"
                exit 1
            fi
            continue
        fi

        # Valid selection - get device at the selected index (convert 1-based to 0-based)
        local index=$((selected_index - 1))
        selected_device="${usb_devices[$index]}"
        break
    done

    echo
    echo "⚠️  WARNING: Device /dev/$selected_device will be formatted!"
    echo "    All data will be PERMANENTLY LOST."
    echo

    # Confirm with YES
    local confirmation=""
    attempt=0
    while [ $attempt -lt 2 ]; do
        echo -n "Type 'YES' to proceed: "
        read confirmation

        if [ "$confirmation" = "YES" ]; then
            break
        else
            ((attempt++))
            if [ $attempt -lt 2 ]; then
                echo "❌ Incorrect. Type 'YES' to continue."
            else
                echo "❌ Cancelled. Exiting."
                exit 1
            fi
        fi
    done

    echo
    echo "Preparing to install Ventoy..."
    echo

    # Check /var/tmp space
    local avail_mb
    avail_mb=$(df /var/tmp 2>/dev/null | awk 'NR==2 {print int($4/1024)}')

    if [ -z "$avail_mb" ] || [ "$avail_mb" -lt 100 ]; then
        echo "❌ ERROR: Insufficient space in /var/tmp"
        echo "   Need at least 100MB, only ${avail_mb}MB available"
        exit 1
    fi

    echo "  ✅ /var/tmp: ${avail_mb}MB available"
    echo

    # Download Ventoy
    echo "Downloading Ventoy ${VENTOY_VERSION}..."
    local ventoy_tar="/var/tmp/ventoy-${VENTOY_VERSION}-linux.tar.gz"

    if ! wget -O "$ventoy_tar" "$VENTOY_DL_URL" 2>&1 | tail -5; then
        echo "❌ ERROR: Failed to download Ventoy"
        exit 1
    fi

    echo "✅ Downloaded Ventoy"
    echo

    # Download SHA256 file
    echo "Downloading SHA256 checksums..."
    local ventoy_sha="/var/tmp/ventoy-sha256.txt"

    if ! wget -O "$ventoy_sha" "$VENTOY_DL_SHA" 2>&1 | tail -3; then
        echo "❌ ERROR: Failed to download SHA256 file"
        rm -f "$ventoy_tar"
        exit 1
    fi

    echo "✅ Downloaded SHA256 file"
    echo

    # Verify SHA256
    if ! verify_sha256 "$ventoy_tar" "$ventoy_sha"; then
        echo "❌ ERROR: SHA256 verification failed. Deleting corrupted download."
        rm -f "$ventoy_tar" "$ventoy_sha"
        exit 1
    fi

    echo

    # Extract
    echo "Extracting Ventoy..."
    if ! tar -xzf "$ventoy_tar" -C /var/tmp; then
        echo "❌ ERROR: Failed to extract Ventoy"
        rm -f "$ventoy_tar" "$ventoy_sha"
        exit 1
    fi

    echo "✅ Extracted Ventoy"
    echo

    # Check Ventoy2Disk.sh executable
    local ventoy_dir="/var/tmp/ventoy-${VENTOY_VERSION}"
    local ventoy_script="$ventoy_dir/Ventoy2Disk.sh"

    if [ ! -x "$ventoy_script" ]; then
        echo "❌ ERROR: Ventoy2Disk.sh not executable"
        rm -rf "$ventoy_dir" "$ventoy_tar" "$ventoy_sha"
        exit 1
    fi

    # Run Ventoy installer from its own directory to ensure PATH is set correctly
    echo "Installing Ventoy to /dev/$selected_device..."
    echo

    if ! /bin/bash -c "cd '${ventoy_dir}' && ./Ventoy2Disk.sh -i '/dev/${selected_device}'"; then
        echo "❌ ERROR: Ventoy installation failed"
        rm -rf "$ventoy_dir" "$ventoy_tar" "$ventoy_sha"
        exit 1
    fi

    echo
    echo "✅ Ventoy installed successfully"
    echo

    # Wait for system to recognize new partitions before cleanup
    echo "Waiting for system to recognize Ventoy partitions..."
    sleep 2

    # Refresh kernel's partition table
    if command -v partprobe &> /dev/null; then
        partprobe "/dev/$selected_device" 2>/dev/null || true
    fi

    sleep 1
    echo

    # Cleanup
    echo "Cleaning up temporary files..."
    rm -rf "$ventoy_dir" "$ventoy_tar" "$ventoy_sha"
    echo "✅ Cleanup complete"
    echo

    VENTOY_DEVICE="/dev/$selected_device"
    VENTOY_FRESH_INSTALL=true
}

# Function to find and mount Ventoy partition
find_and_mount_ventoy() {
    echo "Looking for Ventoy USB mount point..."
    VENTOY_MOUNT=""

    # Check if we're running on Unraid
    local kernel_info=$(uname -a)
    if echo "$kernel_info" | grep -q "Unraid"; then
        echo "✅ Detected Unraid system"
        IS_UNRAID=true

        # Use lsblk to find Ventoy partition on Unraid
        local ventoy_info
        ventoy_info=$(lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN 2>/dev/null | grep 'LABEL="Ventoy"' | head -1)

        # Debug: Show what lsblk found
        if [ -z "$ventoy_info" ]; then
            echo "DEBUG: lsblk output with Ventoy label:"
            lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN 2>/dev/null | grep -i ventoy || echo "  (no matches)"
            echo "DEBUG: All partition labels:"
            lsblk -b -P -o NAME,LABEL 2>/dev/null | grep LABEL | head -10
        fi

        if [ -n "$ventoy_info" ]; then
            VENTOY_DEVICE_NAME=$(echo "$ventoy_info" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
            VENTOY_DEVICE="/dev/$VENTOY_DEVICE_NAME"
            VENTOY_MOUNT="/mnt/disks/Ventoy"

            echo "✅ Found Ventoy device: $VENTOY_DEVICE"

            # Create mount point if it doesn't exist
            if [ ! -d "$VENTOY_MOUNT" ]; then
                echo "Creating mount point: $VENTOY_MOUNT"
                mkdir -p "$VENTOY_MOUNT"
            fi

            # Check if already mounted
            if mountpoint -q "$VENTOY_MOUNT" 2>/dev/null; then
                echo "✅ Ventoy already mounted at $VENTOY_MOUNT"
            else
                echo "Mounting Ventoy partition..."
                if mount "$VENTOY_DEVICE" "$VENTOY_MOUNT"; then
                    echo "✅ Successfully mounted Ventoy at $VENTOY_MOUNT"
                else
                    echo "❌ ERROR: Failed to mount Ventoy device"
                    exit 1
                fi
            fi

            # Verify write access
            echo "Checking if mount is read-write..."
            if touch "$VENTOY_MOUNT/.write_test" 2>/dev/null; then
                rm "$VENTOY_MOUNT/.write_test"
                echo "✅ Ventoy mount is read-write"
            else
                echo "❌ ERROR: Ventoy mount is read-only!"
                echo "   Cannot proceed - we need write access."
                exit 1
            fi
        else
            echo "❌ ERROR: Could not find Ventoy partition on Unraid"
            exit 1
        fi
    else
        echo "Detected non-Unraid system"

        # Try different mount locations
        for mount_point in /media/$USER/$VENTOY_LABEL /media/$VENTOY_LABEL /run/media/$USER/$VENTOY_LABEL /mnt/$VENTOY_LABEL; do
            if [ -d "$mount_point" ]; then
                VENTOY_MOUNT="$mount_point"
                break
            fi
        done

        if [ -z "$VENTOY_MOUNT" ]; then
            echo "❓ Could not auto-detect Ventoy USB mount point."
            echo
            read -p "Enter Ventoy USB mount point (e.g., /media/$USER/Ventoy): " VENTOY_MOUNT

            if [ ! -d "$VENTOY_MOUNT" ]; then
                echo "❌ Directory does not exist: $VENTOY_MOUNT"
                exit 1
            fi
        fi

        # Verify write access
        echo "Checking if mount is read-write..."
        if touch "$VENTOY_MOUNT/.write_test" 2>/dev/null; then
            rm "$VENTOY_MOUNT/.write_test"
            echo "✅ Ventoy mount is read-write"
        else
            echo "❌ ERROR: Ventoy mount is read-only!"
            exit 1
        fi
    fi

    echo "✅ Found Ventoy USB at: $VENTOY_MOUNT"
    echo
}

# Function to check available space on Ventoy
check_ventoy_space() {
    echo "Checking available space on Ventoy partition..."
    local required_space_gb=1
    local required_space_bytes=$((required_space_gb * 1024 * 1024 * 1024))

    local available_space
    available_space=$(df --output=avail -B1 "$VENTOY_MOUNT" 2>/dev/null | tail -n 1)

    if [ -z "$available_space" ] || [ "$available_space" -le 0 ]; then
        echo "❌ ERROR: Could not determine available space on Ventoy partition"
        exit 1
    fi

    local available_space_gb
    available_space_gb=$(awk "BEGIN {printf \"%.2f\", $available_space / 1024 / 1024 / 1024}")

    echo "  Available space: ${available_space_gb} GB"

    if [ "$available_space" -lt "$required_space_bytes" ]; then
        echo "❌ ERROR: Insufficient space on Ventoy partition!"
        echo "   Required: ${required_space_gb} GB"
        echo "   Available: ${available_space_gb} GB"
        exit 1
    else
        echo "  ✅ Sufficient space available"
    fi
    echo
}

# Function to install SystemRescue ISO
install_sysrescue_iso() {
    echo "Checking for SystemRescue ISO..."

    local iso_exists_locally=false
    local iso_exists_on_usb=false

    if [ -f "$SCRIPT_DIR/$SYSRESCUE_ISO" ]; then
        iso_exists_locally=true
    fi

    if [ -f "$VENTOY_MOUNT/$SYSRESCUE_ISO" ]; then
        iso_exists_on_usb=true
    fi

    if $iso_exists_on_usb; then
        echo "✅ SystemRescue ISO already exists on USB"
        if $iso_exists_locally; then
            if ask_yes_no "Local copy also exists. Replace USB copy with local?" "no"; then
                echo "Copying ISO from script directory to USB..."
                cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$VENTOY_MOUNT/$SYSRESCUE_ISO"
                echo "✅ ISO copied to USB"
            fi
        fi
    elif $iso_exists_locally; then
        echo "Found SystemRescue ISO in script directory"
        if ask_yes_no "Copy to USB?" "yes"; then
            echo "Copying ISO to USB..."
            cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$VENTOY_MOUNT/$SYSRESCUE_ISO"
            echo "✅ ISO copied to USB"
        fi
    else
        echo "SystemRescue ISO not found locally or on USB"
        if ask_yes_no "Download SystemRescue ISO to USB?" "yes"; then
            echo "Downloading SystemRescue ISO..."
            if ! wget -O "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SYSRESCUE_URL"; then
                echo "❌ ERROR: Failed to download SystemRescue ISO"
                exit 1
            fi
            echo "✅ Downloaded $SYSRESCUE_ISO"

            echo "Downloading SHA512 checksum..."
            if ! wget -O "$VENTOY_MOUNT/$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512_URL"; then
                echo "❌ ERROR: Failed to download SHA512 checksum"
                exit 1
            fi
            echo "✅ Downloaded $SYSRESCUE_SHA512"

            # Verify SHA512
            if ! verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$VENTOY_MOUNT/$SYSRESCUE_SHA512"; then
                echo "❌ ERROR: SHA512 verification failed. Deleting corrupted ISO."
                rm -f "$VENTOY_MOUNT/$SYSRESCUE_ISO"
                exit 1
            fi
        else
            echo "❌ ERROR: SystemRescue ISO is required. Cannot proceed."
            exit 1
        fi
    fi
    echo
}

# Function to set up recovery scripts directory
setup_recovery_scripts() {
    echo "Setting up recovery script on USB..."
    local scripts_dir="$VENTOY_MOUNT/unraid_recovery"
    mkdir -p "$scripts_dir"

    cp "$SCRIPT_DIR/move_dr_to_unraid.sh" "$scripts_dir/"
    chmod +x "$scripts_dir/move_dr_to_unraid.sh"
    echo "  ✅ Recovery script copied to $scripts_dir/"
    echo
}

# Function to create ventoy.json configuration
create_ventoy_json() {
    echo "Creating Ventoy configuration..."
    local ventoy_dir="$VENTOY_MOUNT/ventoy"
    mkdir -p "$ventoy_dir"

    if [ -f "$ventoy_dir/ventoy.json" ]; then
        echo "  ⚠️  ventoy.json already exists"
        if ask_yes_no "  Overwrite with new ventoy.json?" "no"; then
            cat > "$ventoy_dir/ventoy.json" << VENTOY_JSON_EOF
{
  "control": [
    {
      "VTOY_DEFAULT_SEARCH_ROOT": "/",
      "VTOY_MENU_TIMEOUT": 30
    }
  ],
  "control_uefi": [
    {
      "VTOY_LINUX_REMOUNT": "1"
    }
  ],
  "menu_alias": [
    {
      "image": "/${SYSRESCUE_ISO}",
      "alias": "Unraid Recovery - SystemRescue"
    }
  ]
}
VENTOY_JSON_EOF

            echo "  ✅ ventoy.json updated"
        else
            echo "  ⏭️  Keeping existing ventoy.json"
        fi
    else
        cat > "$ventoy_dir/ventoy.json" << 'VENTOY_JSON_EOF'
{
  "control": [
    {
      "VTOY_DEFAULT_SEARCH_ROOT": "/",
      "VTOY_MENU_TIMEOUT": 30
    }
  ],
  "control_uefi": [
    {
      "VTOY_LINUX_REMOUNT": "1"
    }
  ],
  "menu_alias": [
    {
      "image": "/systemrescue-12.02-amd64.iso",
      "alias": "Unraid Recovery - SystemRescue"
    }
  ]
}
VENTOY_JSON_EOF

        # Replace with actual ISO name
        sed -i "s|/systemrescue-12.02-amd64.iso|/${SYSRESCUE_ISO}|g" "$ventoy_dir/ventoy.json"
        echo "  ✅ ventoy.json created"
    fi
    echo
}

# Function to create user instructions
create_instructions() {
    echo "Creating user instructions..."
    cat > "$VENTOY_MOUNT/UNRAID_RECOVERY_INSTRUCTIONS.txt" << 'INSTRUCTIONS_EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       UNRAID USB RECOVERY - USER INSTRUCTIONS            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

EMERGENCY RECOVERY PROCESS
──────────────────────────
Note:  This process will fail if you have the old UNRAID Usb in the machine,
it must be disabled or removed. The assumption is the drive is out of service.

STEP 1: PREPARE
───────────────
☐ Plug in your backup USB (labeled "UNRAID_DR") - Created by dr_usb_backup.sh
☐ Remove any USB drives labeled "UNRAID"
☐ Insert this Ventoy USB
☐ Restart and boot from this USB

STEP 2: BOOT SYSTEMRESCUE
──────────────────────────
1. At the Ventoy menu, select:
   "Unraid Recovery - SystemRescue" or the Systemrescue.iso

2. Wait for SystemRescue to boot, select normal (~30-60 seconds)

3. You'll see a SystemRescue command prompt

STEP 3: MOUNT VENTOY PARTITION
───────────────────────────────
At the SystemRescue prompt, type:

1. The system will map the ventoy base partition into /dev/mapper
2. run mkdir /mnt/script
3. ls /dev/mapper and find the ventoy partition.  It should be the only sdx1 (like sdb1)
4. Mount the ventoy partition:  mount /dev/mapper/sdb1 /mnt/script
5. If you cannot find the /dev/mapper, run mountall and it should loopback mount it to /dev/sdb1

STEP 4: RUN THE RECOVERY SCRIPT
────────────────────────────────
Change to the directory with the script

   cd /mnt/script/unraid_recovery

Run the script (ensure UNRAID_DR USB plugged in also)

   ./move_dr_to_unraid.sh

STEP 5: FOLLOW THE PROMPTS
───────────────────────────
The script will:
✓ Verify your UNRAID_DR backup USB is plugged in
✓ Check for conflicts with existing UNRAID drives
✓ Change the label from UNRAID_DR to UNRAID
✓ Make the drive bootable, the script may ask to make bootable say "Y"
✓ Enable UEFI boot.  This script will not work with BIOS only, must have UEFI Bios
✓ Show you when it's complete

Note: You may see errors on hidden(2048) on syslinux/MBR.
This is because I use modern partition scheme
which will reduces read/writes as it is not sector aligned w/ USB.
You should ignore.

STEP 6: FINISH
──────────────
When you see "✅ All done!":
1. Type: poweroff
2. Press Enter
3. Wait for shutdown
4. Remove this Ventoy USB
5. Restart w/ restored drive and profit.

Note: Since this is a new USB, you will need to relicense this new drive and the
old drive will be permanently blacklisted so if you are testing DO NOT relicense else
your original UNRAID USB will be permanently eliminated from running Unraid.

═══════════════════════════════════════════════════════════

TROUBLESHOOTING
───────────────

Problem: Can't find the script after mountall
→ Type: ls /mnt/
→ Look for mount points like sdb1, sdc1, etc.
→ Type: ls /mnt/sdb1/ (replace with actual mount point)
→ Look for "unraid_recovery" folder

Problem: "No USB drive with label UNRAID_DR found"
→ Make sure your backup USB is plugged in
→ Check the label is exactly "UNRAID_DR"

Problem: "A drive with label UNRAID already exists"
→ Remove the existing UNRAID USB first
→ This script only works when UNRAID drive is missing/dead

Problem: Permission denied
→ Make sure you're logged in as root
→ SystemRescue boots as root by default

═══════════════════════════════════════════════════════════
INSTRUCTIONS_EOF

    echo "  ✅ User instructions created"
    echo
}

# Function to write current version to Ventoy
write_current_version() {
    if [ ! -f "$VENTOY_MOUNT/CURRENT_VERSION" ]; then
        echo "$VERSION" > "$VENTOY_MOUNT/CURRENT_VERSION"
        echo "  ✅ CURRENT_VERSION created: $VERSION"
    else
        local current_ver=$(cat "$VENTOY_MOUNT/CURRENT_VERSION")
        if [ "$current_ver" != "$VERSION" ]; then
            echo "  ℹ️  CURRENT_VERSION already exists: $current_ver"
            echo "      Script version: $VERSION"
        fi
    fi
    echo
}

# Function to check and handle version upgrades
check_versions() {
    echo "Checking software versions..."
    echo

    # If fresh Ventoy install, skip version check for now
    if [ "$VENTOY_FRESH_INSTALL" = true ]; then
        echo "  ℹ️  Fresh Ventoy installation - will create CURRENT_VERSION"
        echo
        return 0
    fi

    # Check if CURRENT_VERSION exists
    if [ ! -f "$VENTOY_MOUNT/CURRENT_VERSION" ]; then
        echo "  ℹ️  CURRENT_VERSION file missing (Ventoy exists but no version file)"
        echo "      This will be created at the end of setup"
        echo
        return 0
    fi

    # Read current version
    local current_version
    current_version=$(cat "$VENTOY_MOUNT/CURRENT_VERSION")

    echo "  Current installed version: $current_version"
    echo "  Script version:            $VERSION"
    echo

    if version_gt "$VERSION" "$current_version"; then
        echo "  ⚠️  Script version is newer than installed version"
        echo
        if ask_yes_no "  Upgrade to version $VERSION?" "yes"; then
            echo "  Proceeding with upgrade..."
            echo
        else
            echo "  ℹ️  Keeping existing version $current_version"
            echo
            return 0
        fi
    elif version_eq "$VERSION" "$current_version"; then
        echo "  ✅ Versions match"

        # Safety check: ensure sysrescue is installed
        if [ ! -f "$VENTOY_MOUNT/$SYSRESCUE_ISO" ]; then
            echo "  ⚠️  SystemRescue ISO missing despite matching version"
            echo "      Installing missing ISO..."
            echo
            install_sysrescue_iso
        else
            echo "  ✅ All components installed"
            echo
        fi
        return 0
    else
        echo "  ❌ FATAL ERROR: Script version ($VERSION) is older than installed ($current_version)"
        echo "      This is unexpected and may indicate a downgrade attempt."
        echo "      Do not downgrade the script."
        exit 1
    fi
}

# Function to sync filesystem and unmount Ventoy
sync_and_unmount_ventoy() {
    echo "Syncing filesystem..."
    sync
    sleep 2

    if [ "$IS_UNRAID" = true ]; then
        echo "Unmounting Ventoy USB..."

        # Change directory away from mount point
        cd "$SCRIPT_DIR" || cd /tmp

        # Try to unmount with retry
        local unmount_success=false
        for attempt in 1 2 3; do
            if umount "$VENTOY_MOUNT" 2>/dev/null; then
                unmount_success=true
                echo "✅ Ventoy USB unmounted successfully"
                # Remove the mount point directory we created
                if rmdir "$VENTOY_MOUNT" 2>/dev/null; then
                    echo "  Removed mount point: $VENTOY_MOUNT"
                fi
                break
            else
                if [ $attempt -lt 3 ]; then
                    echo "  Unmount attempt $attempt failed, retrying..."
                    sleep 1
                fi
            fi
        done

        if [ "$unmount_success" = false ]; then
            echo "⚠️  Warning: Could not unmount Ventoy USB after multiple attempts"
            echo "   The USB may still be in use by a process."
            echo "   You can unmount manually with: umount $VENTOY_MOUNT"
        fi
    fi
    echo
}

# ============================================================================
# VALIDATION
# ============================================================================

# Check if move_dr_to_unraid.sh exists
if [ ! -f "$SCRIPT_DIR/move_dr_to_unraid.sh" ]; then
    echo "❌ ERROR: move_dr_to_unraid.sh not found!"
    echo "   Please make sure it's in the same directory as this script."
    exit 1
fi

# ============================================================================
# MAIN FLOW
# ============================================================================

check_ventoy_origin
find_and_mount_ventoy
check_ventoy_space

# Determine if version check is needed
if [ "$VENTOY_FRESH_INSTALL" = true ] || [ "$UPGRADE_MODE" = true ] || [ ! -f "$VENTOY_MOUNT/$SYSRESCUE_ISO" ]; then
    check_versions
fi

install_sysrescue_iso
setup_recovery_scripts
create_ventoy_json
create_instructions
write_current_version
sync_and_unmount_ventoy

# Final summary
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅ SETUP COMPLETE!                                ║"
echo "╚════════════════════════════════════════════════════╝"
echo
echo "Your Ventoy USB is ready!"
echo
echo "USB Contents:"
echo "  📁 $VENTOY_MOUNT/"
echo "  ├── $SYSRESCUE_ISO"
echo "  ├── UNRAID_RECOVERY_INSTRUCTIONS.txt"
echo "  ├── CURRENT_VERSION"
echo "  ├── ventoy/"
echo "  │   └── ventoy.json"
echo "  └── unraid_recovery/"
echo "      └── move_dr_to_unraid.sh"
echo
echo "USAGE FOR END USERS:"
echo "  1. Boot from this Ventoy USB"
echo "  2. Select SystemRescue from menu"
echo "  3. At the prompt, type: mountall"
echo "  4. Run: bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh"
echo "     (Replace X with the actual drive letter)"
echo "  5. Follow the prompts"
echo "  6. Type: poweroff when done"
echo
echo "═══════════════════════════════════════════════════════"
echo
