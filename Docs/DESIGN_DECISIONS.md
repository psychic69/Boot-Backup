# Design Decisions Journal

This is the project's **decision record**: *why* things are the way they are, what we considered and
rejected, and what we learned about Unraid along the way. It is deliberately separate from
[`CHANGELOG.md`](../CHANGELOG.md), which says *what changed* in a form meant for users.

**How to use it**

- Entries are tagged with the release they were made in (the `VERSION` file). New work gets a new
  `## Version x.y.z` section at the bottom; **do not rewrite old entries**. If a decision is replaced, mark the
  old one `Superseded by D-nnn` and add a new entry.
- Each entry: **Decision**, **Why**, **Alternatives rejected**, and **Consequences** where they matter.
- A decision that was made and then replaced in the same release stays in the journal (marked superseded), because
  the reason it changed is often the most useful part.
- Part of this journal records working rules agreed with the project owner (see D-1.2.0-27); anyone (or any AI)
  continuing the project should read it before changing behavior.

**Contents**

- [Version 1.2.0](#version-120)
  - [A. Distribution and structure](#a-distribution-and-structure)
  - [B. Backup and create behavior](#b-backup-and-create-behavior)
  - [C. The remote backup and its security](#c-the-remote-backup-and-its-security)
  - [D. Restore (move_dr_to_unraid.sh)](#d-restore-move_dr_to_unraidsh)
  - [E. The maintenance scrub](#e-the-maintenance-scrub)
  - [F. Recovery USB (Ventoy) tooling](#f-recovery-usb-ventoy-tooling)
  - [G. Testing and working rules](#g-testing-and-working-rules)
  - [Facts about Unraid that the design relies on](#facts-about-unraid-that-the-design-relies-on)
  - [Open and parked ideas](#open-and-parked-ideas)
- [Version 1.2.1](#version-121)

---

## Version 1.2.0

*Journal started 2026-11-03.* Goal of the project, which every decision below serves: **mirror the running Unraid
USB as closely as possible, so that if the main USB dies it is easy and safe to promote the backup to be the main
drive.**

### A. Distribution and structure

#### D-1.2.0-01 — One release archive, attached to a GitHub Release (not committed to git)
- **Decision:** the whole project ships as `Boot-Backup-<version>.tar.gz` (plus a `.sha256`), built by
  `build_release.sh` and attached to a GitHub Release for the tag. It extracts to `/boot/config/plugins/dr_usb/`.
- **Why:** the scripts, the shared modules and the recovery-USB tooling must all be present together, and a user
  should install them with one verified download. A purpose-built archive contains only what belongs on the flash drive.
  User settings (`dr_usb.ini`, `remote.ini`, SSH keys) are never in it, so upgrading by extracting over an existing
  install cannot overwrite them.
- **Alternatives rejected:** committing a `.gz` to git (a permanent binary in history on every version, cannot be
  diffed); GitHub's automatic "source code" download (it is the whole repo: docs, tests, dev files).
- **Consequence:** `build_release.sh` syntax-checks every script before packaging, and a test builds the archive and
  inspects it (`test_release.sh`). The release itself is published by hand (tag, create the Release, attach two files).

#### D-1.2.0-02 — A single `VERSION` file at the repo root; the repo layout is the install layout
- **Decision:** one `VERSION` (`SCRIPT_VERSION=x.y.z`) for the whole release, moved from `Recovery-ISO/scripts/`. No
  folders were renamed or moved, so the archive is the repo minus `Docs/`, `Unit Test/` and dev files.
- **Why:** "one release". Every documented path (`Recovery-ISO/scripts/setup_ventoy_usb.sh` and so on) stays valid.
  `setup_ventoy_usb.sh` reads the version from two folders above itself.
- **Alternatives rejected:** separate version numbers per tool; restructuring the folders.

#### D-1.2.0-03 — Shared code lives in `lib/` modules
- **Decision:** `lib/logging.sh`, `drives.sh`, `integrity.sh`, `clone.sh`, `config.sh`, `remote.sh`; both
  `dr_usb_backup.sh`, `dr_usb_create.sh` and `dr_usb_scrub.sh` source them from their own folder and stop with a clear
  message if one is missing.
- **Why:** a comparison showed eleven functions were byte-identical copies in the backup and create scripts (about 420
  lines; `clone_backup` alone was 191), and fixes had already started to drift apart. The functions were moved verbatim,
  checked by script, not retyped.
- **Consequence:** the old "paste the script into the User Scripts plugin" install cannot work (a pasted copy has no
  `lib/` beside it). The plugin now calls the script on the flash drive through a two-line wrapper. Any scheduler works
  (cron, a Komodo action, User Scripts).
- **Exception:** `move_dr_to_unraid.sh` stays standalone and carries its own small copies of a few helpers, because
  `setup_ventoy_usb.sh` copies *only that file* onto the Ventoy recovery USB, where `lib/` does not exist.

#### D-1.2.0-04 — Settings in an optional `dr_usb.ini`; `remote.ini` stays separate
- **Decision:** `LOG_DIR`, `SNAPSHOTS`, `RETENTION_DAYS`, `CLONE_MP` (and an optional `REMOTE_INI` location) moved out of
  the scripts into `dr_usb.ini` beside them. Every value has a built-in default, so the file is optional.
  `remote.ini` is its own file and defaults to beside the scripts.
- **Why:** with settings inside the scripts, extracting a newer release overwrote the user's edits. `remote.ini` holds
  server-specific values and key paths, so it is kept apart and is only needed for `-remote`.
- **Note:** the ini files are `source`d, like the existing `setup_ventoy.ini`. Accepted because `/boot` is already
  root-trusted (it holds the `go` file and the scripts themselves), so this adds no new exposure.

#### D-1.2.0-05 — The create script keeps its own log, with its own name
- **Decision:** `dr_usb_create.sh` writes `usb-create-DATE.log` (not `boot-check-*.log`). When a new one is written,
  earlier create logs that finished successfully are deleted; logs from failed runs are kept.
- **Why:** it is a one-off, tiny log whose only value is historical, and sharing the `boot-check-*` name meant the
  backup's rotation could delete it. Failed runs are kept because they are the ones worth diagnosing.

### B. Backup and create behavior

#### D-1.2.0-06 — The backup is a 1:1 mirror with no snapshots
- **Decision:** the local and remote backups copy `/boot` as it is (including `previous/`). No versioning.
- **Why:** this is for disaster recovery only. Snapshots would mean the restore has to ask the user which snapshot to
  use, which is exactly the complexity the project avoids in an emergency.
- **Alternatives rejected:** `rsync --link-dest` dated snapshots (restore complexity). If someone wants point-in-time
  protection, it belongs on the *destination* (see D-1.2.0-15), outside these scripts.

#### D-1.2.0-07 — Failures must never be masked
- **Decision:** every command whose failure matters reports its own exit status; `rsync` uses `PIPESTATUS` (exit 24,
  "files vanished", counts as success); mount/umount/format steps go through `run_logged`, which shows a failing
  command's output as `ERROR:` lines without needing `-debug`; scripts exit non-zero when a backup fails; rsync is built as
  an array, never through `eval`.
- **Why:** `cmd | while read ...` returns the loop's status, so a failed rsync, mount or format was logged as success.
  In `dr_usb_create.sh` this sat in a destructive path (format, then a "successful" copy onto an unformatted or
  still-mounted drive).

#### D-1.2.0-08 — The create script lists *every* USB disk and refuses the dangerous ones
- **Decision:** all USB disks are listed (blank and unlabeled included); a `*` marks a drive that already holds data and
  its partitions, filesystems and labels are listed, and repeated in the `FORMAT` confirmation. **Not selectable, but shown
  with the reason:** the Unraid boot drive, the Ventoy recovery USB (`Ventoy` / `VTOYEFI` labels), any disk with a mounted
  partition, and drives smaller than 95% of the boot drive (the message gives the minimum). Typed names are checked against
  that list, and the chosen disk is re-checked from fresh data just before the format.
- **Why:** the normal use case is a brand-new or previously used stick. The old list required a labeled partition, so a
  new blank stick was never offered, while the Ventoy recovery stick could be offered for wiping.
- **Related:** `-debug` and `-lsblk` never format; the script unmounts a mounted target first and refuses `/boot`.

#### D-1.2.0-09 — Creation must happen on the Unraid server; `-remote` is backup-only
- **Decision:** `dr_usb_create.sh` stops unless it is running on an Unraid server with `/boot` mounted, and rejects
  `-remote` with an explanation. `-lsblk` test mode skips the check (it never formats).
- **Why:** the backup USB must be made from, and plugged into, the server whose boot drive it protects. `-remote` only
  describes where a *backup* goes.

#### D-1.2.0-10 — Source `/boot` is hash-checked before every backup; a mismatch is a hard stop
- **Decision:** before anything is copied (local clone, the create script's first backup, and `-remote`), every file in
  `/boot` **and `/boot/previous`** that has a `.sha256` sibling is hashed and compared with the bare 64-character hash
  Unraid stores in it. Any mismatch, a missing required file (`bzimage`, `bzroot`, `bzmodules`) or a `.sha256` whose
  file is gone stops the run with nothing copied. A required file with no `.sha256`, or an unparsable one, only warns.
  Failures record the full expected hash, actual hash and size.
- **Why:** the very failure this tool exists for is a dying flash drive; without the check, a silently corrupted binary
  could overwrite the one good copy. Unraid already ships a hash for each boot file, so we reuse them rather than invent
  our own. `previous/` is included because it is part of the mirror and the rollback OS ("check previous 100%").
  `bzfirmware` is not *required* because older Unraid releases may not have it (not verified; it is still checked whenever
  it and its `.sha256` are present).
- **Cost accepted:** roughly 2-3 GB read per run (a minute or two). At the intended 3-4 runs a week this is fine.
- **Alternatives rejected:** verifying the copy afterwards (we trust rsync's transfer checks); hashing only the root files;
  checking weekly instead of every run.
- **Note:** a backup that overlaps an Unraid OS update can fail this check temporarily. It stops safely; the next run is fine.

#### D-1.2.0-11 — `DR_MANIFEST.sums`: a manifest for what Unraid does not hash
- **Decision:** after each local backup, `DR_MANIFEST.sums` is written to the root of the `UNRAID_DR` USB: a SHA-256 for
  every file **except** those Unraid already hashes, `ldlinux.sys` / `ldlinux.c32`, the `BACKUP-*` marker, the manifest
  itself, and `logs/`, `.git/`, `System Volume Information/`. It is written last (after the `EFI` -> `EFI-` rename); an
  old manifest is deleted first so a failed run can never leave a stale one.
- **Why:** it covers `config/` (the license key and settings, the most valuable data) and the other small files at
  almost no cost, since the big files are covered by Unraid's own hashes. `ldlinux.*` are excluded because the syslinux
  install rewrites them (a retry after a rolled-back restore would otherwise fail).
- **The name:** deliberately not `*.sha256` (Unraid's hash files use that suffix, and the checks would treat the manifest as
  a hash file for a file that does not exist) and not `BACKUP-*` (the last-backup marker is found by that pattern and
  sorts before it). Both collisions were caught by tests.
- **Consequence:** the checker is a plain loop comparing hashes, not `sha256sum -c`, whose output for missing files varies
  between implementations.
- **Not done:** no manifest for the remote mirror (it would add a file to the live `/boot`; remote restores are manual).

### C. The remote backup and its security

#### D-1.2.0-12 — `-remote` mirrors `/boot` over SSH with rsync, using a private key staged in RAM
- **Decision:** settings in `remote.ini`; key and pinned `known_hosts` on the flash drive; the script copies the key to
  `/dev/shm` with mode 600 for the run and deletes it on exit. `StrictHostKeyChecking=yes`, `BatchMode=yes`. A `flock`
  stops overlapping runs. `--delete-after` so nothing is deleted on the destination until the transfer succeeded.
  Destination exclusions are configurable; the default is a true 1:1 copy.
- **Why:** `/boot` is FAT, so every file looks world-readable and ssh refuses a key read from it. The key has no
  passphrase because the job is unattended.
- **Known limit:** anyone who can read the flash drive (for example through an exported `flash` SMB share) can read the key.

#### D-1.2.0-13 — The destination MUST lock the key with `rrsync` (write-only, one folder, no shell)
- **Decision:** the key in `authorized_keys` must read
  `restrict,from="<unraid-ip>",command="rrsync -wo <backup folder>" ...`. The script enforces it: a small rsync probe push
  must succeed (so the connection, key, host key, `rrsync` and the folder all work), and then `ssh <host> true` must
  *fail*; if it succeeds the key is unrestricted and the script refuses to run. `REMOTE_DIR` no longer exists: the server
  decides the folder. The probe is a dry run under `-debug`.
- **Why:** the owner's concern was that someone who gets into Unraid (which runs everything as root) could walk straight
  into another server. With this line a stolen key gives no shell, cannot read the backups (they contain the license key
  and password hashes), cannot leave the one folder, and only works from the Unraid address. This is a key-scoping
  problem, not an rsync problem.
- **Alternatives rejected:**
  - *A hash or token as authentication:* a hash proves integrity, not identity; whatever secret proves identity must sit
    on Unraid at backup time, so a compromised Unraid can use it just like the key. Restricting what the credential can do
    is the real fix.
  - *Pull instead of push* (the destination pulls with a read-only key; Unraid holds no secret for the destination):
    the cleaner trust direction, but a different architecture. Kept as a documented alternative, not built.
  - *Client-side encrypted append-only repositories (restic/borg):* strongest, but no longer a 1:1 mirror and every restore
    would need that tool.
- **Consequences:** the folder must be created by the destination admin (the key cannot); the backup user needs a normal
  login shell because sshd runs the forced command through it; **restoring from the mirror uses an administrator account on
  the destination** because the backup key is write-only. The `rrsync` options we depend on must be confirmed on the real
  destination with `-remote -debug`.

#### D-1.2.0-14 — Superseded: the first remote design used SSH commands and a `REMOTE_DIR`
- **Superseded by D-1.2.0-13.** The first version ran `mkdir -p`, `test -w` and `command -v rsync` over SSH and checked that
  `REMOTE_DIR` was at least two levels deep. That requires a key that can run commands, which is the thing D-1.2.0-13
  removes. An old `REMOTE_DIR` line is ignored with a warning.

#### D-1.2.0-15 — What the remote design does *not* protect, and where that is handled
- **Decision:** the documentation states plainly that a compromised Unraid can still overwrite or delete the contents of
  the backup folder (the mirror must write and delete there). The protection is on the destination: its own snapshots
  (ZFS/btrfs/LVM or a hard-link cron copy) that the Unraid key cannot reach, and a firewall that accepts SSH only from
  the Unraid server and gives the destination no credentials for Unraid.
- **Why:** this cannot be solved inside the scripts without giving up the 1:1 mirror (see D-1.2.0-06).

#### D-1.2.0-16 — Everything on the Unraid side runs as root; the destination account is the sandbox
- **Decision:** accepted and documented, not worked around. Unraid has no unprivileged accounts, so the scripts, the key
  and the settings sit with root. The destination user is dedicated, unprivileged, and (per D-1.2.0-13) can do almost nothing.
- **Why:** this is Unraid's security model. The scripts therefore compensate with strict checks (refusing the boot drive,
  mounted or in-use disks, unverified backups) and typed confirmations.

### D. Restore (`move_dr_to_unraid.sh`)

#### D-1.2.0-17 — The restore no longer calls Unraid's `make_bootable_linux`; it does the same steps itself, checked
- **Decision:** the script relabels `UNRAID_DR` to `UNRAID`, renames `EFI-` to `EFI`, runs the backup's own
  `syslinux/syslinux_linux -f --install <partition>`, and writes the backup's own `syslinux/mbr.bin` to the disk, then
  verifies the result. The bundled binaries are used so they match the Unraid release being restored.
- **Why (found by reading the two scripts Unraid ships):** `make_bootable_linux` only prepares and then hands the real
  work to `syslinux/make_bootable_linux.sh`, which ends with `exit 0` whatever happened, so failures were invisible. The
  wrapper also asks an interactive Y/N for UEFI (which loops forever without input), needs `mtools` and `sudo`, requires the
  label to *already* be `UNRAID`, and unmounts a mount the old script was still standing in.
- **Boot support (option B):** syslinux and the MBR are kept so a restored drive keeps the same legacy-BIOS ability as an
  original Unraid flash. UEFI only needs the `EFI` folder; a UEFI-only variant (option A) was considered and left for later,
  after real-hardware testing. Setting the active flag separately (option C) turned out to be unnecessary (D-1.2.0-18).

#### D-1.2.0-18 — `mbr.bin` is 447 bytes: size-guarded, written exactly, read back
- **Decision:** the script refuses an `mbr.bin` outside 440-447 bytes, writes exactly its length, and compares it back
  byte for byte.
- **Why:** an earlier assumption (440 bytes, "nothing sets the active flag") was wrong. Unraid's file is 447 bytes, so its
  last byte is the first partition's active flag (offset 446). The original `dd` has no size limit, so a larger file would
  overwrite the partition table.

#### D-1.2.0-19 — Read-only checks first, a typed confirmation, then change, verify, and roll back on failure
- **Decision:** nothing is changed until: root and tools present, no `UNRAID` drive present, exactly one USB `UNRAID_DR`
  **on its first partition**, the partition unmounted (a failed unmount stops the script), the backup contains a complete
  flash, and the boot tools run. The user sees the drive, model, size and last-backup time and must type `RESTORE`
  (Enter cancels). If any step after the relabel fails, the label and the `EFI` folder are put back, so the stick is a
  normal backup again and the script can be re-run. Rebooting with the restored drive is the only point of no return.
- **Why:** the old order relabeled first, so any later failure left a drive labeled `UNRAID` that could no longer be
  restored (the script then refused to run because an `UNRAID` drive "already exists"). The first-partition rule is a
  requirement of Unraid's own tools. `mountall` (used in the recovery instructions) mounts the backup, so the unmount is real.
- **Also:** device labels are never passed to `eval` (a crafted label could run commands as root), and a stale transport
  value could no longer leak between loop iterations. The final message reminds the user that Unraid will ask for a
  license-key replacement.

#### D-1.2.0-20 — The restore verifies the backup; failures need `OVERRIDE`
- **Decision:** while the backup is mounted read-only, its root and `previous/` are checked against Unraid's `.sha256`
  files and everything else against `DR_MANIFEST.sums`. Failures are listed (first 20, then a count) and the user must type
  `OVERRIDE`, then `RESTORE`. A backup with no manifest only warns.
- **Why:** in an emergency a trivial mismatch must not block recovery, but restoring a damaged backup must be an explicit,
  informed choice. Detection is useful even though rsync copies carefully, because flash media degrade while stored.

### E. The maintenance scrub

#### D-1.2.0-21 — A separate `dr_usb_scrub.sh`; the backup keeps only the quick preflight
- **Decision:** `dr_usb_scrub.sh` always checks the live `/boot` and `/boot/previous` against Unraid's hashes.
  `-backup` also checks the backup: if `remote.ini` exists, the remote mirror; otherwise the local `UNRAID_DR` USB (a user
  has one or the other, so `remote.ini` simply wins). It is read-only and meant for a weekly or monthly schedule.
- **Why:** the daily backup should stay quick; a fuller scheduled check gives early warning while a good copy still exists.
  The backup does not launch the scrub as a process: both use the same `verify_boot_hashes` function, so the backup's
  preflight failures carry the same detail.

#### D-1.2.0-22 — The scrub never compares live to backup; it checks each side on its own terms
- **Decision:** the backup is for disaster recovery, not a perfect sync, so configuration changes since the last backup are
  unavoidable and never reported. The local USB is checked against Unraid's hashes plus its own manifest. The remote mirror
  is compared by an rsync **checksum dry run** (`-rlcn --itemize-changes`) limited to the Unraid-hashed files, which only
  change on an OS upgrade; since live was verified first, a difference means the remote copy is damaged or out of date.
- **Why this works with a write-only key:** in a push, the destination computes its own checksums and sends back only what
  differs; no file contents leave the destination. (Must be confirmed against the real `rrsync`.)

#### D-1.2.0-23 — A failing scrub is loud and specific
- **Decision:** a banner, then for each problem the area (`LIVE /boot`, `BACKUP USB`, `REMOTE MIRROR`), the file, the problem
  and the full expected hash, actual hash and size; what to do for each area; a non-zero exit code; an Unraid alert
  notification; and the same text in `scrub-*.log` (rotated with `SNAPSHOTS` / `RETENTION_DAYS`).
- **Why:** the owner wants to diagnose from the output alone.
- **Known gap:** rsync will not replace a damaged file whose size and date still match, so the advice is to delete the named
  file first (for the remote mirror that needs the destination's administrator). A `-repair` option is parked.

### F. Recovery USB (Ventoy) tooling

#### D-1.2.0-30 — The scrub bypasses the file cache one file at a time
- **Decision:** with `HASH_BYPASS_CACHE=true` (set only by `dr_usb_scrub.sh`), `sha256_of` in `lib/integrity.sh` first runs
  `dd if=<file> iflag=nocache count=0`, which tells the kernel to drop that one file's cached pages, then hashes it. If `dd`
  cannot do this the scrub warns that a clean result may reflect RAM; the backup preflight and the restore are unchanged.
- **Why:** found in the first real-hardware run: the live scrub took 8 s for about 2.3 GB, far faster than a USB stick can
  read, because the create had just read those files and they were in RAM. Hashing RAM cannot detect damage on the flash
  drive, which is the scrub's whole purpose. Unit tests use plain files and could not show this.
- **Verified on the owner's Unraid server:** after the `dd` evict, `sha256sum /boot/bzmodules` (765 MB) took 43 s.
- **Rejected:** writing `3` to `/proc/sys/vm/drop_caches` (first fix, same day) is a hammer: it evicts the cache for
  every file on a large, busy server. `O_DIRECT` reads (FAT support less certain) and remounting `/boot` (risky) were also rejected.
- **Limits:** the remote mirror is hashed by rsync on the destination, so its cache is not touched from here.

#### D-1.2.0-24 — Ventoy and SystemRescue versions come from `setup_ventoy.ini`; upgrades happen in place
- **Decision:** on every run against an existing USB, the installed Ventoy (`Ventoy2Disk.sh -l`) is compared with
  `VENTOY_VERSION` and updated with `-u` (files kept); an older SystemRescue ISO is replaced and the old files removed
  (with confirmation); the script version is compared with `CURRENT_VERSION` (a downgrade is a fatal error) and
  `CURRENT_VERSION` is now always updated. A full wipe (`-I`) is offered only as a default-no fallback if `-u` fails. Ventoy
  is never downgraded.
- **Why:** the old flow upgraded only when the script's version was bumped, and every upgrade wiped the whole USB.
- **`-upgrade` flag:** kept, but deprecated: it prints a notice pointing to the automatic behavior and does nothing else.
  Removing it would break anyone's existing scripts.

#### D-1.2.0-25 — `ventoy.json` follows Ventoy's documented format and is regenerated
- **Decision:** string values (`"30"`), one key per object, `VTOY_DEFAULT_IMAGE` set to the SystemRescue ISO, the ISO name
  injected from the ini, validated after writing; the overwrite prompt defaults to yes and keeps `ventoy.json.bak`.
- **Why:** the menu entry never showed as intended for months. Most likely causes: a stale file was kept by default, a
  numeric timeout, and several keys in one object.

#### D-1.2.0-29 — The Ventoy partition lookup is repeated after the wait
- **Decision:** `find_and_mount_ventoy` runs the `lsblk` lookup again after its 10-second wait.
- **Why:** found in the first real-hardware run: the lookup ran once, before the partition had appeared; the script waited,
  printed debug output that showed the partition, then still aborted because the result variable was never refreshed.
  A longer retry loop was not added; revisit only if a slow partition scan shows up in testing.

#### D-1.2.0-26 — The script version is read from `VERSION`, not hardcoded
- **Decision:** `setup_ventoy_usb.sh` extracts `SCRIPT_VERSION` from the release `VERSION` file with `sed` (the file is
  not sourced) and validates it as `x.y` or `x.y.z`.
- **Why:** one source of truth for the release (D-1.2.0-02).

### G. Testing and working rules

#### D-1.2.0-27 — Working rules agreed with the project owner
- **Ask before implementing anything that was not requested.** Propose, get approval, then build. No extra flags, helpers,
  features or "improvements" on the side; surface ideas as questions instead. (Recorded after a stretch of work where
  unrequested additions were made.)
- **Clear documentation is a first-class deliverable.** Every user-visible change updates the guides, the changelog and
  the manifest.
- **Every claim about a real system is labeled as verified or not.** Things that can only be proven on real hardware (syslinux
  and the MBR, `rrsync` option filtering, `flock`, GNU `find`) are called out for a manual trial rather than assumed.

#### D-1.2.0-28 — Tests use stubs and plain files, and never touch a real device
- **Decision:** `Unit Test/run_tests.sh` runs every `test_*.sh`. Disk tools, `ssh`, `rsync`, `mount` and similar are stubbed
  as shell functions; "devices" are regular files in a temp folder; a safety assertion fails the run if a test device is
  ever outside it. A fake `/boot` (with Unraid-style bare-hash `.sha256` files, in the root and `previous/`) is built by a
  shared helper. `BOOT_DIR` exists in the backup and scrub scripts only so tests can point them at that fake folder.
- **Consequences:** checks that need GNU `find` (log rotation) or `flock` skip themselves on macOS and run on Linux/Unraid.
  Tests found real bugs along the way (the manifest name collisions, a `cmp -n` that only works with GNU `cmp`, padded
  FAT labels, a repeated reap of a child process in the test helper).

### Facts about Unraid that the design relies on

Recorded from the project owner's server and scripts; **re-check them when Unraid changes**.

- Unraid ships a `<file>.sha256` beside `bzfirmware`, `bzimage`, `bzmodules`, `bzroot`, `bzroot-gui` and `memtest`, in `/boot`
  and in `/boot/previous`. Each is a single line holding only the 64-character hash (65 bytes), no filename. `previous/` also
  holds `hardware`, `changes.txt`, `license.txt` and the `make_bootable*` scripts, which have no hash.
- `/boot` is FAT: every file shows as `-rw-------` and mounts without an executable bit, which is why scripts are run as
  `bash script.sh` and the SSH key is staged in RAM.
- The flash root also holds `ldlinux.sys` and `ldlinux.c32` (read-only attribute, written by the syslinux install),
  `syslinux/` (with `syslinux.cfg`, `syslinux_linux`, `mbr.bin`, `make_bootable_linux.sh`), `EFI/` (or `EFI-` when UEFI boot is
  off), `config/`, `config-backup/`, `extra/`, `packages/`, `logs/`, `preclear_reports/`, a root `syslinux.cfg-`, and (on this
  owner's server) a `.git/` folder. The `UNRAID_DR` mirror keeps all of it.
- `EFI-` versus `EFI` is Unraid's UEFI on/off switch. The backup renames the *copy* to `EFI-` so the backup cannot boot by
  accident; the restore (and Unraid's own tool) renames it back.
- `make_bootable_linux` (v1.4): requires `mtools`, a drive labeled `UNRAID` on the **first** partition, asks `Permit UEFI boot
  mode [Y/N]` (Y renames `EFI-` to `EFI`), copies `syslinux/` to `/tmp`, and calls `syslinux/make_bootable_linux.sh`.
  That inner script runs `syslinux_linux -f --install <disk>1` and `dd if=mbr.bin of=<disk>`, then **always exits 0**.
- `syslinux/mbr.bin` is **447 bytes** (boot code, disk-signature area, and the partition-1 active flag at offset 446).
- An Unraid license is tied to the flash drive's GUID. A restored drive is a different drive, so Unraid asks for a key
  replacement, and replacing the key permanently blacklists the old drive.
- Unraid runs everything as root and has no unprivileged accounts.

### Open and parked ideas

Not built, not decided; listed so they are not lost. Each needs the owner's go-ahead.

- A **`-repair`** option so a damaged file in a backup can be re-copied (rsync skips a file whose size and date still match).
- A **shared lock** between the backup and the scrub so they cannot overlap (today the docs only say not to schedule them together).
- **Pull-mode documentation** (destination pulls with a read-only key) and **destination-side snapshot examples**.
- A **UEFI-only restore variant** (skip the syslinux and MBR steps) after trying it on real hardware.
- A **Komodo action** to schedule the backup and the scrub.
- Whether to **remove the deprecated `-upgrade` flag** in a future version.
- Stale wording in the README's description of `dr_usb_create.sh` (it mentions steps that script no longer performs).
- **Real-hardware trials still to do:** the restore on a spare stick (UEFI and, if wanted, legacy BIOS); `rrsync` accepting every
  option the backup and scrub use; the scrub's remote checksum comparison against a real destination.

---

## Version 1.2.1

*Patch release: found in the first real-hardware run of the restore.* The version was bumped (not left at 1.2.0) so that
`setup_ventoy_usb.sh` sees the Ventoy USB's `CURRENT_VERSION` as older and offers the upgrade, which refreshes the copy of
`move_dr_to_unraid.sh` on the recovery USB.

### D. Restore (move_dr_to_unraid.sh)

#### D-1.2.1-01 — The `UNRAID` label is confirmed strictly, read robustly, and retried for about 30 seconds
- **Decision:** `move_dr_to_unraid.sh` reads the label through `get_label()`: `blkid -p -s LABEL -o value` first (probes the
  device itself, no udev cache), then `lsblk -no LABEL`, then `fatlabel` using only its **last** line. `confirm_label()` flushes
  first (`sync`, `blockdev --flushbufs`, `udevadm settle`), reads, and on any miss retries after 2, 4, 8 and 16 seconds
  (`LABEL_RETRY_DELAYS`, about 30s in total, announced on screen). If it still cannot be confirmed, one last check runs:
  after `udevadm trigger` and `settle`, `/dev/disk/by-label/UNRAID` must resolve (`readlink -f`) to **this** partition. If it
  does, the script warns and continues; otherwise the restore fails, rolls back, and prints what each method returned.
  It is used both right after the relabel and in the final verification. `blkid`, `blockdev` and `udevadm` are used when present
  but are not required (they are util-linux/udev tools shipped with SystemRescue); `lsblk` and `fatlabel` remain required.
- **Why:** first real-hardware failure of the restore: everything worked, then verification read the label as
  `There are differences between boot sector and its backup.` and rolled back a good restore. After the syslinux install the FAT
  boot sector no longer matches its backup copy, and `fatlabel` prints that warning on **stdout** (so `2>/dev/null` does not hide
  it) before the label; the old code took the first line. Unraid will not boot a flash drive that is not labelled exactly
  `UNRAID`, so the check must not be skipped or softened, but a quirk of one tool must not stop an emergency restore either.
- **Alternatives rejected:**
  - *Warn and continue when the label is unreadable* - rejected: a wrong or missing label means an unbootable server.
  - *Only `lsblk`* - can return udev's cached (old) label right after a relabel. *Only a text filter on `fatlabel`* - breaks if the
    wording changes.
  - *Rewriting the boot-sector backup (copying sector 0 to sector 6 with `dd`)* to silence the warning - raw writes to a boot
    drive for a cosmetic gain; the warning is harmless (the differences are bytes syslinux patches on purpose).
  - *Accepting any `by-label/UNRAID` link* - rejected: with the old Unraid USB still plugged in it would point at that drive.
  - *Dropping page caches* (as the scrub fix did) - not the cause here: the data read was current; the output was polluted.
- **Not verified on hardware yet:** the 30s backoff and the udev last resort are covered by stubbed tests only; the next real
  restore trial (spare stick) should confirm `blkid -p` reads `UNRAID` straight after the syslinux install.
