#!/bin/bash

# Automated Ventoy USB Setup for Unraid Recovery
# This script sets up a Ventoy USB with SystemRescue and the scripting to move the UNRAID DR drive to prepare to primary boot.

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
        # Example: NAME="sdc1" UUID="..." ... LABEL="Ventoy"
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
            echo "   Cannot proceed - we need write access to download ISO and create files."
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
        echo "   Cannot proceed - we need write access to download ISO and create files."
        exit 1
    fi
fi

echo "✅ Found Ventoy USB at: $VENTOY_MOUNT"
echo

# Check available space on Ventoy partition
echo "Checking available space on Ventoy partition..."
REQUIRED_SPACE_GB=4
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

# Check if SystemRescue ISO exists (in script directory)
ISO_EXISTS_LOCALLY=false
ISO_EXISTS_ON_USB=false

if [ -f "$SCRIPT_DIR/$SYSRESCUE_ISO" ]; then
    ISO_EXISTS_LOCALLY=true
fi

if [ -f "$VENTOY_MOUNT/$SYSRESCUE_ISO" ]; then
    ISO_EXISTS_ON_USB=true
fi

# Determine what to do based on ISO existence
if [ "$ISO_EXISTS_LOCALLY" = true ]; then
    echo "✅ SystemRescue ISO found locally: $SCRIPT_DIR/$SYSRESCUE_ISO"
    
    # Ask if user wants to verify the hash
    echo
    read -p "Do you want to verify the SHA512 hash of this ISO? (yes/no): " verify_response
    
    if [[ "$verify_response" =~ ^[Yy][Ee][Ss]$ ]]; then
        # Check if .sha512 file exists locally
        if [ ! -f "$SCRIPT_DIR/$SYSRESCUE_SHA512" ]; then
            echo "📥 SHA512 hash file not found locally. Downloading..."
            if wget -O "$SCRIPT_DIR/$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512_URL"; then
                echo "✅ SHA512 hash file downloaded"
            else
                echo "❌ ERROR: Failed to download SHA512 hash file"
                echo "   You can download it manually from:"
                echo "   https://www.system-rescue.org/Download/"
                exit 1
            fi
        else
            echo "✅ SHA512 hash file found locally"
        fi
        
        # Verify the hash
        if ! verify_sha512 "$SCRIPT_DIR/$SYSRESCUE_ISO" "$SCRIPT_DIR/$SYSRESCUE_SHA512"; then
            echo
            echo "🛑 CRITICAL: Hash verification failed!"
            echo "   Cannot proceed with a potentially corrupted ISO."
            exit 1
        fi
    else
        echo "⚠️  Skipping SHA512 verification (not recommended)"
    fi
    
elif [ "$ISO_EXISTS_ON_USB" = true ]; then
    echo "✅ SystemRescue ISO already exists on Ventoy USB"
    echo "   Location: $VENTOY_MOUNT/$SYSRESCUE_ISO"
    
    # Ask if user wants to verify the existing ISO on USB
    echo
    read -p "Do you want to verify the SHA512 hash of the ISO on USB? (yes/no): " verify_usb_response
    
    if [[ "$verify_usb_response" =~ ^[Yy][Ee][Ss]$ ]]; then
        # Check if .sha512 file exists on USB (same location as ISO)
        SHA512_ON_USB="$VENTOY_MOUNT/$SYSRESCUE_SHA512"
        
        if [ ! -f "$SHA512_ON_USB" ]; then
            echo "📥 SHA512 hash file not found on USB. Downloading..."
            if wget -O "$SHA512_ON_USB" "$SYSRESCUE_SHA512_URL"; then
                echo "✅ SHA512 hash file downloaded to USB"
            else
                echo "❌ ERROR: Failed to download SHA512 hash file"
                echo "   You can download it manually from:"
                echo "   https://www.system-rescue.org/Download/"
                exit 1
            fi
        else
            echo "✅ SHA512 hash file found on USB"
        fi
        
        # Verify the hash of the ISO on USB
        if ! verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SHA512_ON_USB"; then
            echo
            echo "🛑 CRITICAL: Hash verification failed for ISO on USB!"
            echo "   The ISO on your USB drive may be corrupted."
            echo
            read -p "Do you want to delete it and re-download? (yes/no): " redownload_response
            if [[ "$redownload_response" =~ ^[Yy][Ee][Ss]$ ]]; then
                echo "Removing corrupted ISO from USB..."
                rm "$VENTOY_MOUNT/$SYSRESCUE_ISO"
                ISO_EXISTS_ON_USB=false
                # Set flag to download fresh copy
                NEED_DOWNLOAD=true
            else
                echo "Cannot proceed with potentially corrupted ISO."
                exit 1
            fi
        else
            echo "  ISO on USB is verified and will be used."
        fi
    else
        echo "⚠️  Skipping SHA512 verification of USB ISO (not recommended)"
        echo "  Will use existing ISO on USB"
    fi
    
else
    # No ISO exists anywhere - need to download
    NEED_DOWNLOAD=true
fi

# Download ISO if needed
if [ "$NEED_DOWNLOAD" = true ] || ([ "$ISO_EXISTS_LOCALLY" = false ] && [ "$ISO_EXISTS_ON_USB" = false ]); then
    echo "📥 SystemRescue ISO not found. Download it?"
    echo "   Size: ~800MB"
    echo "   Version: ${SYSRESCUE_VER}"
    read -p "Download now? (yes/no): " download_response
    
    if [[ "$download_response" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Downloading SystemRescue ISO..."
        if wget -O "$SCRIPT_DIR/$SYSRESCUE_ISO" "$SYSRESCUE_URL"; then
            echo "✅ ISO download complete"
            
            # Ask if user wants to verify the downloaded ISO
            echo
            read -p "Do you want to verify the SHA512 hash of the downloaded ISO? (recommended: yes/no): " verify_dl_response
            
            if [[ "$verify_dl_response" =~ ^[Yy][Ee][Ss]$ ]]; then
                # Download .sha512 file if not already present
                if [ ! -f "$SCRIPT_DIR/$SYSRESCUE_SHA512" ]; then
                    echo "📥 Downloading SHA512 hash file..."
                    if wget -O "$SCRIPT_DIR/$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512_URL"; then
                        echo "✅ SHA512 hash file downloaded"
                    else
                        echo "❌ ERROR: Failed to download SHA512 hash file"
                        echo "   Cannot verify ISO integrity"
                        exit 1
                    fi
                fi
                
                # Verify the downloaded ISO
                if ! verify_sha512 "$SCRIPT_DIR/$SYSRESCUE_ISO" "$SCRIPT_DIR/$SYSRESCUE_SHA512"; then
                    echo
                    echo "🛑 CRITICAL: Downloaded ISO failed hash verification!"
                    echo "   The download may be corrupted."
                    echo "   Removing corrupted file..."
                    rm "$SCRIPT_DIR/$SYSRESCUE_ISO"
                    echo
                    echo "Please try downloading again or download manually from:"
                    echo "   https://www.system-rescue.org/Download/"
                    exit 1
                fi
            else
                echo "⚠️  Skipping hash verification of downloaded ISO (not recommended)"
            fi
            
            ISO_EXISTS_LOCALLY=true
        else
            echo "❌ ERROR: Failed to download ISO"
            exit 1
        fi
    else
        echo "❌ SystemRescue ISO required. Please download manually:"
        echo "   https://www.system-rescue.org/Download/"
        exit 1
    fi
fi

echo
echo "Setting up Ventoy USB structure..."
echo "─────────────────────────────────────────────────────"

# Create injection directory structure
INJECTION_DIR="$VENTOY_MOUNT/ventoy/sysrescue_injection"
AUTORUN_DIR="$INJECTION_DIR/sysrescue.d/autorun"

echo "Creating directories..."
mkdir -p "$AUTORUN_DIR"

# Copy SystemRescue ISO to USB root (if not already there)
if [ "$ISO_EXISTS_ON_USB" = false ]; then
    echo "Copying SystemRescue ISO to USB..."
    cp "$SCRIPT_DIR/$SYSRESCUE_ISO" "$VENTOY_MOUNT/"
    echo "  ✅ ISO copied to USB"
else
    echo "✅ ISO already exists on USB, skipping copy"
fi

# Copy recovery script
echo "Copying recovery script..."
cp "$SCRIPT_DIR/move_dr_to_unraid.sh" "$AUTORUN_DIR/"
chmod +x "$AUTORUN_DIR/move_dr_to_unraid.sh"
echo "  ✅ Recovery script copied"

# Create launcher script
echo "Creating launcher script..."
cat > "$AUTORUN_DIR/00-launcher.sh" << 'LAUNCHER_EOF'
#!/bin/bash
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
read -p "Continue? (yes/no): " response
echo

if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
    bash /sysrescue.d/autorun/move_dr_to_unraid.sh
    
    echo
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  ✅ RECOVERY COMPLETE!                           ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo
    echo "Next steps:"
    echo "  1. Type 'poweroff' to shut down"
    echo "  2. Remove this recovery USB"
    echo "  3. Boot normally from your restored Unraid USB"
    echo
else
    echo "Recovery cancelled. Type 'poweroff' to shut down."
fi
LAUNCHER_EOF

chmod +x "$AUTORUN_DIR/00-launcher.sh"
echo "  ✅ Launcher script created"

# Create ventoy.json configuration
echo "Creating Ventoy configuration..."
VENTOY_JSON="$VENTOY_MOUNT/ventoy/ventoy.json"

# Check if ventoy.json already exists
if [ -f "$VENTOY_JSON" ]; then
    echo "  ⚠️  ventoy.json already exists"
    read -p "  Overwrite? (yes/no): " overwrite_response
    if [[ ! "$overwrite_response" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "  ⚠️  Skipping ventoy.json creation"
        echo "  You'll need to manually add the injection configuration"
        echo
        echo "  Add this to your ventoy.json:"
        echo "  {"
        echo "    \"injection\": ["
        echo "      {"
        echo "        \"image\": \"/$SYSRESCUE_ISO\","
        echo "        \"archive\": \"/ventoy/sysrescue_injection.tar.gz\""
        echo "      }"
        echo "    ]"
        echo "  }"
        SKIP_VENTOY_JSON=true
    fi
fi

if [ "$SKIP_VENTOY_JSON" != "true" ]; then
    cat > "$VENTOY_JSON" << EOF
{
  "control": [
    {
      "VTOY_DEFAULT_SEARCH_ROOT": "/",
      "VTOY_MENU_TIMEOUT": 30
    }
  ],
  "injection": [
    {
      "image": "/$SYSRESCUE_ISO",
      "archive": "/ventoy/sysrescue_injection.tar.gz"
    }
  ],
  "menu_alias": [
    {
      "image": "/$SYSRESCUE_ISO",
      "alias": "Unraid Recovery - SystemRescue (Auto-run)"
    }
  ]
}
EOF
    echo "  ✅ ventoy.json created"
fi

# Create the injection archive
echo "Creating injection archive..."
cd "$INJECTION_DIR"
tar -czf "$VENTOY_MOUNT/ventoy/sysrescue_injection.tar.gz" sysrescue.d/
cd "$SCRIPT_DIR"
echo "  ✅ Injection archive created"

# Create user instructions
echo "Creating user instructions..."
cat > "$VENTOY_MOUNT/UNRAID_RECOVERY_INSTRUCTIONS.txt" << 'INSTRUCTIONS_EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       UNRAID USB RECOVERY - VENTOY EDITION                ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

WHAT THIS USB DOES
──────────────────
This USB contains SystemRescue with an automated Unraid USB
recovery script that will restore your Unraid drive from backup.

BEFORE YOU START
────────────────
✓ Plug in your backup USB (labeled "UNRAID_DR")
✓ Remove any USB drives labeled "UNRAID"
✓ Have this Ventoy USB ready

HOW TO USE
──────────
1. INSERT this USB drive into your computer

2. RESTART and press the boot menu key:
   Common keys: F12, F11, F8, ESC, or DEL

3. SELECT this USB drive from the boot menu

4. CHOOSE "Unraid Recovery - SystemRescue" from Ventoy menu
   (Use arrow keys to navigate, Enter to select)

5. WAIT for SystemRescue to boot (30-60 seconds)
   The recovery script will start AUTOMATICALLY!

6. FOLLOW the on-screen instructions:
   - Read the checklist
   - Type "yes" to confirm
   - Wait for completion

7. WHEN YOU SEE "✅ RECOVERY COMPLETE":
   - Type: poweroff
   - Remove this USB
   - Boot normally from your Unraid USB

TROUBLESHOOTING
───────────────
• Can't see boot menu?
  → Press the boot key repeatedly during startup

• Ventoy menu doesn't appear?
  → Try a different USB port
  → Check BIOS boot order

• Script doesn't run?
  → It should start automatically
  → Check the screen for any error messages

• Need to cancel?
  → Type "no" when prompted
  → Type "poweroff" to shut down

TECHNICAL DETAILS
─────────────────
This USB uses Ventoy for multi-boot capability.
Scripts are auto-injected into SystemRescue at boot.
Your recovery script: /sysrescue.d/autorun/move_dr_to_unraid.sh

For support: Check your IT department or Unraid forums
───────────────────────────────────────────────────────────
INSTRUCTIONS_EOF

echo "  ✅ User instructions created"

# Sync filesystem
echo
echo "Syncing filesystem..."
sync
# Give the filesystem a moment to fully flush
sleep 2

# Unmount Ventoy USB (if we mounted it)
if [ "$IS_UNRAID" = true ]; then
    echo "Unmounting Ventoy USB..."
    
    # Change directory away from the mount point (in case we're in it)
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
        echo "   Or check what's using it with: lsof $VENTOY_MOUNT"
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
echo "  └── ventoy/"
echo "      ├── ventoy.json"
echo "      ├── sysrescue_injection.tar.gz"
echo "      └── sysrescue_injection/"
echo "          └── sysrescue.d/autorun/"
echo "              ├── move_dr_to_unraid.sh"
echo "              └── 00-launcher.sh"
echo
echo "WHAT TO DO NOW:"
echo "  1. The Ventoy USB has been safely unmounted"
echo "  2. You can now safely remove the USB drive"
echo "  3. Give it to your user with the instructions"
echo "  4. They boot from USB → Select SystemRescue → Auto-runs!"
echo
echo "TO UPDATE THE SCRIPT LATER:"
echo "  1. Mount the Ventoy USB"
echo "  2. Replace: $VENTOY_MOUNT/ventoy/sysrescue_injection/sysrescue.d/autorun/move_dr_to_unraid.sh"
echo "  3. Recreate archive: cd $VENTOY_MOUNT/ventoy/sysrescue_injection && tar -czf ../sysrescue_injection.tar.gz sysrescue.d/"
echo "  4. Sync and eject"
echo
echo "═══════════════════════════════════════════════════════"
