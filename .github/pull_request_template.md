<!--
Thanks for contributing to the DDB Skillhub. Keep the description short: what
the skill does and when an agent should use it.
-->

## What does this pull request add or change?

<!-- One or two sentences. For a new skill, include its name. -->

## Type of change

- [ ] New skill
- [ ] Update to an existing skill
- [ ] Hub tooling, docs, or CI

## Checklist

- [ ] The skill lives at `skills/<name>/SKILL.md` and `<name>` matches the
      frontmatter `name` and is kebab-case.
- [ ] The `description` says both **what** the skill does and **when** to use
      it, so an agent can route to it without reading the body.
- [ ] `python scripts/validate_skills.py` passes locally.
- [ ] `python scripts/build_catalog.py` has been run, so the README table is
      up to date (CI checks this).
- [ ] The skill contains no secrets, tokens, API keys, or credentials.
- [ ] The skill does not instruct an agent to exfiltrate data, disable safety
      checks, or run destructive commands without confirmation.
- [ ] Extra material lives in `references/`, `scripts/`, `assets/`, `agents/`,
      or `evals/` — nothing else is in the skill directory.
- [ ] I have the right to submit this content and license it under the
      repository's MIT license.

## How was it tested?

<!--
Describe the prompt you gave an agent and what it produced. Paste the raw
output rather than a summary. If the skill needs a specific runtime or tool,
say which one and its version.
-->

## Related issues

<!-- e.g. Closes #12 -->
