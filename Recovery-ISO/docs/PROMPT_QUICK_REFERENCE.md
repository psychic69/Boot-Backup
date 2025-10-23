# Prompt Reference - Quick Guide

## All Prompts with Defaults

| Prompt | Default | Display | Reason for Default |
|--------|---------|---------|-------------------|
| Verify local ISO hash? | **yes** | `(YES/no):` | Verification recommended |
| Verify USB ISO hash? | **yes** | `(YES/no):` | Verification recommended |
| Delete corrupted & re-download? | **no** | `(yes/NO):` | Destructive action |
| Download ISO? | **yes** | `(YES/no):` | User wants to proceed |
| Verify downloaded ISO? | **yes** | `(YES/no):` | Verification recommended |
| Overwrite ventoy.json? | **no** | `(yes/NO):` | Preserve existing config |

## Visual Examples

### Verification Prompts (Default: YES)
```
Do you want to verify the SHA512 hash of this ISO? (YES/no): 
```
- Press Enter → Verifies ✅
- Type "no" → Skips ⚠️

### Destructive Prompts (Default: NO)
```
Do you want to delete it and re-download? (yes/NO): 
```
- Press Enter → Does NOT delete ✅
- Type "yes" → Deletes and re-downloads ⚠️

## Quick Tips

### Fast Workflow (Recommended)
Just press **Enter** for all prompts:
```
(YES/no): [Enter] → yes
(YES/no): [Enter] → yes  
(yes/NO): [Enter] → no
(YES/no): [Enter] → yes
```

### Shortcuts Work
- `y` = yes
- `n` = no
- `YES`, `Yes`, `yes` all work
- `NO`, `No`, `no` all work

### Invalid Input = Re-prompt
```
(YES/no): maybe
Invalid input. Please enter 'yes' or 'no'.
(YES/no): yep
Invalid input. Please enter 'yes' or 'no'.
(YES/no): yes ✅
```

## Safety Features

✅ **Typos caught** - "yse" won't be accepted  
✅ **Defaults make sense** - Safe choices by default  
✅ **Re-prompts** - Won't proceed with bad input  
✅ **Clear indicators** - Shows what Enter will do  

---

**Remember:** Uppercase in prompt = default choice when you press Enter!
