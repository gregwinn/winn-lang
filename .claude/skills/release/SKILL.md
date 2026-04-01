---
name: release
description: Release a new version of the Winn language — bumps version, runs tests, tags, creates GitHub release, updates Homebrew formula, and syncs the website.
disable-model-invocation: true
---

# Release Winn

Release a new version of the Winn language. Argument: `patch`, `minor`, `major`, or an exact version like `0.4.0`.

## Current State

- App version: !`grep vsn /home/gregwinn/Projects/Personal/winn-lang/apps/winn/src/winn.app.src | sed 's/.*"\(.*\)".*/\1/'`
- Latest tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "none"`
- Branch: !`git rev-parse --abbrev-ref HEAD`

## Steps

Given the release type from `$ARGUMENTS` (default: `patch`):

### 1. Pre-flight checks

- Verify all tests pass: `rebar3 eunit`
- Verify no uncommitted changes: `git status --porcelain`
- If either fails, STOP and report the issue.

### 2. Calculate the new version

- Read current version from `apps/winn/src/winn.app.src` (the `{vsn, "X.Y.Z"}` line)
- If argument is `patch`: bump Z. If `minor`: bump Y, reset Z. If `major`: bump X, reset Y and Z.
- If argument looks like a version number (e.g. `0.4.0`), use it directly.

### 3. Update version in ALL source files

- `apps/winn/src/winn.app.src` — the `{vsn, "..."}` line
- `apps/winn/src/winn_cli.erl` — the fallback `"0.X.Y"` in `get_version/0`
- `apps/winn/src/winn_repl.erl` — the fallback `"0.X.Y"` in `get_version/0`

### 4. Update CHANGELOG.md

- Replace `## [Unreleased]` with `## [NEW_VERSION] - YYYY-MM-DD`
- Add a new empty `## [Unreleased]` section above it

### 5. Build the escript

- Run `rebar3 escriptize` and verify it succeeds.
- Verify version: `./_build/default/bin/winn version`

### 6. Commit the version bump

- `git add apps/winn/src/winn.app.src apps/winn/src/winn_cli.erl apps/winn/src/winn_repl.erl CHANGELOG.md`
- `git commit -m "chore: bump version to vNEW_VERSION"`

### 7. Tag and push

- `git tag vNEW_VERSION`
- `git push origin CURRENT_BRANCH --tags`

### 8. Create GitHub release

```
gh release create vNEW_VERSION --title "vNEW_VERSION" --generate-notes
```

### 9. Update Homebrew formula

- Get SHA256: `curl -sL https://github.com/gregwinn/winn-lang/archive/refs/tags/vNEW_VERSION.tar.gz | sha256sum`
- Update `gregwinn/homebrew-winn` Formula/winn.rb via GitHub API:
  - Update `url` to new tag
  - Update `sha256` to new hash
- Commit message: "Update winn to vNEW_VERSION"

### 10. Update ALL docs (CRITICAL)

Update version references across ALL documentation files:
- `README.md` — version in install verify section
- `docs/getting-started.md` — version in verify and help text sections
- `docs/cli.md` — version in `winn version` example
- `docs/roadmap.md` — move shipped items to "What's Shipped" table, update "Coming Next" tables. Roadmap MUST link to GitHub issues, NEVER contain stale plans for shipped features.
- `docs/orm.md` — if database features changed
- `CLAUDE.md` — test count, CLI commands list

### 11. Update website (CRITICAL)

Run the `/website-sync` skill or manually:
- Update version in footer of `/home/gregwinn/Projects/Personal/winn-lang-website/index.html`
- Update version in `build-docs.sh` template footer
- Add any new features to the features grid
- Sync `docs/*.md` from winn-lang to winn-lang-website: `cp docs/*.md ../winn-lang-website/docs/`
- Commit and push the website repo
- Verify deploy succeeds: `gh run list --repo gregwinn/winn-lang-website --limit 1`

### 12. Update VS Code extension (if syntax changed)

If new keywords, operators, or syntax were added:
- Update `syntaxes/winn.tmLanguage.json` in `gregwinn/language-winn-vscode`
- Update `language-configuration.json` for folding/indentation
- Bump `package.json` version
- Clone, `npm install`, `npm run compile`, `npx @vscode/vsce publish`

### 13. Close milestone (if applicable)

If this is a minor/major release, check if there's a matching milestone to close:
```
gh api repos/gregwinn/winn-lang/milestones?state=open
```

### 14. Report

Print a summary:
- Old version → New version
- GitHub release URL
- Homebrew formula updated
- Docs updated (list files)
- Website updated and deployed
- VS Code extension (if updated)
- Milestone closed (if applicable)
- Remind: users can upgrade with `brew upgrade winn`

## Important

- NEVER release without tests passing.
- NEVER force-push tags.
- NEVER skip docs, website, or roadmap updates — this is CRITICAL.
- The roadmap MUST link to GitHub issues. NEVER leave stale planned sections for shipped features.
- If any step fails, stop and report — do not continue with partial state.
