# Contributing to the DDB Skillhub

Thanks for wanting to publish a skill. This repository exists so that a good
procedure, written once, can be installed by anyone in one command.

There are three ways to contribute, in increasing order of effort:

| I want to… | Do this |
| --- | --- |
| Ask for a skill | Open a [new skill issue](.github/ISSUE_TEMPLATE/new-skill.yml) |
| Report a broken skill | Open a [bug issue](.github/ISSUE_TEMPLATE/broken-skill.yml) |
| Publish a skill | Open a pull request (this document) |

---

## The five-minute path

```bash
# 1. Fork and clone
git clone https://github.com/<you>/didib-skillhub.git
cd didib-skillhub

# 2. Copy the minimal skeleton
cp -R skills/hello-world skills/my-new-skill

# 3. Edit it: rename the frontmatter name and write your instructions
$EDITOR skills/my-new-skill/SKILL.md

# 4. Validate
python scripts/validate_skills.py

# 5. Regenerate the README table and skills.json
python scripts/build_catalog.py

# 6. Commit and push
git checkout -b skill/my-new-skill
git add -A
git commit -m "feat(my-new-skill): add the <what it does> skill"
git push -u origin skill/my-new-skill
```

Then open a pull request against `main`.

---

## Naming rules

The most common reason a pull request is sent back.

| Rule | Good | Bad |
| --- | --- | --- |
| kebab-case, lowercase, digits and single hyphens | `pdf-table-extract` | `PDF_Table_Extract` |
| Matches the directory name exactly | `skills/pdf-table-extract/SKILL.md` with `name: pdf-table-extract` | folder `pdf-tables`, name `pdf-table-extract` |
| Describes the job, not the domain | `pdf-table-extract` | `pdf`, `documents`, `utils` |
| Specific enough that a user would say it | `k8s-manifest-review` | `devops` |
| At most 64 characters | | `extract-tables-from-pdf-files-while-preserving-merged-cells` |
| Not already taken | | reusing `hello-world` |

Reserved names that cannot be used: `skill`, `skills`, `hub`, `ddb-skillhub`,
and anything starting with a dot.

---

## The `description` field

This single line determines whether your skill ever triggers, because it is the
only text an agent sees when deciding which skill to load.

```yaml
# Too vague — nothing routes here
description: Helps with PDFs.

# Too long — the trigger is buried in the middle
description: This skill was created because working with PDF tables is hard. It started as an internal tool in 2023 and has since grown. It handles merged cells, multi-page tables, and rotated pages. It can also handle scanned documents. Use it for PDFs.

# Right — what it does, then when to use it
description: Extract tables from PDF files into CSV or Markdown, preserving merged cells and multi-page headers. Use when the user provides a PDF and asks for its tabular data, wants a spreadsheet built from a report, or needs to convert a datasheet's tables.
```

Write it in the third person, present tense. Include the words a user would
actually type — file types, tool names, and the phrasing of the request. Keep it
under 1024 characters; aim for 150–400.

The body of `SKILL.md` should be instructions, organised as steps, decision
rules, or a checklist. It is not a blog post. If you need more than roughly 500
lines, move the detail into `references/` and point at it.

---

## What CI enforces

`python scripts/validate_skills.py` runs on every pull request. It fails on:

- a missing `SKILL.md`, or frontmatter that is absent, unclosed, or unparsable
- a missing, empty, or non-kebab-case `name`
- a `name` that does not match its directory
- a duplicate `name` already used by another skill
- a missing `description`, or one longer than 1024 characters
- an empty body after the frontmatter
- unexpected top-level entries in the skill directory — extra material belongs
  in `references/`, `scripts/`, `assets/`, `agents/`, or `evals/`
- committed OS artifacts such as `.DS_Store` or `Thumbs.db`
- non-UTF-8 files

It warns (and CI still passes) on a description with no "when to use" clause, a
missing top-level heading, an unusually short description, and unknown
frontmatter keys. Warnings are worth fixing; reviewers will ask.

A second CI job checks that the README catalog is current. Run
`python scripts/build_catalog.py` before your final commit.

---

## Review criteria

A maintainer reads your pull request for:

1. **Triggerability.** Would an agent pick this skill up from the description alone?
2. **Correctness.** Is the procedure actually right? Would it work on a hard case?
3. **Specificity.** Does it encode judgement, or restate what a competent agent already knows?
4. **Honesty.** Does it state its limits and when not to use it?
5. **Safety.** Secrets, destructive commands, and data handling.
6. **Testability.** Did you include the prompt you tested with and its output?

A skill that duplicates an existing one is usually merged into it instead.

---

## Safety requirements

Skills are instructions an agent will follow, so treat them as executable
content:

- **No secrets.** Never commit API keys, tokens, personal data, or internal URLs.
  Refer to environment variables and document how a user supplies them.
- **No unrequested destructive operations.** A skill must not instruct an agent
  to delete, overwrite, or push without user confirmation.
- **No exfiltration.** Do not send file contents or environment variables to a
  network endpoint the user did not ask for.
- **No safety bypasses.** Do not instruct an agent to ignore its own guidelines,
  disable confirmation prompts, or hide what it is doing.
- **Disclose requirements.** If your skill needs network access, a paid API, or
  a specific runtime version, say so in the body.

Report violations privately through [SECURITY.md](SECURITY.md), not in a public
issue.

---

## Licensing

This repository is MIT licensed. By opening a pull request you confirm you have
the right to submit the content and agree to license it under MIT. If you are
porting a skill from elsewhere, check that its license permits redistribution and
credit the original in the skill body.

---

## Style

- Write instructions to the agent in the imperative: "Run `git diff --staged`
  before choosing a type."
- Use fenced code blocks with a language tag.
- Prefer tables for decision rules and checklists for sequences.
- Include a short "When NOT to use this skill" section when a plausible
  mis-trigger exists.
- Spell out acronyms on first use.
- Keep lines under 100 characters so diffs stay readable.
