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

---

## Features

* **Fully Automated:** 100% non-interactive.
* **Safe:** Will *only* run if it finds exactly one `UNRAID_DR` partition.
* **Robust:** Works when called from the User Scripts GUI or a manual `cron` job.
* **Efficient:** Uses `rsync` to only copy changed files.
* **Logging:** Creates timestamped logs in your configured `LOG_DIR`.
* **Log Rotation:** Automatically cleans up old logs based on your `SNAPSHOTS` and `RETENTION_DAYS` settings.
* **Boot Protection:** Renames the `EFI` directory on the backup to `EFI-` to prevent the server from accidentally booting from it.

---

## Installation & Scheduling

This script is designed to live and run inside the **User Scripts** plugin.

### Step 1: Install the Script

1.  In the Unraid GUI, go to **Settings** > **User Scripts**.
2.  Click **Add New Script**.
3.  Enter the name `DR_USB_Backup` and click **OK**.
4.  Click the script's icon, then click **Edit Script**.
5.  Paste the **full contents** of your `dr_usb_backup.sh` file into the editor.
6.  Click **Save Changes**.

### Step 2: Schedule the Script (2 Options)

You only need to do **one** of these. Option 1 is the easiest and recommended method.

#### Option 1 (Recommended): Use the User Scripts Scheduler

This is the standard Unraid way. It's simple and persists after reboots.

1.  Find the `DR_USB_Backup` script in your list.
2.  Click on the schedule (which defaults to "Schedule Disabled").
3.  Select a schedule, for example: **Daily** at a time when your server is idle (e.g., 3:00 AM).
4.  Click **Apply** at the bottom of the page.

That's it. The script will now run automatically.

#### Option 2 (Advanced): Use a Manual Cron Job

If you prefer to manage your own cron jobs, you can.

1.  First, follow **Step 1** to install the script, but leave its schedule set to **Schedule Disabled**.
2.  You need the path to the script:
    `/boot/config/plugins/user.scripts/scripts/DR_USB_Backup/script`
3.  Add a custom cron job. The modern "Unraid" way to do this is to add a file to `/config/cron.d/`.
4.  Create a new file on your flash drive at `/boot/config/cron.d/dr_backup`
5.  Add your cron line to that file:

    ```bash
    # Run the DR USB Backup script every day at 3:00 AM
    0 3 * * * /boot/config/plugins/user.scripts/scripts/DR_USB_Backup/script
    ```

6.  Reboot your server (or run `update-cron` from SSH) to apply the new cron file.

---

## Testing Flags

These flags are for development and testing. You can run them from SSH:

```bash
# Example of running from SSH with debug mode
/boot/config/plugins/user.scripts/scripts/DR_USB_Backup/script -debug
-debug: Enables verbose logging. Prints extra "DEBUG:" lines to the log file to help trace the script's logic.

-lsblk: Forces the script to use a local file named test-lsblk in the same directory, instead of running the real lsblk command.

FAQ
Q: The log says "No 'UNRAID_DR' backup partition was found!"

A: You have not run the dr_usb_create.sh script yet. You must run that script once from SSH to set up your backup drive.

Q: The log says "Multiple partitions with the label 'UNRAID_DR' found."

A: This is a safety stop. The script found two or more drives with the UNRAID_DR label and doesn't know which one to back up to. Unplug one, or use lsblk -f to find them and rename the label on the incorrect one.

Q: Can I run this script manually from SSH?

A: Yes. Unlike the _create script, this one is non-interactive and will work perfectly when run from SSH or the GUI.

Q: How do I test if it's working?

A: Go to the User Scripts page and click Run in Background. After a minute, check your LOG_DIR (e.g., /boot/logs/unraid-dr/logs/). You should see a new log file with the details of the successful backup.