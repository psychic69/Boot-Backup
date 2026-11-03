# Unraid DR USB Setup (dr_usb_create.sh)

This document covers the **one-time, interactive** setup script used to create and format your `UNRAID_DR` backup drive.

---

## 🛑 Critical Warning

**DO NOT RUN THIS SCRIPT FROM THE UNRAID GUI.**

This script is **interactive**. It will prompt you to select a drive and confirm formatting. If you run it from the User Scripts plugin GUI or on a schedule, it will hang indefinitely, waiting for input you cannot provide.

You **MUST** run this script from an **SSH terminal**.

---

## Features

* **Interactive:** Guides you through selecting a suitable USB drive.
* **Works with new or used USB drives:** Lists every USB drive, including blank ones with no partitions or label. Drives that already contain data are marked with `*` and their existing partitions, filesystems and labels are listed so you can recognize them.
* **Safe:** Your `UNRAID` boot drive, your Ventoy recovery USB, and any drive with a mounted partition are shown under "Not available" with the reason, and cannot be selected (the script also re-checks right before formatting). Drives that are too small are listed there too, with the minimum size needed.
* **Smart Formatting:** Wipes, partitions, and formats the selected drive as FAT32 with the required `UNRAID_DR` label.
* **Size Aware:** If a drive is > 64GB, it creates a 64GB partition to ensure compatibility.
* **First Backup:** Automatically runs the first backup (`clone_backup`) after formatting is complete.
* **Runs on the Unraid server only:** The backup USB must be created on the Unraid server whose boot drive it protects. The script stops with a clear message on any other machine, and `-remote` (a `dr_usb_backup.sh` option) is rejected with an explanation. The `-lsblk` test mode skips the check because it never changes a drive.
* **Checks your Unraid files first:** Before the first backup is copied, every boot file in `/boot` and `/boot/previous` is verified against the `.sha256` file Unraid ships with it. If anything is damaged the script stops without copying. A manifest of `config/` and the other small files (`DR_MANIFEST.sums`) is written onto the new backup USB for the emergency restore to check.
* **Failsafe:** If an `UNRAID_DR` drive is *already* found, this script will exit with an error, protecting your existing backup.

---

## Installation & Usage

This script is interactive, so you run it from an SSH terminal on the Unraid server. You will **never** run it from the User Scripts plugin or the GUI.

### Step 1: Install the Release

The scripts, shared modules and settings templates ship as one release archive. On the Unraid server (SSH, as root), download it from the [Releases page](https://github.com/psychic69/Boot-Backup/releases), verify it, and extract it (use the current version number in place of `1.2.0`):

```bash
cd /tmp
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz
wget https://github.com/psychic69/Boot-Backup/releases/download/v1.2.0/Boot-Backup-1.2.0.tar.gz.sha256
sha256sum -c Boot-Backup-1.2.0.tar.gz.sha256        # must print: Boot-Backup-1.2.0.tar.gz: OK
tar -xzf Boot-Backup-1.2.0.tar.gz -C /boot/config/plugins/ --no-same-owner --no-same-permissions
```

This creates `/boot/config/plugins/dr_usb/`. If you already installed the release for the backup script, you already have everything. Settings (log folder, retention, mount point) are optional and live in `dr_usb.ini`; see the settings table in the [backup guide](dr_usb_backup.md#step-1-install-the-release).

### Step 2: Run from SSH (One Time Only)

1.  Connect to your Unraid server via **SSH** (this must be the server whose boot drive you want to protect).
2.  Run the script:

    ```bash
    bash /boot/config/plugins/dr_usb/dr_usb_create.sh
    ```

3.  Follow the interactive prompts to select and format your drive. After it finishes, your backup drive is ready; next, schedule `dr_usb_backup.sh` (see the [backup guide](dr_usb_backup.md)).

### Log File

Each run writes a small log to `LOG_DIR/logs/usb-create-DATE_TIME.log` (default `/boot/logs/unraid-dr/logs/`). When a new run starts, earlier create logs that finished successfully are deleted, so you normally keep just the latest one; logs from runs that ended with errors are kept for diagnosis. These logs are separate from the daily backup logs (`boot-check-*.log`) and are not rotated with them.

---

## Testing Flags

These flags are for development and testing. You can run them from SSH:

```bash
# Example of running with debug mode (the full menu and prompts run, but no drive is changed)
bash /boot/config/plugins/dr_usb/dr_usb_create.sh -debug

-debug: Enables verbose logging. Prints extra "DEBUG:" lines to the log file to help trace the script's logic.
-lsblk: Forces the script to use a local file named test-lsblk in the current directory, instead of running the real lsblk command. This is for synthetic testing and never changes a drive.

FAQ
Q: Why can't I run this from the GUI?

A: The script uses the read command to ask you questions. The GUI window has no way to send your answers to the script.

Q: It says "An 'UNRAID_DR' partition was already found!"

A: This is a safety feature. It means your backup drive is already set up. You should now use the dr_usb_backup.sh script for your daily backups.

Q: It can't find my USB drive!

A: The script lists every USB drive, blank or used. Look under "Not available (cannot be selected)" at the end of the list: it shows each skipped drive and why. The usual reasons are that the drive is smaller than 95% of your main Unraid flash drive (the message shows the minimum size), it is your Unraid boot drive or Ventoy recovery USB, or one of its partitions is mounted (unmount it and run the script again). A `*` next to a selectable drive just means it already has data on it, which will be erased.