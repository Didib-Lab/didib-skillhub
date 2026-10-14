---
name: conventional-commits
description: Write, review, and validate Conventional Commits messages so changelogs and semantic releases can be generated automatically. Use when the user asks for a commit message, asks to commit staged changes, wants a PR squash title, needs to fix a bad commit message, or when a repo enforces commitlint / semantic-release conventions.
version: 1.0.0
license: MIT
author: DDB Skillhub
tags:
  - git
  - release
  - changelog
---

# Conventional Commits

Produce commit messages that comply with [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
and that tooling such as `commitlint`, `semantic-release`, and `standard-version`
can parse without manual cleanup.

## The shape of a message

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

A commit that only changes the message itself must still parse; anything the
parser cannot read is invisible to the changelog.

## Workflow

1. **Read the actual change before writing a word.** Run `git diff --staged`
   (or `git diff` when nothing is staged). Never infer the type from the file
   name or from what the user said they were doing.
2. **Pick exactly one type** using the table below. If a change spans two
   types, that is a signal to split it into two commits — say so instead of
   picking the "bigger" one.
3. **Pick a scope** from the repository's existing scopes. Discover them with:
   ```bash
   git log --format='%s' -500 | grep -oP '^\w+\(([^)]+)\)' | sort -u
   ```
   Omit the scope when the change is genuinely repo-wide.
4. **Write the description** in the imperative mood, lowercase, no trailing
   period, at most 72 characters including the type and scope prefix.
5. **Add a body** only when the diff cannot speak for itself — record *why*,
   not *what*. Wrap at 72 columns.
6. **Add footers** for breaking changes and issue references.
7. **Validate** before handing the message over:
   ```bash
   python scripts/commit_lint.py --file -   # lint a message from stdin
   ```

## Type selection

| Type | Use it when the change… | Triggers a release |
| --- | --- | --- |
| `feat` | adds a capability a user can observe | minor |
| `fix` | repairs incorrect behaviour | patch |
| `perf` | makes existing behaviour faster without changing it | patch |
| `refactor` | restructures code with no behaviour change | none |
| `docs` | touches documentation only | none |
| `test` | adds or repairs tests only | none |
| `build` | changes the build system or dependencies | none |
| `ci` | changes CI configuration or scripts | none |
| `chore` | routine maintenance not covered above | none |
| `style` | formatting only, no semantic change | none |
| `revert` | reverts an earlier commit | none |

`feat` and `fix` are the only types that generate changelog entries by default.
If something user-visible would be missing from the changelog, it is almost
always a `feat` or a `fix`.

## Breaking changes

Signal a breaking change **twice** — with `!` and with a footer:

```
feat(api)!: drop support for the v1 token endpoint

BREAKING CHANGE: requests to /v1/token now return 410. Clients must migrate
to /v2/token, which accepts the same payload.
```

The `!` makes the change visible at a glance in `git log --oneline`; the
`BREAKING CHANGE:` footer is what release tooling actually reads. Use the
uppercase spelling exactly — `BREAKING-CHANGE:` is accepted as a synonym,
`breaking change:` is not.

## Footers

```
Refs: #412
Closes: #418, #420
Co-authored-by: Jae <jae@example.com>
Reviewed-by: Kim <kim@example.com>
```

One token, then `: ` or ` #`, then the value. `Closes` and `Fixes` must contain
the issue reference for GitHub to close the issue automatically.

## Common mistakes to correct

- `feat: Added new login flow.` — past tense and a trailing period. Write
  `feat(auth): add SSO login flow`.
- `fix: bugfix` — says nothing. Name the symptom that is gone.
- `update stuff` — no type. The parser drops the commit from the changelog.
- `feat: add user API and fix the login redirect` — two types in one commit.
  Split it.
- `BREAKING CHANGE` inside the description line instead of the footer — release
  tooling will not see it.

## Reference material

- `references/spec.md` — the complete v1.0.0 grammar, including edge cases for
  footers, revert commits, and merge commits.
- `references/examples.md` — twenty real messages annotated with why they pass
  or fail, plus the correct rewrite for each failure.
- `scripts/commit_lint.py` — dependency-free linter used by the workflow above.

## When NOT to use this skill

Repositories that enforce a different convention (for example Gerrit
`Change-Id` trailers without types, or a corporate ticket-prefix scheme) should
follow their own rules. Detect this first:

```bash
git log --format='%s' -20
```

If none of the last twenty subjects contains a colon-delimited type, the repo
does not use Conventional Commits — match the existing style instead.
