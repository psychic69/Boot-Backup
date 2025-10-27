# Unraid Boot Backup Suite

A comprehensive backup and recovery solution for Unraid USB boot drives, providing automated local backups and a bootable emergency recovery environment.

## Overview

The Boot Backup Suite was created to provide local backup and easy recovery when the main Unraid USB boot drive fails. This suite offers peace of mind with automated backups and a simple recovery process that can restore your system in minutes.

The suite consists of **two distinct backup scripts**:
- **`dr_usb_create.sh`** - One-time setup that creates and formats the backup USB
- **`dr_usb_backup.sh`** - Repeatable backup script for ongoing automated backups

This separation ensures you never accidentally reformat your backup USB during routine backups, while keeping the recovery process simple and safe.

> **⚠️ Important License Note:** The backup USB drive (UNRAID_DR) will consume a license slot if kept in the system during boot. To avoid this, only insert the backup USB after the array has started, or remove it before shutdown.

## Table of Contents

- [What You Need](#what-you-need)
- [What This Suite Offers](#what-this-suite-offers)
- [What This Suite Doesn't Offer](#what-this-suite-doesnt-offer)
- [Quick Start Guide](#quick-start-guide)
- [Scripts Overview](#scripts-overview)
- [Recovery Process](#recovery-process)
- [Technical Details](#technical-details)
- [Licensing After Recovery](#licensing-after-recovery)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## What You Need

### Hardware Requirements

1. **Two USB drives:**
   - **Backup USB** (4GB-64GB) - For storing the Unraid boot backup (labeled `UNRAID_DR`)
   - **Recovery USB** (8GB+ recommended) - For the emergency recovery environment

2. **Ventoy installed on the recovery USB**
   - Download from: [Ventoy Official Site](https://www.ventoy.net/)
   - The scripts will configure Ventoy automatically

3. **(Optional) SystemRescue ISO**
   - Recommended version: 12.02 or later
   - If not provided, the setup script will automatically download it

### Software Requirements

- Unraid 6.x or later (tested on UEFI systems)
- Bash (included in Unraid)
- Standard Linux utilities (rsync, lsblk, fatlabel - all included in Unraid)

### Automation (Optional but Recommended)

- **User Scripts plugin** (recommended) - For automated scheduled backups
- **Cron** (alternative) - For custom scheduling

## What This Suite Offers

### Core Features

1. ✅ **Easy Replication** - Complete USB boot drive backup within the same system for emergency recovery
2. ✅ **Bifurcated Script Design** - Separate scripts for creation and backup prevent accidental reformatting
3. ✅ **Modern Sector Alignment** - Prevents unnecessary I/O and wear on USB drives
4. ✅ **Delta Sync Technology** - Uses rsync to minimize write wear by only updating changed files
5. ✅ **Automatic Backup Creation** - Auto-creates and formats backup USB to be Unraid-compliant (up to 64GB)
6. ✅ **Safe Labeling** - Uses `UNRAID_DR` label to prevent boot confusion with main `UNRAID` drive
7. ✅ **UEFI Boot Safety** - Disables conflicting UEFI boot entries and maintains Unraid's `make_bootable` compliance
8. ✅ **Automated Recovery USB Creation** - Creates entire bootable recovery environment from Unraid server
9. ✅ **Repeatable Backups** - Separate backup script for use with your own automation or User Scripts plugin
10. ✅ **Automatic Log Management** - Configurable log retention (by count or age) with customizable log location
11. ✅ **Backup Timestamps** - Writes last successful backup date/time to backup USB for quick verification
12. ✅ **Smart USB Detection** - Prevents accidental writes to main USB with intelligent device selection
13. ✅ **Multiple Safety Checks** - Extensive validation ensures main `/boot` USB is never overwritten or destroyed

### Safety Features

- **Automatic conflict detection** - Won't proceed if it detects unsafe conditions
- **Parent device transport validation** - Correctly identifies USB devices vs internal drives
- **Read-only main boot protection** - Main Unraid USB is never modified by backup operations
- **Boot prevention on backup USB** - Renames `EFI` to `EFI-` on backup to prevent accidental boot
- **Detailed error messages** - Clear diagnostics when issues arise
- **SHA512 verification** - Ensures downloaded ISOs are authentic and uncorrupted
- **Single backup enforcement** - Backup script only runs if exactly one UNRAID_DR drive found

## What This Suite Doesn't Offer

### Current Limitations

1. ❌ **CSM/Legacy BIOS boot** - Designed for UEFI systems only (CSM boot not tested or guaranteed)
2. ❌ **Live restore function** - Cannot restore to main USB while system is running (requires recovery environment for safety)
3. ❌ **Backup snapshots** - Provides 1:1 backup only; no versioning or multiple backup generations
4. ❌ **Automatic USB licensing** - After recovery, you must manually license the new USB with Unraid (see [Licensing After Recovery](#licensing-after-recovery))

### Known Constraints

- **Maximum backup USB size:** 64GB (Unraid USB limitation)
- **Minimum backup USB size:** 4GB (sufficient for typical Unraid boot)
- **Filesystem:** FAT32 only (Unraid requirement)
- **Transport type detection:** USB devices only (will not backup to internal drives)

> **⚠️ Critical:** Re-licensing a USB drive will permanently blacklist the original USB in Unraid. Ensure your original USB is truly dead before re-licensing.

## Quick Start Guide

### Step 1: Create the Backup USB

```bash
# 1. Download the scripts
cd /tmp
git clone <repository-url>
cd <repository-name>

# 2. Make scripts executable (if they are not)
chmod +x dr_usb_create.sh
chmod +x dr_usb_backup.sh

# 3. Plug in your backup USB drive (typically 8GB or more)

# 4. Create the initial backup USB
./dr_usb_create.sh

# Follow the prompts to select your USB drive
```

### Step 2: Create the Recovery USB

> **Note:** The script is `setup_ventoy_usb.sh`.

```bash
# 1. Install Ventoy on your recovery USB drive
# Download from: https://www.ventoy.net/

# 2. Make scripts executable (if not already)
chmod +x setup_ventoy_usb.sh
chmod +x move_dr_to_unraid.sh

# 3. Plug in your Ventoy USB drive

# 4. Create the recovery environment
./setup_ventoy_usb.sh

# The script will:
# - Find your Ventoy USB automatically
# - Download SystemRescue ISO (if needed) with SHA512 verification
# - Copy recovery scripts to USB
# - Create ventoy.json configuration
# - Generate user instructions
```

### Step 3: Set Up Automated Backups

**Using User Scripts Plugin (Recommended):**

1. Install "User Scripts" from Community Applications
2. Add a new script
3. Copy the contents of `dr_usb_backup.sh`
4. Configure schedule (e.g., daily at 3 AM)
5. Save and test

**Using Cron:**

```bash
# Add to /boot/config/go (runs at startup)
# Daily backup at 3 AM
echo "0 3 * * * /path/to/dr_usb_backup.sh" >> /boot/config/crontab
```

## Documentation

Detailed documentation for each script is available in the `docs/` folder:

- **[dr_usb_create.md](docs/dr_usb_create.md)** - Complete guide for the interactive setup script
- **[dr_usb_backup.md](docs/dr_usb_backup.md)** - Complete guide for the automated backup script  
- **[VENTOY_README.md](docs/VENTOY_README.md)** - Complete guide for creating the recovery USB

These documents include:
- Detailed feature explanations
- Installation and scheduling instructions
- Testing flags for development
- Comprehensive FAQ sections
- Troubleshooting specific to each script

## Script Workflow Summary

| Script | Purpose | Frequency | Risk Level | Description |
|--------|---------|-----------|------------|-------------|
| `dr_usb_create.sh` | **Create backup USB** | One-time | ⚠️ High (formats USB) | Initial setup - formats and creates backup USB |
| `dr_usb_backup.sh` | **Update backup** | Daily/Weekly | ✅ Low (rsync only) | Incremental backups - safe for automation |
| `setup_ventoy_usb_simple.sh` | **Create recovery USB** | One-time | ⚠️ Medium (downloads ISO) | Sets up emergency recovery environment |
| `move_dr_to_unraid.sh` | **Emergency restore** | As needed | ⚠️ High (changes labels) | Restores UNRAID_DR → UNRAID during recovery |

> **💡 Key Insight:** The bifurcation of creation vs backup ensures `dr_usb_backup.sh` can run safely on automation without risk of reformatting your backup USB.

## Scripts Overview

### 1. `dr_usb_create.sh`

**Purpose:** One-time interactive setup of backup USB drive

> **🛑 CRITICAL:** This script is **interactive** and MUST be run from SSH. DO NOT run from the Unraid GUI - it will hang waiting for input.

**What it does:**
- Guides you through selecting a suitable USB drive interactively
- Actively scans for and ignores your primary `UNRAID` boot drive
- Formats USB drive as FAT32 with proper sector alignment (1MB/2048 sectors)
- Labels drive as `UNRAID_DR`
- Creates 64GB partition if drive is larger (Unraid USB limit)
- Performs initial full backup from `/boot` (clone_backup)
- Creates necessary directory structure
- Disables conflicting UEFI boot entries (renames `EFI` to `EFI-`)
- Runs Unraid's `make_bootable_linux.sh`

**When to run:** 
- Once during initial setup via SSH
- When recreating backup USB from scratch
- When switching to a new backup USB drive

**Failsafe:** Will exit with error if `UNRAID_DR` drive already exists, protecting your existing backup.

**Installation:**
1. In Unraid GUI: Settings → User Scripts → Add New Script
2. Name it `DR_USB_Create`
3. Paste script contents
4. Set schedule to **Schedule Disabled**
5. Run from SSH: `/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script`

---

### 2. `dr_usb_backup.sh`

**Purpose:** Fully automated incremental backups (set and forget)

> **✅ SAFE:** 100% non-interactive - designed for automated scheduling. Will only run if exactly one `UNRAID_DR` partition is found.

**What it does:**
- Finds the `UNRAID` boot drive automatically
- Finds exactly one `UNRAID_DR` backup drive
- Mounts backup drive, runs rsync, unmounts
- Uses rsync for efficient delta sync (only changed files)
- Creates timestamped logs with detailed operation records
- Manages log retention based on `SNAPSHOTS` and `RETENTION_DAYS` settings
- Updates backup timestamp on completion
- Renames `EFI` directory to `EFI-` to prevent accidental boot from backup
- Reports backup statistics (files transferred, size, duration)

**When to run:** 
- Daily/weekly via User Scripts scheduler (recommended)
- Via cron job
- After major Unraid configuration changes
- After plugin installations or updates

**Safety:** If zero or more than one `UNRAID_DR` drive found, logs clear error and exits safely.

**Installation & Scheduling:**

**Option 1 (Recommended) - User Scripts Scheduler:**
1. Settings → User Scripts → Add New Script
2. Name it `DR_USB_Backup`
3. Paste script contents
4. Click the schedule → Select "Daily" (e.g., 3:00 AM)
5. Click Apply

**Option 2 (Advanced) - Manual Cron:**
1. Install in User Scripts with schedule disabled
2. Create `/boot/config/cron.d/dr_backup`:
   ```bash
   # Run DR USB Backup daily at 3:00 AM
   0 3 * * * /boot/config/plugins/user.scripts/scripts/DR_USB_Backup/script
   ```
3. Reboot or run `update-cron`

**Testing Flags:**
- `-debug`: Enables verbose logging with DEBUG output
- `-lsblk`: Uses local `test-lsblk` file for synthetic testing

---

### 3. `setup_ventoy_usb.sh`

**Purpose:** Creates bootable recovery USB with SystemRescue

**What it does:**
- Detects Ventoy USB automatically (looks for "Ventoy" label)
- Downloads SystemRescue ISO with SHA512 verification (if not present)
- Creates `ventoy.json` with proper UEFI remount settings (`VTOY_LINUX_REMOUNT: "1"`)
- Copies `move_dr_to_unraid.sh` recovery script to USB
- Generates `UNRAID_RECOVERY_INSTRUCTIONS.txt` for users
- Validates all components

**When to run:** Once during initial setup

**What gets created on Ventoy USB:**
```
Ventoy USB/
├── systemrescue-12.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── ventoy/
│   └── ventoy.json
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

---

### 4. `move_dr_to_unraid.sh`

**Purpose:** Emergency recovery - restores UNRAID_DR to UNRAID

**What it does:**
- Validates no conflicting `UNRAID` drive exists
- Finds exactly one `UNRAID_DR` USB drive
- Changes label from `UNRAID_DR` to `UNRAID`
- Runs `make_bootable_linux.sh` to make it bootable
- Provides detailed diagnostics if issues arise

**When to run:** During emergency recovery from SystemRescue environment

## Recovery Process

### When Your Main USB Fails

1. **Prepare for Recovery**
   - ☐ Remove the failed main USB drive (labeled `UNRAID`)
   - ☐ Insert your backup USB (labeled `UNRAID_DR`)
   - ☐ Insert your Ventoy recovery USB
   - ☐ Restart the system

2. **Boot SystemRescue**
   - At the Ventoy menu, select: **"Unraid Recovery - SystemRescue"**
   - Wait 30-60 seconds for SystemRescue to boot
   - You'll see a command prompt

3. **Mount the USB Drives**
   ```bash
   mountall
   ```
   This command mounts all USB drives, including the Ventoy partition.

4. **Find and Run the Recovery Script**
   ```bash
   # List mount points to find the Ventoy USB
   ls /mnt/
   
   # Usually shows: sdb1, sdc1, sdd1, etc.
   # Look for the one with unraid_recovery folder
   ls /mnt/sdb1/
   
   # Use lsblk to confirm which device is the Ventoy partition
   lsblk
   
   # Run the recovery script (replace sdb1 with your actual mount point)
   bash /mnt/sdb1/unraid_recovery/move_dr_to_unraid.sh
   ```

5. **Follow the Script**
   - The script will automatically:
     - ✅ Verify `UNRAID_DR` backup USB is present
     - ✅ Check for conflicts with existing `UNRAID` drives
     - ✅ Change label from `UNRAID_DR` to `UNRAID`
     - ✅ Make the drive bootable
     - ✅ Confirm completion

6. **Shut Down and Boot**
   ```bash
   poweroff
   ```
   - Remove the Ventoy recovery USB
   - Remove the backup USB (now your main `UNRAID` boot drive)
   - Boot normally

7. **License the New USB**
   - Unraid will start but the array won't start automatically
   - You must license the new USB drive
   - See [Licensing After Recovery](#licensing-after-recovery) below

### Recovery Time

**Total recovery time:** 2-5 minutes
- Boot SystemRescue: ~60 seconds
- Run recovery script: ~30 seconds
- Reboot and license: ~2-3 minutes

## Technical Details

### Backup USB Structure

```
/mnt/disks/UNRAID_DR/
├── EFI/
│   └── boot/
│       └── bootx64.efi
├── boot/
├── bzimage
├── bzmodules
├── bzroot
├── config/
├── logs/
├── make_bootable.bat
├── make_bootable_linux.sh
├── make_bootable_mac.sh
├── previous/
├── syslinux/
├── System Volume Information/
└── LAST_BACKUP_SUCCESS.txt
```

### Recovery USB Structure

```
Ventoy USB/
├── systemrescue-12.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── ventoy/
│   └── ventoy.json
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

### Ventoy Configuration

The `ventoy.json` file includes critical settings:

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

**Key setting:** `VTOY_LINUX_REMOUNT: "1"` remounts the Ventoy partition as read-write in UEFI mode, allowing SystemRescue to access the recovery script.

### Sector Alignment

The suite uses modern 1MB (2048 sector) alignment:
- Better performance on modern flash storage
- Reduces write amplification
- Extends USB drive lifespan

### Tools Used

- **rsync** - Delta sync for efficient backups
- **lsblk** - Device detection and validation
- **fatlabel** - Modern FAT32 label management (replaces deprecated mlabel)
- **parted** - Partition creation and alignment
- **mkfs.vfat** - FAT32 filesystem creation
- **Ventoy** - Multi-boot USB solution
- **SystemRescue** - Arch-based rescue environment

## Licensing After Recovery

After restoring your Unraid USB from backup, the system will boot but the array will not start until you license the new USB drive.

### Steps to License New USB

1. **Boot your Unraid system** with the restored USB
2. **Access the Unraid WebGUI** (the UI will load normally)
3. **Go to Tools → Registration**
4. **Click "Replace Key"** or follow the registration prompts
5. **Follow Unraid's USB replacement process**

### Official Unraid Documentation

📖 **USB Flash Drive Replacement Guide:**  
[https://docs.unraid.net/unraid-os/manual/changing-the-flash-device/](https://docs.unraid.net/unraid-os/manual/changing-the-flash-device/)

📖 **Unraid Licensing Information:**  
[https://unraid.net/pricing](https://unraid.net/pricing)

### Important Licensing Notes

> **⚠️ Critical Warning:** Re-licensing a USB drive will **permanently blacklist** the original USB in Unraid. Once you transfer your license to the new USB:
> - The original USB can **never** be used with Unraid again
> - This applies even if you recover the original USB later
> - Ensure your original USB is truly dead before re-licensing

**Recommendation:** If your original USB might be recoverable:
1. Try to repair it first
2. Only re-license if recovery is impossible
3. Keep the failed USB as a physical record

### License Transfer Process

1. **Prepare for transfer:**
   - Have your Unraid account credentials ready
   - Have your registration key/email available

2. **Transfer license:**
   - Log into your Unraid account at [unraid.net](https://unraid.net/)
   - Navigate to your registered devices
   - Follow the USB replacement process
   - Approve the new USB GUID

3. **Activate:**
   - Return to Unraid WebGUI
   - Complete the activation process
   - Your array will now be accessible

## Troubleshooting

### Script Naming Changes

**Note for existing users:** If you're updating from an older version:
- `create_unraid_backup_usb.sh` → **`dr_usb_create.sh`**
- `backup_unraid_usb_to_dr.sh` → **`dr_usb_backup.sh`**

The functionality remains the same, just with clearer names and improved separation of concerns.

---

### Backup Creation Issues

**Problem:** "Why can't I run dr_usb_create.sh from the GUI?"
- **Solution:** The script uses the `read` command for interactive prompts. The GUI has no way to send your answers to the script.
- **Must use SSH:** Connect via SSH and run: `/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script`

**Problem:** "An 'UNRAID_DR' partition was already found!"
- **Solution:** This is a safety feature. Your backup drive is already set up.
- **Action:** Use `dr_usb_backup.sh` for daily backups instead

**Problem:** "It can't find my USB drive!"
- **Solution:** The script looks for USB drives at least 95% the size of your main Unraid flash
- **Requirement:** Drive must already have a label
- **Fix:** If brand new, format it once with any label so it appears in the list

**Problem:** "No suitable USB drives found"
- **Solution:** Ensure USB drive is plugged in and detected by system
- **Check:** `lsblk -o NAME,SIZE,TRAN,LABEL` to see all drives

**Problem:** "USB mount is read-only"
- **Solution:** Remount with: `mount -o remount,rw /dev/sdX1 /mnt/disks/UNRAID_DR`

---

### Backup Script Issues

**Problem:** "No 'UNRAID_DR' backup partition was found!"
- **Solution:** You haven't run `dr_usb_create.sh` yet
- **Action:** Run the create script once from SSH to set up your backup drive

**Problem:** "Multiple partitions with the label 'UNRAID_DR' found."
- **Solution:** Safety stop - script found 2+ drives with UNRAID_DR label
- **Fix:** Unplug one, or use `lsblk -f` to find them and rename the incorrect label

**Problem:** "Can I run dr_usb_backup.sh manually from SSH?"
- **Solution:** Yes! Unlike the create script, this one is non-interactive and works perfectly from SSH or GUI

**Problem:** "How do I test if it's working?"
- **Solution:** 
  1. Go to User Scripts page
  2. Click "Run in Background"
  3. After a minute, check your `LOG_DIR` (e.g., `/boot/logs/unraid-dr/logs/`)
  4. Look for new log file with backup details

---

### Recovery Issues

**Problem:** "No USB drive with label UNRAID_DR found"
- **Solution:** Verify backup USB is plugged in
- **Check:** Label must be exactly `UNRAID_DR` (case-sensitive)
- **Verify:** `lsblk -o NAME,LABEL`

**Problem:** "A drive with label UNRAID already exists"
- **Solution:** Remove the existing UNRAID USB first
- **Note:** This script only works when UNRAID drive is missing/dead

**Problem:** Can't find recovery script after `mountall`
- **Solution:** 
  ```bash
  ls /mnt/
  ls /mnt/sdb1/
  ls /mnt/sdc1/
  # Look for unraid_recovery folder
  ```

**Problem:** "Transport type not USB" error
- **Solution:** Updated script now correctly detects USB at device level, not partition level
- **Update:** Get latest `move_dr_to_unraid.sh`

**Problem:** Ventoy partition mounted read-only
- **Solution:** Ensure `VTOY_LINUX_REMOUNT: "1"` is in ventoy.json
- **Manual fix:** `mount -o remount,rw /dev/sdX1 /mnt/sdX1`

### Setup Issues

**Problem:** "SHA512 verification failed"
- **Solution:** Re-download SystemRescue ISO (file may be corrupted)
- **Check:** Internet connection stability

**Problem:** Ventoy USB not detected during setup
- **Solution:** 
  - Verify Ventoy is properly installed
  - Check USB is labeled "Ventoy"
  - Try: `lsblk -o NAME,LABEL,TRAN`

## Best Practices

### Backup Schedule

**Recommended frequency:**
- **Daily backups** if you frequently modify config/plugins
- **Weekly backups** for stable systems
- **After major changes** (plugin installs, config updates)

### Testing Your Backup

Periodically verify your backup:
1. Check `LAST_BACKUP_SUCCESS.txt` on backup USB
2. Review backup logs for errors
3. Verify backup USB contents match main USB
4. Test recovery process in a VM (if possible)

### USB Drive Selection

**Backup USB recommendations:**
- Use quality USB drives (SanDisk, Samsung, Kingston)
- USB 3.0+ for faster backups
- 8-16GB size (more than enough for Unraid boot)

**Recovery USB recommendations:**
- Use a dedicated USB for recovery only
- 16GB+ recommended
- Keep in a safe, accessible location

### Maintenance

**Monthly:**
- ✅ Verify latest backup timestamp
- ✅ Check backup logs for errors
- ✅ Verify backup USB is readable

**Quarterly:**
- ✅ Test recovery process (if possible)
- ✅ Update SystemRescue ISO (if new version available)
- ✅ Review and clean old backup logs

**Annually:**
- ✅ Consider replacing backup USB (USB drives do age)
- ✅ Update recovery scripts (check repository for updates)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Test thoroughly (especially device detection logic)
5. Submit a pull request with detailed description

### Code Guidelines

- **Maintain separation of concerns**: Keep creation script (`dr_usb_create.sh`) and backup script (`dr_usb_backup.sh`) functionally separate
- **Preserve safety checks**: Never remove or weaken validation logic
- **Test with real hardware**: USB device detection must be tested on actual systems
- **Document changes**: Update README.md for user-facing changes

### Areas for Contribution

- CSM/Legacy BIOS boot support
- Additional safety checks
- Enhanced error handling
- GUI/web interface
- Automated testing suite
- Backup verification/validation features
- Snapshot/versioning support (future)

## License

[Specify your license here - MIT, GPL, etc.]

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review existing GitHub issues
3. Create a new issue with:
   - Unraid version
   - Detailed description of problem
   - Relevant log output
   - Steps to reproduce

## Acknowledgments

- Unraid team for the excellent NAS OS
- SystemRescue project for the rescue environment
- Ventoy project for the multi-boot USB solution
- Community contributors and testers

---

**⚠️ Remember:** This suite is designed for UEFI systems only. Always test your recovery process before you need it in an emergency!

**📝 Note:** Keep your recovery USB in a safe, accessible location separate from your server. A backup is only useful if you can access it when needed!
