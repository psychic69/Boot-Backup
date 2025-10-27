# Getting Started - Quick Reference

**Welcome to the Unraid Boot Backup Suite!** This guide will get you up and running in 15 minutes.

## Prerequisites Checklist

Before you begin, gather:

- [ ] **Two USB drives:**
  - One for backup (4-64GB) → Will become `UNRAID_DR`
  - One for recovery (8GB+) → Must have Ventoy installed
- [ ] **SSH access** to your Unraid server
- [ ] **5-10 minutes** of your time

## Installation - 3 Simple Steps

### Step 1: Create Your Backup USB (5 minutes)

**From SSH Terminal:**

```bash
# 1. Download or locate dr_usb_create.sh
cd /boot/config/plugins/user.scripts/scripts/DR_USB_Create/

# 2. Run the script
./script

# 3. Follow the prompts:
#    - Select your USB drive from the list
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
5. Paste contents of `dr_usb_backup.sh`
6. Click **Save Changes**
7. Set schedule to **Daily** at 3:00 AM (or your preferred time)
8. Click **Apply**

**What happens:**
- ✅ Backup runs automatically every day
- ✅ Only copies changed files (fast!)
- ✅ Creates logs in `/boot/logs/unraid-dr/logs/`
- ✅ Completely hands-off

---

### Step 3: Create Recovery USB (5 minutes)

**From Unraid Terminal:**

```bash
# 1. Ensure Ventoy is installed on your recovery USB
#    Download from: https://www.ventoy.net/

# 2. Plug in Ventoy USB

# 3. Run the setup script
./setup_ventoy_usb.sh

# 4. Wait for SystemRescue ISO download (~2 minutes)
```

**What happens:**
- ✅ Downloads SystemRescue ISO (SHA512 verified)
- ✅ Copies recovery script to USB
- ✅ Creates configuration files
- ✅ Generates user instructions

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
7. **Type:** `bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh`
8. **Type:** `poweroff` when done
9. **Remove** both USBs
10. **Boot** normally and re-license

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
/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script
```

## Important Notes

### ⚠️ License Slot Warning
The backup USB (`UNRAID_DR`) consumes a license slot if kept in system during boot. To avoid:
- **Option 1:** Remove before shutdown
- **Option 2:** Insert after array starts

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
