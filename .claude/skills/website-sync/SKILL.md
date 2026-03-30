---
name: website-sync
description: Update the winn-lang-website repo to match the current release — version, features, code examples, roadmap.
disable-model-invocation: true
---

# Sync Website with Latest Release

Update the winn-lang-website to reflect the current state of the Winn language.

**Website repo**: `/home/gregwinn/Projects/Personal/winn-lang-website`
**Language repo**: `/home/gregwinn/Projects/Personal/winn-lang`

## Steps

### 1. Get current version

```bash
grep vsn apps/winn/src/winn.app.src | sed 's/.*"\(.*\)".*/\1/'
```

### 2. Update website index.html

In `/home/gregwinn/Projects/Personal/winn-lang-website/index.html`:

- **Footer version**: Update `Winn vX.Y.Z` to current version
- **Install command**: Verify `brew install gregwinn/winn/winn` is correct
- **Features grid**: Add any new features from CHANGELOG.md [Unreleased] or latest version section
- **Code examples**: Update if syntax has changed
- **Roadmap section**: Move shipped features out, add new planned features
- **Get started steps**: Verify commands still work

### 3. Read CHANGELOG.md for new features

```bash
cat CHANGELOG.md | head -40
```

Compare with what's on the website. Add any missing features.

### 4. Commit and push website changes

```bash
cd /home/gregwinn/Projects/Personal/winn-lang-website
git add -A
git commit -m "Update website for vX.Y.Z"
git push origin main
```

### 5. Verify deployment

```bash
gh run list --repo gregwinn/winn-lang-website --limit 1
```

### 6. Report

- What was updated (version, features, examples, roadmap)
- Deployment status
- URL: https://gregwinn.github.io/winn-lang-website/
