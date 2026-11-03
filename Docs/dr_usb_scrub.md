# Unraid DR Scrub (dr_usb_scrub.sh)

A maintenance check that looks for **silent damage** to your Unraid boot files, on the running flash
drive and on your backup. Schedule it separately from the daily backup (weekly or monthly).

---

## Why it exists

Flash drives wear out and can corrupt files without any error. The backup script already checks your
running `/boot` before every backup and refuses to copy damaged files, but that only protects the backup
at the moment it runs. The scrub gives you a regular, deeper check of **both** sides, and tells you
exactly what is wrong while you still have a good copy.

The backup is for disaster recovery, not a perfect sync. Changes you made to your configuration since the
last backup are **expected**, and the scrub never reports them. It reports only damaged or missing boot
files (and, for the local backup USB, damage to its own config files).

---

## What it checks

| Run | What is checked |
|-----|-----------------|
| `dr_usb_scrub.sh` | **Always:** the live Unraid flash drive. Every file in `/boot` and `/boot/previous` that has a `.sha256` file from Unraid (`bzimage`, `bzroot`, `bzmodules`, `bzfirmware`, `bzroot-gui`, `memtest`) is hashed and compared with it. |
| `dr_usb_scrub.sh -backup` | The live drive **and** your backup. Which backup is decided by `remote.ini`: if it exists, the **remote mirror**; if not, the **local `UNRAID_DR` USB**. (You are expected to use one or the other.) |

**Local `UNRAID_DR` USB:** the USB is mounted read-only and its root and `previous/` are checked against
Unraid's `.sha256` files, then everything else against `DR_MANIFEST.sums` (the manifest `dr_usb_backup.sh`
writes). These are the same checks the emergency restore script makes, so a clean scrub means the restore will
not warn you. A backup made before the manifest existed gets a warning instead of a failure.

**Remote mirror:** your backup key is write-only, so the script cannot download the mirror. Instead it asks
the destination to compare checksums of the Unraid-hashed files against your (just verified) live drive, using
an rsync dry run that changes nothing. Only the names of files that differ come back. Anything that differs
means the remote copy is damaged, missing, or out of date (for example, you upgraded Unraid since the last
backup: run the backup, then scrub again).

---

## Usage

```bash
# Live drive only
bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh

# Live drive + your backup (remote if remote.ini exists, otherwise the local UNRAID_DR USB)
bash /boot/config/plugins/dr_usb/dr_usb_scrub.sh -backup
```

Options: `-backup`, `-debug` (extra log detail), and `-lsblk` (testing only, reads a sample drive list).
Run it as root on the Unraid server, from cron, a Komodo action, or the User Scripts plugin
(a wrapper script whose body is the command above; the plugin cannot pass flags on its own).

**Cost:** a full scrub reads roughly 2-3 GB from each side that is checked (the destination reads its own
copy for the remote check), so it takes a few minutes. Weekly or monthly is plenty.

**Do not run it at the same time as a backup.** A backup that is writing files can make the scrub see
half-written files.

---

## Reading the result

A clean run ends with:

```
SCRUB CLEAN - no problems found.
```

If anything is wrong, the script prints a loud banner and **everything needed for diagnosis**:

```
################################################################################
##  SCRUB FAILED - 2 PROBLEM(S) FOUND
################################################################################
[LIVE /boot]  previous/bzmodules
    problem : HASH MISMATCH
    expected: a960a948b56ad2e01b007a48980dba186c628d3a4cba89f179beddc0fdee68a1
    actual  : 3c1f...                       (full hash)
    size    : 812216320 bytes
[BACKUP USB]  config/Pro.key
    problem : DOES NOT MATCH THE MANIFEST
    ...
################################################################################
WHAT TO DO:
 - LIVE /boot: your RUNNING Unraid flash drive has damaged or missing boot files. ...
```

Each problem names the **area** (`LIVE /boot`, `BACKUP USB` or `REMOTE MIRROR`), the **file**, **what is
wrong**, and for hash problems the **expected hash, the actual hash and the file size**. The script exits
with a non-zero code and sends an Unraid alert notification (unless disabled), so a scheduler can alert you.
The full text is also saved in the log.

### What to do about each area

| Area | Meaning | Action |
|------|---------|--------|
| `LIVE /boot` | Your **running** flash drive has damaged or missing boot files. The backup scripts will refuse to run, so your good backup is safe. | Copy `/boot` somewhere safe now, then replace or re-image the flash drive from your last good backup. |
| `BACKUP USB` | The `UNRAID_DR` copy is damaged or incomplete and may not restore properly. | If the live drive is fine, delete the named file(s) from the backup USB (or re-run `dr_usb_create.sh`) and run `dr_usb_backup.sh`. rsync does not replace a damaged file whose size and date still match, so the file must be removed first. |
| `REMOTE MIRROR` | The remote copy differs from your verified live drive. | If you recently upgraded Unraid, run the backup and scrub again. Otherwise ask the destination's administrator to delete the named file(s) from the backup folder (the backup key cannot), then run the backup. |

---

## Logs

Each run writes `scrub-DATE_TIME.log` to `LOG_DIR/logs/` (default `/boot/logs/unraid-dr/logs/`), rotated with
the same `SNAPSHOTS` and `RETENTION_DAYS` settings as the backup logs (set in `dr_usb.ini`).

---

## FAQ

**Q: The scrub says my live drive is fine but the backup differs. Is my backup bad?**
A: Only if the named file is a boot file or (for the local USB) a config file that no longer matches its own
manifest. Differences in your configuration since the last backup are never reported.

**Q: "Expected exactly one USB drive labelled UNRAID_DR, found 0."**
A: With `-backup` and no `remote.ini`, the script looks for the local backup USB. Plug it in, or, if you use a
remote backup, check that `remote.ini` is in `/boot/config/plugins/dr_usb/`.

**Q: "THE CHECKSUM COMPARISON COULD NOT RUN" on the remote mirror.**
A: The destination's `rrsync` may be rejecting one of the options the check uses (`-c`, `-n`, `--itemize-changes`,
`--include`/`--exclude`). The log shows rsync's own message. Do the dry run described in the
[remote backup guide](dr_usb_backup.md#remote-backup--remote) first.
