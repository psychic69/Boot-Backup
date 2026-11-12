# Getting Started - Quick Reference

**Welcome to the Unraid Boot Backup Suite!** This guide will get you up and running in 15 minutes.

## Prerequisites Checklist

Before you begin, gather:

- [ ] **Two USB drives:**
  - One for backup (4-64GB) → Will become `UNRAID_DR`
  - One for recovery (8GB+) → Will have Ventoy auto-installed if needed
- [ ] **SSH access** to your Unraid server
- [ ] **5-10 minutes** of your time

## Installation - 4 Simple Steps

### Step 0: Install the Release (2 minutes)

Everything ships as one archive. On the Unraid server (SSH), download it from the [Releases page](https://github.com/psychic69/Boot-Backup/releases), verify it, and extract it (use the current version number in place of `1.2.0`):

```bash
cd /tmp
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz.sha256
sha256sum -c Boot-Backup-1.2.0.tar.gz.sha256        # must print: Boot-Backup-1.2.0.tar.gz: OK
tar -xzf Boot-Backup-1.2.0.tar.gz -C /boot/config/plugins/ --no-same-owner --no-same-permissions
```

**What happens:**
- ✅ Creates `/boot/config/plugins/dr_usb/` with the backup and create scripts, their `lib/` modules, the recovery USB tools (`Recovery-ISO/`) and settings templates
- ✅ Safe to repeat later to upgrade: your own settings files are never overwritten

---

### Step 1: Create Your Backup USB (5 minutes)

**From SSH Terminal on your Unraid server:**

```bash
# 1. Plug in your backup USB (a brand-new or previously used stick both work)

# 2. Run the script
bash /boot/config/plugins/dr_usb/dr_usb_create.sh

# 3. Follow the prompts:
#    - Select your USB drive from the list (drives that already contain data are marked *)
#    - Confirm formatting (WARNING: Erases drive!)
#    - Wait for initial backup to complete
```

**What happens:**
- ✅ Formats USB as FAT32 with `UNRAID_DR` label
- ✅ Performs first full backup of your boot drive
- ✅ Takes ~2-5 minutes

---

### Step 2: Set Up Automated Backups (2 minutes)

**From Unraid WebGUI:**

1. Go to **Settings** → **User Scripts**
2. Click **Add New Script**
3. Name it: `DR_USB_Backup`
4. Click **Edit Script**
5. Replace the contents with these two lines:
   ```bash
   #!/bin/bash
   bash /boot/config/plugins/dr_usb/dr_usb_backup.sh
   ```
6. Click **Save Changes**
7. Set schedule to **Daily** at 3:00 AM (or your preferred time)
8. Click **Apply**

**What happens:**
- ✅ Backup runs automatically every day
- ✅ Only copies changed files (fast!)
- ✅ Checks your Unraid boot files against their hashes first and stops if any are damaged
- ✅ Creates logs in `/boot/logs/unraid-dr/logs/`
- ✅ Completely hands-off

> Want to change the log folder, retention or mount point? Copy `dr_usb.ini.example` to `dr_usb.ini` in the same folder and edit it (optional).

---

### Step 3: Create Recovery USB (5 minutes)

**From Unraid Terminal:**

```bash
# 1. Plug in your recovery USB drive
#    (Ventoy will be auto-installed if not already present)

# 2. Run the setup script
bash /boot/config/plugins/dr_usb/Recovery-ISO/scripts/setup_ventoy_usb.sh

# 3. Follow prompts to scan/select USB if needed
#    (only happens if Ventoy not already installed)

# 4. Wait for SystemRescue ISO download (~2 minutes)
```

**What happens:**
- ✅ Auto-detects existing Ventoy OR installs it from scratch
- ✅ Scans all available USB drives (new, unpartitioned, labeled, unlabeled)
- ✅ Downloads SystemRescue ISO (SHA512 verified)
- ✅ Copies recovery script to USB
- ✅ Creates configuration files
- ✅ Generates user instructions
- ✅ Tracks version for future upgrades

**To upgrade an existing recovery USB later:**

Edit the Ventoy / SystemRescue versions in `Recovery-ISO/scripts/setup_ventoy.ini` if you want newer ones, then plug in the USB and re-run the same script:
```bash
bash /boot/config/plugins/dr_usb/Recovery-ISO/scripts/setup_ventoy_usb.sh
```
It compares what is on the USB with the ini file, updates Ventoy in place (your files are kept), and swaps in a new SystemRescue ISO if needed.

---

## You're Done! 🎉

Your backup system is now active. Here's what you have:

| USB Drive | Label | Purpose | Location |
|-----------|-------|---------|----------|
| Backup USB | `UNRAID_DR` | Daily automated backups | Leave in server or store safely |
| Recovery USB | `Ventoy` | Emergency recovery | Store in safe location |

## Testing Your Setup

### Test the Backup (Optional)

```bash
# From Unraid WebGUI:
# Settings → User Scripts → DR_USB_Backup → "Run in Background"

# Wait 1 minute, then check:
ls -lh /boot/logs/unraid-dr/logs/
cat /mnt/disks/UNRAID_DR/LAST_BACKUP_SUCCESS.txt
```

You should see:
- ✅ New log file with timestamp
- ✅ `LAST_BACKUP_SUCCESS.txt` updated with current date/time

## What Happens Now?

### Daily Operation (Automatic)
- Backup runs every day at scheduled time
- Only changed files are copied (fast!)
- Logs are created and old logs cleaned up
- No intervention needed

### When Emergency Strikes

**If your main USB fails:**

1. **Remove** failed main USB
2. **Insert** backup USB (`UNRAID_DR`)
3. **Insert** recovery USB (Ventoy)
4. **Boot** from recovery USB
5. **Select** "Unraid Recovery - SystemRescue"
6. **Type:** `mountall`
7. **Type:** `bash /mnt/VentoyPart/unraid_recovery/move_dr_to_unraid.sh`  (older recovery USBs may mount as `/mnt/sdX1` instead)
8. **Check** the drive and backup time shown, then **type** `RESTORE` (Enter cancels)
9. **Type:** `poweroff` when done
10. **Remove** both USBs
11. **Boot** normally and re-license

**Recovery time: 2-5 minutes total**

## Quick Command Reference

```bash
# View backup logs
ls /boot/logs/unraid-dr/logs/

# Check last backup time
cat /mnt/disks/UNRAID_DR/LAST_BACKUP_SUCCESS.txt

# View backup USB contents
ls -lh /mnt/disks/UNRAID_DR/

# Manually run backup (for testing)
# From WebGUI: Settings → User Scripts → DR_USB_Backup → "Run in Background"

# Recreate backup USB from scratch
bash /boot/config/plugins/dr_usb/dr_usb_create.sh
```

## Important Notes

### ⚠️ License Slot Warning
Unraid counts every attached storage device against your license's device limit when it boots and starts the array. The backup USB (`UNRAID_DR`) counts as one. **Check how many device slots your license has left.** If there is no spare slot, the array will not start after a reboot while the `UNRAID_DR` USB is plugged in. To avoid this:
- **Option 1:** Remove the `UNRAID_DR` USB **before you reboot or shut down**
- **Option 2:** Plug it in **after the array has started** (creating it and backing up both work while the array is running)

### 🛑 SSH Required for Creation
`dr_usb_create.sh` is interactive and **must** be run from SSH. It will hang if run from GUI.

### ✅ Automated Backup is Safe
`dr_usb_backup.sh` is 100% non-interactive. Safe to run from GUI/cron with no supervision.

### 📝 Keep Recovery USB Safe
Store your Ventoy recovery USB in a safe location separate from your server. You can't recover if you can't access it!

## Next Steps

### Read the Full Documentation
- **Main README:** [README.md](../README.md)
- **Backup Script Guide:** [docs/dr_usb_backup.md](docs/dr_usb_backup.md)
- **Create Script Guide:** [docs/dr_usb_create.md](docs/dr_usb_create.md)
- **Recovery Guide:** [docs/VENTOY_README.md](docs/VENTOY_README.md)
- **Project Structure:** [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)

### Maintenance Schedule

**Weekly or monthly - run the scrub** (checks your running boot drive and your backup for silent damage; read-only):
`bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh -backup`  See [docs/dr_usb_scrub.md](docs/dr_usb_scrub.md).

**Monthly:**
- ✅ Check `LAST_BACKUP_SUCCESS.txt` timestamp
- ✅ Verify backup logs show no errors
- ✅ Confirm backup USB is readable

**Quarterly:**
- ✅ Test manual backup run
- ✅ Update SystemRescue ISO (if new version available)

**Annually:**
- ✅ Consider replacing backup USB (flash drives age)
- ✅ Test recovery process (in VM if possible)

## Getting Help

**Troubleshooting:**
- Check [README.md Troubleshooting section](../README.md#troubleshooting)
- Review script-specific docs in `docs/` folder

**Support:**
- GitHub Issues: [Create an issue](../../issues)
- Unraid Forums: [forums.unraid.net](https://forums.unraid.net)

**Common Issues:**
- "No UNRAID_DR found" → Run `dr_usb_create.sh` first
- "Multiple UNRAID_DR found" → Remove duplicate drive
- "Can't run from GUI" → Use SSH for `dr_usb_create.sh`

---

**That's it!** Your Unraid boot drive is now protected with automated backups and emergency recovery. Sleep better knowing your system is safe. 😊

**Questions?** Check the [Main README](../README.md) or the [docs/](docs/) folder for detailed information.
