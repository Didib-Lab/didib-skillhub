---
name: hello-world
description: Minimal reference skill that demonstrates the required SKILL.md format for the DDB Skillhub. Use when a contributor wants to see the smallest valid skill, or when verifying that the skill loader picks up installed skills.
version: 1.0.0
license: MIT
author: DDB Skillhub
tags:
  - example
---

# Hello World

This is the smallest skill that passes validation. Copy this directory, rename
it, and replace the frontmatter to start a new skill.

## Instructions

1. Greet the user by name if their name is known; otherwise greet them plainly.
2. State that this is the `hello-world` example skill from the DDB Skillhub.
3. Mention the skill's install path, `~/.agents/skills/hello-world`, so the user
   can confirm the loader found it.

Keep the reply to two sentences. The point of this skill is to prove the
plumbing works, not to be useful.

## What this file demonstrates

- The `---` delimited frontmatter block must be the very first thing in the
  file, with no leading blank line.
- `name` must equal the directory name and be kebab-case.
- `description` must state both what the skill does and when to use it, so an
  agent can route to it without reading the body.
- Everything after the closing `---` is the instruction body.
