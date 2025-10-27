# Robust Yes/No Prompts with Validation

## Problem Identified

The original prompts had several issues:

### Issue 1: Bad Input Defaults to Wrong Action
```bash
# Old code
read -p "Do you want to verify the SHA512 hash? (yes/no): " response
if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
    # Verify
else
    # Skip verification  ← Bad input falls here!
fi
```

**Problem:** Typing "yess", "ye", or any typo → skips verification (unsafe!)

### Issue 2: No Default Value
```bash
Do you want to verify the SHA512 hash? (yes/no):
# User presses Enter → skips verification
```

**Problem:** Empty input should use a sensible default, not fail

### Issue 3: No Input Validation
```bash
Do you want to verify the SHA512 hash? (yes/no): maybe
# Falls to else block → skips verification
```

**Problem:** Invalid input is accepted, user doesn't realize mistake

## Solution Implemented

### New `ask_yes_no` Function

```bash
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    # Format prompt with default indicator
    if [ "$default" = "yes" ]; then
        prompt="$prompt (YES/no): "
    elif [ "$default" = "no" ]; then
        prompt="$prompt (yes/NO): "
    else
        prompt="$prompt (yes/no): "
    fi
    
    while true; do
        read -p "$prompt" response
        
        # If empty, use default
        if [ -z "$response" ]; then
            if [ -n "$default" ]; then
                response="$default"
            else
                echo "Please enter yes or no."
                continue
            fi
        fi
        
        # Validate input (case insensitive)
        case "${response,,}" in
            yes|y)
                return 0  # Success = yes
                ;;
            no|n)
                return 1  # Failure = no
                ;;
            *)
                echo "Invalid input. Please enter 'yes' or 'no'."
                # Loop continues, prompts again
                ;;
        esac
    done
}
```

### Key Features

1. **Input Validation** - Only accepts yes/y/no/n (case insensitive)
2. **Re-prompts on Bad Input** - Doesn't accept invalid input
3. **Default Values** - Empty input uses sensible default
4. **Visual Indicators** - Shows default in prompt (YES/no or yes/NO)
5. **Return Codes** - Uses standard shell return codes (0=yes, 1=no)

## Usage Examples

### Basic Usage
```bash
if ask_yes_no "Do you want to continue?" "yes"; then
    echo "Continuing..."
else
    echo "Cancelled"
fi
```

### All Scenarios

#### Scenario 1: User Types "yes"
```
Do you want to verify the SHA512 hash? (YES/no): yes
✅ Proceeds with verification
```

#### Scenario 2: User Types "y"
```
Do you want to verify the SHA512 hash? (YES/no): y
✅ Proceeds with verification (accepts shorthand)
```

#### Scenario 3: User Presses Enter (Default=yes)
```
Do you want to verify the SHA512 hash? (YES/no): 
✅ Uses default (yes) → Proceeds with verification
```

#### Scenario 4: User Types "no"
```
Do you want to verify the SHA512 hash? (YES/no): no
⚠️  Skips verification
```

#### Scenario 5: User Types "n"
```
Do you want to verify the SHA512 hash? (YES/no): n
⚠️  Skips verification
```

#### Scenario 6: Invalid Input (Re-prompts)
```
Do you want to verify the SHA512 hash? (YES/no): maybe
Invalid input. Please enter 'yes' or 'no'.
Do you want to verify the SHA512 hash? (YES/no): yep
Invalid input. Please enter 'yes' or 'no'.
Do you want to verify the SHA512 hash? (YES/no): yes
✅ Proceeds with verification
```

#### Scenario 7: Case Insensitive
```
Do you want to verify the SHA512 hash? (YES/no): YES
✅ Works (case insensitive)

Do you want to verify the SHA512 hash? (YES/no): No
⚠️  Works (case insensitive)

Do you want to verify the SHA512 hash? (YES/no): Y
✅ Works
```

## Prompts Updated

All yes/no prompts in the script now use this function:

### 1. Verify Local ISO
```bash
if ask_yes_no "Do you want to verify the SHA512 hash of this ISO?" "yes"; then
```
- **Default:** yes (verification is recommended)
- **Prompt shows:** `(YES/no):`

### 2. Verify USB ISO
```bash
if ask_yes_no "Do you want to verify the SHA512 hash of the ISO on USB?" "yes"; then
```
- **Default:** yes (verification is recommended)
- **Prompt shows:** `(YES/no):`

### 3. Delete and Re-download Corrupted ISO
```bash
if ask_yes_no "Do you want to delete it and re-download?" "no"; then
```
- **Default:** no (safer - doesn't delete by default)
- **Prompt shows:** `(yes/NO):`

### 4. Download ISO
```bash
if ask_yes_no "Download now?" "yes"; then
```
- **Default:** yes (user wants to proceed)
- **Prompt shows:** `(YES/no):`

### 5. Verify Downloaded ISO
```bash
if ask_yes_no "Do you want to verify the SHA512 hash of the downloaded ISO? (recommended)" "yes"; then
```
- **Default:** yes (verification is recommended)
- **Prompt shows:** `(YES/no):`

### 6. Overwrite ventoy.json
```bash
if ! ask_yes_no "  Overwrite?" "no"; then
```
- **Default:** no (safer - preserves existing config)
- **Prompt shows:** `(yes/NO):`
- **Note:** Uses `!` to invert logic (default no means skip overwrite)

## Default Value Strategy

### Defaults to "yes" When:
- ✅ Action is recommended/safe
- ✅ Verification operations
- ✅ Expected workflow continuation
- ✅ No destructive consequences

**Examples:**
- Verify hash → yes (recommended)
- Download ISO → yes (user wants it)
- Continue setup → yes (expected)

### Defaults to "no" When:
- ⚠️ Action is destructive
- ⚠️ Overwriting existing data
- ⚠️ Deleting files
- ⚠️ Requires user confirmation

**Examples:**
- Delete and re-download → no (destructive)
- Overwrite config → no (preserves existing)
- Format drive → no (destructive, but not in our script)

## Benefits

### 1. User Safety
✅ Invalid input doesn't cause wrong action  
✅ Defaults are sensible and safe  
✅ Re-prompts until valid input received  

### 2. User Experience
✅ Clear visual indicator of default (YES/no)  
✅ Press Enter for default (fast workflow)  
✅ Accepts y/n shortcuts  
✅ Case insensitive  

### 3. Error Prevention
✅ Typos don't cause silent failures  
✅ Bad input is caught immediately  
✅ User always knows what will happen  

### 4. Consistency
✅ All prompts behave the same  
✅ Same validation everywhere  
✅ Predictable behavior  

## Technical Details

### Return Codes (Shell Convention)
```bash
return 0  # Success (yes)
return 1  # Failure (no)
```

**Usage in if statements:**
```bash
if ask_yes_no "Question?" "yes"; then
    # Return code 0 → yes path
else
    # Return code 1 → no path
fi
```

### Case-Insensitive Matching
```bash
case "${response,,}" in  # ${var,,} converts to lowercase
    yes|y) return 0 ;;
    no|n) return 1 ;;
esac
```

### Loop Until Valid
```bash
while true; do
    read -p "$prompt" response
    case "$response" in
        valid) break ;;
        *) echo "Invalid" ;;  # Continue loop
    esac
done
```

### Empty Input Handling
```bash
if [ -z "$response" ]; then  # -z checks for empty string
    response="$default"       # Use default
fi
```

## Examples in Practice

### Example 1: Fast Workflow (All Defaults)
```
Do you want to verify the SHA512 hash? (YES/no): [Enter]
✅ SHA512 verification PASSED!

Do you want to verify the downloaded ISO? (YES/no): [Enter]
✅ SHA512 verification PASSED!

Download now? (YES/no): [Enter]
Downloading...
```

**User just presses Enter repeatedly → all safe defaults**

### Example 2: Explicit No
```
Do you want to verify the SHA512 hash? (YES/no): no
⚠️  Skipping SHA512 verification (not recommended)
```

**User explicitly chose to skip → intentional action**

### Example 3: Error Recovery
```
Do you want to verify the SHA512 hash? (YES/no): yse
Invalid input. Please enter 'yes' or 'no'.
Do you want to verify the SHA512 hash? (YES/no): yes
✅ SHA512 verification PASSED!
```

**Typo caught → user prompted again → correct input accepted**

### Example 4: Destructive Action (Default No)
```
Do you want to delete it and re-download? (yes/NO): [Enter]
Cannot proceed with potentially corrupted ISO.
```

**Destructive action requires explicit "yes" → safe default**

## Testing

### Test Valid Inputs
```bash
# Test yes
echo "yes" | ask_yes_no "Test?" "yes"
echo $?  # Should be 0

# Test y
echo "y" | ask_yes_no "Test?" "yes"
echo $?  # Should be 0

# Test no
echo "no" | ask_yes_no "Test?" "yes"
echo $?  # Should be 1

# Test n
echo "n" | ask_yes_no "Test?" "yes"
echo $?  # Should be 1

# Test default (empty)
echo "" | ask_yes_no "Test?" "yes"
echo $?  # Should be 0 (default yes)
```

### Test Invalid Inputs (Interactive)
```bash
ask_yes_no "Test?" "yes"
# Try: maybe, yep, nope, yeah, nah, ok, etc.
# Should re-prompt each time until valid input
```

## Comparison

### Before (Unsafe)
```bash
read -p "Continue? (yes/no): " response
if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Yes"
else
    echo "No"  # Typos, empty, "maybe" all go here!
fi
```

**Problems:**
- ❌ "yse" → No (wrong!)
- ❌ "" (empty) → No (no default!)
- ❌ "maybe" → No (invalid accepted!)
- ❌ No re-prompt on bad input

### After (Safe)
```bash
if ask_yes_no "Continue?" "yes"; then
    echo "Yes"
else
    echo "No"
fi
```

**Benefits:**
- ✅ "yse" → Re-prompts until valid
- ✅ "" (empty) → Uses default (yes)
- ✅ "maybe" → Re-prompts until valid
- ✅ Clear visual indicator (YES/no)

## Summary

### What Changed
- ✅ Added `ask_yes_no()` function with validation
- ✅ Updated all 6 yes/no prompts in script
- ✅ Added sensible defaults to each prompt
- ✅ Added input validation with re-prompting
- ✅ Made prompts case-insensitive
- ✅ Added visual default indicators

### Benefits
- 🛡️ **Safety**: Invalid input can't cause wrong action
- 🎯 **Usability**: Press Enter for sensible defaults
- 🔄 **Validation**: Re-prompts until valid input
- 👁️ **Clarity**: Visual indicator of default choice
- ⚡ **Speed**: Fast workflow with defaults

### Result
All prompts are now robust, safe, and user-friendly! No more accidental wrong actions from typos or bad input.

---

**Status:** ✅ All prompts upgraded to robust validation!
