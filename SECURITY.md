# Security Policy

## The threat model for this repository

A skill is not a passive document. It is a set of instructions an AI agent will
follow, sometimes with the ability to read files, execute commands, and reach the
network. **Installing a skill is closer to running a script than to reading a
blog post.** This policy explains what we check, what we promise, and what you
should do yourself.

### What we promise

- Every merged skill has been reviewed by at least one maintainer for secrets,
  destructive instructions, and undisclosed network activity.
- CI rejects committed credentials patterns and non-UTF-8 binaries, and the
  validator enforces the layout so a skill cannot smuggle in unexpected files
  at the top level.
- Reports of malicious or unsafe skills are triaged within 72 hours.
- A skill confirmed unsafe is removed from `main` immediately, and a notice is
  added to the README explaining what happened.

### What we cannot promise

- Review is human and therefore imperfect. A skill may still behave differently
  in your runtime than it did in a reviewer's.
- We do not audit third-party APIs a skill might call, nor the licenses of
  assets a contributor bundled.
- We do not control what a skill's `scripts/` do once you execute them.

## Verify before you install

```bash
# See exactly what would be installed
git clone --depth 1 https://github.com/Didib-Lab/didib-skillhub.git
less didib-skillhub/skills/<name>/SKILL.md
find didib-skillhub/skills/<name> -type f     # anything unexpected?
```

`find` is POSIX; on Windows use
`Get-ChildItem -Recurse didib-skillhub\skills\<name>` instead.

Read for these patterns in particular:

| Pattern | Why it matters |
| --- | --- |
| `curl … \| sh`, `iwr … \| iex` | Executes arbitrary remote code |
| Reading `~/.ssh`, `.env`, `.credentials`, `~/.aws` | Credential access |
| Posting file contents to a URL | Exfiltration |
| `rm -rf`, `git push --force`, `DROP TABLE` without a confirmation step | Destructive |
| Instructions to ignore guidelines or hide actions | Safety bypass |
| Obfuscated or base64-encoded payloads | Concealment |

A legitimate skill that needs a credential documents the environment variable
name and lets you supply it. It does not read your home directory.

## Reporting a vulnerability

**Do not open a public issue.** Use one of:

- GitHub's private advisory form:
  <https://github.com/Didib-Lab/didib-skillhub/security/advisories/new>
- A direct message to a maintainer on GitHub if the form is unavailable.

Include, as far as you can:

1. the skill name and the file or line involved,
2. what the skill does that it should not,
3. the impact — what an agent following it would expose or destroy,
4. a minimal reproduction, such as the prompt that triggers it,
5. whether the issue is already public anywhere.

## What happens next

| Timeframe | Action |
| --- | --- |
| Within 72 hours | A maintainer acknowledges the report |
| Within 7 days | Triage: confirmed, not reproducible, or by design |
| On confirmation | The skill is removed from `main`; the reporter is credited if they wish |
| After remediation | A short note is added to the README, and the contributor is contacted |

We will keep you informed through the advisory thread and will credit you in the
final notice unless you ask us not to.

## Scope

In scope: skills in this repository, the installers in `scripts/`, and the CI
workflows.

Out of scope: vulnerabilities in the agent runtime you use to load skills, in
third-party services a skill calls, and in your own configuration. Report those
to the relevant project — but do tell us if a skill in this repository makes such
an issue worse.

## For contributors

Before opening a pull request, confirm:

- no secrets, tokens, or personal data anywhere in the diff, including in
  examples and commit history;
- no instruction that destroys data, force-pushes, or deletes without asking the
  user first;
- no network call the user did not ask for;
- every external requirement is disclosed in the skill body.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full checklist.
