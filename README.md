# DDB Skillhub

A community library of **agent skills** — self-contained instruction packages
that teach an AI agent how to perform a specific task well. Anyone can publish
a skill here by opening a pull request, and anyone can install one with a single
command.

A skill is just a folder with a `SKILL.md` inside it. No packaging, no build
step, no registry account. If you have written a procedure an agent keeps
getting wrong, that procedure is a skill.

[![validate](https://github.com/Didib-Lab/didib-skillhub/actions/workflows/validate.yml/badge.svg)](https://github.com/Didib-Lab/didib-skillhub/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Available skills

<!-- catalog:start -->
| Skill | What it does | Tags |
| --- | --- | --- |
| [`conventional-commits`](skills/conventional-commits) | Write, review, and validate Conventional Commits messages so changelogs and semantic releases can be generated automatically. | `git`, `release`, `changelog` |
| [`hello-world`](skills/hello-world) | Minimal reference skill that demonstrates the required SKILL.md format for the DDB Skillhub. | `example` |
<!-- catalog:end -->

A machine-readable version of this table is in [`skills.json`](skills.json).

---

## Install a skill

Skills install into `~/.agents/skills/<name>`, where DeepSeek Harness and other
agent runtimes look for them.

### macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Didib-Lab/didib-skillhub/main/scripts/install.sh -o install.sh
chmod +x install.sh

./install.sh list                        # what is available
./install.sh install conventional-commits
./install.sh install --all               # everything
./install.sh uninstall conventional-commits
./install.sh doctor                      # what is installed locally
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/Didib-Lab/didib-skillhub/main/scripts/install.ps1 -OutFile install.ps1
.\install.ps1 list
.\install.ps1 install conventional-commits
.\install.ps1 doctor
```

### Manual

Copy any directory under `skills/` into `~/.agents/skills/`. That is the whole
installation procedure:

```bash
git clone https://github.com/Didib-Lab/didib-skillhub.git
cp -R didib-skillhub/skills/conventional-commits ~/.agents/skills/
```

On Windows, `xcopy /E /I didib-skillhub\skills\conventional-commits "%USERPROFILE%\.agents\skills\conventional-commits"`.

> **Review before you install.** A skill is instructions that your agent will
> follow, which makes it executable in a real sense. Skim `SKILL.md` — and any
> script it ships — before trusting it. See [SECURITY.md](SECURITY.md).

---

## Publish a skill

1. **Fork** this repository and create a branch.
2. **Add your skill** at `skills/<your-skill-name>/SKILL.md`:

   ```
   skills/
   └── your-skill-name/
       ├── SKILL.md          # required
       ├── references/       # optional: deep detail loaded on demand
       ├── scripts/          # optional: helper executables
       ├── assets/           # optional: templates, images
       ├── agents/           # optional: per-runtime config (e.g. openai.yaml)
       └── evals/            # optional: test cases
   ```

   The directory name and the frontmatter `name` must match.

3. **Write the frontmatter.** Only `name` and `description` are required:

   ```markdown
   ---
   name: pdf-table-extract
   description: Extract tables from PDF files into CSV or Markdown, preserving merged cells. Use when the user provides a PDF and asks for its tabular data, or wants a spreadsheet built from a report.
   version: 1.0.0
   license: MIT
   tags:
     - pdf
     - data
   ---

   # PDF Table Extract

   ## Instructions
   ...
   ```

   The `description` is the most important line in the file. It is the only
   thing an agent reads when deciding whether your skill applies, so it must
   answer **what it does** *and* **when to use it**.

4. **Validate and regenerate the catalog:**

   ```bash
   python scripts/validate_skills.py     # must pass with zero errors
   python scripts/build_catalog.py       # updates the table in this README
   ```

5. **Open a pull request.** CI runs the same validator plus a catalog freshness
   check. A maintainer reviews for quality and safety, then merges.

The full rules are in [CONTRIBUTING.md](CONTRIBUTING.md); the format reference
is in [docs/skill-format.md](docs/skill-format.md). A step-by-step walkthrough,
including how organization membership works and what to do when git cannot
reach GitHub, is in
[docs/collaborator-guide.zh-CN.md](docs/collaborator-guide.zh-CN.md)
(中文). New to this? Copy
[`skills/hello-world`](skills/hello-world) as a minimal skeleton or
[`skills/conventional-commits`](skills/conventional-commits) as a fuller
example with references and scripts.

---

## What makes a skill worth merging

| | |
| --- | --- |
| **Scoped** | It does one job. A skill named `do-my-job` will never trigger; `pdf-table-extract` will. |
| **Triggerable** | The description contains the phrases a user would actually say. |
| **Actionable** | The body contains steps, decision rules, and output formats — not background reading. |
| **Honest** | It says when *not* to use it, and what it cannot do. |
| **Safe** | No secrets, no destructive commands without confirmation, no data exfiltration. |
| **Tested** | You ran it against a real prompt and pasted the output in your PR. |

Detail belongs in `references/` rather than the body: agents load the body every
time the skill triggers, but reference files only when needed.

---

## Repository layout

```
.
├── skills/                  one directory per published skill
├── scripts/
│   ├── validate_skills.py   the rules, enforced in CI
│   ├── build_catalog.py     regenerates the table above and skills.json
│   ├── install.sh           macOS / Linux installer
│   └── install.ps1          Windows installer
├── tools/
│   ├── selftest_validator.py      tests the validator against broken skills
│   ├── create-repo.ps1            one-shot bootstrap for the GitHub repository
│   ├── push-via-api.ps1           publish when git's transport is blocked
│   └── diagnose-git-transport.ps1 explains a failing clone, fetch, or push
├── docs/skill-format.md     frontmatter and layout reference
├── .github/workflows/       validation, catalog generation, PR automation
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
└── SECURITY.md
```

## Troubleshooting

### `git push` cannot connect, but `gh` works

Some networks allow GitHub's API through one TLS implementation and block
another. The symptom is a bare connection failure from git:

```
fatal: unable to access 'https://github.com/...': Failed to connect to
github.com port 443 after 21179 ms: Could not connect to server
```

Confirm which layer is broken:

```powershell
./tools/diagnose-git-transport.ps1
```

It probes DNS, raw TCP, a TLS handshake, the .NET HTTP stack, curl, and git in
turn. If DNS, TCP, and HTTPS pass while git fails, the network is fine and only
git's transport is affected. Publish through the API instead — the result is an
ordinary commit that clones and pulls normally:

```powershell
./tools/push-via-api.ps1 -Repo Didib-Lab/didib-skillhub -Branch main -DryRun
./tools/push-via-api.ps1 -Repo Didib-Lab/didib-skillhub -Branch main
```

### Validation fails with `unexpected file`

A skill directory may only contain `SKILL.md` plus `references/`, `scripts/`,
`assets/`, `agents/`, and `evals/` (optionally with a skill-local `README.md`,
`LICENSE`, or `skill.json`). Move anything else into one of those directories.

### The catalog check fails after committing

Run `python scripts/build_catalog.py` and commit the regenerated `README.md` and
`skills.json`. CI fails on a stale catalog on purpose, so the README table can
never disagree with what is actually in `skills/`.

## Governance

- Anyone may propose a skill through an issue or a pull request.
- Two maintainers approve before merge; one is enough for typo-level fixes.
- Skills that no longer work are marked deprecated in the README rather than
  deleted, unless they are unsafe — unsafe skills are removed immediately.
- The license is [MIT](LICENSE). By contributing you agree to license your work
  under the same terms.

## License

[MIT](LICENSE) © DDB Skillhub contributors.
