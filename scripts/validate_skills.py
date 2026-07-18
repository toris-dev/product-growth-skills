#!/usr/bin/env python3
"""Validate the structure and local references of this skill collection."""

from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "app-store-listing-creator",
    "seo-geo-optimizer",
    "flutter-android-performance",
    "flutter-interactive-design",
    "expo-android-performance",
    "expo-interactive-design",
    "toris-flutter-play-store-release",
}
STANDALONE_SKILL = "toris-flutter-play-store-release"
REQUIRED_INTERFACE_KEYS = ("display_name", "short_description", "default_prompt")
IGNORED_SCAN_ROOTS = {
    ROOT / ".git",
    ROOT / ".superpowers",
    ROOT / "docs" / "superpowers",
    ROOT / STANDALONE_SKILL / "tests" / "fixtures",
}
SCAN_SUFFIXES = {".md", ".yaml", ".yml", ".py", ".sh", ".rb", ".properties"}
RUBY_FILENAMES = {"Appfile", "Fastfile", "Gemfile", "Gemfile.lock", "Pluginfile"}
ACTIVE_CONFIG_SUFFIXES = {".yaml", ".yml", ".properties"}
EXECUTABLE_SCRIPTS = {
    "install.sh",
    "update.sh",
    "uninstall.sh",
    "scripts/inspect_flutter_project.sh",
    "scripts/bootstrap_android_fastlane.sh",
    "scripts/validate_release_setup.sh",
    "scripts/encode_secret.sh",
    "scripts/decode_secret.sh",
    "scripts/install_flutter_sdk.sh",
    "tests/run_tests.sh",
}
UNFINISHED_TERMS = ("T" + "BD", "T" + "ODO", "FIX" + "ME", "X" + "XX")
UNFINISHED = re.compile(r"\b(?:" + "|".join(UNFINISHED_TERMS) + r")\b", re.IGNORECASE)
MACHINE_HOME = re.compile(r"/Users/[A-Za-z0-9._-]+/|[A-Za-z]:\\Users\\[^\\]+\\")
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
ACTIVE_PLACEHOLDER = re.compile(r"\b(?:CHANGE_ME|REPLACE_ME|YOUR_[A-Z0-9_]+)\b")
PRIVATE_KEY_BLOCK = re.compile(
    "-----BEGIN " + r"(?:RSA |EC |OPENSSH )?" + "PRIVATE KEY-----"
    + r"\s+[A-Za-z0-9+/=\r\n]{40,}\s+-----END "
    + r"(?:RSA |EC |OPENSSH )?" + "PRIVATE KEY-----"
)
SERVICE_ACCOUNT_PAYLOAD = re.compile(
    r"[\"']type[\"']\s*:\s*[\"']service_account[\"'].*"
    r"[\"']private_key[\"']\s*:\s*[\"'][^\"']{20,}",
    re.DOTALL,
)


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("missing opening YAML delimiter")
    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError("missing closing YAML delimiter") from exc

    values: dict[str, str] = {}
    for line in lines[1:end]:
        match = re.fullmatch(r"([a-z_]+):\s*(.+)", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"\'')
    return values


def interface_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"\s{2}([a-z_]+):\s*(\".*\")\s*", line)
        if match:
            values[match.group(1)] = match.group(2)[1:-1]
    return values


def local_link_errors(path: Path) -> list[str]:
    errors: list[str] = []
    for target in MARKDOWN_LINK.findall(path.read_text(encoding="utf-8")):
        target = target.strip().split("#", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        if not (path.parent / target).resolve().exists():
            errors.append(f"{path.relative_to(ROOT)}: broken local link {target!r}")
    return errors


def scan_content() -> list[str]:
    errors: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(root in path.parents for root in IGNORED_SCAN_ROOTS):
            continue
        if path.suffix.lower() not in SCAN_SUFFIXES and path.name not in RUBY_FILENAMES:
            continue
        text = path.read_text(encoding="utf-8")
        if UNFINISHED.search(text):
            errors.append(f"{path.relative_to(ROOT)}: unfinished marker found")
        if MACHINE_HOME.search(text):
            errors.append(f"{path.relative_to(ROOT)}: machine-specific absolute path found")
        if path.suffix.lower() == ".md":
            errors.extend(local_link_errors(path))
        if path.suffix.lower() == ".md" and any(
            ord(char) > 127 and unicodedata.category(char).startswith("L") for char in text
        ):
            errors.append(f"{path.relative_to(ROOT)}: runtime documentation must be English")
        active_config = (
            path.suffix.lower() in ACTIVE_CONFIG_SUFFIXES | {".rb"}
            or path.name in RUBY_FILENAMES
        ) and not path.name.endswith(".example")
        if active_config:
            if ACTIVE_PLACEHOLDER.search(text):
                errors.append(f"{path.relative_to(ROOT)}: active unsafe placeholder found")
        if PRIVATE_KEY_BLOCK.search(text) or SERVICE_ACCOUNT_PAYLOAD.search(text):
            errors.append(f"{path.relative_to(ROOT)}: credential-shaped content found")
    return errors


def validate_standalone_package(directory: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = directory / "install-manifest.txt"
    if not manifest_path.is_file():
        return [f"{STANDALONE_SKILL}: missing install-manifest.txt"]

    entries = manifest_path.read_text(encoding="utf-8").splitlines()
    if not entries or entries != sorted(set(entries)):
        errors.append(f"{STANDALONE_SKILL}/install-manifest.txt: entries must be sorted and unique")
    for entry in entries:
        candidate = directory / entry
        try:
            candidate.resolve().relative_to(directory.resolve())
        except ValueError:
            errors.append(f"{STANDALONE_SKILL}/install-manifest.txt: path escapes package: {entry!r}")
            continue
        if not entry or Path(entry).is_absolute() or ".." in Path(entry).parts:
            errors.append(f"{STANDALONE_SKILL}/install-manifest.txt: invalid path: {entry!r}")
        elif not candidate.is_file() or candidate.is_symlink():
            errors.append(f"{STANDALONE_SKILL}/install-manifest.txt: missing regular file: {entry!r}")

    for relative in sorted(EXECUTABLE_SCRIPTS):
        path = directory / relative
        if not path.is_file() or not path.stat().st_mode & 0o111:
            errors.append(f"{STANDALONE_SKILL}/{relative}: entrypoint must be executable")
    return errors


def validate_skill(name: str) -> list[str]:
    errors: list[str] = []
    directory = ROOT / name
    skill_path = directory / "SKILL.md"
    interface_path = directory / "agents" / "openai.yaml"

    if not directory.is_dir():
        return [f"{name}: missing skill directory"]
    if not skill_path.is_file():
        errors.append(f"{name}: missing SKILL.md")
    if not interface_path.is_file():
        errors.append(f"{name}: missing agents/openai.yaml")
    if errors:
        return errors

    try:
        metadata = parse_frontmatter(skill_path)
    except ValueError as exc:
        errors.append(f"{name}/SKILL.md: {exc}")
    else:
        if metadata.get("name") != name:
            errors.append(f"{name}/SKILL.md: frontmatter name must equal directory name")
        if not metadata.get("description"):
            errors.append(f"{name}/SKILL.md: description is required")

    skill_text = skill_path.read_text(encoding="utf-8")
    execution_policy = (
        "references/execution-defaults.md"
        if name == STANDALONE_SKILL
        else "../shared-references/execution-defaults.md"
    )
    required_content = {
        "## Quick start": "missing Quick start section",
        "## Definition of done": "missing Definition of done section",
        execution_policy: "missing execution policy link",
    }
    for required, message in required_content.items():
        if required not in skill_text:
            errors.append(f"{name}/SKILL.md: {message}")

    interface = interface_values(interface_path)
    for key in REQUIRED_INTERFACE_KEYS:
        if not interface.get(key):
            errors.append(f"{name}/agents/openai.yaml: quoted {key} is required")
    default_prompt = interface.get("default_prompt", "")
    if f"${name}" not in default_prompt:
        errors.append(f"{name}/agents/openai.yaml: default_prompt must mention ${name}")
    short_description = interface.get("short_description", "")
    if short_description and not 25 <= len(short_description) <= 64:
        errors.append(f"{name}/agents/openai.yaml: short_description must be 25-64 characters")
    if name == STANDALONE_SKILL:
        errors.extend(validate_standalone_package(directory))
    return errors


def main() -> int:
    errors: list[str] = []
    discovered = {path.parent.name for path in ROOT.glob("*/SKILL.md")}
    for name in sorted(discovered - EXPECTED):
        errors.append(f"{name}: unexpected top-level skill directory")
    for name in sorted(EXPECTED):
        errors.extend(validate_skill(name))
    errors.extend(scan_content())

    if errors:
        print("Validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(EXPECTED)} skills successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
