# Unraid Boot Backup Suite - Project Structure

## Repository Layout

```
unraid-boot-backup/
├── README.md                          # Main documentation (start here)
├── LICENSE                            # Project license
│
├── docs/                              # Detailed documentation
│   ├── dr_usb_create.md              # Guide for dr_usb_create.sh
│   ├── dr_usb_backup.md              # Guide for dr_usb_backup.sh
│   └── VENTOY_README.md              # Guide for recovery USB setup
│
├── scripts/                           # Main scripts
│   ├── dr_usb_create.sh              # Interactive backup USB creation
│   ├── dr_usb_backup.sh              # Automated backup script
│   ├── setup_ventoy_usb.sh           # Recovery USB setup
│   └── move_dr_to_unraid.sh          # Emergency recovery script
│
└── examples/                          # Optional examples
    ├── user-scripts-config.txt       # Example User Scripts configuration
    └── cron-example.txt              # Example cron configuration
```

## File Descriptions

### Core Scripts

| Script | Type | Run From | Purpose |
|--------|------|----------|---------|
| `dr_usb_create.sh` | Interactive | SSH only | One-time setup of backup USB |
| `dr_usb_backup.sh` | Automated | Cron/User Scripts | Regular incremental backups |
| `setup_ventoy_usb.sh` | Interactive | Unraid terminal | Creates recovery USB |
| `move_dr_to_unraid.sh` | Semi-automated | SystemRescue | Emergency recovery |

### Documentation

| Document | Purpose |
|----------|---------|
| `README.md` | Main documentation, overview, quick start |
| `docs/dr_usb_create.md` | Detailed guide for backup USB creation |
| `docs/dr_usb_backup.md` | Detailed guide for automated backups |
| `docs/VENTOY_README.md` | Detailed guide for recovery USB |

## Getting Started

### First-Time Setup

1. **Read:** Start with the main [README.md](../README.md)
2. **Create Backup USB:** Follow [docs/dr_usb_create.md](dr_usb_create.md)
3. **Create Recovery USB:** Follow [docs/VENTOY_README.md](VENTOY_README.md)
4. **Automate Backups:** Follow [docs/dr_usb_backup.md](dr_usb_backup.md)

### Quick Reference

**Backup USB Creation (one-time, SSH only):**
```bash
/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script
```

**Automated Backup (set schedule in User Scripts):**
```bash
# Runs automatically - no manual intervention needed
# Configured in: Settings → User Scripts → DR_USB_Backup → Schedule
```

**Recovery USB Creation (one-time):**
```bash
./setup_ventoy_usb.sh
```

**Emergency Recovery (when main USB fails):**
1. Boot SystemRescue from Ventoy USB
2. Type: `mountall`
3. Type: `bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh`

## Script Dependencies

### dr_usb_create.sh
- Requires: SSH terminal (interactive)
- Uses: parted, mkfs.vfat, rsync, lsblk
- Creates: Formatted backup USB with UNRAID_DR label

### dr_usb_backup.sh
- Requires: User Scripts plugin or cron
- Uses: rsync, lsblk, mount/umount
- Updates: Existing UNRAID_DR backup USB

### setup_ventoy_usb.sh
- Requires: Ventoy pre-installed on USB
- Uses: wget, sha512sum, mount/umount
- Creates: Recovery USB with SystemRescue ISO

### move_dr_to_unraid.sh
- Requires: SystemRescue environment
- Uses: fatlabel, lsblk, mount/umount
- Action: Converts UNRAID_DR → UNRAID

## Directory Structure on USB Drives

### Backup USB (UNRAID_DR)
```
/mnt/disks/UNRAID_DR/
├── EFI-/                    # Renamed to prevent boot
│   └── boot/
│       └── bootx64.efi
├── config/                  # Your Unraid configuration
├── logs/                    # Backup logs
├── syslinux/                # Bootloader files
├── bzimage                  # Unraid kernel
├── bzmodules                # Kernel modules
├── bzroot                   # Root filesystem
└── LAST_BACKUP_SUCCESS.txt  # Timestamp file
```

### Recovery USB (Ventoy)
```
Ventoy USB/
├── systemrescue-12.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── ventoy/
│   └── ventoy.json
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

## Configuration Files

### ventoy.json (auto-generated)
Located on Recovery USB at: `/ventoy/ventoy.json`

Key settings:
- `VTOY_LINUX_REMOUNT: "1"` - Critical for read-write access
- `VTOY_MENU_TIMEOUT: 30` - Auto-boot timeout
- `menu_alias` - Friendly name for SystemRescue ISO

### Log Configuration (in dr_usb_backup.sh)
Configurable variables:
- `LOG_DIR` - Where logs are written
- `SNAPSHOTS` - Number of logs to retain
- `RETENTION_DAYS` - Age-based log cleanup

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   INITIAL SETUP                         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  1. Run dr_usb_create.sh (SSH)  │
        │     Creates UNRAID_DR backup    │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  2. Run setup_ventoy_usb.sh     │
        │     Creates recovery USB        │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  3. Schedule dr_usb_backup.sh   │
        │     (User Scripts: Daily 3AM)   │
        └──────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                   NORMAL OPERATION                      │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  dr_usb_backup.sh runs daily    │
        │  (automatically via schedule)   │
        └──────────────────────────────────┘
                           │
                ┌──────────┴──────────┐
                │                     │
                ▼                     ▼
        ┌──────────────┐      ┌──────────────┐
        │  Success:    │      │  Error:      │
        │  Log written │      │  Log + email │
        └──────────────┘      └──────────────┘

┌─────────────────────────────────────────────────────────┐
│                   EMERGENCY RECOVERY                    │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  Main USB fails - system down   │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  1. Remove failed USB           │
        │  2. Insert UNRAID_DR backup     │
        │  3. Insert Ventoy recovery USB  │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  4. Boot SystemRescue           │
        │  5. Type: mountall              │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  6. Run move_dr_to_unraid.sh    │
        │     (converts DR → UNRAID)      │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  7. Shutdown, remove USB drives │
        │  8. Boot normally               │
        └──────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  9. Re-license USB via WebGUI   │
        │     (Unraid will prompt)        │
        └──────────────────────────────────┘
```

## Support Resources

- **Main README:** [README.md](../README.md)
- **Script Docs:** [docs/](.)
- **Unraid Forums:** [forums.unraid.net](https://forums.unraid.net)
- **GitHub Issues:** [Create an issue](../../issues)

## Version Information

- **Current Version:** 1.0.0 (pre-release)
- **Unraid Compatibility:** 6.x and later
- **BIOS Support:** UEFI only
- **SystemRescue Version:** 12.02 (or later)

---

**Last Updated:** 2025-01-XX  
**Maintainer:** [Your Name/Organization]
