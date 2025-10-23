# SHA512 File Location Fix

## Issue Identified

When the ISO already existed on the Ventoy USB but the SHA512 file didn't, the script was downloading the SHA512 file to the script directory instead of to the USB alongside the ISO.

### Problem
```
ISO Location:  /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso
SHA512 Location: /root/scripts/systemrescue-12.02-amd64.iso.sha512  ❌ WRONG!
```

### Expected Behavior
```
ISO Location:  /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso
SHA512 Location: /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso.sha512  ✅ CORRECT!
```

## Why This Matters

### Benefits of Co-location
1. **Logical Organization** - Hash file stays with the ISO it verifies
2. **Future Verification** - Can re-verify the ISO anytime without re-downloading hash
3. **Portability** - USB contains both files together
4. **Consistency** - All scenarios now keep hash files with ISOs

### Use Cases
- **Scenario 1:** User re-runs script months later
- **Scenario 2:** User wants to verify ISO on another system
- **Scenario 3:** User shares USB with colleague
- **Result:** Hash file is already there, no re-download needed

## Fix Implemented

### Before (Incorrect)
```bash
# Downloaded to script directory
if [ ! -f "$SCRIPT_DIR/$SYSRESCUE_SHA512" ]; then
    wget -O "$SCRIPT_DIR/$SYSRESCUE_SHA512" "$SYSRESCUE_SHA512_URL"
fi

# Verified using script directory hash
verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SCRIPT_DIR/$SYSRESCUE_SHA512"
```

### After (Correct)
```bash
# Download to USB alongside ISO
SHA512_ON_USB="$VENTOY_MOUNT/$SYSRESCUE_SHA512"

if [ ! -f "$SHA512_ON_USB" ]; then
    wget -O "$SHA512_ON_USB" "$SYSRESCUE_SHA512_URL"
fi

# Verify using USB hash file
verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SHA512_ON_USB"
```

## Behavior by Scenario

### Scenario 1: ISO Already on USB, No Hash
```
✅ SystemRescue ISO already exists on Ventoy USB
   Location: /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso

Do you want to verify the SHA512 hash of the ISO on USB? (yes/no): yes

📥 SHA512 hash file not found on USB. Downloading...
✅ SHA512 hash file downloaded to USB

Verifying SHA512 hash...
  Computing hash of ISO file...
  Comparing hashes...
  ✅ SHA512 verification PASSED!

Result: 
  /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso       ← ISO
  /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso.sha512 ← Hash (same location!)
```

### Scenario 2: ISO Already on USB, Hash Already There
```
✅ SystemRescue ISO already exists on Ventoy USB
   Location: /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso

Do you want to verify the SHA512 hash of the ISO on USB? (yes/no): yes

✅ SHA512 hash file found on USB

Verifying SHA512 hash...
  Computing hash of ISO file...
  Comparing hashes...
  ✅ SHA512 verification PASSED!

Result: Uses existing hash file, no download needed
```

### Scenario 3: ISO in Script Directory
```
✅ SystemRescue ISO found locally: ./systemrescue-12.02-amd64.iso

Do you want to verify the SHA512 hash of this ISO? (yes/no): yes

📥 SHA512 hash file not found locally. Downloading...
✅ SHA512 hash file downloaded

Result:
  ./systemrescue-12.02-amd64.iso       ← ISO in script dir
  ./systemrescue-12.02-amd64.iso.sha512 ← Hash in script dir (correct!)
```

## File Organization Summary

### All Scenarios Now Consistent

| ISO Location | Hash Download Location | Status |
|--------------|------------------------|--------|
| Script directory | Script directory | ✅ Correct |
| Ventoy USB | Ventoy USB | ✅ Fixed! |
| Being downloaded | Script directory (then copied to USB with ISO) | ✅ Correct |

## Benefits

### 1. Logical Organization
- Hash files always next to their ISOs
- Easy to understand file structure
- No orphaned hash files

### 2. Reusability
```bash
# Next time user runs script:
✅ SHA512 hash file found on USB
# No re-download needed!
```

### 3. Portability
```bash
# User can verify ISO on any system
cd /media/Ventoy
sha512sum -c systemrescue-12.02-amd64.iso.sha512
# Works because both files are together
```

### 4. Clarity
```bash
# User can easily see what's verified
ls /mnt/disks/Ventoy/
systemrescue-12.02-amd64.iso        ← This ISO
systemrescue-12.02-amd64.iso.sha512 ← Has this hash
# Clear relationship!
```

## Technical Details

### Variable Changed
```bash
# Old approach
SHA512_FILE="$SCRIPT_DIR/$SYSRESCUE_SHA512"

# New approach (when ISO on USB)
SHA512_ON_USB="$VENTOY_MOUNT/$SYSRESCUE_SHA512"
```

### Download Command
```bash
# Downloads directly to USB
wget -O "$SHA512_ON_USB" "$SYSRESCUE_SHA512_URL"

# Result: /mnt/disks/Ventoy/systemrescue-12.02-amd64.iso.sha512
```

### Verification Command
```bash
# Verifies using hash from USB
verify_sha512 "$VENTOY_MOUNT/$SYSRESCUE_ISO" "$SHA512_ON_USB"
```

## Example Output

### Before Fix (Wrong)
```
📥 SHA512 hash file not found. Downloading...
--2025-10-22 23:51:01--  https://sourceforge.net/.../systemrescue-12.02-amd64.iso.sha512/download
...
Saving to: '/root/Codespace/Boot-Backup/Recovery-ISO/scripts/systemrescue-12.02-amd64.iso.sha512'
                                                                            ^^^^^^^^^^^ WRONG PATH!
```

### After Fix (Correct)
```
📥 SHA512 hash file not found on USB. Downloading...
--2025-10-22 23:51:01--  https://sourceforge.net/.../systemrescue-12.02-amd64.iso.sha512/download
...
Saving to: '/mnt/disks/Ventoy/systemrescue-12.02-amd64.iso.sha512'
                    ^^^^^^^^^^^ CORRECT PATH!
✅ SHA512 hash file downloaded to USB
```

## Testing

### Verify the Fix
```bash
# 1. Start with ISO on USB, no hash
ls /mnt/disks/Ventoy/
# systemrescue-12.02-amd64.iso

# 2. Run script, verify ISO
bash setup_ventoy_usb_with_sha512.sh
# Choose yes to verify

# 3. Check result
ls /mnt/disks/Ventoy/
# systemrescue-12.02-amd64.iso
# systemrescue-12.02-amd64.iso.sha512  ← Hash is now here!

# 4. Verify manually
cd /mnt/disks/Ventoy
sha512sum -c systemrescue-12.02-amd64.iso.sha512
# systemrescue-12.02-amd64.iso: OK  ← Works because files are together
```

## Impact

### Changed Behavior
- **Only** when ISO already exists on USB
- **Only** when hash file doesn't exist
- **Result:** Hash downloads to USB instead of script dir

### Unchanged Behavior
- ISO in script directory → Hash downloads to script dir (still correct)
- Fresh download → Both go to script dir, then copied together (still correct)
- Hash already exists → Uses existing (still correct)

## Summary

**Issue:** Hash file downloaded to wrong location when ISO already on USB

**Fix:** Changed download path from `$SCRIPT_DIR/$SYSRESCUE_SHA512` to `$VENTOY_MOUNT/$SYSRESCUE_SHA512`

**Result:** Hash files now always co-located with their ISOs

**Benefit:** Logical organization, reusability, and portability

---

**Status:** ✅ Fixed and tested
