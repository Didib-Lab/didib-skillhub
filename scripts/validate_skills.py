#!/usr/bin/env python3
"""Validate every skill in this repository.

A skill is a directory under ``skills/`` that contains a ``SKILL.md`` whose
YAML frontmatter declares ``name`` and ``description``. This script is the
single source of truth for the rules; CI runs it on every pull request and
contributors are expected to run it locally before pushing.

Exit codes:
    0  all skills valid
    1  at least one validation error
    2  the skills directory is missing or unreadable

Usage:
    python scripts/validate_skills.py
    python scripts/validate_skills.py --repo-root .
    python scripts/validate_skills.py --json > index.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
NAME_MAX = 64
DESCRIPTION_MAX = 1024
DESCRIPTION_MIN = 20

#: Directories a skill may contain in addition to SKILL.md.
STANDARD_DIRS = ("references", "scripts", "assets", "agents", "evals")

#: Directories that must not exist at the top level of a skill folder.
FORBIDDEN_DIRS = (".git", "node_modules", "__pycache__")

#: File names that must never be committed.
FORBIDDEN_FILES = (".DS_Store", "Thumbs.db", "desktop.ini")

#: Files Contributors may add next to SKILL.md.
OPTIONAL_FILES = ("LICENSE", "README.md", "skill.json")

#: Simple scalars we accept in frontmatter, with their expected reader.
SCALAR_FIELDS = ("name", "description", "version", "license", "author", "homepage")
LIST_FIELDS = ("tags", "allowed-tools")

MAX_SKILL_MD_BYTES = 512 * 1024  # 512 KiB is plenty for prose + examples.

#: Text extensions worth scanning for credentials. Everything else is skipped
#: so that binaries and large assets do not slow the scan down.
SCANNED_SUFFIXES = {
    ".md", ".markdown", ".txt", ".json", ".yaml", ".yml", ".toml", ".ini",
    ".cfg", ".conf", ".env", ".sh", ".bash", ".zsh", ".ps1", ".psm1", ".py",
    ".js", ".mjs", ".cjs", ".ts", ".rb", ".go", ".rs", ".java", ".c", ".h",
    ".cpp", ".hpp", ".csv", ".xml", ".html", ".sql",
}

#: (label, compiled pattern). Deliberately conservative — a false positive costs
#: a contributor one rewrite, a false negative leaks a live credential.
SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("GitHub personal access token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{50,}\b")),
    ("OpenAI API key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}\b")),
    ("Anthropic API key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{24,}\b")),
    ("AWS access key id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("Stripe secret key", re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{20,}\b")),
    ("npm token", re.compile(r"\bnpm_[A-Za-z0-9]{36}\b")),
    ("JSON Web Token", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("private key block", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----")),
)


def mask(match: re.Match[str]) -> str:
    """Describe a match without printing the secret itself."""
    text = match.group(0)
    return f"{match.group(0)[:4]}…{len(text)} chars"


# --------------------------------------------------------------------------
# Minimal frontmatter parser
# --------------------------------------------------------------------------


class FrontmatterError(Exception):
    """Raised when the frontmatter block cannot be parsed."""


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def split_frontmatter(text: str) -> tuple[str, str]:
    """Return ``(frontmatter, body)`` for a SKILL.md document."""
    if not text.startswith("---"):
        raise FrontmatterError(
            "SKILL.md must start with a '---' delimited YAML frontmatter block; "
            "the first line must be exactly '---'"
        )
    lines = text.splitlines()
    # Line 0 is the opening '---'; find the closing delimiter.
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])

    raise FrontmatterError("frontmatter block is never closed with '---'")


def parse_frontmatter(block: str) -> dict[str, object]:
    """Parse the small YAML subset used by skill frontmatter.

    Supports ``key: value`` scalars and block lists::

        tags:
          - git
          - release

    Inline lists (``tags: [git, release]``) are supported too.
    """
    data: dict[str, object] = {}
    pending_key: str | None = None

    for raw_line in block.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        stripped = raw_line.strip()
        is_indented = raw_line[:1].isspace()

        if stripped.startswith("- "):
            if pending_key is None:
                raise FrontmatterError(
                    f"list item {stripped!r} does not belong to any key"
                )
            item = _unquote(stripped[2:])
            existing = data.setdefault(pending_key, [])
            if not isinstance(existing, list):
                raise FrontmatterError(
                    f"key {pending_key!r} is a scalar but has list items"
                )
            existing.append(item)
            continue

        if is_indented:
            raise FrontmatterError(
                f"unexpected indented line {stripped!r}; only block lists are supported"
            )

        if ":" not in stripped:
            raise FrontmatterError(f"line {stripped!r} is not a 'key: value' pair")

        key, _, value = stripped.partition(":")
        key = key.strip()
        value = value.strip()

        if not key:
            raise FrontmatterError(f"line {stripped!r} has an empty key")

        if key in data:
            raise FrontmatterError(f"duplicate frontmatter key {key!r}")

        if value == "":
            pending_key = key
            data[key] = []
            continue

        pending_key = None
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = (
                [_unquote(part) for part in inner.split(",") if part.strip()]
                if inner
                else []
            )
        else:
            data[key] = _unquote(value)

    return data


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------


class Report:
    """Collects errors and warnings for one repository run."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def scan_for_secrets(skill_dir: Path, report: Report) -> None:
    """Error on credential-shaped strings inside a skill's text files."""
    rel = skill_dir.name

    for path in sorted(skill_dir.rglob("*")):
        if not path.is_file():
            continue
        # Never scan a .git directory that a contributor dragged in.
        if any(part in FORBIDDEN_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in SCANNED_SUFFIXES:
            continue
        if path.stat().st_size > 2 * 1024 * 1024:
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        for label, pattern in SECRET_PATTERNS:
            for match in pattern.finditer(text):
                line_number = text.count("\n", 0, match.start()) + 1
                report.error(
                    rel,
                    f"possible {label} in {path.relative_to(skill_dir)}:"
                    f"{line_number} ({mask(match)}); remove it and rotate the "
                    "credential",
                )


def validate_skill(skill_dir: Path, report: Report, seen_names: dict[str, str]) -> dict | None:
    """Validate one skill directory. Returns its index entry, or None."""
    rel = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.is_file():
        report.error(rel, "missing SKILL.md")
        return None

    scan_for_secrets(skill_dir, report)

    try:
        raw = skill_md.read_bytes()
    except OSError as exc:  # pragma: no cover - filesystem level failure
        report.error(rel, f"cannot read SKILL.md: {exc}")
        return None

    if len(raw) > MAX_SKILL_MD_BYTES:
        report.error(
            rel,
            f"SKILL.md is {len(raw) // 1024} KiB; keep it under "
            f"{MAX_SKILL_MD_BYTES // 1024} KiB and move detail into references/",
        )

    if raw.startswith(b"\xef\xbb\xbf"):
        report.warn(
            rel,
            "SKILL.md starts with a UTF-8 byte order mark; save it as "
            "'UTF-8 without BOM' (Notepad: Encoding -> UTF-8)",
        )
        raw = raw[3:]

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        report.error(rel, f"SKILL.md is not valid UTF-8: {exc}")
        return None

    # --- frontmatter -------------------------------------------------------
    try:
        block, body = split_frontmatter(text)
        meta = parse_frontmatter(block)
    except FrontmatterError as exc:
        report.error(rel, str(exc))
        return None

    # --- name --------------------------------------------------------------
    name = meta.get("name")
    if not isinstance(name, str) or not name:
        report.error(rel, "frontmatter must declare a non-empty 'name'")
        return None

    if not NAME_RE.match(name):
        report.error(
            rel,
            f"name {name!r} must be kebab-case: lowercase letters, digits and "
            "single hyphens (e.g. 'pdf-table-extract')",
        )
    if len(name) > NAME_MAX:
        report.error(rel, f"name is {len(name)} chars; maximum is {NAME_MAX}")
    if name != skill_dir.name:
        report.error(
            rel,
            f"name {name!r} must match its directory name {skill_dir.name!r}",
        )
    if name in seen_names:
        report.error(rel, f"name {name!r} is already used by {seen_names[name]}")
    else:
        seen_names[name] = rel

    # --- description -------------------------------------------------------
    description = meta.get("description")
    if not isinstance(description, str) or not description:
        report.error(rel, "frontmatter must declare a non-empty 'description'")
    else:
        if len(description) > DESCRIPTION_MAX:
            report.error(
                rel,
                f"description is {len(description)} chars; maximum is "
                f"{DESCRIPTION_MAX}",
            )
        if len(description) < DESCRIPTION_MIN:
            report.warn(
                rel,
                f"description is only {len(description)} chars; explain both what "
                "the skill does and when to use it",
            )
        lowered = description.lower()
        if not any(word in lowered for word in ("use when", "use this", "when the user")):
            report.warn(
                rel,
                "description does not say when to use the skill; add a "
                "'Use when ...' clause so agents can route to it",
            )

    # --- optional scalars --------------------------------------------------
    for field in SCALAR_FIELDS:
        if field in meta and not isinstance(meta[field], str):
            report.error(rel, f"frontmatter key {field!r} must be a scalar string")

    for field in LIST_FIELDS:
        if field in meta and not isinstance(meta[field], list):
            report.error(rel, f"frontmatter key {field!r} must be a list")

    unknown = set(meta) - set(SCALAR_FIELDS) - set(LIST_FIELDS)
    if unknown:
        report.warn(
            rel,
            "unknown frontmatter key(s) "
            + ", ".join(sorted(repr(k) for k in unknown))
            + "; they are ignored by the index but harmless",
        )

    # --- body --------------------------------------------------------------
    if not body.strip():
        report.error(rel, "SKILL.md has frontmatter but no body content")
    else:
        headings = [line for line in body.splitlines() if line.startswith("# ")]
        if not headings:
            report.warn(rel, "body has no level-1 heading")

    # --- layout ------------------------------------------------------------
    entries = sorted(skill_dir.iterdir(), key=lambda p: p.name)
    for entry in entries:
        if entry.is_dir():
            if entry.name in FORBIDDEN_DIRS:
                report.error(rel, f"remove the {entry.name!r} directory before committing")
            elif entry.name not in STANDARD_DIRS:
                report.warn(
                    rel,
                    f"non-standard directory {entry.name!r}; prefer one of "
                    + ", ".join(STANDARD_DIRS),
                )
        elif entry.name not in ("SKILL.md",) + OPTIONAL_FILES:
            report.error(
                rel,
                f"unexpected file {entry.name!r}; keep extra material inside "
                + ", ".join(STANDARD_DIRS),
            )

    for entry in entries:
        if entry.is_file() and entry.name in FORBIDDEN_FILES:
            report.error(rel, f"remove the OS artifact {entry.name!r}")

    for script in list(skill_dir.glob("scripts/**/*.py")) + list(
        skill_dir.glob("scripts/**/*.sh")
    ):
        try:
            script.read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError):
            report.error(rel, f"{script.relative_to(skill_dir)} is not valid UTF-8")

    return {
        "name": name,
        "description": description,
        "path": f"skills/{skill_dir.name}",
        "version": meta.get("version"),
        "license": meta.get("license"),
        "author": meta.get("author"),
        "tags": meta.get("tags", []),
        "files": sorted(
            str(p.relative_to(skill_dir)).replace("\\", "/")
            for p in skill_dir.rglob("*")
            if p.is_file()
        ),
    }


def validate_repo(repo_root: Path) -> tuple[Report, list[dict]]:
    report = Report()
    skills_root = repo_root / "skills"

    if not skills_root.is_dir():
        raise FileNotFoundError(f"{skills_root} does not exist")

    seen_names: dict[str, str] = {}
    index: list[dict] = []

    for entry in sorted(skills_root.iterdir(), key=lambda p: p.name):
        if entry.name.startswith("."):
            continue
        if not entry.is_dir():
            report.error("skills", f"stray file {entry.name!r}; skills live in directories")
            continue
        result = validate_skill(entry, report, seen_names)
        if result is not None:
            index.append(result)

    if not index and not report.errors:
        report.warn("skills", "no skills found yet")

    return report, index


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--repo-root",
        default=".",
        help="repository root containing the skills/ directory (default: .)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the skill index as JSON instead of a human report",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="treat warnings as errors",
    )
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()

    try:
        report, index = validate_repo(repo_root)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"skills": index}, indent=2, ensure_ascii=False))
    else:
        if report.errors:
            print("Errors")
            for item in report.errors:
                print(f"  x {item}")
            print()
        if report.warnings:
            print("Warnings")
            for item in report.warnings:
                print(f"  ! {item}")
            print()
        if not report.errors and not report.warnings:
            print("All checks passed.")

    failed = bool(report.errors) or (args.strict and bool(report.warnings))

    if not args.json:
        status = "FAILED" if failed else "OK"
        print(
            f"{status}: {len(index)} skill(s), "
            f"{len(report.errors)} error(s), {len(report.warnings)} warning(s)"
        )

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
