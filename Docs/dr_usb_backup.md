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

This creates `/boot/config/plugins/dr_usb/` containing `dr_usb_backup.sh`, `dr_usb_create.sh`, `lib/`, `Recovery-ISO/` and the `*.ini.example` templates. To **upgrade**, repeat the same commands with the new version: your own files (`dr_usb.ini`, `remote.ini`, SSH keys) are not in the archive, so they are never overwritten.

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
| `REMOTE_INI` | `remote.ini` beside the scripts | Location of the remote backup settings (`-remote` only) |

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

## Remote Backup (`-remote`)

By default the script clones `/boot` to the local `UNRAID_DR` USB. With `-remote` it instead makes a
**1:1 mirror of `/boot` on another server** over SSH, using rsync with `--delete-after`. The remote copy
always matches the running USB, including `previous/`; there are no snapshots. Without `-remote`,
behavior is unchanged, and `-remote` does not use the `UNRAID_DR` USB at all.

**The destination must restrict the key with `rrsync`.** This is a requirement, not an option: it is what
keeps a compromised Unraid server from becoming a way into your other server (see
[Security model](#security-model-of-the-remote-backup)). The script checks this on every run and refuses to
continue if the key can run ordinary commands.

### Requirements

| Where | Needs |
|-------|-------|
| Unraid server | `rsync`, `ssh`, `ssh-keygen`, `ssh-keyscan`, `flock` (all included with Unraid) |
| Destination server | Linux with `sshd`, `rsync` and **`rrsync`** (see below), reachable from the Unraid server |
| Destination server | A dedicated unprivileged user that has a normal login shell (not `nologin`: sshd runs the forced `rrsync` command through the shell) and a backup folder it can write to |

**About `rrsync`:** it is a small helper that ships with rsync and limits what a key can do. Check it on
the destination with `rrsync -h`: it must list the `-wo` (write-only) option. Where the file lives varies
by distribution (`/usr/bin/rrsync`, or `/usr/share/doc/rsync/scripts/rrsync`); newer versions are Python
scripts and need `python3`. In `authorized_keys` use the full path if `rrsync` is not on the user's `PATH`.

### Files and where they go

| File | Location on Unraid | Purpose |
|------|--------------------|---------|
| `dr_usb_backup.sh` + `lib/` | `/boot/config/plugins/dr_usb/` | The script and its shared modules (installed from the release archive) |
| `remote.ini` | `/boot/config/plugins/dr_usb/remote.ini` | Your remote settings (copy of `remote.ini.example`) |
| `id_ed25519` | `/boot/config/plugins/dr_usb/id_ed25519` | Private key used to log in to the destination |
| `known_hosts` | `/boot/config/plugins/dr_usb/known_hosts` | Pinned host key of the destination |

Everything lives on the flash drive so it survives reboots. The `remote.ini` location is set by the
`REMOTE_INI` setting in `dr_usb.ini` if you want it elsewhere.

### `remote.ini` variable reference

`remote.ini` is a plain shell variable file (`NAME="value"`). Values must not contain spaces or shell
special characters (except `RSYNC_EXCLUDES`, which is a space-separated list of patterns).

| Variable | Required | Default | Description / rules |
|----------|----------|---------|---------------------|
| `REMOTE_HOST` | Yes | – | Hostname or IPv4 address of the destination (letters, digits, `.`, `_`, `-`). IPv6 is not supported. |
| `REMOTE_PORT` | No | `22` | SSH port, 1–65535. |
| `REMOTE_USER` | Yes | – | The dedicated account on the destination. Never `root`. |
| `SSH_KEY_FILE` | Yes | – | Path to the private key on the Unraid server. Must exist, be readable, and have no passphrase. |
| `SSH_KNOWN_HOSTS` | Yes | – | Path to the file holding the destination's pinned host key. Must exist and not be empty. |
| `SSH_CONNECT_TIMEOUT` | No | `15` | Seconds to wait when connecting. |
| `RSYNC_TIMEOUT` | No | `120` | rsync aborts if no data moves for this many seconds. |
| `RSYNC_BWLIMIT_KBPS` | No | `0` | Bandwidth limit in KB/s; `0` means unlimited. |
| `RSYNC_EXCLUDES` | No | *(empty)* | Space-separated rsync patterns to skip, e.g. `"/logs/"`. Empty gives a true 1:1 copy, including this script's own logs. |
| `NOTIFY_ON_FAILURE` | No | `true` | `true` or `false`. Sends an Unraid GUI notification when the remote backup fails. |

There is **no folder setting**: the folder that receives the mirror is fixed on the destination by the
`rrsync` command in `authorized_keys` (step 4). An old `REMOTE_DIR` line is ignored with a warning.
If any value is invalid, the script logs each problem and exits without contacting the destination.

### Step-by-step setup

**1. Install the release and create `remote.ini` (Unraid, as root)**

Install the release as described under [Installation](#step-1-install-the-release), then:

```bash
cd /boot/config/plugins/dr_usb
cp remote.ini.example remote.ini
```

Edit `remote.ini` and set at least `REMOTE_HOST` and `REMOTE_USER`.

**2. Create the SSH key (Unraid, as root)**

```bash
ssh-keygen -t ed25519 -N "" -C "unraid-dr-backup" -f /boot/config/plugins/dr_usb/id_ed25519
cat /boot/config/plugins/dr_usb/id_ed25519.pub
```

The key has no passphrase because the backup runs unattended. Copy the single line printed by `cat`;
you need it in step 4.

**3. Create the user and the backup folder (destination, with sudo)**

The commands below are for Debian/Ubuntu; adjust for your distribution.

```bash
sudo apt install rsync                                   # provides rrsync
rrsync -h | head -20                                     # confirm the -wo option exists
sudo adduser --disabled-password --gecos "" unraidbackup
sudo mkdir -p /srv/backups/unraid-boot
sudo chown unraidbackup:unraidbackup /srv/backups/unraid-boot
```

`--disabled-password` blocks password logins but still allows the key. Use the same user name as in
`remote.ini`. **Create the backup folder yourself**, now: the restricted key cannot create it.

**4. Authorize the key, locked to rrsync (destination, with sudo)**

Replace `UNRAID_IP` with the Unraid server's IP address, and paste your public key line from step 2:

```bash
sudo install -d -m 700 -o unraidbackup -g unraidbackup /home/unraidbackup/.ssh
echo 'restrict,from="UNRAID_IP",command="rrsync -wo /srv/backups/unraid-boot" ssh-ed25519 AAAA...your-key... unraid-dr-backup' \
  | sudo tee -a /home/unraidbackup/.ssh/authorized_keys
sudo chown unraidbackup:unraidbackup /home/unraidbackup/.ssh/authorized_keys
sudo chmod 600 /home/unraidbackup/.ssh/authorized_keys
```

What each part does:
- `restrict` turns off terminals, port forwarding, agent forwarding and X11 for this key.
- `from="UNRAID_IP"` makes the destination refuse this key from any other address.
- `command="rrsync -wo /srv/backups/unraid-boot"` means that whatever the client asks for, only rsync
  runs, only inside that one folder, and **write-only**: the key can send and delete files there but can
  never read anything back. There is no shell.

**5. Pin the destination's host key (Unraid, as root)**

```bash
ssh-keyscan -p 22 backup.lan > /boot/config/plugins/dr_usb/known_hosts
ssh-keygen -lf /boot/config/plugins/dr_usb/known_hosts
```

Use the exact value of `REMOTE_HOST` (and your `REMOTE_PORT`) in the `ssh-keyscan` command; ssh matches
the name as written. Then **verify** that one of the fingerprints printed equals the destination's own. Run
this on the destination and compare:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

This check is what protects you from a man-in-the-middle; the script will refuse to connect to any host
whose key does not match `known_hosts`.

**6. Test with a dry run (Unraid)**

```bash
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote -debug
```

`-debug` runs rsync with `--dry-run`, so nothing is copied or deleted. Check the log (see below) for:
- `Boot file hashes OK` (the source check, see below)
- `Destination OK: writable, and the key is restricted to rrsync.`
- a list of files rsync would transfer

If rrsync rejects any rsync option the script uses, the error appears here, so do this step before the
first real run.

**7. Run the first real mirror**

```bash
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote
```

### What the script checks before it sends anything

Every `-remote` run, in this order, and it stops at the first failure:

1. **`/boot` is mounted** and contains `config/` and `bzroot`.
2. **The source boot files are intact.** Every file in `/boot` and in `/boot/previous` that has a `.sha256`
   file from Unraid (`bzimage`, `bzroot`, `bzmodules`, `bzfirmware`, `bzroot-gui`, `memtest`) is hashed and
   compared with it. **A mismatch is a hard stop:** nothing is sent, so a damaged flash drive can never overwrite
   your good remote copy. (The same check runs before every backup to the local `UNRAID_DR` USB.) This reads
   roughly 2–3 GB, so it takes a minute or two per run.
3. **The destination accepts a small test file** (proves the key, host key, `rrsync` and the folder all work).
4. **The key cannot run ordinary commands.** The script tries to run a harmless command with the key; if that
   *succeeds*, the key is not restricted and the script refuses to continue.

### Scheduling the remote backup

Run `bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote` as root on the Unraid server, from any
scheduler: a cron line, a Komodo action, or the User Scripts plugin. The plugin cannot pass flags and the FAT
flash drive cannot hold an executable bit, so with User Scripts create a **second** script (leave your
existing `DR_USB_Backup` alone if you also use the local USB backup) whose entire body is:

```bash
#!/bin/bash
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -remote
```

### Logs

Each run writes a log to `LOG_DIR/logs/` (default `/boot/logs/unraid-dr/logs/boot-check-DATE_TIME.log`).
The log says `Mode: REMOTE` and ends with either `script completed.` or
`script finished WITH ERRORS (exit N)`. The script's exit code is non-zero on failure, so a scheduler can alert on it.

### Security model of the remote backup

- **Everything on the Unraid side runs as root.** Unraid has no unprivileged accounts, so the scripts, the key
  and the settings all sit with root.
- **The destination key is deliberately weak.** With the `authorized_keys` line from step 4, someone who steals
  the key (or controls the Unraid server) gets no shell on the destination, cannot read your backups, cannot
  reach anything outside the one folder, and cannot use the key from another address. The script enforces this
  by refusing to run when the key can run ordinary commands.
- **What a compromised Unraid can still do:** overwrite or delete the contents of the backup folder, because
  the mirror needs to write and delete there. Protect against that **on the destination**, where the Unraid key
  cannot reach:
  - take snapshots of the folder (ZFS/btrfs/LVM snapshots, or a cron job that hard-link-copies it), so a bad
    mirror can be rolled back;
  - firewall the destination so SSH is accepted only from the Unraid server, and give the destination no
    credentials for Unraid.
- **The private key sits on the flash drive without a passphrase.** If you export the `flash` share over SMB,
  anyone with access to that share can read it. Keep that share private.
- **`/boot` contains your Unraid license key and password hashes**, so the destination must be a machine you
  trust, ideally with an encrypted disk.

### Troubleshooting

| Log message | Cause / fix |
|-------------|-------------|
| `Remote config file not found` | `remote.ini` is not at `REMOTE_INI`. Copy `remote.ini.example` to that path. |
| `... is missing or invalid` | A `remote.ini` value broke a rule in the table above; the message names the variable. |
| `SSH_KNOWN_HOSTS is missing or empty` | Run the `ssh-keyscan` command in step 5. |
| `is not a valid private key` | `SSH_KEY_FILE` is wrong, corrupted, or has a passphrase. Regenerate with `-N ""`. |
| `SOURCE /boot FAILED THE HASH CHECK` | A boot file on the Unraid flash drive does not match its `.sha256` (or is missing). Nothing was sent. The log names the file. If an Unraid update was running at that moment, simply run again. Otherwise your flash drive may be failing: back it up another way and replace it. |
| `Could not reach or write to the destination` | The log shows rsync's own message. Check the host, port, key, `SSH_KNOWN_HOSTS`, the `rrsync` line in `authorized_keys` (path, `from=` address), and that the backup folder exists and is writable by the user. |
| `SECURITY CHECK FAILED ... can run arbitrary commands` | The key is not restricted. Fix the `authorized_keys` line as in step 4. |
| `Another remote backup is already running` | A previous run is still active (or hung). Wait for it or check running `rsync` processes. |
| `/boot is not mounted or is missing config/ or bzroot` | Safety stop. Do not proceed until `/boot` is healthy. |
| `Remote mirror FAILED (rsync exit code N)` | See the `rsync:` lines just above it in the log. An `rrsync` that rejects an option shows up here. |

To test SSH by hand, copy the key to RAM first (ssh rejects keys on the FAT drive). A restricted key will
refuse the command, which is the correct result:

```bash
cp /boot/config/plugins/dr_usb/id_ed25519 /dev/shm/k && chmod 600 /dev/shm/k
ssh -i /dev/shm/k -o UserKnownHostsFile=/boot/config/plugins/dr_usb/known_hosts unraidbackup@backup.lan true
rm -f /dev/shm/k
```

### Restoring from the remote mirror

Because the backup key is write-only, you restore using an **administrator account on the destination
machine** (not the backup key): copy the contents of the backup folder onto a freshly prepared Unraid flash
drive (FAT32, label `UNRAID`), then run the `make_bootable` script that came with the copied files, as in
Unraid's standard procedure for a flash drive. Unlike the local `UNRAID_DR` clone, the remote mirror keeps
`EFI` exactly as it is on the running USB. Note that an Unraid license is tied to the original flash drive's
GUID, so restoring onto a different drive requires Unraid's license replacement process (see the Unraid
documentation).

---

## Testing Flags

These flags are for development and testing. You can run them from SSH:

```bash
# Example of running from SSH with debug mode
bash /boot/config/plugins/dr_usb/dr_usb_backup.sh -debug
-remote: Mirror /boot to the server in remote.ini instead of the local UNRAID_DR USB.

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