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

# Check if move_DR_to_UNRAID.sh exists
if [ ! -f "$SCRIPT_DIR/move_DR_to_UNRAID.sh" ]; then
    echo "❌ ERROR: move_DR_to_UNRAID.sh not found!"
    echo "   Please make sure it's in the same directory as this script."
    exit 1
fi

# Find Ventoy USB partition
echo "Looking for Ventoy USB drive..."
VENTOY_MOUNT=""

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

echo "✅ Found Ventoy USB at: $VENTOY_MOUNT"
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
        # Check if .sha512 file exists locally (we'll need it for verification)
        if [ ! -f "$SCRIPT_DIR/$SYSRESCUE_SHA512" ]; then
            echo "📥 SHA512 hash file not found. Downloading..."
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
        
        # Verify the hash of the ISO on USB
        if ! verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SCRIPT_DIR/$SYSRESCUE_SHA512"; then
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
cp "$SCRIPT_DIR/move_DR_to_UNRAID.sh" "$AUTORUN_DIR/"
chmod +x "$AUTORUN_DIR/move_DR_to_UNRAID.sh"
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
    bash /sysrescue.d/autorun/move_DR_to_UNRAID.sh
    
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
Your recovery script: /sysrescue.d/autorun/move_DR_to_UNRAID.sh

For support: Check your IT department or Unraid forums
───────────────────────────────────────────────────────────
INSTRUCTIONS_EOF

echo "  ✅ User instructions created"

# Sync filesystem
echo
echo "Syncing filesystem..."
sync

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
echo "              ├── move_DR_to_UNRAID.sh"
echo "              └── 00-launcher.sh"
echo
echo "WHAT TO DO NOW:"
echo "  1. Safely eject/unmount the USB"
echo "  2. Give it to your user with the instructions"
echo "  3. They boot from USB → Select SystemRescue → Auto-runs!"
echo
echo "TO UPDATE THE SCRIPT LATER:"
echo "  1. Mount the Ventoy USB"
echo "  2. Replace: $VENTOY_MOUNT/ventoy/sysrescue_injection/sysrescue.d/autorun/move_DR_to_UNRAID.sh"
echo "  3. Recreate archive: cd $VENTOY_MOUNT/ventoy/sysrescue_injection && tar -czf ../sysrescue_injection.tar.gz sysrescue.d/"
echo "  4. Sync and eject"
echo
echo "═══════════════════════════════════════════════════════"