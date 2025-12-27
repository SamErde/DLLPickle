---
title: Release Workflow Migration Guide
description: Step-by-step guide for transitioning from separate workflows to the unified release system
---

# 📋 Migration Guide: Unified Release Workflow

## Overview

This guide explains how to migrate from the **old system** (4 separate workflows) to the **new system** (1 unified workflow + 1 dependency workflow).

---

## System Comparison

### OLD SYSTEM (Before Consolidation)

**4 Separate Workflows:**

1. **Update Dependencies.yml** (Daily schedule)
   - Checks NuGet for package updates
   - Creates/updates PR with updates
   - ↓ Triggers

2. **Release.yml** (Dependency-triggered)
   - Triggered by dependency workflow completion
   - Bumps patch version (manual option for major/minor)
   - Creates release and publishes
   - 🔴 **COMPETING with Workflow 3**

3. **Create Release.yml** (Code commit-triggered)
   - Triggered by push to main with code changes
   - Analyzes conventional commits for version bump
   - Creates release and publishes
   - 🔴 **COMPETING with Workflow 2**

4. **Publish Module.yml** (Standalone)
   - Manual trigger or release published event
   - Re-publishes existing module
   - 🔴 **DUPLICATES logic from Workflow 3**

**Problems:**

- ❌ Workflows 2 and 3 compete, causing race conditions
- ❌ Workflow 4 duplicates Workflow 3 logic
- ❌ 250+ lines of duplicated code
- ❌ Single bug fix requires changes in 3+ places
- ❌ Confusing for new contributors

---

### NEW SYSTEM (After Consolidation)

**2 Workflows:**

1. **Update Dependencies.yml** (Daily schedule)
   - Checks NuGet for package updates
   - Creates/updates PR with updates
   - Auto-merges when ready
   - ↓ Triggers code push to main
   - ✅ **SINGLE SOURCE OF TRUTH**

2. **Release.yml** (Unified)
   - Triggered by: code push, manual dispatch, OR dependency PR merge
   - Single path for ALL release scenarios
   - Analyzes version OR accepts manual input
   - Creates release and publishes
   - ✅ **USES 5 HELPER SCRIPTS** (tested separately)
   - ✅ **NO COMPETITION**, no duplication

**Benefits:**

- ✅ Single source of truth for release logic
- ✅ No competing workflows
- ✅ Bug fixes in one place
- ✅ Clear, sequential job dependencies
- ✅ Reusable helper scripts can be tested independently
- ✅ 125+ lines removed from workflows

---

## Migration Steps

### STEP 1: Review Unified Workflow ✅ DONE

**Action:** You have reviewed `release.yml` and understand:

- ✅ It triggers on: push to main, manual dispatch, or dependency merge
- ✅ It uses helper scripts created in Phase 2
- ✅ It has 6 sequential jobs with clear dependencies
- ✅ It includes approval gates for publishing

**Status:** ✅ Complete (workflow created and documented)

---

### STEP 2: Configure Required Secrets

**Action:** Ensure these secrets are configured in repository:

1. **PSGALLERY_API_KEY** (Required for `publish` job)
   - Location: Settings → Secrets and variables → Actions → New repository secret
   - Value: Your PowerShell Gallery API token
   - Get token: <https://www.powershellgallery.com/account/apikeys>
   - Check existing: Go to Settings → Secrets and look for PSGALLERY_API_KEY

```bash
# Verify the secret exists (you won't see the value)
# Go to Settings → Secrets and variables → Actions
# You should see: PSGALLERY_API_KEY (with green checkmark)
```

**Recommendation:** If PSGALLERY_API_KEY is already set for old workflows, it's already available for the new one.

---

### STEP 3: Configure Approval Gates

**Action:** Set up approval gate for publishing (optional but recommended)

1. Go to **Settings → Environments**
2. Click **New environment** (or use existing `psgallery` if it exists)
3. Enter name: `psgallery`
4. Click **Configure environment**
5. Check **Required reviewers** checkbox
6. Add team members who can approve releases (e.g., project maintainers)
7. Click **Save protection rules**

**Why this matters:**

- Prevents accidental publishes to live gallery
- Ensures second pair of eyes on releases
- Provides control point for release management

**If you don't configure this:**

- Publish job will proceed without approval
- Still recommended to add at least one reviewer

---

### STEP 4: Test Code Commit Trigger

**Action:** Make a test code change and verify the new workflow triggers correctly

**Test Steps:**

1. Create a feature branch:

   ```bash
   git checkout -b test/release-workflow-validation
   ```

2. Make a small code change in `src/DLLPickle/`:

   ```bash
   # Example: Add a comment or update a function
   echo "# Test change for workflow validation" >> src/DLLPickle/Imports.ps1
   ```

3. Commit with conventional commit message:

   ```bash
   git commit -m "test: validate release workflow triggers correctly"
   ```

4. Push and create a PR:

   ```bash
   git push origin test/release-workflow-validation
   # Then create PR on GitHub
   ```

5. Get review and merge to main:

   ```bash
   # After PR approval and checks pass, click "Merge to main"
   ```

6. **Verify workflow triggered:**
   - Go to **Actions** tab
   - Look for **Release and Publish** workflow
   - Verify it shows as running or completed
   - Click to see job details:
     - ✅ `analyze` - Detected test commit, should NOT release (no conventional bump)
     - OR ✅ `analyze` - Detected test commit, WILL release with patch bump if it's a fix
     - ✅ `update-version` - Updated manifest
     - ✅ `build-and-test` - Ran build and tests
     - ✅ `create-release` - Created release tag
     - ⏳ `publish` - Waiting for approval (if configured)

**Expected Result:**

- Workflow runs automatically
- Build and tests pass
- Version is bumped appropriately

**If something goes wrong:**

- Check workflow run details
- Review error messages in job logs
- Common issues:
  - Build failed: Fix compilation errors in the code change
  - Test failed: Fix test failures (tests must pass before publishing)
  - Approval timeout: Visit workflow run, click "Review deployments", approve

---

### STEP 5: Test Dependency Update Trigger

**Action:** Verify dependency updates still trigger releases correctly

**Test Steps:**

1. Let the dependency workflow run naturally (scheduled for 2 AM UTC daily)
   OR manually trigger it:
   - Go to **Actions → 1 - Update Dependencies**
   - Click **Run workflow**
   - Select **Run workflow**

2. Wait for workflow to complete
   - If updates found, it creates/updates a PR
   - PR auto-merges when checks pass

3. **Verify release workflow triggered:**
   - When PR merges to main, code push event triggers `release.yml`
   - Go to **Actions → Release and Publish**
   - Verify workflow is running with dependency version bump

**Expected Result:**

- Dependency updates are detected
- PR is created (or updated if one exists)
- PR auto-merges to main
- Release workflow triggers automatically
- Version is bumped with patch increment

**If something goes wrong:**

- Check `1 - Update Dependencies` workflow logs for API errors
- Verify NuGet package names are correct in `Packages.json`
- Check that dependency update PR auto-merge is not blocked by branch protection

---

### STEP 6: Configure Approval (If Not Done)

**Action:** Complete the approval gate configuration

**In the UI:**

1. After testing, go to the `publish` job in a workflow run
2. If it shows "Waiting for approval", click "Review deployments"
3. Select the "psgallery" environment
4. Click "Approve" to approve the deployment

**Result:**

- Workflow continues and publishes to gallery
- Next time, approval step will require review from configured reviewers

---

### STEP 7: Validate Against Live Gallery

**Action:** Verify the published version appears on PowerShell Gallery

**Validation:**

```powershell
# After publish job completes, verify module is on gallery
Find-Module -Name DLLPickle -Repository PSGallery | 
  Select-Object Name, Version, PublishedDate, Description

# Expected output:
# Name      Version PublishedDate Description
# ----      ------- ------------- -----------
# DLLPickle 1.X.X   MM/DD/YYYY    ...
```

**If version doesn't appear:**

- Wait 30-60 seconds (gallery indexing can be slow)
- Check `publish` job log for error messages
- Verify PSGallery_API_KEY is correct
- Check that version isn't already published

---

### STEP 8: Update Team Documentation

**Action:** Update your team's internal documentation (wiki, README, etc.)

**Update these places:**

- Team wiki: Point to new release process
- README.md: Update release instructions
- CONTRIBUTING.md: Update contribution guide
- Team Slack/Teams: Announce new unified workflow

**Key message:**

- Old: "Create Release and Publish Module workflows were separate"
- New: "Release and Publish workflow handles all scenarios"
- Action: "No changes to how you work, workflow just works better internally"

---

### STEP 9: Monitor First Full Cycle

**Action:** Let the system run for 1-2 complete cycles before removing old workflows

**Timeline:**

- Week 1: Test with code commit (STEP 4 above)
- Week 2: Test with dependency update (STEP 5 above)
- Week 3: Monitor dependency workflow's next scheduled run
- Then: Remove legacy workflows (STEP 10)

**Monitor:**

- Watch Actions tab for any failures
- Review workflow logs for warnings
- Check PSGallery for successful publishes
- Get feedback from team

---

### STEP 10: Remove Legacy Workflows ⏳ PENDING

**Action:** Delete old workflows after validation complete

**Delete these files:**

```bash
# Remove competing release workflow
git rm '.github/workflows/2 - Release.yml'

# Remove standalone publish workflow  
git rm '.github/workflows/4 - Publish Module.yml'

# Keep these (they still work with new system):
# - '.github/workflows/1 - Update Dependencies.yml' (creates PRs)
# - '.github/workflows/2 - Build Module - Windows.yml' (PR checks)
# - '.github/workflows/release.yml' (new unified workflow)
```

**Commit:**

```bash
git add .github/workflows/
git commit -m "chore: remove legacy workflows (consolidated to release.yml)

- Remove '2 - Release.yml' (consolidated into unified release.yml)
- Remove '4 - Publish Module.yml' (consolidated into unified release.yml)
- Keep '1 - Update Dependencies.yml' (still creates dependency PRs)
- All release logic now in single 'release.yml' workflow

This completes the workflow consolidation started in Phase 2.
Unified workflow is tested and validated through both:
- Code commit trigger (conventional commits for version bumping)
- Dependency update trigger (from dependency workflow)
"

git push origin main
```

**Why wait before removing:**

- Ensures no edge cases or issues we missed
- Gives team time to understand new system
- Allows rollback if problems discovered
- Validates both trigger pathways work

---

## Rollback Plan (If Needed)

**Unlikely but possible:** If you discover critical issues with the unified workflow

**Rollback Steps:**

1. Restore deleted workflows from git history:

   ```bash
   git checkout HEAD~1 '.github/workflows/2 - Release.yml'
   git checkout HEAD~1 '.github/workflows/4 - Publish Module.yml'
   ```

2. Commit restoration:

   ```bash
   git add .github/workflows/
   git commit -m "revert: restore legacy workflows (rollback from unified)"
   ```

3. Stop using unified workflow:
   - Go to Actions tab
   - Click "Disable workflow" on `release.yml`

4. **Root cause analysis:**
   - What specific issue occurred?
   - Was it in unified workflow itself or helper scripts?
   - Can it be fixed without full rollback?

---

## FAQ

### Q: Will the unified workflow break existing release processes?

**A:** No. The new workflow does the same thing as the old system, just more efficiently. Users don't need to change how they work.

### Q: What if I need to release multiple times in one day?

**A:** The new workflow supports this. Each code push or manual dispatch creates a new release. No limitations.

### Q: Can I skip a release for a specific commit?

**A:** Yes! Use commit message flags:

```bash
git commit -m "docs: update readme [skip-release]"
# or
git commit -m "chore: update deps [no-release]"
```

### Q: How do I manually release a specific version bump?

**A:** Use workflow dispatch:

1. Go to Actions → Release and Publish
2. Click "Run workflow"
3. Select version_bump: "major", "minor", or "patch"
4. Click "Run workflow"

### Q: What if approval timeout expires?

**A:** The workflow job will stay pending until you manually approve or reject:

1. Go to the workflow run
2. Click "Review deployments"
3. Click "Approve" or "Reject"

### Q: Can I run multiple releases in parallel?

**A:** No. The workflow uses `concurrency` to prevent parallel releases:

```yaml
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
```

This ensures releases happen sequentially, preventing race conditions.

### Q: What if my PSGallery API key expires?

**A:** The `publish` job will fail with an authentication error:

1. Generate new API key at <https://www.powershellgallery.com/account/apikeys>
2. Update secret: Settings → Secrets and variables → Actions → PSGALLERY_API_KEY
3. Re-run the failed workflow or trigger a new one

### Q: How do I know if a release was successful?

**A:** Check multiple places:

1. **GitHub Actions:** Release and Publish workflow shows all green checkmarks
2. **GitHub Releases:** New release appears at /releases with version tag
3. **PowerShell Gallery:** Version appears in `Find-Module -Name DLLPickle` results

---

## Post-Migration Checklist

- [ ] Step 1: Reviewed unified workflow (DONE)
- [ ] Step 2: Verified/configured PSGALLERY_API_KEY secret
- [ ] Step 3: Set up approval gates in psgallery environment
- [ ] Step 4: Tested code commit trigger
- [ ] Step 5: Tested dependency update trigger
- [ ] Step 6: Approved test publish
- [ ] Step 7: Validated version on PSGallery
- [ ] Step 8: Updated team documentation
- [ ] Step 9: Monitored 1-2 complete cycles
- [ ] Step 10: Removed legacy workflows (when ready)

---

## Summary

The migration from separate workflows to the unified system is:

- ✅ **Non-breaking** - Users don't change how they work
- ✅ **Low-risk** - New workflow uses proven helper scripts
- ✅ **Reversible** - Can rollback if issues discovered
- ✅ **Gradual** - Test before removing old workflows
- ✅ **Well-documented** - Clear steps and troubleshooting

The new system is **simpler, safer, and more maintainable** than the old one. Enjoy the consolidation!
