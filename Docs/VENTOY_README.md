# Unraid USB Recovery Prep- Ventoy Solution

## Quick Start

**You only need:**
1. `setup_ventoy_usb.sh` - The setup script
2. `move_dr_to_unraid.sh` - The recovery script

**No other files needed!** The script creates everything else automatically.

## Setup (Run from Unraid)

# Install the release first (see the Installation section of dr_usb_backup.md), then run setup
# (it will auto-create ventoy.json). The script finds the release VERSION file two folders above itself.
bash /boot/config/plugins/dr_usb/Recovery-ISO/scripts/setup_ventoy_usb.sh


The script will:
- ✅ Find your Ventoy USB automatically
- ✅ Download SystemRescue ISO with SHA512 verification
- ✅ Copy recovery script to USB
- ✅ Auto-create ventoy.json with proper settings
- ✅ Create user instructions

## What Gets Created on the Ventoy drive

```
Ventoy USB/
├── systemrescue-13.02-amd64.iso
├── UNRAID_RECOVERY_INSTRUCTIONS.txt
├── ventoy/
│   └── ventoy.json (auto-created)
└── unraid_recovery/
    └── move_dr_to_unraid.sh
```

## ventoy.json Configuration

The script automatically creates `ventoy.json` with these important settings,
to make booting easier.  

```json
{
  "control": [
    { "VTOY_DEFAULT_SEARCH_ROOT": "/" },
    { "VTOY_MENU_TIMEOUT": "30" },
    { "VTOY_DEFAULT_IMAGE": "/systemrescue-13.02-amd64.iso" }
  ],
  "control_uefi": [
    { "VTOY_LINUX_REMOUNT": "1" }
  ],
  "menu_alias": [
    {
      "image": "/systemrescue-13.02-amd64.iso",
      "alias": "Unraid Recovery - SystemRescue"
    }
  ]
}
```

### Key Settings Explained

**`VTOY_DEFAULT_SEARCH_ROOT: "/"`**
- Searches for ISOs in the root of the USB drive
- Keeps things simple and organized

**`VTOY_MENU_TIMEOUT: "30"`** (values must be strings; one key per object)
- Gives users 30 seconds to select an option
- Auto-boots first entry if no selection made

**`VTOY_LINUX_REMOUNT: "1"`** ⭐ **CRITICAL SETTING**
- Remounts the Ventoy partition as **read-write** in UEFI mode
- Without this, the Ventoy partition would be read-only in SystemRescue
- This allows the `mountall` command to work properly
- Required for accessing the recovery script on the Ventoy USB

**`menu_alias`**
- Gives SystemRescue ISO a friendly name in the menu
- Shows as "Unraid Recovery - SystemRescue"

## User Experience

### For End Users (Emergency Recovery):

1. **Boot from Ventoy USB**
2. **Select "Unraid Recovery - SystemRescue"**
3. **At prompt, type:** `mountall`
4. **The Ventoy partition is mounted at `/mnt/VentoyPart`** (run `lsblk` to confirm; see the reference run below)
5. **Run:** `bash /mnt/VentoyPart/unraid_recovery/move_dr_to_unraid.sh`
6. **Review the drive, the backup time and any verification warnings, then type `RESTORE` to continue** (Enter cancels). If files on the backup failed their hash checks they are listed first and you must type `OVERRIDE` to go on
7. **When complete, type:** `poweroff`

The entire process takes 2-3 minutes after boot.

### Reference: what a real SystemRescue session looks like

Captured on real hardware (test machine with an NVMe disk, the Ventoy USB and the `UNRAID_DR` stick plugged in). Your device
names will differ; what matters is the pattern.

```
[root@sysrescue ~]# lsblk
NAME           MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0            7:0    0   1.1G  1 loop /run/archiso/sfs/airootfs
sda              8:0    1  14.6G  0 disk
├─sda1           8:1    1  14.6G  0 part
│ ├─ventoy     253:0    0   1.3G  1 dm   /run/archiso/bootmnt
│ └─VentoyPart 253:1    0  14.6G  0 dm
└─sda2           8:2    1    32M  0 part
sdb              8:16   1  56.3G  0 disk
└─sdb1           8:17   1  56.3G  0 part
nvme0n1        259:0    0 119.2G  0 disk
├─nvme0n1p1    259:1    0   300M  0 part
└─nvme0n1p2    259:2    0 118.9G  0 part
[root@sysrescue ~]# mountall
mounting /dev/nvme0n1p1 to /mnt/nvme0n1p1... OK
mounting /dev/nvme0n1p2 to /mnt/nvme0n1p2... OK
bind mounted /dev to /mnt/nvme0n1p2/dev
bind mounted /sys to /mnt/nvme0n1p2/sys
bind mounted /proc to /mnt/nvme0n1p2/proc
mounting /dev/sda1 to /mnt/sda1... mount: /mnt/sda1: fsconfig() failed: /dev/sda1: Can't open blockdev.
       dmesg(1) may have more information after failed mount system call.
error mounting /dev/sda1 to /mnt/sda1 (options )
mounting /dev/sda2 to /mnt/sda2... OK
mounting /dev/sdb1 to /mnt/sdb1... OK
mounting /dev/mapper/VentoyPart to /mnt/VentoyPart... OK
[root@sysrescue ~]# lsblk
NAME           MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0            7:0    0   1.1G  1 loop /run/archiso/sfs/airootfs
sda              8:0    1  14.6G  0 disk
├─sda1           8:1    1  14.6G  0 part
│ ├─ventoy     253:0    0   1.3G  1 dm   /run/archiso/bootmnt
│ └─VentoyPart 253:1    0  14.6G  0 dm   /mnt/VentoyPart
└─sda2           8:2    1    32M  0 part /mnt/sda2
sdb              8:16   1  56.3G  0 disk
└─sdb1           8:17   1  56.3G  0 part /mnt/sdb1
nvme0n1        259:0    0 119.2G  0 disk
├─nvme0n1p1    259:1    0   300M  0 part /mnt/nvme0n1p1
└─nvme0n1p2    259:2    0 118.9G  0 part /mnt/nvme0n1p2
[root@sysrescue ~]# cd /mnt/VentoyPart/
[root@sysrescue /mnt/VentoyPart]# ls
CURRENT_VERSION               systemrescue-13.02-amd64.iso.sha512  UNRAID_RECOVERY_INSTRUCTIONS.txt
systemrescue-13.02-amd64.iso  unraid_recovery                      ventoy
[root@sysrescue /mnt/VentoyPart]# cd unraid_recovery/
[root@sysrescue /mnt/VentoyPart/unraid_recovery]# ls
move_dr_to_unraid.sh
```

How to read it:

- **The Ventoy USB is `/mnt/VentoyPart`.** Ventoy exposes its data partition through the device-mapper (`/dev/mapper/VentoyPart`),
  so it does **not** show up as a plain `/mnt/sdX1`. Run the script from there:
  `bash /mnt/VentoyPart/unraid_recovery/move_dr_to_unraid.sh`. *Historical note:* earlier recovery USBs mounted as
  `/mnt/sdX1` (for example `/mnt/sdb1`); if `/mnt/VentoyPart` does not exist, run `ls /mnt/` and look for the folder
  containing `unraid_recovery`.
- **One error during `mountall` is normal.** `mounting /dev/sda1 ... Can't open blockdev` appears because Ventoy already holds the
  USB's big partition (`sda1`) for its own boot image. Ignore it; the same space is mounted fine as `VentoyPart`. The small
  `sda2` (Ventoy's 32 MB EFI partition) also mounts.
- **`mountall` mounts everything**, including this machine's own disks (`nvme0n1p1`, `nvme0n1p2`) and the `UNRAID_DR` stick
  (`sdb1` here). That is expected: `move_dr_to_unraid.sh` unmounts the backup partition itself before it changes anything.
  The machine's own disks are never touched.
- **Finding the backup stick:** it is the small removable disk that is not the Ventoy USB (`sdb`, 56.3G, in this run). You do not
  have to pick it; the script finds the one USB drive labeled `UNRAID_DR` and shows it for confirmation before asking for `RESTORE`.

## Why This Approach Works

✅ **No injection complexity** - Just plain files  
✅ **No ISO rebuilding** - No special tools needed  
✅ **Works on Unraid** - No package manager required  
✅ **Easy to update** - Just edit the script file  
✅ **UEFI compatible** - VTOY_LINUX_REMOUNT handles read-write access  
✅ **SHA512 verified** - Ensures ISO integrity  

## Updating the Recovery Script

To update `move_dr_to_unraid.sh` later:

### From Unraid:
```bash
mkdir -p /mnt/ventoy
mount /dev/sdX1 /mnt/ventoy  # Replace X with your USB
nano /mnt/ventoy/unraid_recovery/move_dr_to_unraid.sh
# Make changes, save, exit
umount /mnt/ventoy
```

### From Any Computer:
1. Mount the Ventoy USB (usually auto-mounts)
2. Navigate to: `unraid_recovery/`
3. Edit: `move_dr_to_unraid.sh`
4. Save and safely eject

## Troubleshooting

### Setup Issues

**"Ventoy USB not found"**
- Ensure Ventoy is installed on a USB drive
- Check `lsblk -o NAME,LABEL,TRAN` to find it

**"SHA512 verification failed"**
- Re-download the ISO (may be corrupted)
- Check internet connection

### Recovery Issues

**"Can't find the recovery script"**
- After `mountall`, type: `ls /mnt/VentoyPart/`
- Look for the `unraid_recovery` folder
- Older recovery USBs mounted as `/mnt/sdX1`: type `ls /mnt/` and try each mount (`ls /mnt/sdb1/`)

**"No USB drive with label UNRAID_DR found"**
- Verify backup USB is plugged in
- Check label is exactly "UNRAID_DR"

**"Verification failed: label is ..., expected 'UNRAID'" / "Label not confirmed yet"**
- The script re-reads the label for about 30 seconds before giving up; progress lines are normal, not a hang
- The message "There are differences between boot sector and its backup" is a harmless `fatlabel` warning after the boot loader
  install and no longer causes a failure
- If it still fails, the report shows what `blkid`, `lsblk`, `fatlabel` and `/dev/disk/by-label/UNRAID` returned. The drive is put
  back to `UNRAID_DR` and it is safe to run the script again. Unraid will not boot unless the label is exactly `UNRAID`

**"Ventoy partition mounted read-only"**
- This shouldn't happen with `VTOY_LINUX_REMOUNT: "1"`
- If it does, manually remount: `mount -o remount,rw /dev/mapper/VentoyPart /mnt/VentoyPart` (older USBs: `mount -o remount,rw /dev/sdX1 /mnt/sdX1`)

## Technical Details

### Why VTOY_LINUX_REMOUNT is Critical

In UEFI boot mode, Ventoy normally mounts its partition as **read-only** to Linux systems. This is a safety feature, but it prevents SystemRescue from accessing files on the Ventoy partition.

Setting `VTOY_LINUX_REMOUNT: "1"` tells Ventoy to:
1. Mount the partition initially as read-only (safe)
2. Remount it as read-write after boot (functional)
3. Allow Linux tools like `mountall` to access the files

Without this setting, users would have to manually remount the partition, adding complexity.

### Tools Used

- **Ventoy** - Multi-boot USB solution
- **SystemRescue** - Arch-based rescue environment. Will download in creation.  
- **fatlabel** - Modern FAT32 label tool (native in SystemRescue)
- **syslinux_linux / mbr.bin** - Boot-loader tools taken from the backup itself (the same files Unraid's `make_bootable_linux` uses)
- **SHA512** - Cryptographic verification of ISO integrity

### Security

- All ISO downloads are SHA512 verified
- Device selection excludes boot and DR drives
- Multiple confirmation prompts before destructive operations
- Read-only mount initially, then remount as needed

## Files Needed

### Required (in same directory):
- `setup_ventoy_usb.sh`
- `move_dr_to_unraid.sh`

### Auto-generated:
- `ventoy.json` (created by setup script)
- `UNRAID_RECOVERY_INSTRUCTIONS.txt` (created by setup script)

### Optional Reference:
- `ventoy.json` (standalone file for reference only - not required)
- `UNRAID_RECOVERY_INSTRUCTIONS_SIMPLE.txt` (detailed user guide)

## Support

For issues:
1. Check the troubleshooting section above
2. Review `UNRAID_RECOVERY_INSTRUCTIONS.txt` on the USB
3. Consult Unraid forums for Unraid-specific questions

---

**Remember:** This solution requires only TWO files to start:
1. `setup_ventoy_usb.sh`
2. `move_dr_to_unraid.sh`

Everything else is auto-generated! 🎉
