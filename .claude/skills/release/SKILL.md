---
name: release
description: Release a new version of the Winn language — bumps version, runs tests, tags, creates GitHub release, updates Homebrew formula.
disable-model-invocation: true
---

# Release Winn

Release a new version of the Winn language. Argument: `patch`, `minor`, `major`, or an exact version like `0.2.0`.

## Current State

- App version: !`grep vsn /Users/greg.winn/Documents/Projects/language-winn/apps/winn/src/winn.app.src | sed 's/.*"\(.*\)".*/\1/'`
- Latest tag: !`git -C /Users/greg.winn/Documents/Projects/language-winn describe --tags --abbrev=0 2>/dev/null || echo "none"`
- Branch: !`git -C /Users/greg.winn/Documents/Projects/language-winn rev-parse --abbrev-ref HEAD`

## Steps

Given the release type from `$ARGUMENTS` (default: `patch`):

### 1. Pre-flight checks

- Verify all tests pass: `rebar3 eunit`
- Verify no uncommitted changes: `git status --porcelain`
- If either fails, STOP and report the issue.

### 2. Calculate the new version

- Read current version from `apps/winn/src/winn.app.src` (the `{vsn, "X.Y.Z"}` line)
- If argument is `patch`: bump Z. If `minor`: bump Y, reset Z. If `major`: bump X, reset Y and Z.
- If argument looks like a version number (e.g. `0.2.0`), use it directly.

### 3. Update version in source

- Edit `apps/winn/src/winn.app.src` — update the `{vsn, "..."}` line to the new version.

### 4. Build the escript

- Run `rebar3 escriptize` and verify it succeeds.

### 5. Commit the version bump

- `git add apps/winn/src/winn.app.src`
- `git commit -m "chore: bump version to vNEW_VERSION"`

### 6. Tag and push

- `git tag -a vNEW_VERSION -m "Winn vNEW_VERSION"`
- `git push origin CURRENT_BRANCH`
- `git push origin vNEW_VERSION`

### 7. Create GitHub release

Use `gh release create` with a summary of changes since the last tag:

```
gh release create vNEW_VERSION --title "Winn vNEW_VERSION" --generate-notes
```

### 8. Update Homebrew formula

- Download the source tarball: `curl -sL https://github.com/gregwinn/winn-lang/archive/refs/tags/vNEW_VERSION.tar.gz -o /tmp/winn-NEW_VERSION.tar.gz`
- Compute SHA256: `shasum -a 256 /tmp/winn-NEW_VERSION.tar.gz`
- Clone or update the tap repo: `/tmp/homebrew-winn` (from `gregwinn/homebrew-winn`)
- Edit `Formula/winn.rb`: update the `url` to the new tag and `sha256` to the new hash.
- Commit and push: `git commit -m "Bump to vNEW_VERSION" && git push origin main`

### 9. Report

Print a summary:
- Old version → New version
- GitHub release URL
- Homebrew formula updated
- Remind: users can upgrade with `brew upgrade winn`

## Important

- NEVER release without tests passing.
- NEVER force-push tags.
- If any step fails, stop and report — do not continue with partial state.
- The Homebrew tap repo is at `gregwinn/homebrew-winn`, cloned to `/tmp/homebrew-winn`.
