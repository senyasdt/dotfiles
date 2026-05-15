import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path


# ============================================================
# Output path
# ============================================================

def get_vial_helper_dir() -> Path:
    custom_dir = os.environ.get("VIAL_HELPER_DIR")
    if custom_dir:
        return Path(custom_dir).expanduser()

    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "vial-helper"
        return Path.home() / "AppData" / "Roaming" / "vial-helper"

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "vial-helper"

    xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config_home:
        return Path(xdg_config_home) / "vial-helper"

    return Path.home() / ".config" / "vial-helper"


VIAL_HELPER_DIR = get_vial_helper_dir()
OUTPUT_FILE = VIAL_HELPER_DIR / "ahk_bindings.json"


# ============================================================
# Parsing regexes
# ============================================================

HOTKEY_RE = re.compile(
    r"""
    ^\s*
    (?P<hotkey>[^;\s][^:]*)   # everything before ::
    ::
    (?P<body>.*?)             # one-line body, may be empty or {
    (?:\s*;\s*(?P<comment>.*))?
    \s*$
    """,
    re.VERBOSE,
)

HOTIF_RE = re.compile(
    r"^\s*#HotIf(?:\s+(?P<expr>.*?))?\s*$",
    re.IGNORECASE,
)

LAYER_SECTION_RE = re.compile(r"^\s*;\s*(LAYER\s+\d+.*)$", re.IGNORECASE)
PROFILE_SECTION_RE = re.compile(r"^\s*;\s*(.+Macropad Profile.*)$", re.IGNORECASE)

WINACTIVE_STRING_RE = re.compile(
    r"""
    WinActive
    \(
        \s*
        ["']
        (?P<value>.*?)
        ["']
        \s*
    \)
    """,
    re.IGNORECASE | re.VERBOSE,
)

AHK_EXE_RE = re.compile(
    r"\bahk_exe\s+([^\s]+)",
    re.IGNORECASE,
)

AHK_CLASS_RE = re.compile(
    r"\bahk_class\s+([^\s]+)",
    re.IGNORECASE,
)


AHK_MODIFIERS = {
    "^": "Ctrl",
    "+": "Shift",
    "!": "Alt",
    "#": "Win",
}

SIDE_PREFIX = {
    "<": "L",
    ">": "R",
}


# ============================================================
# Hotkey normalization
# ============================================================

def normalize_key_name(key: str) -> str:
    key = key.strip()
    lower = key.lower()

    known = {
        "pgdn": "PgDn",
        "pgup": "PgUp",
        "home": "Home",
        "end": "End",
        "insert": "Ins",
        "ins": "Ins",
        "delete": "Del",
        "del": "Del",
        "escape": "Esc",
        "esc": "Esc",
        "space": "Space",
        "tab": "Tab",
        "enter": "Enter",
        "pause": "Pause",
        "printscreen": "PrtSc",
        "prtsc": "PrtSc",
        "scrolllock": "ScrLk",
        "scrlk": "ScrLk",
        "wheelup": "WheelUp",
        "wheeldown": "WheelDown",
        "volume_up": "Volume_Up",
        "volume_down": "Volume_Down",
        "volume_mute": "Volume_Mute",
        "media_play_pause": "Media_Play_Pause",
    }

    if lower in known:
        return known[lower]

    if re.fullmatch(r"f\d{1,2}", lower):
        return lower.upper()

    if len(key) == 1:
        return key.upper()

    return key


def canonicalize_hotkey(hotkey: str) -> str:
    """
    Converts AHK syntax into the same labels vial-helper emits.

    Examples:
      F16      -> F16
      >^F16    -> RCtrl+F16
      >+PgDn   -> RShift+PgDn
      <!F13    -> LAlt+F13
    """

    hotkey = hotkey.strip()

    modifiers: list[str] = []
    i = 0

    while i < len(hotkey):
        ch = hotkey[i]

        # Ignore common AHK hotkey prefixes
        if ch in "~*$":
            i += 1
            continue

        # Side-specific modifier: <^, >+, <! ...
        if ch in SIDE_PREFIX and i + 1 < len(hotkey):
            side = SIDE_PREFIX[ch]
            next_ch = hotkey[i + 1]

            if next_ch in AHK_MODIFIERS:
                modifiers.append(side + AHK_MODIFIERS[next_ch])
                i += 2
                continue

        # Generic modifier: ^, +, !, #
        if ch in AHK_MODIFIERS:
            modifiers.append(AHK_MODIFIERS[ch])
            i += 1
            continue

        break

    key = normalize_key_name(hotkey[i:])

    if not modifiers:
        return key

    return "+".join(modifiers + [key])


# ============================================================
# HotIf parsing
# ============================================================

def parse_hotif_contexts(expr: str | None) -> list[dict]:
    """
    Extracts app matching contexts from common #HotIf expressions.

    Supported examples:
      #HotIf WinActive("ahk_exe ZBrush.exe")
      #HotIf WinActive("ZBrush")
      #HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush")
    """

    if not expr:
        return []

    expr = expr.strip()
    if not expr:
        return []

    contexts: list[dict] = []

    for match in WINACTIVE_STRING_RE.finditer(expr):
        value = match.group("value").strip()

        exe_match = AHK_EXE_RE.search(value)
        if exe_match:
            contexts.append(
                {
                    "kind": "exe",
                    "value": exe_match.group(1),
                }
            )
            continue

        class_match = AHK_CLASS_RE.search(value)
        if class_match:
            contexts.append(
                {
                    "kind": "class",
                    "value": class_match.group(1),
                }
            )
            continue

        if value:
            contexts.append(
                {
                    "kind": "title_contains",
                    "value": value,
                }
            )

    return contexts


# ============================================================
# General parsing helpers
# ============================================================

def clean_comment(comment: str | None) -> str:
    if not comment:
        return ""
    return comment.strip()


def compact_body(body: str) -> str:
    body = body.strip()

    if not body:
        return ""

    if body == "{":
        return "block"

    return re.sub(r"\s+", " ", body)


def make_title(comment: str, body: str, canonical: str) -> str:
    if comment:
        return comment

    body = body.strip()

    if not body:
        return canonical

    if body == "{":
        return "AHK block"

    return body


# ============================================================
# AHK file parsing
# ============================================================

def parse_ahk_file(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8-sig")

    bindings: list[dict] = []

    current_section = ""
    current_hotif_expr = ""
    current_hotif_contexts: list[dict] = []

    for line_no, line in enumerate(text.splitlines(), start=1):
        hotif_match = HOTIF_RE.match(line)
        if hotif_match:
            current_hotif_expr = (hotif_match.group("expr") or "").strip()
            current_hotif_contexts = parse_hotif_contexts(current_hotif_expr)
            continue

        layer_match = LAYER_SECTION_RE.match(line)
        if layer_match:
            current_section = layer_match.group(1).strip()
            continue

        profile_match = PROFILE_SECTION_RE.match(line)
        if profile_match and not current_section:
            current_section = profile_match.group(1).strip()
            continue

        hotkey_match = HOTKEY_RE.match(line)
        if not hotkey_match:
            continue

        hotkey = hotkey_match.group("hotkey").strip()
        body = compact_body(hotkey_match.group("body") or "")
        comment = clean_comment(hotkey_match.group("comment"))

        if not hotkey:
            continue

        canonical = canonicalize_hotkey(hotkey)
        title = make_title(comment, body, canonical)

        bindings.append(
            {
                "canonical": canonical,
                "hotkey": hotkey,
                "title": title,
                "comment": comment,
                "body": body,
                "section": current_section,
                "line": line_no,
                "source": str(path),
                "source_name": path.name,
                "hotif": current_hotif_expr,
                "contexts": list(current_hotif_contexts),
                "contextual": bool(current_hotif_expr),
            }
        )

    return bindings


# ============================================================
# Source discovery
# ============================================================

def collect_ahk_files(source: Path, recursive: bool) -> list[Path]:
    if source.is_file():
        if source.suffix.lower() != ".ahk":
            raise SystemExit(f"Source file is not an .ahk file: {source}")
        return [source]

    if not source.is_dir():
        raise SystemExit(f"Source path does not exist: {source}")

    pattern = "**/*.ahk" if recursive else "*.ahk"

    return sorted(
        path
        for path in source.glob(pattern)
        if path.is_file()
    )


def group_bindings(files: list[Path]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = {}

    for path in files:
        parsed = parse_ahk_file(path)

        for binding in parsed:
            canonical = binding["canonical"]
            grouped.setdefault(canonical, []).append(binding)

    return grouped


def count_variants(grouped: dict[str, list[dict]]) -> int:
    return sum(len(items) for items in grouped.values())


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Export AutoHotkey bindings into vial-helper JSON format."
    )
    parser.add_argument(
        "source",
        help="Path to one .ahk file or a directory containing .ahk files.",
    )
    parser.add_argument(
        "--no-recursive",
        action="store_true",
        help="When source is a directory, only parse *.ahk files directly inside it.",
    )

    args = parser.parse_args()

    source = Path(args.source).expanduser()
    recursive = not args.no_recursive

    files = collect_ahk_files(source, recursive=recursive)

    if not files:
        raise SystemExit(f"No .ahk files found in: {source}")

    grouped = group_bindings(files)

    payload = {
        "schema": 3,
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "source_root": str(source),
        "recursive": recursive,
        "file_count": len(files),
        "hotkey_count": len(grouped),
        "binding_variant_count": count_variants(grouped),
        "files": [str(path) for path in files],
        "bindings": grouped,
    }

    VIAL_HELPER_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Parsed {len(files)} AHK file(s)")
    print(f"Exported {len(grouped)} hotkey(s)")
    print(f"Binding variants: {payload['binding_variant_count']}")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
