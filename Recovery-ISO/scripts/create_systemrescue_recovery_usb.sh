#!/bin/bash

# SystemRescue Emergency USB Creator for Unraid
# This script creates a bootable SystemRescue USB with embedded restore script
# that runs automatically on boot

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSRESCUE_VER="12.02"
SYSRESCUE_ISO="systemrescue-${SYSRESCUE_VER}-amd64.iso"
SYSRESCUE_SHA512="${SYSRESCUE_ISO}.sha512"
SYSRESCUE_URL="https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${SYSRESCUE_VER}/${SYSRESCUE_ISO}/download"
SYSRESCUE_SHA512_URL="https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${SYSRESCUE_VER}/${SYSRESCUE_SHA512}/download"
SYSRESCUE_CUSTOMIZE_URL="https://gitlab.com/systemrescue/systemrescue-sources/-/raw/main/airootfs/usr/share/sysrescue/bin/sysrescue-customize"

# Path to your restore script
RESTORE_SCRIPT="$SCRIPT_DIR/move_dr_to_unraid.sh"

WORK_DIR="/tmp/sysrescue_usb_creation"
RECIPE_DIR="$WORK_DIR/recipe"

echo "╔════════════════════════════════════════════════════╗"
echo "║  SystemRescue Emergency USB Creator for Unraid    ║"
echo "╚════════════════════════════════════════════════════╝"
echo

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

# Check if restore script exists
if [ ! -f "$RESTORE_SCRIPT" ]; then
    echo "❌ ERROR: $RESTORE_SCRIPT not found!"
    echo "   Please make sure it's in the same directory as this script."
    exit 1
fi

echo "✅ Found restore script: $RESTORE_SCRIPT"
echo

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download SystemRescue ISO and SHA512 if not already present
if [ -f "$SCRIPT_DIR/$SYSRESCUE_ISO" ] && [ -f "$SCRIPT_DIR/$SYSRESCUE_SHA512" ]; then
    echo "Found SystemRescue ISO and SHA512 in script directory"
    if ask_yes_no "Use existing files?" "yes"; then
        cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$SYSRESCUE_ISO"
        cp "$SCRIPT_DIR/$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512"
        echo "✅ Copied files from script directory"
    else
        rm -f "$SYSRESCUE_ISO" "$SYSRESCUE_SHA512"
    fi
fi

if [ ! -f "$SYSRESCUE_ISO" ]; then
    echo "Downloading SystemRescue ISO..."
    if ! wget -O "$SYSRESCUE_ISO" "$SYSRESCUE_URL"; then
        echo "❌ ERROR: Failed to download SystemRescue ISO"
        exit 1
    fi
    echo "✅ Downloaded $SYSRESCUE_ISO"
fi

if [ ! -f "$SYSRESCUE_SHA512" ]; then
    echo "Downloading SHA512 checksum..."
    if ! wget -O "$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512_URL"; then
        echo "❌ ERROR: Failed to download SHA512 checksum"
        exit 1
    fi
    echo "✅ Downloaded $SYSRESCUE_SHA512"
fi

# Verify SHA512
if ! verify_sha512 "$SYSRESCUE_ISO" "$SYSRESCUE_SHA512"; then
    echo "❌ ERROR: SHA512 verification failed. Aborting."
    exit 1
fi
echo

# Download sysrescue-customize script
echo "Downloading sysrescue-customize tool..."
if ! wget -O sysrescue-customize "$SYSRESCUE_CUSTOMIZE_URL"; then
    echo "❌ ERROR: Failed to download sysrescue-customize"
    exit 1
fi
chmod +x sysrescue-customize
echo "✅ Downloaded customization tool"
echo

# Create recipe directory structure
echo "Creating customization recipe..."
mkdir -p "$RECIPE_DIR/add-files/autorun"

# Copy the restore script to the recipe as an autorun script
cp "$RESTORE_SCRIPT" "$RECIPE_DIR/add-files/autorun/autorun"
chmod +x "$RECIPE_DIR/add-files/autorun/autorun"

# Create a launcher wrapper script
cat > "$RECIPE_DIR/add-files/autorun/00-launcher.sh" << 'LAUNCHER_EOF'
#!/bin/bash

# SystemRescue autorun launcher for Unraid USB recovery
# This script runs automatically when SystemRescue boots

# Wait a moment for system to fully initialize
sleep 3

clear
echo "╔══════════════════════════════════════════════════╗"
echo "║                                                  ║"
echo "║        UNRAID USB RECOVERY TOOL                  ║"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo
echo "This tool will restore your Unraid USB drive"
echo "from a backup labeled 'UNRAID_DR'"
echo
echo "CHECKLIST:"
echo "  ☐ Backup USB (UNRAID_DR) is plugged in"
echo "  ☐ Any existing UNRAID USB drives are removed"
echo "  ☐ You're ready to proceed"
echo
echo "──────────────────────────────────────────────────"

# Ask for confirmation
while true; do
    read -p "Continue? (yes/no): " response
    case "${response,,}" in
        yes|y)
            break
            ;;
        no|n)
            echo
            echo "Recovery cancelled."
            echo "Type 'poweroff' to shut down the system."
            exit 0
            ;;
        *)
            echo "Please enter 'yes' or 'no'."
            ;;
    esac
done

echo
echo "Starting recovery process..."
echo

# Check if required tools are available (fatlabel is part of dosfstools)
if ! command -v fatlabel &> /dev/null; then
    echo "⚠️  Installing required tools (dosfstools for fatlabel)..."
    if ! pacman -Sy --noconfirm dosfstools; then
        echo "❌ ERROR: Failed to install dosfstools"
        echo "   This tool is required for the recovery process."
        echo
        echo "Manual installation: pacman -Sy dosfstools"
        exit 1
    fi
    echo "✅ Tools installed successfully"
    echo
fi

# Run the actual restore script
SCRIPT_PATH="/run/archiso/bootmnt/autorun/autorun"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ ERROR: Recovery script not found at $SCRIPT_PATH"
    echo "   This should not happen. The USB may be corrupted."
    exit 1
fi

# Execute the restore script
if bash "$SCRIPT_PATH"; then
    echo
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  ✅ RECOVERY COMPLETE!                           ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo
    echo "Next steps:"
    echo "  1. Type 'poweroff' to shut down"
    echo "  2. Remove this recovery USB"
    echo "  3. Remove the UNRAID_DR backup USB"
    echo "  4. Boot normally from your restored Unraid USB"
    echo
else
    echo
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  ❌ RECOVERY FAILED                              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo
    echo "The recovery script encountered an error."
    echo "Please review the messages above for details."
    echo
    echo "You can:"
    echo "  - Type 'poweroff' to shut down"
    echo "  - Run the script manually: bash $SCRIPT_PATH"
    echo
    exit 1
fi
LAUNCHER_EOF

chmod +x "$RECIPE_DIR/add-files/autorun/00-launcher.sh"
echo "  ✅ Created autorun scripts"

# Create the custom ISO
echo
echo "Building custom SystemRescue ISO..."
echo "  This may take several minutes..."
if ! ./sysrescue-customize --auto \
    --source="$SYSRESCUE_ISO" \
    --dest=systemrescue-custom.iso \
    --recipe-dir="$RECIPE_DIR"; then
    echo "❌ ERROR: Failed to create custom ISO"
    exit 1
fi
echo "✅ Custom ISO created successfully"
echo

# Now detect and select USB device
echo "╔════════════════════════════════════════════════════╗"
echo "║  USB Device Selection                              ║"
echo "╚════════════════════════════════════════════════════╝"
echo

# Get list of USB drives, excluding boot and DR drives
echo "Detecting USB drives..."
echo

# Build exclusion list
declare -a EXCLUDE_DEVICES
declare -a EXCLUDE_LABELS

# Always exclude boot drive
BOOT_DEVICE=$(lsblk -n -o PKNAME $(findmnt -n -o SOURCE /boot) 2>/dev/null || true)
if [ -n "$BOOT_DEVICE" ]; then
    EXCLUDE_DEVICES+=("$BOOT_DEVICE")
    EXCLUDE_LABELS+=("UNRAID (boot)")
fi

# Exclude any UNRAID_DR labeled drives
while IFS= read -r line; do
    if [ -n "$line" ]; then
        DEVICE=$(echo "$line" | awk '{print $1}')
        EXCLUDE_DEVICES+=("$DEVICE")
        EXCLUDE_LABELS+=("UNRAID_DR")
    fi
done < <(lsblk -n -o NAME,LABEL | grep "UNRAID_DR" | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//' | sort -u)

# Get all USB devices
declare -a USB_DEVICES
declare -a USB_MODELS
declare -a USB_SIZES
declare -a USB_LABELS

while IFS='|' read -r name size tran model label; do
    # Skip if not a USB device
    [ "$tran" != "usb" ] && continue
    
    # Skip if it's a partition (has a number at the end)
    [[ "$name" =~ [0-9]$ ]] && continue
    
    # Check if this device should be excluded
    local skip=false
    for excluded in "${EXCLUDE_DEVICES[@]}"; do
        if [ "$name" = "$excluded" ]; then
            skip=true
            break
        fi
    done
    
    [ "$skip" = true ] && continue
    
    # Add to list
    USB_DEVICES+=("$name")
    USB_MODELS+=("${model:-Unknown}")
    USB_SIZES+=("$size")
    
    # Check if any partition on this device has a label
    DEVICE_LABEL=$(lsblk -n -o LABEL "/dev/$name" 2>/dev/null | grep -v "^$" | head -n 1 || echo "")
    USB_LABELS+=("$DEVICE_LABEL")
    
done < <(lsblk -n -d -o NAME,SIZE,TRAN,MODEL,LABEL | awk '{print $1"|"$2"|"$3"|"$4"|"$5}')

# Check if any USB devices were found
if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    echo "❌ ERROR: No suitable USB drives found!"
    echo "   Please plug in a USB drive and try again."
    echo
    if [ ${#EXCLUDE_DEVICES[@]} -gt 0 ]; then
        echo "   Excluded devices:"
        for i in "${!EXCLUDE_DEVICES[@]}"; do
            echo "     - ${EXCLUDE_DEVICES[$i]} (${EXCLUDE_LABELS[$i]})"
        done
    fi
    exit 1
fi

# Display available devices
echo "Available USB drives:"
echo
for i in "${!USB_DEVICES[@]}"; do
    local num=$((i + 1))
    local size_human=$(numfmt --to=iec-i --suffix=B "${USB_SIZES[$i]}" 2>/dev/null || echo "${USB_SIZES[$i]}")
    echo "  [$num] /dev/${USB_DEVICES[$i]}"
    echo "      Model: ${USB_MODELS[$i]}"
    echo "      Size:  $size_human"
    if [ -n "${USB_LABELS[$i]}" ]; then
        echo "      Label: ${USB_LABELS[$i]}"
    fi
    echo
done

if [ ${#EXCLUDE_DEVICES[@]} -gt 0 ]; then
    echo "Excluded devices (boot/DR drives):"
    for i in "${!EXCLUDE_DEVICES[@]}"; do
        echo "  - /dev/${EXCLUDE_DEVICES[$i]} (${EXCLUDE_LABELS[$i]})"
    done
    echo
fi

# Prompt for selection
while true; do
    read -p "Select USB drive number [1-${#USB_DEVICES[@]}]: " selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid input. Please enter a number."
        continue
    fi
    
    if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#USB_DEVICES[@]} ]; then
        echo "❌ Invalid selection. Please choose a number between 1 and ${#USB_DEVICES[@]}."
        continue
    fi
    
    break
done

# Get selected device
SELECTED_INDEX=$((selection - 1))
USB_DEVICE="/dev/${USB_DEVICES[$SELECTED_INDEX]}"
USB_MODEL="${USB_MODELS[$SELECTED_INDEX]}"
USB_SIZE="${USB_SIZES[$SELECTED_INDEX]}"
USB_LABEL="${USB_LABELS[$SELECTED_INDEX]}"

# Final confirmation
echo
echo "╔════════════════════════════════════════════════════╗"
echo "║  ⚠️  WARNING: ALL DATA WILL BE ERASED!            ║"
echo "╚════════════════════════════════════════════════════╝"
echo
echo "Selected device:"
echo "  Device: $USB_DEVICE"
echo "  Model:  $USB_MODEL"
echo "  Size:   $(numfmt --to=iec-i --suffix=B "$USB_SIZE" 2>/dev/null || echo "$USB_SIZE")"
if [ -n "$USB_LABEL" ]; then
    echo "  Label:  $USB_LABEL"
fi
echo
echo "This will COMPLETELY ERASE all data on this device!"
echo

if ! ask_yes_no "Are you absolutely sure you want to proceed?" "no"; then
    echo
    echo "❌ Operation cancelled."
    echo "   Cleaning up..."
    cd /
    rm -rf "$WORK_DIR"
    exit 0
fi

# Unmount any mounted partitions on the device
echo
echo "Unmounting any partitions on $USB_DEVICE..."
umount ${USB_DEVICE}* 2>/dev/null || true
sleep 1

# Write custom ISO to USB device
echo
echo "Writing SystemRescue to USB device..."
echo "  This may take several minutes. Please be patient..."
if ! dd if=systemrescue-custom.iso of="$USB_DEVICE" bs=4M status=progress oflag=sync conv=fsync; then
    echo "❌ ERROR: Failed to write ISO to USB device"
    exit 1
fi

# Final sync
sync
sleep 2

echo
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅ SUCCESS!                                       ║"
echo "╚════════════════════════════════════════════════════╝"
echo
echo "Recovery USB has been created on $USB_DEVICE"
echo
echo "The restore script will run AUTOMATICALLY when booting"
echo "from this USB. No manual intervention required!"
echo
echo "USAGE INSTRUCTIONS:"
echo "──────────────────"
echo "  1. Boot the system from this USB"
echo "  2. SystemRescue will load automatically"
echo "  3. After ~30-60 seconds, the recovery tool will start"
echo "  4. Follow the on-screen prompts"
echo "  5. Type 'yes' to confirm and run the restore"
echo "  6. When complete, type 'poweroff' and remove USB"
echo
echo "USER CHECKLIST:"
echo "  ☐ Backup USB (UNRAID_DR) must be plugged in"
echo "  ☐ Remove any existing UNRAID USB drives first"
echo "  ☐ Boot from this recovery USB"
echo
echo "══════════════════════════════════════════════════════"

# Cleanup
cd /
rm -rf "$WORK_DIR"

echo
echo "✅ All done! USB is ready to use."
echo
