# Skill format reference

A skill is a directory containing a `SKILL.md` file. That is the entire
requirement. Everything else is convention, and the conventions exist so agents
can discover, route to, and load your skill reliably.

## Directory layout

```
skills/<skill-name>/
├── SKILL.md          required — frontmatter plus instructions
├── references/       optional — long-form detail, loaded on demand
├── scripts/          optional — helper executables the skill invokes
├── assets/           optional — templates, images, fixtures
├── agents/           optional — per-runtime configuration
└── evals/            optional — test cases for the skill
```

`<skill-name>` must equal the frontmatter `name` and be kebab-case. Any other
top-level file or directory fails validation — this keeps a skill a skill rather
than a general-purpose folder.

## SKILL.md

The file must begin with a YAML frontmatter block delimited by `---` on lines of
its own, with no leading blank line or BOM:

```markdown
---
name: pdf-table-extract
description: Extract tables from PDF files into CSV or Markdown, preserving merged cells. Use when the user provides a PDF and asks for its tabular data.
version: 1.0.0
license: MIT
author: Your Name
homepage: https://example.com/my-skill
tags:
  - pdf
  - data
allowed-tools:
  - Bash
  - Read
---

# PDF Table Extract

## Instructions

...
```

### Frontmatter fields

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `name` | **yes** | string | kebab-case, ≤ 64 chars, must equal the directory name |
| `description` | **yes** | string | ≤ 1024 chars; states what the skill does *and* when to use it |
| `version` | no | string | semver, for your own change tracking |
| `license` | no | string | SPDX identifier; defaults to the repository's MIT |
| `author` | no | string | attribution, shown nowhere automatically |
| `homepage` | no | string | URL for docs or the upstream project |
| `tags` | no | list | short keywords, rendered in the README catalog |
| `allowed-tools` | no | list | runtimes that honour it use this as a permission hint |

The parser is deliberately small: it accepts `key: value` scalars and block
lists (`- item`), plus inline lists (`[a, b]`). Nested maps, multi-line block
scalars (`>` and `|`), and anchors are not supported. Keep the frontmatter flat.

Unknown keys produce a warning, not an error — they are preserved in
`skills.json` but ignored elsewhere.

### Body

Everything after the closing `---` is the instruction body. Structure it for an
agent that may be reading it mid-task:

- Open with a level-1 heading matching the skill's purpose.
- Use `##` sections with action-oriented names: *Instructions*, *Workflow*,
  *Decision rules*, *Output format*, *Common mistakes*.
- Number sequential steps; use tables for branching decisions.
- Put commands in fenced code blocks with a language tag.
- State the expected output shape explicitly when it matters.
- Add a **When NOT to use this skill** section if a plausible mis-trigger exists.

Agents load the body every time the skill triggers, so keep it focused. Put
exhaustive tables, specifications, and long examples in `references/` and link
to them — those files are read only when the agent needs them.

## How a runtime finds skills

Skills are discovered by scanning a skills directory, one level deep, for
`SKILL.md`. On this platform the default location is:

| Platform | Directory |
| --- | --- |
| macOS / Linux | `~/.agents/skills/<name>/SKILL.md` |
| Windows | `%USERPROFILE%\.agents\skills\<name>\SKILL.md` |

The loader reads the frontmatter of every `SKILL.md` it finds, which is why a
malformed frontmatter block makes the whole skill invisible rather than merely
broken.

## `references/`

Long-form material that would bloat the body. Name files by the question they
answer:

```
references/
├── spec.md          the normative rules
├── examples.md      annotated worked examples
├── api-notes.md     endpoint details and rate limits
└── troubleshooting.md
```

Link to them from the body so an agent knows they exist:

```markdown
Full grammar, including footer edge cases, is in `references/spec.md`.
```

## `scripts/`

Executables the skill tells the agent to run. Keep them dependency-free when
possible — a script that needs `pip install` at run time is a script that fails
unattended.

- Use a shebang and make the file executable (`git update-index --chmod=+x`).
- Accept input from stdin and files, not just hard-coded paths.
- Print machine-readable output with a `--json` flag where useful.
- Exit non-zero only for genuine failure.
- Never embed credentials.

The repository's own `skills/conventional-commits/scripts/commit_lint.py` is a
complete example: standard library only, `--json` supported, documented exit
codes.

## `agents/`

Per-runtime configuration, for runtimes that define one. For example an OpenAI
agent definition might live at `agents/openai.yaml`. Include this directory only
if you actually use such a runtime; it is inert elsewhere.

## `evals/`

Test cases that demonstrate the skill works. A useful eval records the prompt,
the expected behaviour, and a pass/fail assertion:

```json
{
  "evals": [
    {
      "prompt": "Commit the staged changes to the auth module.",
      "assert": "The response proposes a message matching ^(feat|fix|refactor)\\(auth\\): ",
      "notes": "Must read the diff before choosing a type."
    }
  ]
}
```

## Validation rules, in full

Run `python scripts/validate_skills.py` from the repository root. Add `--strict`
to promote warnings to errors, or `--json` for machine-readable output.

**Errors** — the pull request will not merge:

| Rule | Message you will see |
| --- | --- |
| `SKILL.md` exists | `missing SKILL.md` |
| Frontmatter opens and closes with `---` | `frontmatter block is never closed with '---'` |
| Frontmatter parses | `line '...' is not a 'key: value' pair` |
| `name` is present | `frontmatter must declare a non-empty 'name'` |
| `name` is kebab-case | `name 'X' must be kebab-case` |
| `name` matches the directory | `name 'X' must match its directory name 'Y'` |
| `name` is unique | `name 'X' is already used by Y` |
| `name` is ≤ 64 chars | `name is N chars; maximum is 64` |
| `description` is present | `frontmatter must declare a non-empty 'description'` |
| `description` is ≤ 1024 chars | `description is N chars; maximum is 1024` |
| Body is non-empty | `SKILL.md has frontmatter but no body content` |
| Only standard entries | `unexpected file '...'` |
| No OS artifacts | `remove the OS artifact '.DS_Store'` |
| UTF-8 everywhere | `SKILL.md is not valid UTF-8` |

**Warnings** — fix them, but CI still passes:

| Rule | Message you will see |
| --- | --- |
| Description states when to use the skill | `description does not say when to use the skill` |
| Description is substantial | `description is only N chars` |
| Body has a level-1 heading | `body has no level-1 heading` |
| Standard subdirectories | `non-standard directory 'X'` |
| Known frontmatter keys | `unknown frontmatter key(s) 'X'` |
