#!/bin/bash
# lib/remote.sh - connecting to the rrsync-restricted remote destination
# Shared module for dr_usb_backup.sh and dr_usb_scrub.sh.
# Sourced by those scripts; not meant to be run directly.

# --- Remove the temporary private key copy ---
cleanup_remote() {
    if [ -n "$SSH_KEY_TMP" ]; then
        rm -f "$SSH_KEY_TMP"
        SSH_KEY_TMP=""
    fi
}

# --- Load and validate remote.ini ---
load_remote_config() {
    if [[ ! "$REMOTE_INI" =~ ^/ ]]; then
        log_message "FATAL: REMOTE_INI must be an absolute path. Got: '$REMOTE_INI'"
        return 1
    fi
    if [ ! -f "$REMOTE_INI" ]; then
        log_message "FATAL: Remote config file not found: $REMOTE_INI"
        log_message "FATAL: Copy remote.ini.example to that location and edit it."
        return 1
    fi

    # Defaults (remote.ini overrides these)
    REMOTE_PORT=22
    SSH_CONNECT_TIMEOUT=15
    RSYNC_TIMEOUT=120
    RSYNC_BWLIMIT_KBPS=0
    RSYNC_EXCLUDES=""
    NOTIFY_ON_FAILURE=true

    unset REMOTE_DIR
    # shellcheck source=/dev/null
    if ! source "$REMOTE_INI"; then
        log_message "FATAL: Failed to read $REMOTE_INI"
        return 1
    fi
    if [ -n "${REMOTE_DIR:-}" ]; then
        log_message "WARNING: REMOTE_DIR in $REMOTE_INI is no longer used and is ignored."
        log_message "WARNING: The destination folder is now fixed on the server by the rrsync command in authorized_keys."
    fi

    local errors=0
    local safe_path='^[A-Za-z0-9._@+/-]+$'

    if [[ ! "$REMOTE_HOST" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log_message "FATAL: REMOTE_HOST is missing or invalid (hostname or IPv4 only). Got: '$REMOTE_HOST'"; ((errors++))
    fi
    if [[ ! "$REMOTE_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log_message "FATAL: REMOTE_USER is missing or invalid. Got: '$REMOTE_USER'"; ((errors++))
    fi
    if [[ ! "$REMOTE_PORT" =~ ^[0-9]+$ ]] || [ "$REMOTE_PORT" -lt 1 ] || [ "$REMOTE_PORT" -gt 65535 ]; then
        log_message "FATAL: REMOTE_PORT must be 1-65535. Got: '$REMOTE_PORT'"; ((errors++))
    fi

    if [[ ! "$SSH_KEY_FILE" =~ $safe_path ]] || [ ! -r "$SSH_KEY_FILE" ]; then
        log_message "FATAL: SSH_KEY_FILE is missing, unreadable, or has spaces/special characters. Got: '$SSH_KEY_FILE'"; ((errors++))
    fi
    if [[ ! "$SSH_KNOWN_HOSTS" =~ $safe_path ]] || [ ! -s "$SSH_KNOWN_HOSTS" ]; then
        log_message "FATAL: SSH_KNOWN_HOSTS is missing or empty: '$SSH_KNOWN_HOSTS'"
        log_message "FATAL: Create it with: ssh-keyscan -p $REMOTE_PORT $REMOTE_HOST > $SSH_KNOWN_HOSTS  (then verify the fingerprint)"
        ((errors++))
    fi

    local n
    for n in SSH_CONNECT_TIMEOUT RSYNC_TIMEOUT RSYNC_BWLIMIT_KBPS; do
        if [[ ! "${!n}" =~ ^[0-9]+$ ]]; then
            log_message "FATAL: $n must be a non-negative number. Got: '${!n}'"; ((errors++))
        fi
    done
    if [ "$NOTIFY_ON_FAILURE" != true ] && [ "$NOTIFY_ON_FAILURE" != false ]; then
        log_message "FATAL: NOTIFY_ON_FAILURE must be true or false. Got: '$NOTIFY_ON_FAILURE'"; ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_message "FATAL: $errors remote configuration error(s) in $REMOTE_INI"
        return 1
    fi

    log_message "INFO: Remote configuration loaded from $REMOTE_INI"
    log_message "INFO:   REMOTE_HOST=$REMOTE_HOST  REMOTE_PORT=$REMOTE_PORT  REMOTE_USER=$REMOTE_USER"
    log_message "INFO:   SSH_KEY_FILE=$SSH_KEY_FILE"
    log_message "INFO:   SSH_KNOWN_HOSTS=$SSH_KNOWN_HOSTS"
    log_message "INFO:   RSYNC_TIMEOUT=${RSYNC_TIMEOUT}s  RSYNC_BWLIMIT_KBPS=$RSYNC_BWLIMIT_KBPS  RSYNC_EXCLUDES='$RSYNC_EXCLUDES'"
    return 0
}

# --- Copy the private key from the flash drive to RAM with strict permissions ---
# /boot is FAT: every file looks world-readable and ssh refuses such a key.
stage_ssh_key() {
    local dir="/dev/shm"
    if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then dir="/tmp"; fi
    if ! SSH_KEY_TMP=$(mktemp "$dir/dr_usb_key.XXXXXX"); then
        log_message "ERROR: Could not create temporary key file in $dir"
        SSH_KEY_TMP=""
        return 1
    fi
    chmod 600 "$SSH_KEY_TMP"
    if ! cat "$SSH_KEY_FILE" > "$SSH_KEY_TMP"; then
        log_message "ERROR: Could not read $SSH_KEY_FILE"
        return 1
    fi
    if ! ssh-keygen -y -f "$SSH_KEY_TMP" >/dev/null 2>&1; then
        log_message "ERROR: $SSH_KEY_FILE is not a valid private key (or it has a passphrase; unattended use needs none)"
        return 1
    fi
    debug_print "Staged SSH key at $SSH_KEY_TMP"
    return 0
}

# --- Connect to the destination and prove it is set up safely ---
# Needs load_remote_config to have run. Sets REMOTE_TARGET and REMOTE_SSH_OPTS.
# The destination key must be locked to rrsync (rsync only, one folder). Two checks:
#  1. a tiny rsync push works (connection, key, known_hosts, rrsync, and the folder exist and are writable)
#  2. the same key can NOT run an arbitrary command - if it can, refuse to run (see Docs/dr_usb_backup.md).
#     The probe command is `id`, which rrsync rejects. NOT `true`: rrsync 3.4.1 accepts a bare `true` and exits 0, which
#     made a correctly restricted key look unrestricted (found on real hardware, D-1.2.3-01).
remote_prepare() {
    stage_ssh_key || return 1

    REMOTE_SSH_OPTS=(
        -i "$SSH_KEY_TMP" -p "$REMOTE_PORT"
        -o BatchMode=yes -o IdentitiesOnly=yes
        -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS"
        -o "ConnectTimeout=$SSH_CONNECT_TIMEOUT"
        -o ServerAliveInterval=15 -o ServerAliveCountMax=4
    )
    REMOTE_TARGET="$REMOTE_USER@$REMOTE_HOST"

    log_message "INFO: Testing the connection to the rrsync-restricted destination on $REMOTE_HOST..."
    local out rc probe_dir
    probe_dir=$(mktemp -d /tmp/dr_usb_probe.XXXXXX) || { log_message "ERROR: Could not create a temporary folder."; return 1; }
    : > "$probe_dir/.dr_usb_probe"
    local -a probe_args=(-t "--timeout=$SSH_CONNECT_TIMEOUT" -e "ssh ${REMOTE_SSH_OPTS[*]}")
    [ "$DEBUG" = true ] && probe_args+=(--dry-run)
    out=$(rsync "${probe_args[@]}" "$probe_dir/.dr_usb_probe" "$REMOTE_TARGET:./" 2>&1)
    rc=$?
    rm -rf "$probe_dir"
    if [ $rc -ne 0 ]; then
        log_message "ERROR: Could not reach or write to the destination (rsync exit $rc)."
        [ -n "$out" ] && log_message "ERROR: rsync said: $out"
        log_message "ERROR: Check the host, port, key, SSH_KNOWN_HOSTS, the rrsync line in authorized_keys on the server,"
        log_message "ERROR: and that the folder named in that line exists and is writable by '$REMOTE_USER'."
        return 1
    fi
    out=$(ssh "${REMOTE_SSH_OPTS[@]}" "$REMOTE_TARGET" id 2>&1)
    if [ $? -eq 0 ]; then
        log_message "ERROR: SECURITY CHECK FAILED: the key for $REMOTE_TARGET can run arbitrary commands on the destination."
        log_message "ERROR: Refusing to run. Restrict the key in authorized_keys on the server, for example:"
        log_message "ERROR:   restrict,from=\"<unraid-ip>\",command=\"rrsync -wo /path/to/backup/folder\" ssh-ed25519 AAAA... "
        return 1
    fi
    log_message "INFO: Destination OK: writable, and the key is restricted to rrsync."
    return 0
}
