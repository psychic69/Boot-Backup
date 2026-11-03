#!/bin/bash
# lib/clone.sh - rsync clone to the UNRAID_DR USB
# Shared module for dr_usb_backup.sh and dr_usb_create.sh.
# Sourced by those scripts; not meant to be run directly.

# --- Function to perform clone backup (NON-INTERACTIVE) ---
clone_backup() {
    local clone_device="$1"
    if [ -z "$clone_device" ]; then
        log_message "ERROR: No clone device provided to clone_backup function"
        return 1
    fi
    log_message "INFO: Starting clone backup process for device: $clone_device"
    debug_print "clone_backup called with device: $clone_device"
    local clone_source="${clone_device}1"
    debug_print "Clone source partition set to: $clone_source"
    if [ ! -b "$clone_source" ]; then
        log_message "ERROR: Clone source partition $clone_source does not exist as a block device"
        return 1
    fi
    log_message "INFO: Clone source partition: $clone_source"
    local clone_mounted_already="FALSE"
    local current_mount_point=""
    current_mount_point=$(findmnt -n -o TARGET "$clone_source" 2>/dev/null)
    if [ -n "$current_mount_point" ]; then
        log_message "INFO: $clone_source is already mounted at: $current_mount_point"
        local mount_options=$(findmnt -n -o OPTIONS "$clone_source" 2>/dev/null)
        debug_print "Mount options: $mount_options"
        local first_option=$(echo "$mount_options" | cut -d',' -f1)
        debug_print "First mount option: $first_option"
        if [[ "$first_option" == "rw" ]]; then
            log_message "INFO: $clone_source is mounted read/write"
            CLONE_MP="$current_mount_point"
            clone_mounted_already="TRUE"
            debug_print "Using existing mount point: $CLONE_MP"
        else
            log_message "WARNING: $clone_source is mounted read-only (first option: $first_option). Unmounting..."
            if ! run_logged "umount" umount "$clone_source"; then
                log_message "ERROR: Failed to unmount $clone_source, attempting force unmount..."
                if ! run_logged "umount -f" umount -f "$clone_source"; then
                    log_message "ERROR: Failed to force unmount $clone_source"
                    return 1
                fi
            fi
            log_message "INFO: Successfully unmounted $clone_source"
        fi
    fi
    if [ "$clone_mounted_already" != "TRUE" ]; then
        log_message "INFO: Mounting $clone_source at $CLONE_MP..."
        if [ ! -d "$CLONE_MP" ]; then
            debug_print "Creating mount point directory: $CLONE_MP"
            if ! mkdir -p "$CLONE_MP"; then
                log_message "ERROR: Failed to create mount point directory: $CLONE_MP"
                return 1
            fi
        fi
        if [ ! -w "$CLONE_MP" ]; then
            log_message "ERROR: Mount point directory $CLONE_MP is not writable"
            return 1
        fi
        debug_print "Mount point directory verified: $CLONE_MP"
        if ! run_logged "mount" mount "$clone_source" "$CLONE_MP"; then
            log_message "ERROR: Failed to mount $clone_source at $CLONE_MP"
            return 1
        fi
        log_message "INFO: Successfully mounted $clone_source at $CLONE_MP"
        local mount_options=$(findmnt -n -o OPTIONS "$clone_source" 2>/dev/null)
        debug_print "Checking mount options after mount: $mount_options"
        local first_option=$(echo "$mount_options" | cut -d',' -f1)
        debug_print "First mount option: $first_option"
        if [[ "$first_option" == "rw" ]]; then
            log_message "INFO: Mount verified as read/write"
        else
            log_message "ERROR: Device mounted but not read/write. First option: $first_option, Full options: $mount_options"
            umount "$CLONE_MP"
            return 1
        fi
    fi
    log_message "INFO: Verifying /boot is mounted..."
    if ! mountpoint -q /boot; then
        log_message "ERROR: /boot is not mounted"
        if [ "$clone_mounted_already" != "TRUE" ]; then
            umount "$CLONE_MP"
        fi
        return 1
    fi
    log_message "INFO: /boot is correctly mounted"
    # Hard stop: never copy a corrupted /boot over a good backup
    if ! verify_boot_hashes /boot; then
        log_message "ERROR: SOURCE /boot FAILED THE HASH CHECK. Backup aborted so the existing backup is not overwritten with damaged files."
        if [ "$clone_mounted_already" != "TRUE" ]; then
            umount "$CLONE_MP"
        fi
        return 1
    fi
    log_message "INFO: Starting rsync backup from /boot/ to $CLONE_MP/"
    local -a rsync_args=(-ah)
    if [ "$DEBUG" = true ]; then
        rsync_args+=(-v --dry-run)
        log_message "INFO: DEBUG MODE - Running rsync with --dry-run (no actual changes)"
    fi
    rsync_args+=(/boot/ "$CLONE_MP/")
    debug_print "Rsync command: rsync ${rsync_args[*]}"
    log_message "INFO: Executing: rsync ${rsync_args[*]}"
    local rsync_rc
    rsync "${rsync_args[@]}" 2>&1 | while IFS= read -r line; do log_message "  rsync: $line"; done
    rsync_rc=${PIPESTATUS[0]}
    if [ "$rsync_rc" -eq 24 ]; then
        log_message "WARNING: rsync exit 24 (some source files vanished during transfer) - treating as success"
    elif [ "$rsync_rc" -ne 0 ]; then
        log_message "ERROR: Rsync backup failed (exit code $rsync_rc)"
        if [ "$clone_mounted_already" != "TRUE" ]; then
            umount "$CLONE_MP"
        fi
        return 1
    fi
    log_message "INFO: Rsync backup completed successfully"
    log_message "INFO: Checking for old BACKUP-* marker files in $CLONE_MP..."
    local backup_files_found=false
    while IFS= read -r backup_file; do
        if [ -n "$backup_file" ]; then
            backup_files_found=true
            log_message "INFO: Deleting old backup marker: $backup_file"
            debug_print "Removing file: $backup_file"
            if [ "$DEBUG" != true ]; then
                rm -f "$backup_file"
            else
                log_message "INFO: DEBUG MODE - Would delete: $backup_file"
            fi
        fi
    done < <(find "$CLONE_MP" -maxdepth 1 -type f -name "BACKUP-*" 2>/dev/null)
    if [ "$backup_files_found" = false ]; then
        log_message "INFO: No old BACKUP-* marker files found"
    fi
    local timestamp=$(date '+%m-%d-%Y-%H-%M')
    local backup_marker="$CLONE_MP/BACKUP-$timestamp"
    log_message "INFO: Creating backup marker file: BACKUP-$timestamp"
    debug_print "Touch file: $backup_marker"
    if [ "$DEBUG" != true ]; then
        if ! touch "$backup_marker"; then
            log_message "ERROR: Failed to create backup marker file: $backup_marker"
            if [ "$clone_mounted_already" != "TRUE" ]; then
                umount "$CLONE_MP"
            fi
            return 1
        fi
    else
        log_message "INFO: DEBUG MODE - Would create: $backup_marker"
    fi
    log_message "INFO: Backup marker created successfully"
    log_message "INFO: Disabling EFI boot to prevent accidental boot from backup..."
    local efi_dir="$CLONE_MP/EFI"
    local efi_disabled_dir="$CLONE_MP/EFI-"
    if [ -d "$efi_dir" ]; then
        log_message "INFO: Found EFI directory, renaming to EFI-"
        debug_print "Moving $efi_dir to $efi_disabled_dir"
        if [ "$DEBUG" != true ]; then
            if [ -d "$efi_disabled_dir" ]; then
                debug_print "Removing existing EFI- directory"
                rm -rf "$efi_disabled_dir"
            fi
            if ! mv "$efi_dir" "$efi_disabled_dir"; then
                log_message "ERROR: Failed to rename EFI directory"
                if [ "$clone_mounted_already" != "TRUE" ]; then
                    umount "$CLONE_MP"
                fi
                return 1
            fi
            if [ -d "$efi_disabled_dir" ] && [ ! -d "$efi_dir" ]; then
                log_message "INFO: EFI directory successfully renamed to EFI-"
            else
                log_message "ERROR: EFI directory rename verification failed"
                if [ "$clone_mounted_already" != "TRUE" ]; then
                    umount "$CLONE_MP"
                fi
                return 1
            fi
        else
            log_message "INFO: DEBUG MODE - Would rename $efi_dir to $efi_disabled_dir"
        fi
    else
        log_message "INFO: No EFI directory found, skipping EFI disable step"
    fi
    # Manifest of the backup in its final state (EFI folder renamed), used by the restore check.
    # Any old manifest is removed first so a failure can never leave a stale one behind.
    if [ "$DEBUG" != true ]; then
        rm -f "$CLONE_MP/$BACKUP_MANIFEST_NAME"
        log_message "INFO: Writing the backup manifest..."
        if ! write_backup_manifest "$CLONE_MP"; then
            if [ "$clone_mounted_already" != "TRUE" ]; then
                umount "$CLONE_MP"
            fi
            return 1
        fi
    else
        log_message "INFO: DEBUG MODE - Would write $BACKUP_MANIFEST_NAME"
    fi
    if [ "$clone_mounted_already" != "TRUE" ]; then
        log_message "INFO: Unmounting $clone_source from $CLONE_MP..."
        debug_print "Unmounting: $clone_source"
        if [ "$DEBUG" != true ]; then
            if ! run_logged "umount" umount "$CLONE_MP"; then
                log_message "ERROR: Failed to unmount $clone_source"
                return 1
            fi
            if mountpoint -q "$CLONE_MP"; then
                log_message "ERROR: Device still appears to be mounted after unmount attempt"
                return 1
            fi
            log_message "INFO: Successfully unmounted $clone_source"
        else
            log_message "INFO: DEBUG MODE - Would unmount $clone_source"
        fi
    else
        log_message "INFO: Leaving $clone_source mounted (was already mounted before backup)"
    fi
    log_message "INFO: Clone backup process completed successfully"
    return 0
}
