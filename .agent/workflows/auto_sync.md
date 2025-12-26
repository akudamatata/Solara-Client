---
description: Automatically sync changes to the remote repository (add, commit, pull, push)
---

This workflow automatically commits all changes, pulls the latest updates from the remote, and pushes the local commits.

// turbo-all
1. Sync changes
```powershell
git add . ; git commit -m "Auto-sync: Update codebase" ; git pull ; git push
```
