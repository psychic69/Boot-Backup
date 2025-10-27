# Documentation Index

Complete guide to all documentation in the Unraid Boot Backup Suite.

## 📚 Start Here

| Document | Purpose | Time to Read |
|----------|---------|--------------|
| **[GETTING_STARTED.md](GETTING_STARTED.md)** | Quick setup guide - get running in 15 minutes | 5 min |
| **[README.md](README.md)** | Complete project documentation and reference | 20 min |

## 📖 Core Documentation

### For Users

| Document | What You'll Learn |
|----------|-------------------|
| **[GETTING_STARTED.md](GETTING_STARTED.md)** | How to set up the entire backup system from scratch |
| **[docs/dr_usb_create.md](docs/dr_usb_create.md)** | How to create your backup USB (one-time setup) |
| **[docs/dr_usb_backup.md](docs/dr_usb_backup.md)** | How to automate daily backups |
| **[docs/VENTOY_README.md](docs/VENTOY_README.md)** | How to create your recovery USB |

### For Developers

| Document | What You'll Learn |
|----------|-------------------|
| **[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** | Repository layout, file descriptions, workflows |
| **[README.md#contributing](README.md#contributing)** | How to contribute to the project |

## 🚀 Quick Navigation by Task

### "I want to set up the backup system"
→ Start with [GETTING_STARTED.md](GETTING_STARTED.md)

### "I want to create my backup USB"
→ Read [docs/dr_usb_create.md](docs/dr_usb_create.md)

### "I want to automate my backups"
→ Read [docs/dr_usb_backup.md](docs/dr_usb_backup.md)

### "I want to create my recovery USB"
→ Read [docs/VENTOY_README.md](docs/VENTOY_README.md)

### "My main USB died, I need to recover NOW!"
→ Jump to [README.md#recovery-process](README.md#recovery-process)

### "I'm getting an error message"
→ Check [README.md#troubleshooting](README.md#troubleshooting)

### "I want to understand how everything works"
→ Read [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)

### "I want to contribute code"
→ Read [README.md#contributing](README.md#contributing)

## 📋 Document Details

### Primary Documents

#### GETTING_STARTED.md
**Purpose:** Your first stop - gets you from zero to fully protected in 15 minutes

**Contents:**
- Prerequisites checklist
- 3-step installation process
- Testing your setup
- Quick command reference
- Important warnings and notes

**When to read:** Before doing anything else

---

#### README.md
**Purpose:** Comprehensive project documentation and reference manual

**Contents:**
- Complete feature list
- Detailed installation instructions
- All four scripts explained in depth
- Recovery process walkthrough
- Licensing information
- Troubleshooting guide
- Best practices
- Contributing guidelines

**When to read:** After initial setup, when you need detailed information

---

### Script-Specific Documentation

#### docs/dr_usb_create.md
**Purpose:** Everything about the interactive backup USB creation script

**Key Topics:**
- Critical SSH-only warning
- Interactive setup process
- Size and compatibility requirements
- Safety features and failsafes
- Testing flags for development
- Comprehensive FAQ

**When to read:** Before running `dr_usb_create.sh` for the first time

---

#### docs/dr_usb_backup.md
**Purpose:** Everything about the automated backup script

**Key Topics:**
- Non-interactive operation
- Scheduling with User Scripts or cron
- Logging and log rotation
- Boot protection mechanisms
- Testing and troubleshooting
- Integration with automation

**When to read:** When setting up automated backups

---

#### docs/VENTOY_README.md
**Purpose:** Everything about creating the emergency recovery USB

**Key Topics:**
- Ventoy configuration details
- SystemRescue ISO download and verification
- `ventoy.json` settings explained
- Recovery workflow
- UEFI remount functionality
- Updating recovery scripts

**When to read:** When creating your recovery USB

---

#### docs/PROJECT_STRUCTURE.md
**Purpose:** Developer reference and project organization guide

**Key Topics:**
- Repository file structure
- Script dependencies and relationships
- USB directory structures
- Workflow diagrams
- Configuration file locations
- Version information

**When to read:** When contributing, debugging, or understanding internals

---

## 🎯 Documentation by Skill Level

### Beginner (Never used Unraid scripts before)
1. [GETTING_STARTED.md](GETTING_STARTED.md) ⭐ Start here
2. [docs/dr_usb_create.md](docs/dr_usb_create.md)
3. [docs/dr_usb_backup.md](docs/dr_usb_backup.md)
4. [docs/VENTOY_README.md](docs/VENTOY_README.md)

### Intermediate (Familiar with Unraid)
1. [README.md](README.md) - Skim the overview
2. [GETTING_STARTED.md](GETTING_STARTED.md) - Follow the steps
3. Script-specific docs as needed

### Advanced (Wants to customize or contribute)
1. [README.md](README.md) - Full read
2. [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)
3. [README.md#contributing](README.md#contributing)
4. Individual script documentation as needed

## 🔍 Finding Information

### By Topic

**Backup Creation:**
- [GETTING_STARTED.md → Step 1](GETTING_STARTED.md#step-1-create-your-backup-usb-5-minutes)
- [docs/dr_usb_create.md](docs/dr_usb_create.md)
- [README.md → Scripts Overview → dr_usb_create.sh](README.md#1-dr_usb_createsh)

**Automated Backups:**
- [GETTING_STARTED.md → Step 2](GETTING_STARTED.md#step-2-set-up-automated-backups-2-minutes)
- [docs/dr_usb_backup.md](docs/dr_usb_backup.md)
- [README.md → Scripts Overview → dr_usb_backup.sh](README.md#2-dr_usb_backupsh)

**Recovery USB:**
- [GETTING_STARTED.md → Step 3](GETTING_STARTED.md#step-3-create-recovery-usb-5-minutes)
- [docs/VENTOY_README.md](docs/VENTOY_README.md)
- [README.md → Scripts Overview → setup_ventoy_usb_simple.sh](README.md#3-setup_ventoy_usb_simplesh)

**Emergency Recovery:**
- [README.md → Recovery Process](README.md#recovery-process)
- [GETTING_STARTED.md → When Emergency Strikes](GETTING_STARTED.md#when-emergency-strikes)
- [docs/VENTOY_README.md → User Experience](docs/VENTOY_README.md#user-experience)

**Troubleshooting:**
- [README.md → Troubleshooting](README.md#troubleshooting)
- [docs/dr_usb_create.md → FAQ](docs/dr_usb_create.md#faq)
- [docs/dr_usb_backup.md → FAQ](docs/dr_usb_backup.md#faq)
- [docs/VENTOY_README.md → Troubleshooting](docs/VENTOY_README.md#troubleshooting)

**Configuration:**
- [README.md → Technical Details](README.md#technical-details)
- [docs/VENTOY_README.md → ventoy.json Configuration](docs/VENTOY_README.md#ventoyjson-configuration)
- [docs/PROJECT_STRUCTURE.md → Configuration Files](docs/PROJECT_STRUCTURE.md#configuration-files)

**Safety & Best Practices:**
- [README.md → What This Suite Offers](README.md#what-this-suite-offers)
- [README.md → Best Practices](README.md#best-practices)
- [GETTING_STARTED.md → Important Notes](GETTING_STARTED.md#important-notes)

## 📊 Documentation Statistics

| Document | Word Count | Sections | Difficulty |
|----------|-----------|----------|------------|
| GETTING_STARTED.md | ~1,500 | 8 | ⭐ Beginner |
| README.md | ~8,000 | 15 | ⭐⭐ Intermediate |
| dr_usb_create.md | ~1,000 | 7 | ⭐⭐ Intermediate |
| dr_usb_backup.md | ~1,200 | 6 | ⭐ Beginner |
| VENTOY_README.md | ~2,000 | 11 | ⭐⭐ Intermediate |
| PROJECT_STRUCTURE.md | ~3,000 | 9 | ⭐⭐⭐ Advanced |

**Total Documentation:** ~16,700 words across 6 comprehensive documents

## 🔄 Documentation Updates

This documentation is actively maintained. Last updated: 2025-01-XX

**Found an issue?**
- Report documentation bugs on GitHub Issues
- Suggest improvements via Pull Requests
- Ask questions on Unraid Forums

## 💡 Tips for Reading

1. **Start with GETTING_STARTED.md** if you're new
2. **Use the Table of Contents** in README.md to jump to sections
3. **Check the FAQ** in script docs before asking questions
4. **Follow the Quick Navigation** links above for specific tasks
5. **Bookmark this page** for quick reference

## 📞 Still Need Help?

If you've read the relevant documentation and still need help:

1. **Check the troubleshooting sections** in multiple docs
2. **Search existing GitHub issues** for similar problems
3. **Create a new GitHub issue** with:
   - Which document you read
   - What you tried
   - Error messages or unexpected behavior
   - Your Unraid version and system details

---

**Welcome to the Unraid Boot Backup Suite!** 🎉

We've worked hard to make this documentation comprehensive and easy to follow. Start with [GETTING_STARTED.md](GETTING_STARTED.md) and you'll be protected in no time!
