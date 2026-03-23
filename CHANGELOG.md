# Changelog

All notable changes to the Unraid Boot Backup Suite are documented in this file.

## [1.1.3] - 2026-03-23

### Changed

#### Device Selection UI - Index-Based Selection (Safety Improvement)
- **Replaced device name entry with index number selection**
  - Before: User typed device name (e.g., "sdb") — prone to typos and fat-fingering
  - After: User selects by index number (e.g., "1", "2") — much safer and clearer
  - Example: User sees "[1] Device: sdl" and enters "1" instead of typing "sdl"

#### Input Validation Improvements
- Added explicit number validation for index selection
- Shows valid range if user enters invalid index
- Clear error messages: "Please enter a valid number" vs "Device not in list"
- Maximum 2 attempts before exiting (prevents accidental device selection)

### Benefits
✅ **Eliminates fat-finger errors** on device names
✅ **Clearer user interface** with explicit numbered options
✅ **Faster selection** (type one digit instead of device name)
✅ **Better error messages** guide user to correct input
✅ **Safer overall** reduces risk of selecting wrong device

---

## [1.1.2] - 2026-03-23

### Fixed

#### Critical Bug in Ventoy Detection
- **CRITICAL FIX:** Corrected exit status check for existing Ventoy detection
  - Bug: Used command substitution in if condition which always succeeds, even with empty output
  - Symptom: Script incorrectly reported "Found existing Ventoy: /dev/" even when no Ventoy exists
  - Root cause: `if var=$(command)` checks assignment success, not command output
  - Fix: Changed to `var=$(command); if [ -n "$var" ]` to properly validate output
  - Impact: Script now correctly continues to USB scanning when no Ventoy is found

### Details

The first `check_ventoy_origin()` function was checking Ventoy existence incorrectly:
- **Before:** `if ventoy_info=$(lsblk ... | grep 'LABEL="Ventoy"' ...);` — Always evaluates TRUE
- **After:** `ventoy_info=$(lsblk ...); if [ -n "$ventoy_info" ];` — Only TRUE if output found

This bug prevented users from seeing the USB selection menu and automatically bootstrap Ventoy on new drives.

---

## [1.1.1] - 2026-03-23

### Fixed

#### USB Device Scanning
- **Critical fix:** USB device scanning now detects **all USB drives** regardless of partition state or label status
  - Previously only detected USB drives with existing partitions that had labels
  - Now detects: unpartitioned drives, partitioned unlabeled drives, drives with custom labels
  - Properly filters by size (≥2GB) and excludes UNRAID/UNRAID_DR devices
  - Example: New unpartitioned USB drives (like `sdl`) now appear in selection list

### Changed

#### Device Selection UI
- Shows current label for each USB device, or "(no label)" if unlabeled
- Clearer error message explaining which USB drives qualify
- Improved device detection logic using two-pass scanning:
  - **Pass 1:** Identifies any devices with reserved (UNRAID/UNRAID_DR) partitions
  - **Pass 2:** Lists all qualifying USB devices regardless of partition state

---

## [1.1] - 2026-03-23

### Added

#### Core Features
- **Automatic Ventoy Bootstrap** — `setup_ventoy_usb.sh` now automatically detects or installs Ventoy from scratch
  - Scans attached USB drives and presents user-friendly selection menu
  - Downloads Ventoy 1.1.10 with SHA256 hash verification
  - Validates USB requirements: ≥2GB size, excludes UNRAID/UNRAID_DR labeled drives
  - Executes Ventoy2Disk.sh for automatic installation
  - Automatic cleanup of temporary files after installation

- **Version Tracking System** — New version management for recovery USB
  - `CURRENT_VERSION` file written to Ventoy USB after setup
  - Tracks script version to enable future upgrades
  - Automatic version comparison on subsequent runs

- **Upgrade Support** — New `-upgrade` command-line flag
  - `./setup_ventoy_usb.sh -upgrade` forces version check and upgrade
  - Compares `VERSION` (script) vs `CURRENT_VERSION` (USB)
  - Prompts user to upgrade both Ventoy and SystemRescue if newer version available
  - Prevents downgrade attempts with fatal error

- **Configuration File** — New `setup_ventoy.ini` for parameter management
  - Externalizes all version strings and download URLs
  - Single source of truth for Ventoy and SystemRescue configuration
  - Easy to update versions without editing shell script
  - Modularized URLs with version variable injection

#### New Functions
- `check_ventoy_origin()` — Detects existing Ventoy or scans for USB to bootstrap
- `verify_sha256()` — SHA256 hash verification for Ventoy downloads
- `find_and_mount_ventoy()` — Refactored from inline code, handles Unraid and non-Unraid systems
- `check_ventoy_space()` — Validates sufficient space on Ventoy partition
- `install_sysrescue_iso()` — Refactored from inline code, handles download/copy/verification
- `setup_recovery_scripts()` — Modularized script installation
- `create_ventoy_json()` — Refactored from inline code
- `create_instructions()` — Refactored from inline code
- `write_current_version()` — Writes version tracking file
- `check_versions()` — Intelligent version comparison and upgrade logic
- `sync_and_unmount_ventoy()` — Refactored from inline code

#### Validation & Safety
- USB drive scanning excludes UNRAID and UNRAID_DR labeled drives
- Minimum 2GB USB size requirement enforced
- /var/tmp space validation (100MB minimum for downloads)
- SHA256 verification for Ventoy package integrity
- Device selection retry mechanism (2 attempts max)
- Explicit YES confirmation before formatting USB
- Version downgrade prevention with fatal error

#### Documentation
- Updated `README.md` with new bootstrap features
- Added `-upgrade` flag documentation
- Updated hardware prerequisites (Ventoy no longer required pre-installed)
- Updated Quick Start Guide for simplified workflow
- Updated Scripts Overview section with new capabilities
- Added CURRENT_VERSION to USB structure diagram
- Added setup_ventoy.ini to technical details

- Updated `INDEX.md` with new documentation references
- Updated last-modified date

- Updated `GETTING_STARTED.md`
  - Removed Ventoy pre-installation requirement
  - Simplified Step 3 with automatic bootstrap explanation
  - Added `-upgrade` flag usage example

- Updated `FILE_MANIFEST.txt`
  - Version updated to 1.1
  - Added setup_ventoy.ini
  - Updated script descriptions
  - Added CURRENT_VERSION to auto-generated files
  - Updated file organization with new directory structure
  - Added comprehensive 1.1 changelog

### Changed

#### Script Behavior
- `setup_ventoy_usb.sh` now requires `setup_ventoy.ini` in the same directory
- Argument parsing added at start of script
- Global variable initialization added: `VENTOY_FRESH_INSTALL`, `UPGRADE_MODE`
- Main flow refactored to use new functions instead of inline code
- Version comparison logic added before component installation

#### ventoy.json Generation
- Fixed hardcoded ISO name `/systemrescue-*.iso` to use actual version: `/${SYSRESCUE_ISO}`
- Now injects correct SystemRescue version into menu alias
- Applied to both new and overwrite paths

#### User Experience
- More detailed prompts during USB selection
- Displays USB model and size information for selection
- Clear status messages for each step
- Better error messages for common issues
- Confirmation step uses explicit "YES" (all caps) instead of yes/no

#### Script Structure
- Entire script reorganized with clear sections:
  - Utility functions (ask_yes_no, verify_sha512, verify_sha256, version helpers)
  - Main setup functions (check_ventoy_origin, find_and_mount_ventoy, etc.)
  - Validation checks
  - Main flow
- Improved code readability with consistent formatting
- Added comprehensive inline documentation

### Fixed

- **ventoy.json wildcard issue** — Now generates exact ISO filename instead of wildcard pattern
- **Ventoy label detection** — More robust parsing of lsblk output
- **Script path handling** — INI file validation with clear error message if missing
- **Device enumeration** — Parent device calculation now correctly handles both sdX and sdXpY naming conventions

### Removed

- `setup_ventoy_usb_simple.sh` — Replaced by enhanced `setup_ventoy_usb.sh`
- Inline variable declarations — All moved to `setup_ventoy.ini`
- Inline setup logic — Refactored into modular functions
- Hardcoded ISO version strings — Now uses variables from configuration file

### Security

- SHA256 verification added for Ventoy download integrity
- Explicit device confirmation (YES vs yes/no) to prevent accidental selections
- Validation that parent device is USB transport (TRAN=usb)
- Minimum device size enforcement (2GB)
- Read-write access verification on Ventoy mount

### Performance

- Modular function design allows for future optimization
- Configuration externalization simplifies deployment and updates
- Version tracking eliminates unnecessary re-installations

### Compatibility

- **Backward Compatible** — Script still works with existing Ventoy USBs
- **Non-Unraid Systems** — Full support for Linux desktop systems
- **Upgrade Path** — Existing installations can upgrade using `-upgrade` flag

---

## [1.0.0] - 2025-01-XX

### Initial Release

- Complete Unraid Boot Backup Suite
- `dr_usb_create.sh` — Interactive backup USB creation
- `dr_usb_backup.sh` — Automated incremental backups
- `setup_ventoy_usb_simple.sh` — Recovery USB setup (Ventoy pre-required)
- `move_dr_to_unraid.sh` — Emergency recovery script
- Comprehensive documentation suite
- SHA512 verification for SystemRescue downloads
- UEFI-only support
- Bifurcated script design (create vs backup separation)

---

## Migration Guide: 1.0 → 1.1

### For End Users

**No action required!** Your existing setup continues to work unchanged.

To take advantage of new features:
1. Update `Recovery-ISO/scripts/setup_ventoy_usb.sh` to new version
2. Create `Recovery-ISO/scripts/setup_ventoy.ini` with provided configuration
3. Run `./Recovery-ISO/scripts/setup_ventoy_usb.sh -upgrade` on existing Ventoy USB

### For Developers

If you've customized `setup_ventoy_usb.sh`:
1. **Parameters moved to INI file** — Edit `setup_ventoy.ini` instead of script
2. **Ventoy version** — Now in `VENTOY_VERSION` variable with modularized URLs
3. **Function calls** — Rewrite to use new `check_versions()` function for smart installation logic
4. **Configuration** — All URLs and versions now centralized and easily maintainable

### Breaking Changes

- Script now requires `setup_ventoy.ini` in same directory (migration automatically created)
- Version variable in script now tracks setup script version, not component versions (use INI for that)

### New Configuration Options

In `setup_ventoy.ini`:
```bash
VENTOY_VERSION="1.1.10"           # Update to bootstrap newer Ventoy
SYSRESCUE_VER="12.02"             # Update to use newer SystemRescue
VENTOY_DL_URL="..."               # Custom Ventoy download location
VENTOY_DL_SHA="..."               # Custom SHA256 source
SYSRESCUE_URL="..."               # Custom SystemRescue download location
```

---

## Known Issues

None at this time.

## Acknowledgments

- Ventoy project for the multi-boot USB solution
- SystemRescue project for the rescue environment
- Unraid team for the excellent NAS OS
- Community testers and contributors

---

**For detailed information, see [README.md](README.md) or [GETTING_STARTED.md](GETTING_STARTED.md)**
