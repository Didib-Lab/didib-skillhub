# Conventional Commits v1.0.0 — full grammar

This is the normative summary of the specification the skill follows. When
tooling disagrees with this document, the tooling is authoritative for that
repository; when the two agree, this is the quickest place to check an edge
case.

## 1. Structure

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

1. Commits **MUST** be prefixed with a type, followed by an optional scope, an
   optional `!`, and a mandatory terminal colon and space.
2. The type `feat` **MUST** be used when a commit adds a new feature.
3. The type `fix` **MUST** be used when a commit represents a bug fix.
4. A scope **MAY** be provided after a type, in parentheses, to describe a
   section of the codebase.
5. A description **MUST** immediately follow the colon and space.
6. A longer body **MAY** be provided after the description, beginning one blank
   line after it.
7. The body is free-form and **MAY** consist of multiple paragraphs.
8. One or more footers **MAY** be provided one blank line after the body. Each
   footer **MUST** consist of a word token, followed by either `: ` or ` #`,
   followed by a value.
9. A footer's token **MUST** use `-` in place of whitespace (for example
   `Acked-by`), except for `BREAKING CHANGE`, which **MAY** be used as a token.
10. A footer's value **MAY** contain spaces and newlines; parsing terminates
    when the next valid footer token or the end of the message is observed.
11. Breaking changes **MUST** be indicated either by `!` before the colon in
    the header, by a `BREAKING CHANGE:` footer, or by both.
12. If `!` is used, `BREAKING CHANGE:` **MAY** be omitted from the footer and
    the description **MUST** be used to describe the breaking change.

Types other than `feat` and `fix` are permitted — this skill's list is a
convention, not part of the specification.

## 2. Grammar, informally

```
message      := header blank-line (body blank-line)? footers?
header       := type ("(" scope ")")? "!"? ": " description
type         := /[a-z]+/
scope        := /[a-z0-9][a-z0-9._/-]*/
description  := /.{8,}/          ; this repository's own minimum
footer       := token (": " | " #") value
token        := /[A-Za-z][A-Za-z-]*|[A-Z]{2,}/
```

## 3. Edge cases

### Revert commits

`git revert` produces `Revert "<original subject>"`. The specification does not
forbid this, and changelog generators usually special-case it. When hand-writing
a revert, the `revert` type with a reference to the reverted commit is clearer:

```
revert: let us never again speak of the noodle incident

Refs: 676104e, a215868
```

### Merge commits

Merge commits are exempt. Do not rewrite them to satisfy a linter; configure
the linter with a `Merge ` prefix exemption instead.

### Multi-paragraph bodies

Blank lines separate paragraphs. A line that looks like a footer but is meant
as prose must be reworded, because the parser will treat it as a footer:

```
fix: prevent racing of requests

Introduce a request id and a reference to the latest request. Dismiss
incoming responses other than the one with the matching id.

Reviewed-by: Z
Refs: #123
```

Note that `Reviewed-by` here is a real footer, while a prose line such as
`Note: this only happens under load` would be mis-parsed as a footer token.

### Empty scope

`feat(): add thing` is invalid — either name the scope or drop the parentheses.

### Non-ASCII

Types and footer tokens must be ASCII. Descriptions, bodies, and footer values
may contain any Unicode; the skill's own linter assumes UTF-8 input.

### Trailing whitespace and comment lines

Git strips lines beginning with `#` and trailing blank lines from
`COMMIT_EDITMSG` by default (`cleanup=strip`). A linter invoked on the raw file
must do the same or it will report spurious errors.

## 4. What release tooling reads

| Consumer | Reads |
| --- | --- |
| `semantic-release` | `type`, `scope`, `!`, `BREAKING CHANGE:` footer |
| `commitlint` | the whole header plus configured footer rules |
| `standard-version` | `type`, `scope`, `BREAKING CHANGE:` footer |
| GitHub | `Closes` / `Fixes` / `Resolves` footers for issue linking |
| `git-cliff` | all of the above, plus custom footer parsers |

Tooling reads the footer, never the body — which is why a breaking change
written only as prose in the body is silently lost from the major version bump.
