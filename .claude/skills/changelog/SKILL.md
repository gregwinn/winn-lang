---
name: changelog
description: Generate a CHANGELOG entry from recent git commits since the last tag.
disable-model-invocation: true
---

# Generate Changelog Entry

Generate a CHANGELOG.md entry from git history since the last release tag.

## Steps

### 1. Get the last tag and commits since then

```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
git log ${LAST_TAG}..HEAD --oneline --no-merges
```

### 2. Categorize commits

Group commits into these categories:
- **Language Features** — new syntax, keywords, operators
- **Testing Framework** — test-related changes
- **Tooling** — CLI commands, docs generator, watch, etc.
- **Compiler** — codegen, transform, parser, lexer internals
- **Bug Fixes** — anything starting with "Fix:" or "fix:"
- **Documentation** — docs-only changes

### 3. Generate the entry

Format as:

```markdown
## [Unreleased]

### Language Features
- **Feature name** — brief description

### Tooling
- **`winn command`** — brief description

### Bug Fixes
- **Fix description** — what was broken and how it was fixed
```

### 4. Update CHANGELOG.md

Insert the new entry after the `# Changelog` header and before the previous version entry. If an `[Unreleased]` section exists, replace it.

### 5. Show the diff

Show the user what was added to CHANGELOG.md so they can review.
