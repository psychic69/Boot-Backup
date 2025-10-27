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
* **Safe:** Actively scans for and ignores your primary `UNRAID` boot drive.
* **Smart Formatting:** Wipes, partitions, and formats the selected drive as FAT32 with the required `UNRAID_DR` label.
* **Size Aware:** If a drive is > 64GB, it creates a 64GB partition to ensure compatibility.
* **First Backup:** Automatically runs the first backup (`clone_backup`) after formatting is complete.
* **Failsafe:** If an `UNRAID_DR` drive is *already* found, this script will exit with an error, protecting your existing backup.

---

## Installation & Usage

It's recommended to add this script to the User Scripts plugin for easy management, but you will **never** run it from the GUI.

### Step 1: Install the Script

1.  In the Unraid GUI, go to **Settings** > **User Scripts**.
2.  Click **Add New Script**.
3.  Enter the name `DR_USB_Create` and click **OK**.
4.  Click the script's icon, then click **Edit Script**.
5.  Paste the **full contents** of your `dr_usb_create.sh` file into the editor.
6.  Click **Save Changes**.

### Step 2: Set Schedule to Disabled

1.  Find the `DR_USB_Create` script in your list.
2.  Set its schedule to **Schedule Disabled**. This is critical.

### Step 3: Run from SSH (One Time Only)

1.  Connect to your Unraid server via **SSH**.
2.  Find the path to your script. It will be:
    `/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script`
3.  Run the script by pasting that full path into your terminal and pressing Enter:

    ```bash
    /boot/config/plugins/user.scripts/scripts/DR_USB_Create/script
    ```

4.  Follow the interactive prompts to select and format your drive. After it finishes, your backup drive is ready.

---

## Testing Flags

These flags are for development and testing. You can run them from SSH:

```bash
# Example of running with debug mode
/boot/config/plugins/user.scripts/scripts/DR_USB_Create/script -debug

-debug: Enables verbose logging. Prints extra "DEBUG:" lines to the log file to help trace the script's logic.
-lsblk: Forces the script to use a local file named test-lsblk in the same directory, instead of running the real lsblk command. This is for synthetic testing.

FAQ
Q: Why can't I run this from the GUI?

A: The script uses the read command to ask you questions. The GUI window has no way to send your answers to the script.

Q: It says "An 'UNRAID_DR' partition was already found!"

A: This is a safety feature. It means your backup drive is already set up. You should now use the dr_usb_backup.sh script for your daily backups.

Q: It can't find my USB drive!

A: The script looks for USB drives that are at least 95% the size of your main Unraid flash drive and already have a label. If it's a brand new drive, you may need to format it once (with any label) so that it appears in the list.