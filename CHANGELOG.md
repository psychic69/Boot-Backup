# Changelog

All notable changes to the Unraid Boot Backup Suite are documented in this file.

## [1.2.3] - 2026-11-11

### Fixed
- **`-remote`: a correctly restricted key was refused with "SECURITY CHECK FAILED ... can run arbitrary commands".** Found on real
  hardware (rsync/rrsync 3.4.1 on the destination). The check ran `ssh ... true` and treated exit 0 as "unrestricted", but
  rrsync accepts a bare `true` and exits 0, while it rejects any real command (`rrsync error: SSH_ORIGINAL_COMMAND does not run
  rsync`, exit 1). The probe now runs `id`. An unrestricted key still runs `id` and is still refused. See D-1.2.3-01
  - `Docs/dr_usb_backup.md` manual SSH test updated to use `id`, with a note on why not `true`
- Existing installs: replace the scripts (`lib/remote.sh` is the changed file); recovery USBs are unaffected

## [1.2.2] - 2026-11-11

### Fixed
- **`move_dr_to_unraid.sh`: survives the USB stick dropping off the system mid-restore, and can resume a half-finished one.**
  Found on real hardware: right after `fatlabel` the stick vanished (`/dev/sdb1` gone; `blkid`, `lsblk` and `fatlabel` read
  nothing), the label check failed, and the rollback could not restore `UNRAID_DR`, leaving a stick labelled `UNRAID` with no boot
  loader. The next identical run succeeded, so the drop is intermittent.
  - The partition's filesystem UUID is remembered. Before the relabel, label checks, mounts, boot-loader install, MBR write and
    rollback, a missing device is waited for (up to 30s) and found again by UUID, even under a new name (sdb -> sdc)
  - If it never returns, the message says to replug, run `mountall` and run the script again
  - A USB first partition already labelled `UNRAID` that still carries its `BACKUP-*` marker is treated as an unfinished restore
    and resumed (label step only verified, rollback never changes its label). A drive with no marker is still refused, so a real
    Unraid flash is never touched. See D-1.2.2-01 and D-1.2.2-02
  - `test_move_dr.sh` now has 191 checks
- Existing recovery USBs: run `setup_ventoy_usb.sh` again to upgrade to 1.2.2

## [1.2.1] - 2026-11-09

### Fixed
- **`move_dr_to_unraid.sh`: the `UNRAID` label check no longer fails (and rolls back) a good restore.** Found in the first
  real-hardware run. After the syslinux install `fatlabel` prints "There are differences between boot sector and its backup."
  on stdout, which the old check took as the label.
  - The label is now read with `blkid -p` (falling back to `lsblk`, then `fatlabel`'s last line), and the drive is flushed first
    (`sync`, `blockdev --flushbufs`, `udevadm settle`)
  - A miss is retried for about 30 seconds (2/4/8/16s) with progress lines. As a last check before rolling back,
    `/dev/disk/by-label/UNRAID` must point at the restored partition
  - The label is still strictly required (Unraid will not boot without it); a failure prints what each method returned. See D-1.2.1-01
  - `test_move_dr.sh` now has 166 checks, including the warning-line case, the fallback chain, the retry/backoff and the udev check
- **Recovery paths corrected everywhere.** After `mountall` the Ventoy USB is at `/mnt/VentoyPart`, not `/mnt/sdX1`; the run
  command is now `bash /mnt/VentoyPart/unraid_recovery/move_dr_to_unraid.sh`. Updated in `README.md`, `GETTING_STARTED.md`,
  `Docs/VENTOY_README.md`, `Docs/PROJECT_STRUCTURE.md`, the test checklist, and the instructions text that
  `setup_ventoy_usb.sh` writes to the USB (which also had a stale manual `/dev/mapper` + `/mnt/script` procedure). Each keeps a
  short note that older recovery USBs mounted as `/mnt/sdX1`. `Docs/VENTOY_README.md` gains a captured real SystemRescue session
  (including the normal `sda1 ... Can't open blockdev` message during `mountall`)
- Existing recovery USBs: run `setup_ventoy_usb.sh` again; it sees `CURRENT_VERSION` 1.2.0 on the USB and offers the upgrade
  to 1.2.1, which copies the fixed `move_dr_to_unraid.sh` onto it

## [1.2.0] - 2026-11-03

### Changed
- `setup_ventoy_usb.sh` now reads the script version from the release `VERSION` file at the repo root
  (`SCRIPT_VERSION=x.y.z`, two folders above the script) instead of a hardcoded `VERSION="1.1.9"`
  - Value is extracted with `sed` (file is not sourced) and validated as `x.y` or `x.y.z`
  - Script exits with a clear error if the file is missing or invalid
  - `VERSION` file now ends with a trailing newline
- **`dr_usb_backup.sh -remote`: mirror the running USB to a remote server over SSH**
  - New flag `-remote` backs up `/boot` to another machine instead of the local UNRAID_DR USB;
    without the flag the existing local behavior is unchanged
  - Settings in `remote.ini` (template: `remote.ini.example`, default location
    `/boot/config/plugins/dr_usb/remote.ini`, overridable via `REMOTE_INI` in the script)
  - 1:1 mirror (`rsync -rlth --delete-after`), no snapshots
  - SSH hardening: dedicated key, pinned `known_hosts`, `StrictHostKeyChecking=yes`, `BatchMode`;
    the private key is copied from the (FAT) flash drive to RAM with 600 permissions and removed on exit
  - Safety checks: `/boot` must be mounted with `config/` and `bzroot` before mirroring with `--delete`;
    all ini values validated; `flock` prevents overlapping runs
  - Remote preflight (rsync probe push to the rrsync-restricted destination, plus a check that the key cannot run
    commands; see "Hash checks, and a locked-down remote destination" below) and optional Unraid notification on failure
  - Documentation: full Remote Backup guide in `Docs/dr_usb_backup.md` (file locations, `remote.ini` variable
    reference, step-by-step key/user/known_hosts setup on both servers, scheduling, troubleshooting, restore);
    cross-referenced from `README.md`, `INDEX.md`, `GETTING_STARTED.md` and `Docs/PROJECT_STRUCTURE.md`
  - `Docs/PROJECT_STRUCTURE.md` repository layout corrected to match the actual folders; added `setup_ventoy.ini`,
    `VERSION`, `remote.ini` and the in-place upgrade behavior
  - `GETTING_STARTED.md`: optional remote backup section, remote test/commands, upgrade instructions updated
- **One release archive, shared modules and a universal settings file**
  - Single release: the whole project (backup tools plus the recovery USB tools) now ships as
    `Boot-Backup-<version>.tar.gz`, built by the new `build_release.sh` (syntax-checks everything, writes a `.sha256`)
    and attached to a GitHub Release. Extract it into `/boot/config/plugins/` (with `--no-same-owner --no-same-permissions`);
    upgrading never overwrites `dr_usb.ini`, `remote.ini` or SSH keys because they are not in the archive
  - One `VERSION` file at the repo root (moved from `Recovery-ISO/scripts/VERSION`) is the version for the whole release;
    `setup_ventoy_usb.sh` now reads it from two folders above itself
  - Shared code moved from `dr_usb_create.sh` / `dr_usb_backup.sh` into `lib/` (`logging.sh`, `drives.sh`, `clone.sh`,
    `config.sh`): eleven functions were byte-identical copies in both scripts and `clone_backup` alone was 191 duplicated
    lines. Behavior is unchanged; each fix now exists once. The scripts stop with a clear message if `lib/` is missing
    (so the old "paste the script into User Scripts" install no longer works; User Scripts now just calls the script on the flash drive)
  - New `dr_usb.ini` (template `dr_usb.ini.example`) replaces the "edit these values" block inside both scripts:
    `LOG_DIR`, `SNAPSHOTS`, `RETENTION_DAYS`, `CLONE_MP`, optional `REMOTE_INI`. All have built-in defaults, the file is optional,
    and `remote.ini` now defaults to beside the scripts
  - `dr_usb_create.sh` writes its own log, `usb-create-DATE.log`, separate from `boot-check-*.log`; when a new create log is
    written, earlier create logs that finished successfully are removed (failed ones are kept)
  - `log_message` before logging starts now prints to stderr only for both scripts (create no longer also writes `/tmp/dr_usb_create.log`)
  - `-debug` / `-lsblk` on `dr_usb_create.sh` now print a startup line saying nothing will be formatted (they were always dry runs); documented in `Docs/dr_usb_create.md`
  - Automated tests: `Unit Test/run_tests.sh` runs 16 `test_*.sh` files (modules, USB menu, format logic with stubbed disk tools,
    startup checks, remote config, create/backup end to end against sample `lsblk` data in `Unit Test/fixtures/`, and the release build)
  - Docs updated for the new install (extract the archive; User Script becomes a one-line wrapper) and settings
- **New `Docs/TEST_CHECKLIST_v1.2.0.md`:** a hands-on test plan for this release, ordered from safest to riskiest, with the
  expected messages, failure drills on backups only, and a results table
- **New `Docs/DESIGN_DECISIONS.md`:** a versioned journal of *why* things are built the way they are (decisions, reasons,
  alternatives rejected, Unraid facts relied on, parked ideas). Separate from this changelog, which says what changed
- **`dr_usb_scrub.sh`: maintenance scrub (new)**
  - `dr_usb_scrub.sh` always verifies the live `/boot` and `/boot/previous` against Unraid's `.sha256` files;
    `dr_usb_scrub.sh -backup` also checks the backup, chosen by `remote.ini` (present -> the remote mirror, absent -> the
    local `UNRAID_DR` USB). Read-only; designed to be scheduled weekly/monthly, separately from the backup
  - Live-versus-backup differences are never reported (the backup is for DR, not a perfect sync). The local USB is checked
    on its own terms (Unraid's hashes plus `DR_MANIFEST.sums`, the same checks the restore makes). The remote mirror is
    compared with an rsync checksum dry run limited to the Unraid-hashed files, which works with the write-only `rrsync` key
    because the destination only reports what differs
  - The scrub reads the drive itself, not RAM: just before hashing each file of the live `/boot` or a local backup USB it
    drops that one file's cached pages (`dd iflag=nocache count=0`; nothing else on the server is touched). A first test
    run finished in 8 s because the files had just been read by the create. If `dd` cannot do it, the scrub warns that a
    clean result may reflect RAM
  - A failing scrub is loud and specific: a banner, then per problem the area (`LIVE /boot`, `BACKUP USB`, `REMOTE MIRROR`),
    the file, the problem, the full expected and actual hash and the size, then what to do; non-zero exit and an Unraid
    notification. Everything is also written to `scrub-*.log` (rotated with `SNAPSHOTS` / `RETENTION_DAYS`)
  - The backup's preflight uses the same shared check (`verify_boot_hashes`), so its failures now carry the same detail
    (full expected/actual hashes and size) as the scrub
  - New shared module `lib/remote.sh` (remote config, SSH key staging, the rrsync checks) used by the backup and the scrub;
    `notify_failure` moved to `lib/logging.sh`
  - New `Unit Test/test_scrub.sh` (75 checks) and a new guide `Docs/dr_usb_scrub.md`
- **Hash checks, and a locked-down remote destination** (pipelined with the items below)
  - **Source check before every backup (hard stop).** New `lib/integrity.sh`: `verify_boot_hashes` checks every file in
    `/boot` AND `/boot/previous` that has a `.sha256` sibling (`bzimage`, `bzroot`, `bzmodules`, `bzfirmware`,
    `bzroot-gui`, `memtest`; Unraid's files hold a bare 64-character hash) and stops the run on any mismatch, a missing
    required file (`bzimage`, `bzroot`, `bzmodules`), or a `.sha256` whose file is gone. Runs at the start of
    `clone_backup` (local backup and the first backup in `dr_usb_create.sh`) and in `-remote` before anything is sent, so a
    damaged flash drive can never overwrite a good backup. A file with no `.sha256`, or an unparsable one, only warns
  - **Backup manifest.** After each local backup `DR_MANIFEST.sums` is written onto the `UNRAID_DR` USB: SHA-256 of every
    file except those Unraid already hashes, `ldlinux.sys`/`ldlinux.c32` (the syslinux install rewrites them), the
    `BACKUP-*` marker, `logs/`, `.git/` and `System Volume Information/`. It is written last, in the backup's final state
    (after the `EFI-` rename); an old manifest is removed first so a failure never leaves a stale one. (The name avoids
    both `BACKUP-*`, which finds the marker, and `*.sha256`, which Unraid's hash files use)
  - **Restore check.** `move_dr_to_unraid.sh` verifies the backup's root and `previous/` against Unraid's `.sha256` files and
    the rest against `DR_MANIFEST.sums` while the backup is still mounted read-only. Failures are listed in the summary
    (first 20, then a count) and the user must type `OVERRIDE` before the normal `RESTORE` prompt; Enter cancels. A backup
    with no manifest only warns. `bzmodules` is now a required file of a complete flash backup
  - **`-remote` now REQUIRES `rrsync` on the destination.** The key must be locked with
    `restrict,from="<ip>",command="rrsync -wo <folder>"`: rsync only, write-only, one folder, no shell. `REMOTE_DIR` is
    gone from `remote.ini` (an old line is ignored with a warning); the folder is fixed on the server. The SSH-command
    preflight (`mkdir`, `test -w`, `command -v rsync`) is replaced by a small rsync probe push, followed by an
    enforcement check: if the same key can run `ssh <host> true`, the script refuses to run. In `-debug` the probe is a dry run
  - New tests: `test_integrity.sh` (52), `test_remote_flow.sh` (39), and 40 more checks in `test_move_dr.sh` (now 148)
  - Docs: the remote guide is rewritten for rrsync, with a security-model section (root locally, a deliberately weak
    destination key, snapshots and a firewall on the destination to protect the mirror itself), new troubleshooting rows
    and a restore-from-mirror procedure that uses an administrator account on the destination, because the backup key is write-only
- **`move_dr_to_unraid.sh` (emergency restore) rewritten: safer, verified, and self-contained**
  - Stops depending on Unraid's `make_bootable_linux` wrapper. That wrapper hands the real work to
    `syslinux/make_bootable_linux.sh`, which always `exit 0`s (so failures were invisible), asks an interactive
    Y/N, needs `mtools`/`sudo`, and unmounts a mount the old script was still standing in. The new script does the same
    steps itself, using the `syslinux_linux` and `mbr.bin` stored on the backup (so they match that Unraid release):
    relabel `UNRAID_DR` to `UNRAID`, rename `EFI-` to `EFI` (UEFI boot), `syslinux_linux -f --install <partition>`,
    and write the MBR
  - Read-only checks first, before anything is changed: root and tools present, no `UNRAID` drive, exactly one USB
    `UNRAID_DR` on its first partition, the partition is unmounted (the old script ignored a failed unmount), and the
    backup is a complete flash (`bzimage`, `bzroot`, `config/`, `syslinux/*`); `mbr.bin` must be 440-447 bytes
    (Unraid's is 447: its last byte is the partition-1 active flag) so it can never overwrite the partition table
  - Shows the drive, model, size and the last-backup time (from the `BACKUP-*` marker) and requires typing `RESTORE`
    (Enter cancels). Before this point nothing has been changed
  - Every step is checked and the result is verified (label, EFI folder, MBR read back byte-for-byte); if any step
    fails after the relabel, the label and `EFI` folder are put back so the USB is a normal `UNRAID_DR` backup again and
    the script can be re-run. Rebooting with the restored drive remains the point of no return
  - No more `eval` on device labels (a crafted label could run commands as root), and no stale transport value
    carried between loop iterations; ends with a license-replacement reminder
  - New `Unit Test/test_move_dr.sh` (106 checks, all disk tools stubbed, devices are plain files)
- **`dr_usb_create.sh`: safer, failures no longer hidden** (first pass)
  - Masked failures fixed (same `cmd | while read` bug as `dr_usb_backup.sh`): `wipefs`, `sfdisk`, `partprobe`,
    `mkfs.vfat`, `mount`, `umount` and `rsync` now report their own exit status; rsync is built as an array
    (no `eval`) and exit 24 is treated as success; `wipefs`, `sfdisk` and `mkfs.vfat` failures now stop the run
  - Any partition of the target drive that is mounted (e.g. auto-mounted by Unassigned Devices) is unmounted before
    wiping; if that fails nothing is changed, and a device mounted at `/boot` is refused
  - `-debug` and `-lsblk` no longer wipe/format anything: after the prompts the script logs what it would do and exits
  - Script now ends with a completed / finished-WITH-ERRORS message and exits non-zero on failure
  - **New USB drive menu (second pass):** every USB disk is now listed, including blank/unpartitioned and unlabeled
    drives (previously only drives with a labeled partition appeared, so new sticks were never found)
    - Drives that already contain partitions, labels or a filesystem are marked `*` and their partitions are listed;
      the list is repeated in the FORMAT confirmation
    - The Unraid boot drive, the Ventoy recovery USB (`Ventoy` / `VTOYEFI` labels), drives with a mounted partition,
      and drives that are too small are shown under "Not available" with the reason (and the minimum size) and cannot
      be selected; typed names are checked against that list, and the chosen disk is re-checked just before formatting
    - Each drive is listed once (previously once per labeled partition)
  - Startup check: `dr_usb_create.sh` stops with a clear message unless it is running on an Unraid server with `/boot`
    mounted (skipped with `-lsblk`, which never changes a drive); `-remote` is rejected with an explanation that the
    backup USB must be created locally and `-remote` is only for `dr_usb_backup.sh`
  - Interactive check now tests stdin (`-t 0`) instead of stdout, so `./dr_usb_create.sh | tee log` works
- **`run_logged` (both scripts)** now logs a failing command's output as `ERROR:` lines (previously only visible with
  `-debug`); `clone_backup` (both scripts) unmounts the backup USB if the EFI-rename verification fails
- **`dr_usb_backup.sh`: fixed masked failures.** `cmd | while read ...` returned the loop's status, so a
  failed rsync/mount/umount was still logged as success. Now rsync uses `PIPESTATUS` (exit 24 treated as
  success), mount/umount use a new `run_logged` helper, rsync is built as an array instead of `eval`, and the
  script exits non-zero when the backup fails
- **In-place upgrades driven by `setup_ventoy.ini`** (replaces the wipe-on-version-bump flow):
  - Every run on an existing USB now checks the installed Ventoy (`Ventoy2Disk.sh -l`) against
    `VENTOY_VERSION`; if older, it updates with `Ventoy2Disk.sh -u` (files on the USB are kept)
  - If `-u` fails, a full reinstall (`-I`, ERASES the drive) is offered only after a default-no confirmation
  - An installed Ventoy newer than the ini is never downgraded (warning only)
  - SystemRescue: when the ISO named by `SYSRESCUE_VER` differs from what is on the USB, the new ISO is
    downloaded/verified and older `systemrescue-*.iso` / `.sha512` files are removed (with confirmation)
  - Script `VERSION` vs `CURRENT_VERSION` is still compared: newer refreshes config and updates
    `CURRENT_VERSION`; an older script than the USB is a fatal downgrade error
  - `write_current_version` now always writes the current version (previously never updated an existing file)
  - `-upgrade` flag is still accepted but now prints a deprecation notice (it has no effect; upgrades are automatic)
  - New helpers: `download_ventoy`, `resolve_ventoy_disk`, `get_installed_ventoy_version`,
    `update_ventoy_in_place`, `preflight_upgrade_check`, `remove_old_sysrescue_isos`
  - Fixed a typo (`echo"`) in the "Sleeping for 10 seconds" message that would abort the script
  - Fixed: after a fresh Ventoy install the script waited 10 seconds for the new `Ventoy` partition but never looked
    again, so it failed with "Could not find Ventoy partition on Unraid" even though the partition was present
    (`find_and_mount_ventoy`); it now repeats the lookup after the wait
- Fixed `ventoy.json` generation so Ventoy honors it (`create_ventoy_json`):
  - Control values are now strings (`"30"`, was number `30`), as Ventoy requires
  - Each control key is in its own object (was several keys in one object)
  - Added `VTOY_DEFAULT_IMAGE` so the SystemRescue entry is the default selection
  - Overwrite prompt now defaults to yes and saves the old file as `ventoy.json.bak`
    (previously a stale file was kept by default)
  - Removed duplicated heredoc/`sed` branch with hardcoded ISO name; JSON is validated after writing
- Updated bundled software versions in `setup_ventoy.ini`:
  - Ventoy: `1.1.18`
  - SystemRescue: `13.02`
- Updated `FILE_MANIFEST.txt` to 1.2.0 and listed the `VERSION` file
- Existing USBs with `CURRENT_VERSION` below 1.2.0 will go through the upgrade path

## [1.1.9] - 2026-03-24

### Fixed

#### Version Check Moved to Preflight
- **CRITICAL FIX:** Version compatibility check now runs immediately after mounting existing Ventoy
  - Before: Version check happened at end of script after setup was already done
  - After: Preflight check before any setup actions
  - Impact: Version upgrades now properly trigger full Ventoy and SystemRescue reinstall

#### Version Comparison Function
- Replaced custom `version_decoder()` with tested `version_compare()` function
  - Returns: 0 (equal), 1 (first > second), 2 (second > first)
  - Properly handles x.y.z format (e.g., 1.1.8 > 1.1.7)
  - Works reliably in all bash environments
  - Fixed return code capture using `set +e/set -e` to prevent `set -e` from masking exit codes

#### Upgrade Flow - Full Reinstallation
- When script version > installed version:
  1. Unmounts existing Ventoy partition
  2. Downloads latest Ventoy version with SHA256 verification
  3. **Directly runs Ventoy2Disk.sh with `-i` flag to overwrite** (not just re-mount)
  4. Waits for kernel partition table refresh (`partprobe`)
  5. Mounts freshly installed Ventoy partition
  6. Downloads and installs latest SystemRescue ISO
  7. Updates configuration files and version tracking
- Prevents "partially upgraded" state where some components are old, some are new

#### Device Handling Fixes
- Fixed partition vs disk device naming:
  - Ventoy2Disk.sh requires disk device (`/dev/sdl`), not partition (`/dev/sdl1`)
  - Uses parameter expansion to strip partition numbers: `sdl1` → `sdl`, `nvme0n1p1` → `nvme0n1`
  - Fixed partprobe to use disk device
  - Fixed mount to use correct partition after reinstall

#### Error Handling & Safety
- Added explicit unmount before Ventoy reinstall to prevent mount conflicts
- Added SHA256 verification for Ventoy downloads
- Added space validation in `/var/tmp` before download
- Proper error messages with exit codes if any step fails
- Fixed variable scoping (`local` keyword only used in functions)

### UX Improvements
- Clear messaging when upgrade is triggered
- Shows version comparison (current vs script) at preflight stage
- Progress indicators through Ventoy download and installation phases
- Shows which device is being installed to and why
- Prevents downgrade attempts with fatal error

---

## [1.1.8] - 2026-03-23

### Fixed

#### Ventoy2Disk.sh Invocation - Critical PATH Bug
- **CRITICAL FIX:** Ventoy2Disk.sh now runs from its own directory for correct PATH setup
  - Bug: Calling with absolute path caused `$OLDDIR` to point to wrong location
  - Symptom: `mkexfatfs` and other Ventoy tools not found in PATH during installation
  - Root cause: Ventoy2Disk.sh uses relative paths (`./tool/$TOOLDIR`) that broke when invoked from outside directory
  - Fix: Changed invocation to `cd '${ventoy_dir}' && ./Ventoy2Disk.sh` for correct PATH initialization
  - Impact: Ventoy installation now succeeds on all systems with proper tool discovery

#### Partition Discovery Timing
- Added 3-second delay and `partprobe` call after Ventoy installation
  - Ensures kernel recognizes new partitions before script attempts to mount
  - Prevents "partition not found" errors immediately after installation

#### Confirmation Retry Logic
- Fixed YES confirmation prompt to properly handle empty input (pressing Return)
  - Changed from arithmetic-based loop to safer `while true` with manual increment
  - Now allows 2 full attempts as intended instead of exiting on first wrong input
  - Uses safer `read` with fallback to ensure empty input is handled

#### Stale Mount Handling
- Script now checks if `/mnt/disks/Ventoy` is mounted to a different device
  - If mounted to old/stale device, unmounts it first before mounting new Ventoy
  - Prevents "already mounted" or "read-only" errors from prior installations
  - Safely handles cleanup of previous Ventoy USB configurations

### UX Improvements
- Clearer error messages when mount conflicts detected
- Debug output shows partition detection attempts if mounting fails
- More robust partition discovery after fresh Ventoy installation

---

## [1.1.7] - 2026-03-23

### Changed

#### Smart Default Selection & Grammar Fixes
- **Auto-select when only one device:** If only 1 USB drive available and user presses Enter, automatically selects it
  - No need to type "1" — just press Enter
  - Faster workflow for single-drive scenarios

- **Grammatically correct error messages:**
  - Single device: `❌ Invalid selection '2'. Only option is 1` ✅
  - Multiple devices: `❌ Invalid selection '3'. Please choose between 1,2,3` ✅
  - No more awkward "choose between 1" when there's only one option

### UX Improvements
- Fewer keystrokes when only one drive is available
- Better grammar matches the actual situation
- More natural, conversational error messages

---

## [1.1.6] - 2026-03-23

### Fixed

#### Retry Logic Still Not Working - Root Cause Found and Fixed
- **REAL FIX:** The `[[ ]] =~ regex` pattern matching was the culprit
  - Interaction with `set -e` causes silent script exit in some bash environments
  - Replaced with portable `printf '%d'` number validation
  - Now safely checks if input is numeric without triggering `set -e`

#### Improved Error Handling for `set -e`
- Added explicit variable assignment after read: `read -r ... || selected_index=""`
- Added `|| true` to arithmetic operations to prevent `set -e` exits
- Quoted all variable comparisons for safety
- All error messages now show the invalid input user provided

### Testing
Now when user enters invalid index (e.g., "2" with only 1 device):
- ✅ Error message displays: `❌ Invalid selection '2'. Please choose between 1`
- ✅ Prompt appears again immediately for retry
- ✅ User gets 2 full attempts
- ✅ Script continues only with valid input

---

## [1.1.5] - 2026-03-23

### Fixed

#### Critical Bug: Silent Script Exit on Invalid Input
- **CRITICAL FIX:** Script was silently exiting instead of showing error messages and retrying
  - Root cause: `seq | tr | sed` pipeline could fail with `set -e`, causing silent exit
  - Symptom: User enters invalid index (e.g., "2" when only 1 device exists) → script exits with no message
  - Fix: Replaced fragile pipeline with simple for-loop string building
  - Impact: Error messages now display properly and users get actual retry opportunities

#### Robustness Improvements
- Replaced `echo` with `printf` for consistent, safe output
- Added `|| true` to read command to handle edge cases
- Used `read -r` for safer input reading
- Removed shell pipeline dependencies that could fail silently

### Testing
After this fix, when user enters invalid index:
- ✅ Error message displays immediately
- ✅ User is prompted to try again
- ✅ 2 retry attempts actually work
- ✅ Script only exits after exceeding max attempts

---

## [1.1.4] - 2026-03-23

### Changed

#### Device Selection UX - Major Improvements
- **Shows available choices in prompt:** `Select USB drive by index number (1,2,3): `
  - Users can see valid options without looking up at the list
  - Eliminates confusion about what to enter

- **Better error messages:** All errors show valid choices
  - `❌ Invalid selection. Please choose between 1,2,3`
  - Users know exactly what inputs are acceptable

- **Guaranteed retry attempts:**
  - Fixed logic to properly allow 2 attempts before exiting
  - Users can correct mistakes (typos, wrong index)
  - Previous bug caused script to exit silently

- **Clearer error handling:**
  - Checks for empty input separately
  - Different messages for: non-numeric, out-of-range, empty
  - No more silent exits

### User Experience
Before (v1.1.3):
```
Select USB drive by index number: 2
[script exits with no message]
```

After (v1.1.4):
```
Select USB drive by index number (1): 2
❌ Invalid selection. Please choose between 1
Select USB drive by index number (1): 1
[continues with valid selection]
```

---

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
