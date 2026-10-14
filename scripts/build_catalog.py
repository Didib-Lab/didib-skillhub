#!/usr/bin/env python3
"""Regenerate the generated artifacts from the repository contents.

Reads the same validation rules as ``validate_skills.py`` and rewrites:

* the table between the ``<!-- catalog:start -->`` and ``<!-- catalog:end -->``
  markers in README.md, and
* ``skills.json``, the machine-readable index.

Both are written as UTF-8 without a byte order mark, so the output is identical
on Windows, macOS, and Linux.

Usage:
    python scripts/build_catalog.py            # rewrite README.md and skills.json
    python scripts/build_catalog.py --check    # exit 1 if either is stale
    python scripts/build_catalog.py --json     # print the index to stdout
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from validate_skills import validate_repo  # noqa: E402

START_MARKER = "<!-- catalog:start -->"
END_MARKER = "<!-- catalog:end -->"

README_NAME = "README.md"
INDEX_NAME = "skills.json"

HEADER = (
    "| Skill | What it does | Tags |\n"
    "| --- | --- | --- |\n"
)


def _escape(text: str) -> str:
    """Make a description safe inside a Markdown table cell."""
    return text.replace("|", "\\|").replace("\n", " ").strip()


def _first_sentence(description: str) -> str:
    """Trim a description to its first sentence, keeping tables readable."""
    for separator in (". ", "? ", "! "):
        index = description.find(separator)
        if index != -1:
            return description[: index + 1]
    return description


def render_table(skills: list[dict]) -> str:
    if not skills:
        return "_No skills yet — be the first to contribute one._\n"

    lines = [HEADER.rstrip("\n")]
    for skill in skills:
        name = skill["name"]
        summary = _escape(_first_sentence(skill.get("description") or ""))
        tags = skill.get("tags") or []
        tag_text = ", ".join(f"`{tag}`" for tag in tags) if tags else "—"
        lines.append(f"| [`{name}`]({skill['path']}) | {summary} | {tag_text} |")

    return "\n".join(lines) + "\n"


def replace_block(readme: str, block: str) -> str:
    if START_MARKER not in readme or END_MARKER not in readme:
        raise ValueError(
            f"README.md must contain both {START_MARKER} and {END_MARKER}"
        )

    head, _, rest = readme.partition(START_MARKER)
    _, _, tail = rest.partition(END_MARKER)
    return f"{head}{START_MARKER}\n{block}{END_MARKER}{tail}"


def render_index(skills: list[dict]) -> str:
    payload = {
        "name": "DDB Skillhub",
        "repository": "Didib-Lab/didib-skillhub",
        "skills": skills,
    }
    return json.dumps(payload, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo-root", default=".", help="repository root")
    parser.add_argument("--check", action="store_true", help="do not write; verify")
    parser.add_argument("--json", action="store_true", help="print the index to stdout")
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()

    try:
        report, skills = validate_repo(repo_root)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if report.errors:
        print("refusing to build the catalog while validation fails:", file=sys.stderr)
        for item in report.errors:
            print(f"  x {item}", file=sys.stderr)
        return 2

    index = render_index(skills)

    if args.json:
        sys.stdout.write(index)
        return 0

    readme_path = repo_root / README_NAME
    index_path = repo_root / INDEX_NAME

    try:
        current_readme = readme_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"error: cannot read {README_NAME}: {exc}", file=sys.stderr)
        return 2

    try:
        current_index = index_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        current_index = None
    except OSError as exc:
        print(f"error: cannot read {INDEX_NAME}: {exc}", file=sys.stderr)
        return 2

    try:
        updated_readme = replace_block(current_readme, render_table(skills))
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.check:
        stale: list[str] = []
        if current_readme != updated_readme:
            stale.append(README_NAME)
        if current_index != index:
            stale.append(INDEX_NAME)
        if stale:
            print(
                f"{' and '.join(stale)} out of date; run "
                "'python scripts/build_catalog.py' and commit the result",
                file=sys.stderr,
            )
            return 1
        print(f"catalog is up to date ({len(skills)} skill(s))")
        return 0

    changed: list[str] = []
    if current_readme != updated_readme:
        readme_path.write_text(updated_readme, encoding="utf-8", newline="\n")
        changed.append(README_NAME)
    if current_index != index:
        index_path.write_text(index, encoding="utf-8", newline="\n")
        changed.append(INDEX_NAME)

    if changed:
        print(f"rewrote {' and '.join(changed)} ({len(skills)} skill(s))")
    else:
        print(f"catalog already up to date ({len(skills)} skill(s))")

    return 0


if __name__ == "__main__":
    sys.exit(main())
