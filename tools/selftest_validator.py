#!/usr/bin/env python3
"""Ad-hoc exercise of the validator's rules against deliberately broken skills.

Not part of the repository's CI; run it by hand when changing validation logic:

    python tools/selftest_validator.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = REPO_ROOT / "scripts" / "validate_skills.py"


def skill(root: Path, name: str, body: str, extra: dict[str, str] | None = None) -> None:
    directory = root / "skills" / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "SKILL.md").write_text(body, encoding="utf-8")
    for filename, content in (extra or {}).items():
        target = directory / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


GOOD = """---
name: {name}
description: Use when testing that {name} validates, because it is a well formed skill.
tags:
  - test
---

# {name}

Body content.
"""


def run(root: Path) -> tuple[int, str]:
    process = subprocess.run(
        [sys.executable, str(VALIDATOR), "--repo-root", str(root)],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return process.returncode, process.stdout + process.stderr


CASES: list[tuple[str, dict[str, str], str, int]] = [
    (
        "name does not match directory",
        {"wrong-dir": GOOD.format(name="other-name")},
        "must match its directory name",
        1,
    ),
    (
        "uppercase name",
        {"BadName": GOOD.format(name="BadName")},
        "must be kebab-case",
        1,
    ),
    (
        "description without a trigger clause",
        {"vague": "---\nname: vague\ndescription: Does things with files and other things.\n---\n\n# Vague\n\nBody.\n"},
        "does not say when to use the skill",
        0,  # a warning, not an error
    ),
    (
        "missing description",
        {"nodesc": "---\nname: nodesc\n---\n\n# Nodesc\n\nBody.\n"},
        "must declare a non-empty 'description'",
        1,
    ),
    (
        "unclosed frontmatter",
        {"unclosed": "---\nname: unclosed\ndescription: Use when testing unclosed frontmatter.\n\nBody.\n"},
        "never closed with '---'",
        1,
    ),
    (
        "no frontmatter at all",
        {"bare": "# Bare\n\nBody only.\n"},
        "the first line must be exactly '---'",
        1,
    ),
    (
        "empty body",
        {"emptybody": "---\nname: emptybody\ndescription: Use when testing an empty body case.\n---\n"},
        "no body content",
        1,
    ),
    (
        "stray top-level file",
        {"stray": GOOD.format(name="stray")},
        "unexpected file",
        1,
    ),
    (
        "OS artifact",
        {"osjunk": GOOD.format(name="osjunk")},
        "OS artifact",
        1,
    ),
    (
        "committed GitHub token",
        {"leaky": "---\nname: leaky\ndescription: Use when checking that secrets are caught.\n---\n\n# Leaky\n\nkey: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n"},
        "GitHub personal access token",
        1,
    ),
    (
        "committed private key",
        {"keyfile": "---\nname: keyfile\ndescription: Use when checking that key blocks are caught.\n---\n\n# Key\n\n-----BEGIN RSA PRIVATE KEY-----\n"},
        "private key block",
        1,
    ),
    (
        "description that is too long",
        {"longdesc": "---\nname: longdesc\ndescription: " + ("x" * 1100) + "\n---\n\n# Long\n\nBody.\n"},
        "maximum is 1024",
        1,
    ),
]

PASSING = {
    "good-one": GOOD.format(name="good-one"),
    "good-two": GOOD.format(name="good-two"),
}


def main() -> int:
    failures: list[str] = []

    for label, skills, expected, expected_code in CASES:
        root = Path(tempfile.mkdtemp(prefix="skillhub-selftest-"))
        try:
            directory = root / "skills" / next(iter(skills))
            directory.mkdir(parents=True, exist_ok=True)
            name, content = next(iter(skills.items()))
            (directory / "SKILL.md").write_text(content, encoding="utf-8")

            if label == "stray top-level file":
                (directory / "notes.txt").write_text("junk", encoding="utf-8")
            if label == "OS artifact":
                (directory / ".DS_Store").write_text("x", encoding="utf-8")

            code, output = run(root)
            ok = code == expected_code and expected.lower() in output.lower()
            print(f"{'PASS' if ok else 'FAIL'}  {label}")
            if not ok:
                failures.append(
                    f"{label}\n    expected {expected!r} with exit {expected_code}\n"
                    f"    got exit {code}\n{output}"
                )
        finally:
            shutil.rmtree(root, ignore_errors=True)

    # A clean tree must pass with zero diagnostics.
    root = Path(tempfile.mkdtemp(prefix="skillhub-selftest-"))
    try:
        for name, content in PASSING.items():
            skill(root, name, content)
        code, output = run(root)
        ok = code == 0 and "0 error" in output and "0 warning" in output
        print(f"{'PASS' if ok else 'FAIL'}  clean tree passes")
        if not ok:
            failures.append(f"clean tree\n    got exit {code}\n{output}")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # A UTF-8 BOM warns but does not fail.
    root = Path(tempfile.mkdtemp(prefix="skillhub-selftest-"))
    try:
        directory = root / "skills" / "bom"
        directory.mkdir(parents=True)
        (directory / "SKILL.md").write_bytes(
            b"\xef\xbb\xbf" + GOOD.format(name="bom").encode("utf-8")
        )
        code, output = run(root)
        ok = code == 0 and "byte order mark" in output
        print(f"{'PASS' if ok else 'FAIL'}  BOM warns without failing")
        if not ok:
            failures.append(f"BOM case\n    got exit {code}\n{output}")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # Duplicate names across directories must be rejected.
    root = Path(tempfile.mkdtemp(prefix="skillhub-selftest-"))
    try:
        skill(root, "dup-a", GOOD.format(name="dup-a"))
        skill(root, "dup-b", GOOD.format(name="dup-a"))
        code, output = run(root)
        ok = code == 1 and "already used by" in output
        print(f"{'PASS' if ok else 'FAIL'}  duplicate names rejected")
        if not ok:
            failures.append(f"duplicate names\n    got exit {code}\n{output}")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # Build output inside a skill must not reach the catalog, or the generated
    # index would depend on whether anyone happened to run Python that day.
    root = Path(tempfile.mkdtemp(prefix="skillhub-selftest-"))
    try:
        skill(root, "cachey", GOOD.format(name="cachey"), {"scripts/helper.py": "print('hi')\n"})
        cache = root / "skills" / "cachey" / "scripts" / "__pycache__"
        cache.mkdir(parents=True, exist_ok=True)
        (cache / "helper.cpython-312.pyc").write_bytes(b"\x00\x01\x02")

        process = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "build_catalog.py"),
             "--repo-root", str(root), "--json"],
            capture_output=True, text=True, encoding="utf-8",
        )
        listed: list[str] = []
        if process.returncode == 0:
            index = json.loads(process.stdout)
            for entry in index.get("skills", []):
                listed.extend(entry.get("files", []))

        leaked = [name for name in listed if "__pycache__" in name or name.endswith(".pyc")]
        ok = not leaked and "scripts/helper.py" in listed
        print(f"{'PASS' if ok else 'FAIL'}  build output stays out of the catalog")
        if not ok:
            failures.append(
                "build output exclusion\n"
                f"    listed files: {listed}\n"
                f"    exit {process.returncode}\n{process.stdout}{process.stderr}"
            )
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print()
    if failures:
        print(f"{len(failures)} case(s) failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("all validator self-tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
