# Unraid USB Recovery - Ventoy Solution

## Quick Start

**You only need:**
1. `setup_ventoy_usb_simple.sh` - The setup script
2. `move_dr_to_unraid.sh` - The recovery script

**No other files needed!** The script creates everything else automatically.

## Setup (Run from Unraid)

```bash
# Make scripts executable
chmod +x setup_ventoy_usb_simple.sh
chmod +x move_dr_to_unraid.sh

# Run setup (will auto-create ventoy.json)
./setup_ventoy_usb_simple.sh
```

The script will:
- ✅ Find your Ventoy USB automatically
- ✅ Download SystemRescue ISO with SHA512 verification
- ✅ Copy recovery script to USB
- ✅ Auto-create ventoy.json with proper settings
- ✅ Create user instructions

## What Gets Created

```
Ventoy USB/
├── systemrescue-12.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── ventoy/
│   └── ventoy.json (auto-created)
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

## ventoy.json Configuration

The script automatically creates `ventoy.json` with these important settings:

```json
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
```

### Key Settings Explained

**`VTOY_DEFAULT_SEARCH_ROOT: "/"`**
- Searches for ISOs in the root of the USB drive
- Keeps things simple and organized

**`VTOY_MENU_TIMEOUT: 30`**
- Gives users 30 seconds to select an option
- Auto-boots first entry if no selection made

**`VTOY_LINUX_REMOUNT: "1"`** ⭐ **CRITICAL SETTING**
- Remounts the Ventoy partition as **read-write** in UEFI mode
- Without this, the Ventoy partition would be read-only in SystemRescue
- This allows the `mountall` command to work properly
- Required for accessing the recovery script on the Ventoy USB

**`menu_alias`**
- Gives SystemRescue ISO a friendly name in the menu
- Shows as "Unraid Recovery - SystemRescue"

## User Experience

### For End Users (Emergency Recovery):

1. **Boot from Ventoy USB**
2. **Select "Unraid Recovery - SystemRescue"**
3. **At prompt, type:** `mountall`
4. **Run:** `bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh`
5. **When complete, type:** `poweroff`

The entire process takes 2-3 minutes after boot.

## Why This Approach Works

✅ **No injection complexity** - Just plain files  
✅ **No ISO rebuilding** - No special tools needed  
✅ **Works on Unraid** - No package manager required  
✅ **Easy to update** - Just edit the script file  
✅ **UEFI compatible** - VTOY_LINUX_REMOUNT handles read-write access  
✅ **SHA512 verified** - Ensures ISO integrity  

## Updating the Recovery Script

To update `move_dr_to_unraid.sh` later:

### From Unraid:
```bash
mkdir -p /mnt/ventoy
mount /dev/sdX1 /mnt/ventoy  # Replace X with your USB
nano /mnt/ventoy/unraid_recovery/move_dr_to_unraid.sh
# Make changes, save, exit
umount /mnt/ventoy
```

### From Any Computer:
1. Mount the Ventoy USB (usually auto-mounts)
2. Navigate to: `unraid_recovery/`
3. Edit: `move_dr_to_unraid.sh`
4. Save and safely eject

## Troubleshooting

### Setup Issues

**"Ventoy USB not found"**
- Ensure Ventoy is installed on a USB drive
- Check `lsblk -o NAME,LABEL,TRAN` to find it

**"SHA512 verification failed"**
- Re-download the ISO (may be corrupted)
- Check internet connection

### Recovery Issues

**"Can't find the recovery script"**
- After `mountall`, type: `ls /mnt/`
- Try each mount: `ls /mnt/sdb1/`
- Look for `unraid_recovery` folder

**"No USB drive with label UNRAID_DR found"**
- Verify backup USB is plugged in
- Check label is exactly "UNRAID_DR"

**"Ventoy partition mounted read-only"**
- This shouldn't happen with `VTOY_LINUX_REMOUNT: "1"`
- If it does, manually remount: `mount -o remount,rw /dev/sdX1 /mnt/sdX1`

## Technical Details

### Why VTOY_LINUX_REMOUNT is Critical

In UEFI boot mode, Ventoy normally mounts its partition as **read-only** to Linux systems. This is a safety feature, but it prevents SystemRescue from accessing files on the Ventoy partition.

Setting `VTOY_LINUX_REMOUNT: "1"` tells Ventoy to:
1. Mount the partition initially as read-only (safe)
2. Remount it as read-write after boot (functional)
3. Allow Linux tools like `mountall` to access the files

Without this setting, users would have to manually remount the partition, adding complexity.

### Tools Used

- **Ventoy** - Multi-boot USB solution
- **SystemRescue** - Arch-based rescue environment  
- **fatlabel** - Modern FAT32 label tool (native in SystemRescue)
- **SHA512** - Cryptographic verification of ISO integrity

### Security

- All ISO downloads are SHA512 verified
- Device selection excludes boot and DR drives
- Multiple confirmation prompts before destructive operations
- Read-only mount initially, then remount as needed

## Files Needed

### Required (in same directory):
- `setup_ventoy_usb_simple.sh`
- `move_dr_to_unraid.sh`

### Auto-generated:
- `ventoy.json` (created by setup script)
- `UNRAID_RECOVERY_INSTRUCTIONS.txt` (created by setup script)

### Optional Reference:
- `ventoy.json` (standalone file for reference only - not required)
- `UNRAID_RECOVERY_INSTRUCTIONS_SIMPLE.txt` (detailed user guide)

## Support

For issues:
1. Check the troubleshooting section above
2. Review `UNRAID_RECOVERY_INSTRUCTIONS.txt` on the USB
3. Consult Unraid forums for Unraid-specific questions

---

**Remember:** This solution requires only TWO files to start:
1. `setup_ventoy_usb_simple.sh`
2. `move_dr_to_unraid.sh`

Everything else is auto-generated! 🎉
