#!/bin/bash

# Simplified Ventoy USB Setup for Unraid Recovery
# This script sets up a Ventoy USB with SystemRescue ISO and recovery script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENTOY_LABEL="Ventoy"
SYSRESCUE_VER="12.02"
SYSRESCUE_ISO="systemrescue-${SYSRESCUE_VER}-amd64.iso"
SYSRESCUE_SHA512="${SYSRESCUE_ISO}.sha512"
SYSRESCUE_URL="https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${SYSRESCUE_VER}/${SYSRESCUE_ISO}/download"
SYSRESCUE_SHA512_URL="https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${SYSRESCUE_VER}/${SYSRESCUE_SHA512}/download"

echo "╔════════════════════════════════════════════════════╗"
echo "║  Ventoy USB Setup for Unraid Recovery             ║"
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

# Check if move_dr_to_unraid.sh exists
if [ ! -f "$SCRIPT_DIR/move_dr_to_unraid.sh" ]; then
    echo "❌ ERROR: move_dr_to_unraid.sh not found!"
    echo "   Please make sure it's in the same directory as this script."
    exit 1
fi

# Find Ventoy USB partition
echo "Looking for Ventoy USB drive..."
VENTOY_MOUNT=""

# Check if we're running on Unraid
KERNEL_INFO=$(uname -a)
IS_UNRAID=false
if echo "$KERNEL_INFO" | grep -q "Unraid"; then
    echo "✅ Detected Unraid system"
    IS_UNRAID=true
    
    # Use lsblk to find Ventoy partition on Unraid
    VENTOY_INFO=$(lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN | grep 'LABEL="Ventoy"')
    
    if [ -n "$VENTOY_INFO" ]; then
        # Parse the NAME from the lsblk output
        VENTOY_DEVICE_NAME=$(echo "$VENTOY_INFO" | grep -o 'NAME="[^"]*"' | cut -d'"' -f2)
        VENTOY_DEVICE="/dev/$VENTOY_DEVICE_NAME"
        VENTOY_MOUNT="/mnt/disks/Ventoy"
        
        echo "✅ Found Ventoy device: $VENTOY_DEVICE"
        
        # Create mount point if it doesn't exist
        if [ ! -d "$VENTOY_MOUNT" ]; then
            echo "Creating mount point: $VENTOY_MOUNT"
            mkdir -p "$VENTOY_MOUNT"
        fi
        
        # Check if already mounted at the expected location
        if mountpoint -q "$VENTOY_MOUNT" 2>/dev/null; then
            echo "✅ Ventoy already mounted at $VENTOY_MOUNT"
        else
            # Mount the Ventoy partition
            echo "Mounting Ventoy partition..."
            if mount "$VENTOY_DEVICE" "$VENTOY_MOUNT"; then
                echo "✅ Successfully mounted Ventoy at $VENTOY_MOUNT"
            else
                echo "❌ ERROR: Failed to mount Ventoy device"
                exit 1
            fi
        fi
        
        # Verify the mount is read-write
        echo "Checking if mount is read-write..."
        if touch "$VENTOY_MOUNT/.write_test" 2>/dev/null; then
            rm "$VENTOY_MOUNT/.write_test"
            echo "✅ Ventoy mount is read-write"
        else
            echo "❌ ERROR: Ventoy mount is read-only!"
            echo "   Cannot proceed - we need write access to copy files."
            echo "   Please remount with read-write permissions:"
            echo "   mount -o remount,rw $VENTOY_DEVICE $VENTOY_MOUNT"
            exit 1
        fi
    else
        echo "❌ ERROR: Could not find Ventoy partition on Unraid system"
        echo "   Please ensure Ventoy USB is plugged in"
        exit 1
    fi
else
    # Non-Unraid system - use original detection logic
    echo "Detected non-Unraid system"
    
    # Try different mount locations
    for mount_point in /media/$USER/$VENTOY_LABEL /media/$VENTOY_LABEL /run/media/$USER/$VENTOY_LABEL /mnt/$VENTOY_LABEL; do
        if [ -d "$mount_point" ]; then
            VENTOY_MOUNT="$mount_point"
            break
        fi
    done

    # If not found, ask user
    if [ -z "$VENTOY_MOUNT" ]; then
        echo "❓ Could not auto-detect Ventoy USB mount point."
        echo
        read -p "Enter Ventoy USB mount point (e.g., /media/$USER/Ventoy): " VENTOY_MOUNT
        
        if [ ! -d "$VENTOY_MOUNT" ]; then
            echo "❌ Directory does not exist: $VENTOY_MOUNT"
            exit 1
        fi
    fi
    
    # Verify write access on non-Unraid systems too
    echo "Checking if mount is read-write..."
    if touch "$VENTOY_MOUNT/.write_test" 2>/dev/null; then
        rm "$VENTOY_MOUNT/.write_test"
        echo "✅ Ventoy mount is read-write"
    else
        echo "❌ ERROR: Ventoy mount is read-only or no write permission!"
        echo "   Cannot proceed - we need write access to copy files."
        exit 1
    fi
fi

echo "✅ Found Ventoy USB at: $VENTOY_MOUNT"
echo

# Check available space on Ventoy partition
echo "Checking available space on Ventoy partition..."
REQUIRED_SPACE_GB=1
REQUIRED_SPACE_BYTES=$((REQUIRED_SPACE_GB * 1024 * 1024 * 1024))

# Get available space in bytes using df
AVAILABLE_SPACE=$(df --output=avail -B1 "$VENTOY_MOUNT" | tail -n 1)

if [ -z "$AVAILABLE_SPACE" ] || [ "$AVAILABLE_SPACE" -le 0 ]; then
    echo "❌ ERROR: Could not determine available space on Ventoy partition"
    exit 1
fi

# Convert to human-readable format
AVAILABLE_SPACE_GB=$(awk "BEGIN {printf \"%.2f\", $AVAILABLE_SPACE / 1024 / 1024 / 1024}")

echo "  Available space: ${AVAILABLE_SPACE_GB} GB"

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE_BYTES" ]; then
    echo "❌ ERROR: Insufficient space on Ventoy partition!"
    echo "   Required: ${REQUIRED_SPACE_GB} GB"
    echo "   Available: ${AVAILABLE_SPACE_GB} GB"
    echo "   Please free up space or use a larger USB drive."
    exit 1
else
    echo "  ✅ Sufficient space available (need ${REQUIRED_SPACE_GB} GB for ISO download)"
fi
echo

# Check if SystemRescue ISO exists (in script directory or on USB)
ISO_EXISTS_LOCALLY=false
ISO_EXISTS_ON_USB=false

if [ -f "$SCRIPT_DIR/$SYSRESCUE_ISO" ]; then
    ISO_EXISTS_LOCALLY=true
fi

if [ -f "$VENTOY_MOUNT/$SYSRESCUE_ISO" ]; then
    ISO_EXISTS_ON_USB=true
fi

# Download or copy ISO
if $ISO_EXISTS_ON_USB; then
    echo "✅ SystemRescue ISO already exists on USB"
    if $ISO_EXISTS_LOCALLY; then
        if ask_yes_no "Local copy also exists. Replace USB copy with local?" "no"; then
            echo "Copying ISO from script directory to USB..."
            cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$VENTOY_MOUNT/$SYSRESCUE_ISO"
            echo "✅ ISO copied to USB"
        fi
    fi
elif $ISO_EXISTS_LOCALLY; then
    echo "Found SystemRescue ISO in script directory"
    if ask_yes_no "Copy to USB?" "yes"; then
        echo "Copying ISO to USB..."
        cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$VENTOY_MOUNT/$SYSRESCUE_ISO"
        echo "✅ ISO copied to USB"
    else
        echo "Skipping ISO copy"
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

# Create scripts directory on Ventoy USB
echo "Setting up recovery script on USB..."
SCRIPTS_DIR="$VENTOY_MOUNT/unraid_recovery"
mkdir -p "$SCRIPTS_DIR"

# Copy the recovery script
cp "$SCRIPT_DIR/move_dr_to_unraid.sh" "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR/move_dr_to_unraid.sh"
echo "  ✅ Recovery script copied to $SCRIPTS_DIR/"

# Copy or create ventoy.json
VENTOY_DIR="$VENTOY_MOUNT/ventoy"
mkdir -p "$VENTOY_DIR"

if [ -f "$VENTOY_DIR/ventoy.json" ]; then
    echo "  ⚠️  ventoy.json already exists"
    if ask_yes_no "  Overwrite with new ventoy.json?" "no"; then
        cat > "$VENTOY_DIR/ventoy.json" << VENTOY_JSON_EOF
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
      "image": "$SYSRESCUE_ISO",
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
    cat > "$VENTOY_DIR/ventoy.json" << 'VENTOY_JSON_EOF'
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
      "image": "/systemrescue-*.iso",
      "alias": "Unraid Recovery - SystemRescue"
    }
  ]
}
VENTOY_JSON_EOF
    echo "  ✅ ventoy.json created"
fi

# Create user instructions
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

# Sync filesystem
echo
echo "Syncing filesystem..."
sync
sleep 2

# Unmount Ventoy USB (if we mounted it)
if [ "$IS_UNRAID" = true ]; then
    echo "Unmounting Ventoy USB..."
    
    # Change directory away from the mount point
    cd "$SCRIPT_DIR" || cd /tmp
    
    # Try to unmount with retry
    UNMOUNT_SUCCESS=false
    for attempt in 1 2 3; do
        if umount "$VENTOY_MOUNT" 2>/dev/null; then
            UNMOUNT_SUCCESS=true
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
    
    if [ "$UNMOUNT_SUCCESS" = false ]; then
        echo "⚠️  Warning: Could not unmount Ventoy USB after multiple attempts"
        echo "   The USB may still be in use by a process."
        echo "   You can unmount manually with: umount $VENTOY_MOUNT"
    fi
fi

echo
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
echo "NOTE: The Ventoy partition is automatically remounted read-write"
echo "      in UEFI mode thanks to VTOY_LINUX_REMOUNT setting."
echo
echo "TO UPDATE THE SCRIPT LATER:"
echo "  1. Mount the Ventoy USB"
echo "  2. Edit: $VENTOY_MOUNT/unraid_recovery/move_dr_to_unraid.sh"
echo "  3. Save and safely eject"
echo
echo "═══════════════════════════════════════════════════════"
