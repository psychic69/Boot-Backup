# Unraid Boot Backup Suite - Project Structure

## Repository Layout

```
Boot-Backup/                           # = /boot/config/plugins/dr_usb/ once installed
├── README.md                          # Main documentation (start here)
├── GETTING_STARTED.md                 # Quick-start guide
├── INDEX.md                           # Documentation navigation
├── CHANGELOG.md                       # Release history
├── FILE_MANIFEST.txt                  # File list and version history
├── LICENSE                            # Project license
├── VERSION                            # Single version for the whole release (SCRIPT_VERSION=x.y.z)
│
├── dr_usb_create.sh                   # Interactive backup USB creation
├── dr_usb_backup.sh                   # Automated backup (local USB, or -remote to another server)
├── dr_usb_scrub.sh                    # Maintenance scrub: checks the live /boot and (with -backup) the backup for damage
├── dr_usb.ini.example                 # Template for dr_usb.ini (settings shared by the scripts)
├── remote.ini.example                 # Template for remote.ini (used by dr_usb_backup.sh -remote)
├── lib/                               # Shared modules sourced by both scripts
│   ├── logging.sh                     #   log_message, setup_logging, file_rotation, run_logged, ...
│   ├── drives.sh                      #   lsblk drive-state helpers
│   ├── integrity.sh                   #   boot-file hash checks (root + previous/) and the backup manifest
│   ├── clone.sh                       #   clone_backup (rsync to the UNRAID_DR USB)
│   ├── remote.sh                      #   remote destination: config, SSH key, rrsync checks (backup and scrub)
│   └── config.sh                      #   defaults, dr_usb.ini loading, parameter validation
├── build_release.sh                   # Builds the release archive (developers; not in the archive)
│
├── Docs/                              # Detailed documentation (not in the archive)
│   ├── dr_usb_create.md               # Guide for dr_usb_create.sh
│   ├── dr_usb_backup.md               # Guide for dr_usb_backup.sh (includes remote backup)
│   ├── dr_usb_scrub.md                # Guide for dr_usb_scrub.sh
│   ├── DESIGN_DECISIONS.md            # Journal of design decisions and why, tagged by version
│   ├── TEST_CHECKLIST_v1.2.0.md       # Hands-on test plan for release 1.2.0 (real hardware)
│   ├── VENTOY_README.md               # Guide for recovery USB setup
│   ├── PROJECT_STRUCTURE.md           # This file
│   └── Historical/                    # Archived notes
│
├── Recovery-ISO/
│   └── scripts/                       # Recovery USB tooling
│       ├── setup_ventoy_usb.sh        # Recovery USB setup / in-place upgrade
│       ├── setup_ventoy.ini           # Ventoy and SystemRescue versions, URLs, ISO names
│       ├── move_dr_to_unraid.sh       # Emergency recovery script
│       └── historical/                # Legacy scripts
│
└── Unit Test/                         # Automated tests (run_tests.sh) and older test helpers
```

The repository layout is the installed layout: the release archive is the repository minus `Docs/`, `Unit Test/`, `build_release.sh` and the other development files.

## File Descriptions

### Core Scripts

| Script | Type | Run From | Purpose |
|--------|------|----------|---------|
| `dr_usb_create.sh` | Interactive | SSH only | One-time setup of backup USB |
| `dr_usb_backup.sh` | Automated | Cron/User Scripts | Regular incremental backups (`-remote`: mirror to another server) |
| `dr_usb_scrub.sh` | Automated | Cron/Komodo/User Scripts | Weekly/monthly damage check of the live `/boot` and (`-backup`) the backup |
| `setup_ventoy_usb.sh` | Interactive | Unraid terminal | Creates recovery USB |
| `move_dr_to_unraid.sh` | Semi-automated | SystemRescue | Emergency recovery |

### Documentation

| Document | Purpose |
|----------|---------|
| `README.md` | Main documentation, overview, quick start |
| `GETTING_STARTED.md` | Quick-start guide |
| `INDEX.md` | Documentation navigation |
| `CHANGELOG.md` | Release history |
| `FILE_MANIFEST.txt` | File list and version history |
| `Docs/dr_usb_create.md` | Detailed guide for backup USB creation |
| `Docs/dr_usb_backup.md` | Detailed guide for automated backups, including remote backup (`-remote`) |
| `Docs/dr_usb_scrub.md` | Detailed guide for the maintenance scrub |
| `Docs/TEST_CHECKLIST_v1.2.0.md` | Step-by-step hands-on test plan for release 1.2.0, with expected results and a results table |
| `Docs/DESIGN_DECISIONS.md` | Journal of design decisions and the reasons for them (read before changing behavior) |
| `Docs/VENTOY_README.md` | Detailed guide for recovery USB |

## Getting Started

### First-Time Setup

1. **Read:** Start with the main [README.md](../README.md)
2. **Create Backup USB:** Follow [Docs/dr_usb_create.md](dr_usb_create.md)
3. **Create Recovery USB:** Follow [Docs/VENTOY_README.md](VENTOY_README.md)
4. **Automate Backups:** Follow [Docs/dr_usb_backup.md](dr_usb_backup.md)
5. **(Optional) Mirror to another server:** Follow [Remote Backup in dr_usb_backup.md](dr_usb_backup.md#remote-backup--remote)

### Quick Reference

**Backup USB Creation (one-time, SSH only):**
```bash
bash /boot/config/plugins/dr_usb/dr_usb_create.sh
```

**Automated Backup (set schedule in User Scripts):**
```bash
# Runs automatically - no manual intervention needed
# Configured in: Settings → User Scripts → DR_USB_Backup → Schedule
# The User Script body is one line: bash /boot/config/plugins/dr_usb/dr_usb_backup.sh
```

**Remote Backup (optional, mirrors /boot to another server over SSH):**
```bash
# One-time setup (remote.ini, SSH key, known_hosts): see Docs/dr_usb_backup.md
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote -debug   # dry run
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote          # real mirror
# Schedule it with a second User Script whose body is the second command above
```

**Recovery USB Creation / Upgrade (re-run any time to upgrade):**
```bash
bash /boot/config/plugins/dr_usb/Recovery-ISO/scripts/setup_ventoy_usb.sh
```

**Emergency Recovery (when main USB fails):**
1. Boot SystemRescue from Ventoy USB
2. Type: `mountall`
3. Type: `bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh`

## Script Dependencies

### dr_usb_create.sh
- Requires: SSH terminal (interactive) on the Unraid server; the release installed in `/boot/config/plugins/dr_usb/`
- Uses: parted, mkfs.vfat, rsync, lsblk
- Creates: Formatted backup USB with UNRAID_DR label

### dr_usb_backup.sh
- Requires: The release installed in `/boot/config/plugins/dr_usb/` (scripts + `lib/`); the User Scripts plugin or cron to schedule it
- Uses: rsync, lsblk, mount/umount, sha256sum
- Updates: Existing UNRAID_DR backup USB
- Before copying anything it verifies the boot files in `/boot` and `/boot/previous` against Unraid's `.sha256` files and stops if any are damaged
- With `-remote`: also uses ssh, ssh-keygen, flock; reads `/boot/config/plugins/dr_usb/remote.ini` (see `remote.ini.example`) and mirrors `/boot` to another server instead of the USB. The destination must lock the key to `rrsync` (write-only, one folder); the script checks this and refuses otherwise

### dr_usb_scrub.sh
- Requires: The release installed in `/boot/config/plugins/dr_usb/` (scripts + `lib/`); run as root on the Unraid server
- Uses: sha256sum; for `-backup` with the local USB: lsblk, mount/umount; with `remote.ini`: ssh, ssh-keygen, rsync (dry run)
- Checks: the live `/boot` and `/boot/previous` against Unraid's `.sha256` files; with `-backup` also the backup (remote if `remote.ini` exists, else the local `UNRAID_DR` USB). Never changes anything
- Reports: a loud, detailed failure banner (area, file, expected/actual hash, size), a non-zero exit code and an Unraid notification

### setup_ventoy_usb.sh
- Requires: A USB drive (Ventoy is installed automatically if missing); `setup_ventoy.ini` beside it and the release `VERSION` file two folders above it
- Uses: wget, sha256/sha512 verification, Ventoy2Disk.sh, mount/umount
- Creates: Recovery USB with SystemRescue ISO
- On an existing USB: updates Ventoy in place (`-u`, files kept) and replaces an older SystemRescue ISO when `setup_ventoy.ini` specifies newer versions

### move_dr_to_unraid.sh
- Requires: SystemRescue environment
- Uses: fatlabel, lsblk, findmnt, mount/umount, dd, cmp, plus `syslinux/syslinux_linux` and `syslinux/mbr.bin` from the backup itself
- Action: Converts UNRAID_DR → UNRAID (relabel, `EFI-` → `EFI`, boot loader and MBR) after you type `RESTORE`; rolls back on failure
- Stands alone: it is copied by itself to the Ventoy USB, so it cannot use `lib/`

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
├── previous/                # The previous Unraid release (mirrored and hash-checked like the root)
├── bzimage, bzroot, ...     # Unraid kernel / root filesystem, each with Unraid's own .sha256
├── BACKUP-<timestamp>       # Marker: when the last backup completed
└── DR_MANIFEST.sums         # SHA-256 of config/, syslinux/, EFI-/ and other small files (checked at restore)
```

### Recovery USB (Ventoy)
```
Ventoy USB/
├── systemrescue-13.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── CURRENT_VERSION          # Script version that set up this USB
├── ventoy/
│   └── ventoy.json
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

## Configuration Files

### ventoy.json (auto-generated)
Located on Recovery USB at: `/ventoy/ventoy.json`

Key settings (Ventoy requires string values, one key per object):
- `VTOY_LINUX_REMOUNT: "1"` - Critical for read-write access
- `VTOY_MENU_TIMEOUT: "30"` - Auto-boot timeout
- `VTOY_DEFAULT_IMAGE` - SystemRescue ISO is the default menu selection
- `menu_alias` - Friendly name for SystemRescue ISO

### setup_ventoy.ini
Located in `Recovery-ISO/scripts/` (not copied to the USB). Holds `VENTOY_VERSION`, `SYSRESCUE_VER`, the download URLs and the ISO name. Edit it to change which Ventoy and SystemRescue versions are installed; the ISO name is injected into `ventoy.json` automatically.

### VERSION
Located at the root of the release. A single line, `SCRIPT_VERSION=x.y.z`: the one version number for the whole release. `setup_ventoy_usb.sh` reads it (from two folders above itself) and writes it to `CURRENT_VERSION` on the Recovery USB, and `build_release.sh` uses it to name the archive.

### dr_usb.ini (optional)
Created by copying `dr_usb.ini.example` to `dr_usb.ini` beside the scripts. Holds the settings shared by `dr_usb_create.sh` and `dr_usb_backup.sh` (`LOG_DIR`, `SNAPSHOTS`, `RETENTION_DAYS`, `CLONE_MP`, and an optional `REMOTE_INI` location). Every value has a built-in default, so the file is only needed to change them, and upgrading never overwrites it.

### remote.ini (optional, for `dr_usb_backup.sh -remote`)
Created by copying `remote.ini.example` to `remote.ini` beside the scripts (`/boot/config/plugins/dr_usb/remote.ini`) on the Unraid server. Holds the remote host and user, the SSH key and `known_hosts` paths, and rsync options. The destination folder is not set here: it is fixed on the server by the `rrsync` command in `authorized_keys`. See the variable reference in [dr_usb_backup.md](dr_usb_backup.md#remote-backup--remote).

### Log Configuration (in dr_usb.ini)
Configurable variables:
- `LOG_DIR` - Where logs are written
- `SNAPSHOTS` - Number of backup logs to retain
- `RETENTION_DAYS` - Age-based backup log cleanup

Log files: `boot-check-DATE.log` (one per backup run, rotated by the two settings above) and `usb-create-DATE.log` (one per create run; earlier successful ones are removed when a new one is written, failed ones are kept).

## Building a Release

Run from the repository root (developers only):

```bash
bash build_release.sh
```

It reads `VERSION`, syntax-checks every script and module, and writes `dist/Boot-Backup-<version>.tar.gz` plus a `.sha256` file (`dist/` is git-ignored). The archive has a single top-level `dr_usb/` folder and contains no personal settings (`dr_usb.ini`, `remote.ini`, keys). Then tag the release (`git tag v<version>`), create a GitHub Release for the tag, and attach both files.

## Tests

```bash
bash "Unit Test/run_tests.sh"            # run everything
bash "Unit Test/run_tests.sh" menu       # run only tests whose name contains "menu"
```

The `test_*.sh` files cover the modules, the USB drive menu, the format logic (with stubbed disk tools), the startup checks, the remote config, the backup/create scripts end to end against sample `lsblk` data (`Unit Test/fixtures/`), and the release build. Tests never touch real drives and need only bash, python3 and ssh-keygen; the GNU-`find` log-rotation check and the `flock` remote check are skipped on systems that lack them (e.g. macOS).

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
                           │
                           ▼
        ┌──────────────────────────────────┐
        │  4. (Optional) Schedule         │
        │     dr_usb_backup.sh -remote    │
        │     (mirror to another server)  │
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
- **Script Docs:** [Docs/](.)
- **Unraid Forums:** [forums.unraid.net](https://forums.unraid.net)
- **GitHub Issues:** [Create an issue](../../issues)

## Version Information

- **Current Version:** 1.2.0
- **Unraid Compatibility:** 6.x and later
- **BIOS Support:** UEFI only
- **SystemRescue Version:** 13.02 (or later)

---

**Last Updated:** 2026-11-03  
**Maintainer:** [Your Name/Organization]
