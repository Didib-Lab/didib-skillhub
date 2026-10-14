# Annotated examples

Twenty messages, each with the verdict and — where relevant — the rewrite. Use
these as the reference set when reviewing someone else's commit message.

## Passing

**1. Simple feature**
```
feat: add CSV export to the reports page
```
Correct type, imperative description, no period, 42 characters.

**2. Scoped fix**
```
fix(parser): handle unclosed string literals
```
The scope names the module, not the file.

**3. Breaking change, both markers**
```
feat(api)!: remove the deprecated v1 token endpoint

BREAKING CHANGE: /v1/token now returns 410. Migrate to /v2/token, which
accepts the same payload and returns the same shape.
```
`!` for humans scanning `git log`, footer for the release tool.

**4. Body carrying the reasoning**
```
perf(search): drop the redundant index scan

The planner was choosing a sequential scan because the partial index did
not cover the ORDER BY clause. Rewriting the query to sort in memory keeps
p95 latency under 40 ms for result sets below 10k rows.

Benchmarks: 12.4 ms -> 3.1 ms on the 500k-row fixture.
```
The body explains *why*, which the diff cannot.

**5. Issue linking**
```
fix(auth): stop rotating the refresh token twice

Closes: #412
```
GitHub closes #412 automatically on merge.

**6. Multiple footers**
```
docs: document the retry semantics of the sync client

Refs: #98
Reviewed-by: Kim <kim@example.com>
```

**7. Revert with reference**
```
revert: remove the speculative cache warming

Refs: 676104e
```

**8. Dependency bump**
```
build(deps): bump cryptography from 42.0.2 to 42.0.5
```
`build` for dependencies, `ci` for pipeline configuration.

**9. CI change**
```
ci: cache the pnpm store between runs
```

**10. Test-only change**
```
test(billing): cover proration across a month boundary
```

**11. Refactor with no behaviour change**
```
refactor: extract the retry policy into its own module
```
If behaviour changed, this is not a refactor — use `fix` or `feat`.

**12. Style-only change**
```
style: apply ruff format to the scheduler package
```

**13. Documentation-only change**
```
docs(readme): correct the installation command
```

**14. Chore**
```
chore: remove the unused legacy migration script
```

## Failing

**15. Past tense and a trailing period**
```
feat: Added new login flow.
```
Two violations: non-imperative description, trailing period.
→ `feat(auth): add SSO login flow`

**16. No type at all**
```
update dependencies
```
The parser drops this commit from the changelog entirely.
→ `build(deps): bump requests to 2.32.0`

**17. Meaningless description**
```
fix: bugfix
```
Says nothing about the symptom that is gone.
→ `fix(upload): reject files larger than the 25 MB limit`

**18. Two changes in one commit**
```
feat: add the user API and fix the login redirect
```
Two types, two reviews, two changelog entries. Split it:
`feat(api): add the user endpoint` + `fix(auth): honour the redirect target on login`

**19. Breaking change hidden in the body**
```
refactor: rename the config keys

Note that `timeout` is now `request_timeout` and old keys are rejected.
```
The prose is invisible to release tooling, so no major version bump happens.
→
```
refactor(config)!: rename the timeout key to request_timeout

BREAKING CHANGE: configurations using `timeout` are now rejected at startup.
Rename the key to `request_timeout`.
```

**20. Scope as a file path**
```
fix(src/components/forms/Input.tsx): correct the label association
```
Scopes name a *section of the codebase*, not a file. Long scopes also blow the
72-character header budget.
→ `fix(forms): correct the label association on the input`

## Review checklist

When reviewing a commit message, ask in this order:

1. Does the type match the diff? (`git diff --staged --stat` is enough.)
2. Is the description imperative, lowercase, and free of a trailing period?
3. Is the header ≤ 72 characters?
4. Is there exactly one logical change?
5. If behaviour is broken for a caller, is `!` **and** `BREAKING CHANGE:` present?
6. Are issue references in footers rather than the body?
