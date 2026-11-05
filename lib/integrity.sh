#!/bin/bash
# lib/integrity.sh - hash checks for the Unraid boot files, and the manifest written onto the backup USB.
# Shared module for dr_usb_backup.sh and dr_usb_create.sh.
# Sourced by those scripts; not meant to be run directly.
# (move_dr_to_unraid.sh runs by itself from the recovery USB, so it carries its own copy of the verify logic.)

# Name of the manifest written to the root of the UNRAID_DR USB.
# (Deliberately not "BACKUP-*": the BACKUP-<timestamp> marker is found by that pattern.)
BACKUP_MANIFEST_NAME="DR_MANIFEST.sums"

# Files the Unraid OS needs to boot; a missing one means the flash drive is damaged.
REQUIRED_BOOT_FILES="bzimage bzroot bzmodules"

# Details of every failed check, filled in by the verify functions (reset at the start of each call).
# One entry per failure: "name|problem|expected|actual|size-in-bytes"  (fields may be empty)
HASH_FAILURES=()

# --- Print the SHA-256 of one file (hash only) ---
# When HASH_BYPASS_CACHE=true (the scrub sets it), the kernel is first told to forget this one file's cached pages
# (GNU dd iflag=nocache count=0), so the hash is read from the drive itself, not RAM. Other files and other
# workloads on the server are untouched. If dd cannot do it, the hash is still computed from whatever is available.
HASH_BYPASS_CACHE="${HASH_BYPASS_CACHE:-false}"
sha256_of() {
    if [ "$HASH_BYPASS_CACHE" = true ]; then
        dd if="$1" iflag=nocache count=0 2>/dev/null || CACHE_BYPASS_FAILED=true
    fi
    sha256sum -- "$1" 2>/dev/null | awk '{print $1}'
}

# --- Verify the Unraid boot files against the .sha256 files Unraid ships ---
# Usage: verify_boot_hashes [dir]      (default /boot)
# Every file in <dir> and <dir>/previous that has a "<file>.sha256" sibling is hashed and compared
# with the 64-character hash stored in that sibling. Returns 1 if anything fails to match.
verify_boot_hashes() {
    local boot="${1:-/boot}"
    local dir hash_file target name stored actual size_mb size_bytes req
    local verified=0 failed=0 warned=0
    HASH_FAILURES=()

    log_message "INFO: Verifying Unraid boot files in '${boot}' (and previous/) against their .sha256 files..."

    for req in ${REQUIRED_BOOT_FILES}; do
        if [ ! -f "${boot}/${req}" ]; then
            log_message "ERROR: Required boot file is missing: ${req}"
            HASH_FAILURES+=("${req}|REQUIRED BOOT FILE IS MISSING|||")
            failed=$((failed + 1))
        elif [ ! -f "${boot}/${req}.sha256" ]; then
            log_message "WARNING: ${req} has no ${req}.sha256 file, so it cannot be verified."
            warned=$((warned + 1))
        fi
    done

    for dir in "${boot}" "${boot}/previous"; do
        [ -d "${dir}" ] || continue
        for hash_file in "${dir}"/*.sha256; do
            [ -e "${hash_file}" ] || continue
            target="${hash_file%.sha256}"
            name="${target#"${boot}"/}"
            if [ ! -f "${target}" ]; then
                log_message "ERROR: ${name}: ${name}.sha256 exists but the file itself is missing"
                HASH_FAILURES+=("${name}|FILE IS MISSING (its .sha256 file exists)|||")
                failed=$((failed + 1))
                continue
            fi
            stored=$(awk 'NR==1 {print tolower($1)}' "${hash_file}")
            if [[ ! "${stored}" =~ ^[0-9a-f]{64}$ ]]; then
                log_message "WARNING: ${name}.sha256 does not contain a valid SHA-256, so ${name} cannot be verified."
                warned=$((warned + 1))
                continue
            fi
            size_bytes=$(wc -c < "${target}" | tr -d ' ')
            size_mb=$(( size_bytes / 1048576 ))
            log_message "INFO: Verifying ${name} (${size_mb} MB)..."
            actual=$(sha256_of "${target}")
            if [ "${actual}" = "${stored}" ]; then
                verified=$((verified + 1))
            else
                log_message "ERROR: ${name}: HASH MISMATCH"
                log_message "ERROR:    expected: ${stored}"
                log_message "ERROR:    actual  : ${actual}"
                log_message "ERROR:    size    : ${size_bytes} bytes"
                HASH_FAILURES+=("${name}|HASH MISMATCH|${stored}|${actual}|${size_bytes}")
                failed=$((failed + 1))
            fi
        done
    done

    if [ "${failed}" -gt 0 ]; then
        log_message "ERROR: ${failed} boot file check(s) FAILED (${verified} verified, ${warned} warning(s))."
        return 1
    fi
    log_message "INFO: Boot file hashes OK (${verified} verified, ${warned} warning(s))."
    return 0
}

# --- Write the manifest onto the backup USB ---
# Usage: write_backup_manifest <backup-root>
# Lists a SHA-256 for every file EXCEPT: files Unraid already hashes (checked by verify_boot_hashes),
# ldlinux.sys / ldlinux.c32 (rewritten by the syslinux install at restore time), the BACKUP-* marker,
# the manifest itself, and the volatile or bulky folders logs/, .git/ and System Volume Information/.
write_backup_manifest() {
    local dir="$1"
    local manifest="${dir}/${BACKUP_MANIFEST_NAME}"
    local tmp="${manifest}.tmp"
    local count

    (
        cd "${dir}" || exit 1
        find . \( -path ./logs -o -path ./.git -o -path "./System Volume Information" \) -prune -o -type f -print0 |
        while IFS= read -r -d '' rel; do
            case "${rel}" in
                "./${BACKUP_MANIFEST_NAME}"|"./${BACKUP_MANIFEST_NAME}.tmp"|./BACKUP-*|./ldlinux.sys|./ldlinux.c32) continue ;;
            esac
            [ -f "${rel}.sha256" ] && continue
            sha256sum -- "${rel}" || exit 1
        done
    ) > "${tmp}"
    if [ $? -ne 0 ]; then
        rm -f "${tmp}"
        log_message "ERROR: Failed to compute the backup manifest."
        return 1
    fi
    if ! mv -f "${tmp}" "${manifest}"; then
        log_message "ERROR: Failed to write ${manifest}."
        return 1
    fi
    count=$(wc -l < "${manifest}" | tr -d ' ')
    log_message "INFO: Wrote ${BACKUP_MANIFEST_NAME} (${count} files)."
    return 0
}

# --- Verify a backup USB against the manifest written by write_backup_manifest ---
# Usage: verify_backup_manifest_dir <backup-root>
# Returns 0 = all match, 1 = something differs or is missing (details in HASH_FAILURES),
#         2 = there is no manifest (an older backup, or the manifest step failed): nothing could be checked.
verify_backup_manifest_dir() {
    local dir="$1"
    local manifest="${dir}/${BACKUP_MANIFEST_NAME}"
    local line expected path actual size total=0 bad=0
    HASH_FAILURES=()

    if [ ! -f "${manifest}" ]; then
        log_message "WARNING: ${BACKUP_MANIFEST_NAME} not found in '${dir}': config/ and the other small files could not be checked."
        return 2
    fi
    log_message "INFO: Checking '${dir}' against ${BACKUP_MANIFEST_NAME}..."
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        total=$((total + 1))
        expected="${line%% *}"
        path="${line#*  }"
        if [[ "${expected}" == \\* ]]; then
            log_message "WARNING: ${path#./} has special characters in its name and was not checked."
            continue
        fi
        if [ ! -f "${dir}/${path}" ]; then
            log_message "ERROR: ${path#./}: MISSING (the manifest lists it)"
            HASH_FAILURES+=("${path#./}|FILE IS MISSING (the manifest lists it)|${expected}||")
            bad=$((bad + 1))
            continue
        fi
        actual=$(sha256_of "${dir}/${path}")
        if [ "${actual}" != "${expected}" ]; then
            size=$(wc -c < "${dir}/${path}" | tr -d ' ')
            log_message "ERROR: ${path#./}: DOES NOT MATCH THE MANIFEST"
            log_message "ERROR:    expected: ${expected}"
            log_message "ERROR:    actual  : ${actual}"
            log_message "ERROR:    size    : ${size} bytes"
            HASH_FAILURES+=("${path#./}|DOES NOT MATCH THE MANIFEST|${expected}|${actual}|${size}")
            bad=$((bad + 1))
        fi
    done < "${manifest}"
    if [ "${bad}" -gt 0 ]; then
        log_message "ERROR: ${bad} of ${total} manifest file(s) FAILED."
        return 1
    fi
    log_message "INFO: All ${total} manifest file(s) match."
    return 0
}
