# Unraid DR USB Backup (dr_usb_backup.sh)

This document covers the **non-interactive, automated** backup script that you can schedule to run daily.

---

## Purpose

This is the script you will "set and forget." It is designed to be run automatically in the background by the Unraid User Scripts plugin or a `cron` job.

It will **not** ask any questions. Its logic is simple:
1.  Find the `UNRAID` boot drive.
2.  Find the *one* `UNRAID_DR` backup drive.
3.  If it finds exactly one, it mounts it, runs `rsync`, and unmounts it.
4.  If it finds zero or more than one `UNRAID_DR` drive, it will log a clear error and exit.

> ⚠️ **License slots:** Unraid counts every attached storage device against your license's device limit when it boots and starts the array, and the `UNRAID_DR` USB counts as one. Check how many slots your license has left. If there is no spare slot, the array will not start after a reboot while the `UNRAID_DR` USB is plugged in, so **remove it before you reboot** (you can plug it back in once the array is running).

---

## Features

* **Fully Automated:** 100% non-interactive.
* **Safe:** Will *only* run if it finds exactly one `UNRAID_DR` partition.
* **Robust:** Works when called from the User Scripts GUI or a manual `cron` job.
* **Efficient:** Uses `rsync` to only copy changed files.
* **Logging:** Creates timestamped logs in your configured `LOG_DIR` (default `/boot/logs/unraid-dr`; set in `dr_usb.ini`).
* **Log Rotation:** Automatically cleans up old logs based on your `SNAPSHOTS` and `RETENTION_DAYS` settings (in `dr_usb.ini`).
* **Boot Protection:** Renames the `EFI` directory on the backup to `EFI-` to prevent the server from accidentally booting from it.
* **Source Integrity Check:** Before copying anything, every Unraid boot file in `/boot` and `/boot/previous` is checked against the `.sha256` file Unraid ships with it. A mismatch is a **hard stop**: nothing is copied, so a damaged flash drive can never overwrite your good backup. This reads roughly 2-3 GB, so each run takes a minute or two longer.
* **Backup Manifest:** After each local backup, `DR_MANIFEST.sums` (SHA-256 hashes of `config/`, `syslinux/`, the `EFI-` folder and the other small files) is written onto the `UNRAID_DR` USB. The emergency restore script checks it, together with Unraid's own hashes, before it turns the USB into your boot drive.
* **Deeper checks are a separate job:** the backup only runs this quick preflight. For a regular, fuller check of both your running drive and your backup, schedule the maintenance scrub (see [dr_usb_scrub.md](dr_usb_scrub.md)).

---

## Installation & Scheduling

The scripts, their shared modules (`lib/`) and the settings templates are distributed as **one release archive**. You extract it onto the flash drive and run the scripts from there; the User Scripts plugin only calls them. (Do not paste the script into the plugin: it needs the `lib/` folder next to it.)

### Step 1: Install the Release

On the Unraid server (SSH, as root), download the release from the [Releases page](https://github.com/psychic69/Boot-Backup/releases), verify it, and extract it. Use the current version number in place of `1.2.0`:

```bash
cd /tmp
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz.sha256
sha256sum -c Boot-Backup-1.2.0.tar.gz.sha256        # must print: Boot-Backup-1.2.0.tar.gz: OK
tar -xzf Boot-Backup-1.2.0.tar.gz -C /boot/config/plugins/ --no-same-owner --no-same-permissions
```

This creates `/boot/config/plugins/dr_usb/` containing `dr_usb_backup.sh`, `dr_usb_create.sh`, `lib/`, `Recovery-ISO/` and the `*.ini.example` templates. To **upgrade**, repeat the same commands with the new version: your own file (`dr_usb.ini`) is not in the archive, so they are never overwritten.

**Optional settings:** the built-in defaults work as-is. To change anything, copy the template and edit it:

```bash
cd /boot/config/plugins/dr_usb
cp dr_usb.ini.example dr_usb.ini
```

| Setting (`dr_usb.ini`) | Default | Meaning |
|------------------------|---------|---------|
| `LOG_DIR` | `/boot/logs/unraid-dr` | Where logs are written (a `logs` folder is created inside it) |
| `SNAPSHOTS` | `10` | Number of backup logs to keep (>= 1) |
| `RETENTION_DAYS` | `30` | Days to keep backup logs (>= 1) |
| `CLONE_MP` | `/mnt/disks/usb-backup-temp` | Temporary mount point for the `UNRAID_DR` USB |
| `NOTIFY_ON_FAILURE` | `true` | `true` or `false`. Sends an Unraid GUI notification when a backup (or scrub) fails |

The same `dr_usb.ini` is used by `dr_usb_create.sh` and `dr_usb_backup.sh`.

### Step 2: Schedule the Script (2 Options)

You only need to do **one** of these. Option 1 is the easiest and recommended method.

#### Option 1 (Recommended): Use the User Scripts Scheduler

This is the standard Unraid way. It's simple and persists after reboots.

1.  In the Unraid GUI, go to **Settings** > **User Scripts** and click **Add New Script**.
2.  Enter the name `DR_USB_Backup` and click **OK**.
3.  Click the script's icon, then **Edit Script**, and replace the contents with just these two lines:

    ```bash
    #!/bin/bash
    bash /boot/config/plugins/dr_usb/dr_usb_backup.sh
    ```

4.  Click **Save Changes**.
5.  Click on the schedule (which defaults to "Schedule Disabled") and select a schedule, for example **Daily** at a time when your server is idle (e.g., 3:00 AM).
6.  Click **Apply** at the bottom of the page.

That's it. The script will now run automatically.

#### Option 2 (Advanced): Use a Manual Cron Job

If you prefer to manage your own cron jobs, you can.

1.  Follow **Step 1** to install the release (no User Script is needed).
2.  Create a new file on your flash drive at `/boot/config/cron.d/dr_backup` (the modern Unraid way to add cron jobs).
3.  Add your cron line to that file:

    ```bash
    # Run the DR USB Backup script every day at 3:00 AM
    0 3 * * * bash /boot/config/plugins/dr_usb/dr_usb_backup.sh
    ```

4.  Reboot your server (or run `update-cron` from SSH) to apply the new cron file.

---

## Testing Flags

These flags are for development and testing. You can run them from SSH:

```bash
# Example of running from SSH with debug mode
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -debug
-debug: Enables verbose logging. Prints extra "DEBUG:" lines to the log file to help trace the script's logic.

-lsblk: Forces the script to use a local file named test-lsblk in the current directory, instead of running the real lsblk command. Used by the test suite in "Unit Test/".

FAQ
Q: The log says "No 'UNRAID_DR' backup partition was found!"

A: You have not run the dr_usb_create.sh script yet. You must run that script once from SSH to set up your backup drive.

Q: The log says "Multiple partitions with the label 'UNRAID_DR' found."

A: This is a safety stop. The script found two or more drives with the UNRAID_DR label and doesn't know which one to back up to. Unplug one, or use lsblk -f to find them and rename the label on the incorrect one.

Q: Can I run this script manually from SSH?

A: Yes. Unlike the _create script, this one is non-interactive and will work perfectly when run from SSH or the GUI.

Q: How do I test if it's working?

A: Go to the User Scripts page and click Run in Background. After a minute, check your LOG_DIR (e.g., /boot/logs/unraid-dr/logs/). You should see a new log file with the details of the successful backup.