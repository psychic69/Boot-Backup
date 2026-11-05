# Test Checklist - Version 1.2.0

Hands-on test plan for release **1.2.0**, to run on real hardware before publishing. The automated tests
(`Unit Test/run_tests.sh`) already pass with stubbed tools; this checklist covers what only real drives, a real
Unraid server and a real destination can prove.

Work top to bottom: the steps go from safest to most risky. Tick each box, and write what you saw in the
**Results** table at the end. If anything fails, see [If something fails](#if-something-fails).

---

## Safety rules for testing

- [ ] **Have a copy of `/boot`** somewhere else before you start (for example `cp -a /boot /mnt/user/<share>/boot-copy-1.2.0`).
- [ ] **Never corrupt or edit files on the live `/boot`.** All "failure drills" below are done on a **backup** (the
      `UNRAID_DR` USB, the spare stick, or the destination folder), never on the running flash drive.
- [ ] **Use spare USB sticks** for steps 5, 7 and 8. Anything you select in the create script is **erased**.
- [ ] **Do not relicense** the restored stick during the restore rehearsal. Replacing the key permanently blacklists your original drive.
- [ ] **Do not run the backup and the scrub at the same time.**
- [ ] The restore rehearsal (step 7) runs on a **test machine or VM**, not on your production server.

## Record your environment

| Item | Value |
|------|-------|
| Unraid version (`cat /etc/unraid-version`) | |
| `/etc/unraid-version` exists? (`ls /etc/unraid-version`) | |
| bash on Unraid (`bash --version \| head -1`) | |
| rsync on Unraid (`rsync --version \| head -1`) | |
| Destination OS, rsync and `rrsync -h` output | |
| Spare USB sticks (sizes) | |
| Release tested (`cat VERSION`) | 1.2.0 |

---

## Step 0 - Automated tests on Linux

Run on a Linux machine or container (not the Unraid server; some tests need `python3`).

- [ ] `bash "Unit Test/run_tests.sh"`
- **Expect:** `ALL TESTS PASSED`. On Linux the two checks skipped on macOS (log rotation by count, the `-remote` check that needs `flock`) should now **run**, not skip.

## Step 1 - Build and install

- [ ] On your dev machine: `bash build_release.sh`. **Expect:** `Built dist/Boot-Backup-1.2.0.tar.gz (... 16 files)` and a SHA-256 line.
- [ ] Copy the `.tar.gz` and `.sha256` files to the Unraid server (`/tmp`).
- [ ] On Unraid: `cd /tmp && sha256sum -c Boot-Backup-1.2.0.tar.gz.sha256`. **Expect:** `Boot-Backup-1.2.0.tar.gz: OK`.
- [ ] `tar -xzf Boot-Backup-1.2.0.tar.gz -C /boot/config/plugins/ --no-same-owner --no-same-permissions`
- [ ] `ls /boot/config/plugins/dr_usb /boot/config/plugins/dr_usb/lib`. **Expect:** the three scripts, `dr_usb.ini.example`, `remote.ini.example`, `VERSION`, `lib/` with `logging.sh drives.sh integrity.sh clone.sh config.sh remote.sh`, and `Recovery-ISO/`.
- [ ] (Optional) `cp dr_usb.ini.example dr_usb.ini`. Not required: every value has a default.

## Step 2 - Scrub of the live drive (read-only, safe)

- [ ] `time bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh; echo "exit=$?"`
- **Expect:** `Boot file hashes OK (N verified, 0 warning(s))`, then `SCRUB CLEAN - no problems found.` and `exit=0`.
- [ ] `N` equals the number of Unraid hash files: `ls /boot/*.sha256 /boot/previous/*.sha256 | wc -l`.
- [ ] **Expect** a line `Each file was read from the drive itself (its cached copy was dropped first), not from RAM.`
- [ ] Note how long it took (it reads roughly 2-3 GB from a USB stick, so expect about a minute or more, not seconds): ____
- [ ] A log exists: `ls -t /boot/logs/unraid-dr/logs/ | head -3` shows `scrub-*.log`.

## Step 3 - Local backup to the `UNRAID_DR` USB

Needs an existing `UNRAID_DR` USB (if you have none yet, do step 5 first).

- [ ] **Dry run:** `bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -debug`
  - **Expect:** `Boot file hashes OK`, `DEBUG MODE - Running rsync with --dry-run`, `DEBUG MODE - Would write DR_MANIFEST.sums`, ends with `script completed.`
  - In `-debug` the USB stays mounted: `umount /mnt/disks/usb-backup-temp` afterwards.
- [ ] **Real run:** `bash /boot/config/plugins/dr_usb/dr_usb_backup.sh; echo "exit=$?"`
  - **Expect, in order:** the hash check passes, rsync output, `EFI directory successfully renamed to EFI-`, `Wrote DR_MANIFEST.sums (N files).`, `Successfully unmounted`, `script completed.`, `exit=0`.
  - Manifest file count N: ____
- [ ] **Inspect the USB** (read-only): `mkdir -p /mnt/disks/chk && mount -o ro /dev/sdX1 /mnt/disks/chk` (use your `UNRAID_DR` device), then
  `ls -a /mnt/disks/chk`. **Expect:** `DR_MANIFEST.sums`, a `BACKUP-<timestamp>` file, `EFI-` (not `EFI`), `previous/`, `config/`, and the `bz*` files with their `.sha256`. Then `umount /mnt/disks/chk`.
- [ ] **Second run** straight away. **Expect:** fast, `script completed.`, and a fresh manifest.

## Step 4 - Scrub of the local backup, and a failure drill

- [ ] `bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh -backup; echo "exit=$?"` (no `remote.ini` present)
  - **Expect:** `CHECKING THE LOCAL BACKUP USB (UNRAID_DR)`, `Boot file hashes OK` for the backup, `All N manifest file(s) match.`, `SCRUB CLEAN`, `exit=0`.
- [ ] **Failure drill (backup USB only):** mount the `UNRAID_DR` USB read-write and damage one **small** file:
  ```
  mount /dev/sdX1 /mnt/disks/chk
  echo x >> /mnt/disks/chk/previous/memtest
  umount /mnt/disks/chk
  ```
  Run `dr_usb_scrub.sh -backup` again.
  - **Expect:** a banner `SCRUB FAILED - 1 PROBLEM(S) FOUND`; `[BACKUP USB]  previous/memtest`, `problem : HASH MISMATCH`, the **full expected and actual hashes and the size**, a "WHAT TO DO" section, `exit=1`, an Unraid GUI notification, and the same text in the `scrub-*.log`.
- [ ] **Repair as the report advises:** mount the USB, `rm /mnt/disks/chk/previous/memtest`, unmount, run `dr_usb_backup.sh`, then `dr_usb_scrub.sh -backup`. **Expect:** clean again.
- [ ] **Manifest drill:** damage a file in the backup's `config/` the same way (append a byte), scrub. **Expect:** `DOES NOT MATCH THE MANIFEST` naming that file. Repair by deleting the file and running the backup.

## Step 5 - Creating a backup USB (spare stick only)

Unplug any existing `UNRAID_DR` USB first, or the script will (correctly) refuse.

- [ ] `bash /boot/config/plugins/dr_usb/dr_usb_create.sh -debug`, then pick the spare stick and type `FORMAT`.
  - **Expect:** a menu where the spare stick is selectable (marked `*` if it holds data, with its partitions listed); your **Unraid boot drive** and any **Ventoy stick** shown under "Not available (cannot be selected)" with the reason; typing one of those names is refused with its reason; at the end `DEBUG/TEST MODE - /dev/sdX was NOT changed.`
- [ ] **Real run** on the spare stick. **Expect:** it unmounts anything mounted from that stick, partitions and formats it, runs the hash check, copies the first backup, writes the manifest, and ends `CREATE** script completed.`
- [ ] The new log exists: `usb-create-*.log` in the logs folder.
- [ ] Run create **again**. **Expect:** `An 'UNRAID_DR' partition was already found` and exit 1.
- [ ] Stick too small (if you have one under 95% of your boot drive's size): it is listed under "Not available" with `too small ... minimum is ...`.
- [ ] Run `dr_usb_backup.sh` and `dr_usb_scrub.sh -backup` against the new stick. **Expect:** clean.

## Step 6 - Remote backup (needs a destination)

Follow [the remote backup guide](dr_usb_backup.md#remote-backup--remote) steps 1-5 (including `rrsync`).

- [ ] On the destination: `rrsync -h` lists `-wo`. Version/location noted in the environment table.
- [ ] **Dry run:** `bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote -debug`
  - **Expect:** `Boot file hashes OK`, `Destination OK: writable, and the key is restricted to rrsync.`, a dry-run rsync listing, `script completed.`
  - Any `rsync error` mentioning a refused option means `rrsync` rejected a flag: **record the exact message**.
- [ ] **Failure drills** (undo each one afterwards):
  - [ ] Remove `command="rrsync ..."` from the key line on the destination. **Expect:** `SECURITY CHECK FAILED ... can run arbitrary commands`, and nothing is sent.
  - [ ] Change `from="..."` to a wrong address. **Expect:** `Could not reach or write to the destination` with rsync's own message.
  - [ ] Point `rrsync` at a folder that doesn't exist. **Expect:** the same "Could not reach or write" error.
- [ ] **Real run:** `bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote; echo "exit=$?"`. **Expect:** `Remote mirror completed successfully`, `exit=0`.
- [ ] **On the destination** (as an administrator): the backup folder holds a copy of `/boot` including `previous/`, with `EFI` exactly as on the live drive, and **no** `.dr_usb_probe` file left behind.
- [ ] **The key is truly restricted:** from the Unraid server, using the key copied to RAM (see the guide's "test SSH by hand"), `ssh ... true` is refused, and the key cannot list or download the backup.
- [ ] **Scrub the remote mirror:** `bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh -backup` (with `remote.ini` present).
  - **Expect:** `CHECKING THE REMOTE BACKUP`, `The Unraid-hashed files on the remote mirror match the live drive.`, `SCRUB CLEAN`.
  - If you see `THE CHECKSUM COMPARISON COULD NOT RUN`, **record the rsync message** (likely an `rrsync` option restriction).
- [ ] **Remote failure drill:** as destination admin, append a byte to `previous/memtest` in the backup folder. Scrub. **Expect:** `[REMOTE MIRROR]  previous/memtest` ... `DIFFERS from the verified live file`, `exit=1`. Repair: delete that file on the destination, run the backup, scrub clean.
- [ ] (Optional) A daily/weekly scheduled run works from your scheduler (User Scripts wrapper, cron or Komodo).

## Step 7 - Restore rehearsal (spare stick, test machine)

- [ ] Create a Ventoy recovery USB with `setup_ventoy_usb.sh` (a spare Ventoy USB). **Expect:** `UNRAID_RECOVERY_INSTRUCTIONS.txt` mentions the `RESTORE` and `OVERRIDE` prompts.
- [ ] Use the spare `UNRAID_DR` stick from step 5 (it must contain a real backup), plug it and the Ventoy USB into a **test machine or VM** that has **no** drive labeled `UNRAID`.
- [ ] Boot the Ventoy USB, pick "Unraid Recovery - SystemRescue", run `mountall`, then
      `bash /mnt/sdX1/unraid_recovery/move_dr_to_unraid.sh`.
- **Expect, in order:**
  - [ ] `No conflicting 'UNRAID' drive found`, then `Found one and only one matching USB drive`
  - [ ] `Backup contents look complete`
  - [ ] `Checking <file> (N MB)...` for the boot files, including `previous/...`, and `N file(s) match Unraid's hashes`
  - [ ] `... of ... file(s) match the manifest`
  - [ ] the summary with the **drive, model, size and last-backup time**, and `All checked files match their hashes`
  - [ ] the prompt `Type RESTORE to continue`
- [ ] **Cancel test first:** press Enter at the prompt. **Expect:** `Cancelled. Nothing was changed.` and the stick is still labeled `UNRAID_DR` (`fatlabel /dev/sdX1`).
- [ ] **Run again and type `RESTORE`.** **Expect:** `Label is now 'UNRAID'`, `Renamed EFI- to EFI`, `Boot loader installed`, `MBR written and verified (447 bytes)`, `Verification passed` (note any warnings, especially about the active flag or the SYSLINUX boot sector), then `All done!` and the license reminder.
- [ ] **Boot the restored stick** on a UEFI machine. **Expect:** Unraid starts and (as expected) asks for a license key replacement. **Do not replace the key.**
- [ ] (If you want legacy-BIOS support) boot it on a machine in legacy/CSM mode.
- [ ] **Verification drill:** on a fresh `UNRAID_DR` stick, append a byte to `previous/memtest`, then run the restore. **Expect:** `1 file(s) on the backup FAILED verification`, then the prompt `Type OVERRIDE to restore anyway`; **Enter** cancels with nothing changed.
- [ ] **Conflict drill:** with a drive labeled `UNRAID` plugged in, run the script. **Expect:** `A drive with the label 'UNRAID' already exists` and exit 1.

## Step 8 - Recovery USB upgrade (spare Ventoy USB)

- [ ] Run `setup_ventoy_usb.sh` on the existing spare Ventoy USB. **Expect:** it checks the installed Ventoy (`Ventoy2Disk.sh -l`) and reports "up to date" or offers the in-place update.
- [ ] Change `VENTOY_VERSION` or `SYSRESCUE_VER` in `setup_ventoy.ini` to a newer release and run again. **Expect:** an in-place update (`Ventoy2Disk.sh -u`), files kept, an old SystemRescue ISO replaced.
- [ ] The Ventoy menu shows "Unraid Recovery - SystemRescue" and boots it. **Record** if the `Ventoy2Disk.sh -l` output could not be parsed (the script says so and skips the update).
- [ ] `-upgrade` still works but prints the deprecation notice.

---

## Sign-off

- [ ] Every step above passed, or each failure is understood and fixed.
- [ ] Anything unexpected is written down below and added to the [design journal](DESIGN_DECISIONS.md) under "Open and parked ideas" or as a new entry.
- [ ] Ready to publish: `git tag v1.2.0`, create the GitHub Release, attach the `.tar.gz` and `.sha256` from `dist/`.

## Results

| Step | Date | Pass / Fail | Notes (messages, timings, anything odd) |
|------|------|-------------|------------------------------------------|
| 0 - automated tests on Linux | | | |
| 1 - build and install | | | |
| 2 - scrub, live | | | |
| 3 - local backup | | | |
| 4 - scrub, local backup + drills | | | |
| 5 - create (spare stick) | | | |
| 6 - remote backup, scrub + drills | | | |
| 7 - restore rehearsal | | | |
| 8 - Ventoy upgrade | | | |

## If something fails

Send the following (nothing in them is secret, but skim the log before sharing):

1. The exact command you ran and what you expected.
2. The complete log file: `/boot/logs/unraid-dr/logs/` (`boot-check-*.log`, `usb-create-*.log` or `scrub-*.log`). For the restore script, the full terminal output, since it has no log file.
3. `uname -a`, the Unraid version, `bash --version | head -1`, `rsync --version | head -1`, and for remote problems the destination's `rrsync -h` output.

Failures are written to be diagnosed from the output alone: the messages name the file, the cause and the next step.
