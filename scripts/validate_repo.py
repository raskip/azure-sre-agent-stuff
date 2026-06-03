#!/usr/bin/env python3
"""Repository structure validator for azure-sre-agent-stuff.

Lightweight, dependency-light "set and forget" quality gate. Validates:
  1. Skill frontmatter  - each plugins/*/skills/*/SKILL.md has valid YAML
     frontmatter with required keys (name, description, tools) and the name
     matches its directory.
  2. Hook YAML          - each hooks/examples/*.yaml parses and has a valid
     top-level `hooks:` map keyed by known events, each entry typed.
  3. marketplace.json   - both copies (.claude-plugin/ and .github/plugin/)
     are valid JSON and agree on plugin names.
  4. README counts      - skill/hook counts claimed in README.md match what is
     actually on disk (catches docs drifting out of sync).
  5. Markdown links     - relative intra-repo links in every *.md resolve to a
     real file (catches dangling references after renames).

Exit 0 = all good (green). Exit 1 = at least one problem (red).

Run locally:
    python3 scripts/validate_repo.py
Requires PyYAML:
    pip install pyyaml   (CI installs it automatically)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

REPO = Path(__file__).resolve().parent.parent

# Known Azure SRE Agent / Claude-style hook events. Extend as the platform adds more.
VALID_HOOK_EVENTS = {
    "PreToolUse",
    "PostToolUse",
    "UserPromptSubmit",
    "Stop",
    "SubagentStop",
    "Notification",
    "PreCompact",
    "SessionStart",
    "SessionEnd",
}
VALID_HOOK_TYPES = {"command", "prompt"}

errors: list[str] = []
warnings: list[str] = []
checks = 0


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def parse_frontmatter(text: str):
    """Return the YAML frontmatter dict from a markdown file, or None."""
    if not text.startswith("---"):
        return None
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        return None
    return yaml.safe_load(m.group(1))


# ---------------------------------------------------------------------------
# 1. Skills
# ---------------------------------------------------------------------------
skill_files = sorted(REPO.glob("plugins/*/skills/*/SKILL.md"))
skill_count = 0
for sf in skill_files:
    skill_count += 1
    rel = sf.relative_to(REPO)
    try:
        fm = parse_frontmatter(sf.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        err(f"[skill] {rel}: frontmatter YAML parse error: {e}")
        continue
    if fm is None:
        err(f"[skill] {rel}: missing or malformed YAML frontmatter")
        continue
    for key in ("name", "description", "tools"):
        if key not in fm or fm[key] in (None, "", []):
            err(f"[skill] {rel}: missing required frontmatter key '{key}'")
    name = fm.get("name")
    dir_name = sf.parent.name
    if name and name != dir_name:
        err(f"[skill] {rel}: frontmatter name '{name}' != directory '{dir_name}'")
    if isinstance(fm.get("tools"), list) and len(fm["tools"]) == 0:
        err(f"[skill] {rel}: 'tools' is an empty list")
    checks += 1

if skill_count == 0:
    err("[skill] no SKILL.md files found under plugins/*/skills/*/")

# ---------------------------------------------------------------------------
# 2. Hooks
# ---------------------------------------------------------------------------
hook_files = sorted(REPO.glob("hooks/examples/*.yaml")) + sorted(
    REPO.glob("hooks/examples/*.yml")
)
hook_count = 0
for hf in hook_files:
    hook_count += 1
    rel = hf.relative_to(REPO)
    try:
        doc = yaml.safe_load(hf.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        err(f"[hook] {rel}: YAML parse error: {e}")
        continue
    if not isinstance(doc, dict) or "hooks" not in doc:
        err(f"[hook] {rel}: missing top-level 'hooks:' map")
        continue
    hooks = doc["hooks"]
    if not isinstance(hooks, dict) or not hooks:
        err(f"[hook] {rel}: 'hooks:' is empty or not a map")
        continue
    for event, entries in hooks.items():
        if event not in VALID_HOOK_EVENTS:
            err(f"[hook] {rel}: unknown event '{event}'")
        if not isinstance(entries, list) or not entries:
            err(f"[hook] {rel}: event '{event}' must be a non-empty list")
            continue
        for i, entry in enumerate(entries):
            if not isinstance(entry, dict):
                err(f"[hook] {rel}: event '{event}'[{i}] not a mapping")
                continue
            htype = entry.get("type")
            if htype not in VALID_HOOK_TYPES:
                err(f"[hook] {rel}: event '{event}'[{i}] invalid type '{htype}'")
            if htype == "command" and not entry.get("script"):
                err(f"[hook] {rel}: event '{event}'[{i}] command hook missing 'script'")
            if htype == "prompt" and not entry.get("prompt"):
                err(f"[hook] {rel}: event '{event}'[{i}] prompt hook missing 'prompt'")
    checks += 1

if hook_count == 0:
    err("[hook] no hook YAML files found under hooks/examples/")

# ---------------------------------------------------------------------------
# 3. marketplace.json (both copies)
# ---------------------------------------------------------------------------
mp_paths = [
    REPO / ".claude-plugin" / "marketplace.json",
    REPO / ".github" / "plugin" / "marketplace.json",
]
mp_plugin_names = []
for mp in mp_paths:
    rel = mp.relative_to(REPO)
    if not mp.exists():
        warn(f"[marketplace] {rel}: not found")
        continue
    try:
        data = json.loads(mp.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        err(f"[marketplace] {rel}: invalid JSON: {e}")
        continue
    if "plugins" not in data or not isinstance(data["plugins"], list):
        err(f"[marketplace] {rel}: missing 'plugins' list")
        continue
    names = sorted(p.get("name", "") for p in data["plugins"])
    mp_plugin_names.append((rel, names))
    checks += 1

if len(mp_plugin_names) == 2:
    if mp_plugin_names[0][1] != mp_plugin_names[1][1]:
        err(
            "[marketplace] plugin name mismatch between copies: "
            f"{mp_plugin_names[0][1]} vs {mp_plugin_names[1][1]}"
        )

# ---------------------------------------------------------------------------
# 4. README count smoke check
# ---------------------------------------------------------------------------
readme = REPO / "README.md"
if readme.exists():
    text = readme.read_text(encoding="utf-8")
    # Look for "<n> ... skill" and "<n> ... hook" claims.
    skill_claims = [int(n) for n in re.findall(r"(\d+)\s+(?:VM\s+)?(?:example\s+)?skills?\b", text, re.I)]
    hook_claims = [int(n) for n in re.findall(r"(\d+)\s+(?:governance\s+)?hooks?\b", text, re.I)]
    if skill_claims and skill_count not in skill_claims:
        warn(
            f"[readme] skill count on disk ({skill_count}) not among README claims {skill_claims}"
        )
    if hook_claims and hook_count not in hook_claims:
        warn(
            f"[readme] hook count on disk ({hook_count}) not among README claims {hook_claims}"
        )
    checks += 1
else:
    warn("[readme] README.md not found")

# ---------------------------------------------------------------------------
# 5. Relative markdown link check
# ---------------------------------------------------------------------------
# Catches broken intra-repo links (e.g. file renames that leave dangling
# references). Only relative links are checked; external (http/https/mailto)
# and absolute (/...) links are skipped. Anchors (#section) are ignored.
LINK_RE = re.compile(r"\]\(([^)]+)\)")
md_files = [p for p in REPO.rglob("*.md") if ".git" not in p.parts]
link_count = 0
for md in md_files:
    base = md.parent
    try:
        body = md.read_text(encoding="utf-8")
    except OSError as e:
        err(f"[link] {md.relative_to(REPO)}: cannot read ({e})")
        continue
    for m in LINK_RE.finditer(body):
        raw = m.group(1).strip()
        before = raw.split("#", 1)[0].strip()
        if not before:
            continue
        target = before.split()[0].strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "/")):
            continue
        link_count += 1
        resolved = (base / target).resolve()
        if not resolved.exists():
            err(f"[link] {md.relative_to(REPO)}: broken relative link -> {target}")
checks += 1

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
print(f"Validated: {skill_count} skills, {hook_count} hooks, {link_count} links, {checks} check groups.")
for w in warnings:
    print(f"WARN  {w}")
for e in errors:
    print(f"ERROR {e}")

if errors:
    print(f"\nFAILED with {len(errors)} error(s).")
    sys.exit(1)
print(f"\nOK — all checks passed ({len(warnings)} warning(s)).")
sys.exit(0)
