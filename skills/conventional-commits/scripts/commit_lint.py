#!/usr/bin/env python3
"""Lint a Conventional Commits message. No third-party dependencies.

Usage:
    python commit_lint.py --file -            # read the message from stdin
    python commit_lint.py --file .git/COMMIT_EDITMSG
    python commit_lint.py --message "feat(api): add /v2/token endpoint"
    python commit_lint.py --file - --json     # machine-readable output

Exit codes:
    0  the message complies
    1  the message violates the specification
    2  the input could not be read
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TYPES = (
    "feat",
    "fix",
    "perf",
    "refactor",
    "docs",
    "test",
    "build",
    "ci",
    "chore",
    "style",
    "revert",
)

HEADER_RE = re.compile(
    r"^(?P<type>[a-z]+)"
    r"(?:\((?P<scope>[^()\s]+)\))?"
    r"(?P<breaking>!)?"
    r": (?P<description>.+)$"
)

BREAKING_FOOTER_RE = re.compile(r"^(BREAKING CHANGE|BREAKING-CHANGE): .+", re.MULTILINE)
FOOTER_RE = re.compile(r"^[A-Za-z][A-Za-z-]*: .+$|^[A-Za-z][A-Za-z-]* #\d+$")

HEADER_MAX = 72
BODY_WRAP = 72
DESCRIPTION_MIN = 8

SKIP_PREFIXES = (
    "Merge ",
    "Revert \"",
    "fixup!",
    "squash!",
    "amend!",
)


class Result:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    @property
    def ok(self) -> bool:
        return not self.errors


def lint(message: str, strict: bool = False) -> Result:
    result = Result()

    # Strip comment lines the way git does, then normalise line endings.
    lines = [
        line.rstrip()
        for line in message.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        if not line.lstrip().startswith("#")
    ]
    while lines and not lines[-1].strip():
        lines.pop()
    while lines and not lines[0].strip():
        lines.pop(0)

    if not lines:
        result.error("the message is empty")
        return result

    header = lines[0]

    if header.startswith(SKIP_PREFIXES):
        result.warn(f"'{header.split(' ')[0]}' commits are exempt from the specification")
        return result

    match = HEADER_RE.match(header)
    if not match:
        result.error(
            "header does not match '<type>[optional scope][!]: <description>'; "
            f"got {header!r}"
        )
        return result

    commit_type = match.group("type")
    scope = match.group("scope")
    description = match.group("description")

    if commit_type not in TYPES:
        result.error(
            f"unknown type {commit_type!r}; allowed types are {', '.join(TYPES)}"
        )

    if scope is not None:
        if not re.fullmatch(r"[a-z0-9][a-z0-9._/-]*", scope):
            result.error(f"scope {scope!r} must be lowercase alphanumeric")
        if len(scope) > 32:
            result.warn(f"scope {scope!r} is {len(scope)} chars; keep it short")

    if len(header) > HEADER_MAX:
        result.error(f"header is {len(header)} chars; the limit is {HEADER_MAX}")

    if len(description) < DESCRIPTION_MIN:
        result.error(
            f"description {description!r} is too short to be meaningful "
            f"(minimum {DESCRIPTION_MIN} chars)"
        )

    if description.endswith("."):
        result.error("description must not end with a period")

    if description[0:1].isupper():
        result.warn("description should start lowercase")

    if description.startswith(("add ", "fix ", "update ", "remove ")):
        # These are fine in the imperative, but flag the past-tense forms.
        pass
    if re.match(r"^(added|fixed|updated|removed|changed|refactored)\b", description, re.I):
        result.error(
            f"description {description!r} is not imperative; write "
            "'add ...' instead of 'added ...'"
        )

    if re.search(r"\b(and|also)\b.*\b(and|also)\b", description):
        result.warn("description may be bundling several changes; consider splitting")

    # --- body and footers --------------------------------------------------
    if len(lines) > 1:
        if lines[1].strip():
            result.error("line 2 must be blank, separating the header from the body")
        else:
            rest = lines[2:]

            first_footer = None
            for index, line in enumerate(rest):
                if FOOTER_RE.match(line) or BREAKING_FOOTER_RE.match(line):
                    first_footer = index
                    break

            body = rest[:first_footer] if first_footer is not None else rest
            footers = rest[first_footer:] if first_footer is not None else []

            if body and not body[-1].strip():
                body = body[:-1]

            for line in body:
                if len(line) > BODY_WRAP:
                    result.warn(
                        f"body line is {len(line)} chars; wrap at {BODY_WRAP}"
                    )
                    break

            for line in footers:
                if line.strip() and not (
                    FOOTER_RE.match(line) or BREAKING_FOOTER_RE.match(line)
                ):
                    result.warn(
                        f"footer line {line!r} does not look like 'Token: value'"
                    )
                    break

    # --- breaking changes --------------------------------------------------
    has_bang = bool(match.group("breaking"))
    has_footer = bool(BREAKING_FOOTER_RE.search("\n".join(lines)))

    if has_bang and not has_footer:
        result.error(
            "the '!' marker must be accompanied by a 'BREAKING CHANGE: ...' footer"
        )
    if has_footer and not has_bang:
        result.warn(
            "a BREAKING CHANGE footer is present but the header has no '!' marker"
        )

    if strict:
        result.errors.extend(result.warnings)
        result.warnings = []

    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Lint a Conventional Commits message")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", help="path to a commit message file, or '-' for stdin")
    source.add_argument("--message", "-m", help="the commit message itself")
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument(
        "--strict", action="store_true", help="treat warnings as errors"
    )
    args = parser.parse_args(argv)

    if args.message is not None:
        text = args.message
    elif args.file == "-":
        text = sys.stdin.read()
    else:
        try:
            text = Path(args.file).read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: cannot read {args.file}: {exc}", file=sys.stderr)
            return 2

    result = lint(text, strict=args.strict)

    if args.json:
        print(
            json.dumps(
                {
                    "ok": result.ok,
                    "errors": result.errors,
                    "warnings": result.warnings,
                },
                indent=2,
            )
        )
    else:
        for message in result.errors:
            print(f"x {message}")
        for message in result.warnings:
            print(f"! {message}")
        print("commit message is valid" if result.ok else "commit message is invalid")

    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
