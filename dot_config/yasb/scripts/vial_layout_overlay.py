import ctypes
import json
import os
import re
import sys
from ctypes import wintypes
from pathlib import Path
import tkinter as tk


# ============================================================
# Vial Helper paths
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

STATE_FILE = VIAL_HELPER_DIR / "state.json"
LAYOUT_FILE = VIAL_HELPER_DIR / "layout.json"
AHK_BINDINGS_FILE = VIAL_HELPER_DIR / "ahk_bindings.json"


# ============================================================
# Visual style
# ============================================================

WINDOW_BG = "#202432"
PANEL_BG = "#2a3040"
CARD_BG = "#353c50"
CARD_BORDER = "#55617c"
ENC_CARD_BG = "#2f3547"

TEXT = "#e2e8f5"
TEXT_MUTED = "#aeb9d2"
ACCENT = "#b9c7e6"
ACCENT_BLUE = "#98b4df"

WINDOW_WIDTH = 610
WINDOW_HEIGHT = 680
WINDOW_ALPHA = 0.94

BODY_WIDTH = 574
BODY_HEIGHT = 520

KEY_W = 56
KEY_H = 50
KEY_GAP = 8

BOTTOM_KEY_W = 60
BOTTOM_KEY_H = 54

PANEL_PAD = 12
PANEL_RADIUS = 16
CARD_RADIUS = 12

ENC_CARD_W = 96
ENC_CARD_H = 88
ENC_CARD_GAP = 10
ENC_KNOB_SIZE = 56

DETAILS_TOP = 316
DETAILS_GAP = 14
DETAILS_PANEL_W = (BODY_WIDTH - DETAILS_GAP) // 2
DETAILS_PANEL_H = 188
DETAILS_PAD = 14
DETAILS_TITLE_Y = 18

MAX_COMBO_ROWS = 6
MAX_TAP_DANCE_ROWS = 4

TD_RE = re.compile(r"^TD\((\d+)\)$")


# ============================================================
# JSON helpers
# ============================================================

def read_json(path: Path, default=None):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def file_mtime_ns(path: Path) -> int:
    try:
        return path.stat().st_mtime_ns
    except Exception:
        return 0


# ============================================================
# Foreground window detection
# ============================================================

def get_active_window_context() -> dict:
    """
    Captures the foreground app BEFORE the Tk popup is created.

    On Windows:
      - exe name
      - process path
      - window title

    On other systems:
      returns an empty context.
    """

    if sys.platform != "win32":
        return {
            "exe": "",
            "exe_lower": "",
            "path": "",
            "title": "",
            "title_lower": "",
        }

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32

    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return {
            "exe": "",
            "exe_lower": "",
            "path": "",
            "title": "",
            "title_lower": "",
        }

    # Window title
    title_length = user32.GetWindowTextLengthW(hwnd)
    title_buffer = ctypes.create_unicode_buffer(title_length + 1)
    user32.GetWindowTextW(hwnd, title_buffer, title_length + 1)
    title = title_buffer.value

    # PID
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    process_handle = kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        False,
        pid.value,
    )

    path = ""
    exe = ""

    if process_handle:
        try:
            buffer_len = wintypes.DWORD(32768)
            path_buffer = ctypes.create_unicode_buffer(buffer_len.value)

            ok = kernel32.QueryFullProcessImageNameW(
                process_handle,
                0,
                path_buffer,
                ctypes.byref(buffer_len),
            )

            if ok:
                path = path_buffer.value
                exe = Path(path).name
        finally:
            kernel32.CloseHandle(process_handle)

    return {
        "exe": exe,
        "exe_lower": exe.lower(),
        "path": path,
        "title": title,
        "title_lower": title.lower(),
    }


# Capture context before popup steals focus
ACTIVE_WINDOW_CONTEXT = get_active_window_context()


# ============================================================
# Label helpers
# ============================================================

def label_of(payload: dict | None, default="—") -> str:
    if not isinstance(payload, dict):
        return default
    return str(payload.get("label", default))


def is_empty_label(label: str) -> bool:
    return label in {"", "—", "NO", "TRNS"}


def compact_label(label: str, max_len: int = 18) -> str:
    label = str(label or "—")
    if len(label) <= max_len:
        return label
    return label[:max_len - 1] + "…"


def ahk_bindings_map(ahk_data: dict) -> dict:
    if not isinstance(ahk_data, dict):
        return {}

    bindings = ahk_data.get("bindings", {})
    if not isinstance(bindings, dict):
        return {}

    return bindings


def context_match_score(binding: dict, active_window: dict) -> int | None:
    """
    Returns:
      - integer score if binding matches current app context
      - None if contextual binding does NOT match

    Score priority:
      exe match            300
      title contains       200
      class match          reserved, currently ignored
      unconditional         50
    """

    contexts = binding.get("contexts", [])
    contextual = bool(binding.get("contextual"))

    if not contextual:
        return 50

    if not contexts:
        return None

    best_score = None

    active_exe = active_window.get("exe_lower", "")
    active_title = active_window.get("title_lower", "")

    for context in contexts:
        if not isinstance(context, dict):
            continue

        kind = str(context.get("kind", "")).strip().lower()
        value = str(context.get("value", "")).strip()

        if not value:
            continue

        value_lower = value.lower()

        if kind == "exe":
            if active_exe and active_exe == value_lower:
                best_score = max(best_score or 0, 300)

        elif kind == "title_contains":
            if active_title and value_lower in active_title:
                best_score = max(best_score or 0, 200)

        elif kind == "class":
            # Reserved for future improvements.
            # We export it already, but do not resolve it in the overlay yet.
            continue

    return best_score


def binding_for_label(label: str, ahk_bindings: dict, active_window: dict) -> dict | None:
    if not label:
        return None

    variants = ahk_bindings.get(label, [])
    if not isinstance(variants, list):
        return None

    best_binding = None
    best_score = -1

    for binding in variants:
        if not isinstance(binding, dict):
            continue

        score = context_match_score(binding, active_window)
        if score is None:
            continue

        if score > best_score:
            best_binding = binding
            best_score = score

    return best_binding


def action_title_for_label(
    label: str,
    ahk_bindings: dict,
    active_window: dict,
    fallback=None,
) -> str:
    binding = binding_for_label(label, ahk_bindings, active_window)

    if binding:
        title = str(binding.get("title", "")).strip()
        if title:
            return title

    if fallback is not None:
        return fallback

    return label


# ============================================================
# Combo / Tap Dance helpers
# ============================================================

def active_entries(entries):
    return [entry for entry in entries if isinstance(entry, dict) and entry.get("active")]


def collect_used_tap_dance_indexes(rows: list, encoder_presses: list, encoders: list) -> set[int]:
    found: set[int] = set()

    def scan_payload(payload):
        label = label_of(payload, "")
        match = TD_RE.match(label)
        if match:
            found.add(int(match.group(1)))

    for row in rows:
        for key in row:
            scan_payload(key)

    for key in encoder_presses:
        scan_payload(key)

    for encoder in encoders:
        if not isinstance(encoder, dict):
            continue
        scan_payload(encoder.get("ccw"))
        scan_payload(encoder.get("cw"))

    return found


def filter_tap_dances_for_layer(all_tap_dances: list, used_indexes: set[int]) -> list:
    result = []

    for entry in all_tap_dances:
        if not isinstance(entry, dict):
            continue

        if not entry.get("active"):
            continue

        index = entry.get("index")
        if index in used_indexes:
            result.append(entry)

    return result


def format_combo_inputs(entry: dict) -> str:
    inputs = entry.get("inputs", [])
    labels = []

    for payload in inputs:
        label = label_of(payload)
        if not is_empty_label(label):
            labels.append(label)

    if not labels:
        return "—"

    return " + ".join(labels)


def format_combo_output(entry: dict, ahk_bindings: dict, active_window: dict) -> str:
    raw_label = label_of(entry.get("output"))
    return action_title_for_label(
        raw_label,
        ahk_bindings,
        active_window,
        fallback=raw_label,
    )


def tap_dance_value(payload: dict | None, ahk_bindings: dict, active_window: dict) -> str:
    raw = label_of(payload)
    return action_title_for_label(
        raw,
        ahk_bindings,
        active_window,
        fallback=raw,
    )


def format_tap_dance_line(entry: dict, ahk_bindings: dict, active_window: dict) -> str:
    index = entry.get("index", "?")
    on_tap = tap_dance_value(entry.get("on_tap"), ahk_bindings, active_window)
    on_hold = tap_dance_value(entry.get("on_hold"), ahk_bindings, active_window)

    parts = []

    if not is_empty_label(on_tap):
        parts.append(f"Tap {on_tap}")

    if not is_empty_label(on_hold):
        parts.append(f"Hold {on_hold}")

    if not parts:
        parts.append("No Tap / Hold")

    return f"TD({index}) · " + " · ".join(parts)


def format_tap_dance_extra(entry: dict, ahk_bindings: dict, active_window: dict) -> str:
    on_double = tap_dance_value(entry.get("on_double_tap"), ahk_bindings, active_window)
    on_tap_hold = tap_dance_value(entry.get("on_tap_hold"), ahk_bindings, active_window)

    parts = []

    if not is_empty_label(on_double):
        parts.append(f"2× {on_double}")

    if not is_empty_label(on_tap_hold):
        parts.append(f"Tap+Hold {on_tap_hold}")

    if not parts:
        return ""

    return " · ".join(parts)


# ============================================================
# Overlay
# ============================================================

class LayoutOverlay:
    def __init__(self):
        self.active_window = ACTIVE_WINDOW_CONTEXT

        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", WINDOW_ALPHA)
        self.root.configure(bg=WINDOW_BG)

        self.root.bind("<Escape>", lambda _event: self.root.destroy())
        self.root.bind("<Button-3>", lambda _event: self.root.destroy())

        self.last_layer = None
        self.last_state_mtime = 0
        self.last_layout_mtime = 0
        self.last_ahk_mtime = 0

        self.outer = tk.Frame(
            self.root,
            bg=WINDOW_BG,
            highlightthickness=1,
            highlightbackground="#46516a",
        )
        self.outer.pack(fill="both", expand=True)

        self.header = tk.Frame(self.outer, bg=WINDOW_BG)
        self.header.pack(fill="x", padx=18, pady=(14, 4))

        self.close_btn = tk.Label(
            self.header,
            text="×",
            fg=TEXT,
            bg=WINDOW_BG,
            font=("Segoe UI", 14),
            cursor="hand2",
        )
        self.close_btn.pack(anchor="w")
        self.close_btn.bind("<Button-1>", lambda _e: self.root.destroy())

        self.title_label = tk.Label(
            self.header,
            text="VIAL LAYOUT",
            fg=ACCENT,
            bg=WINDOW_BG,
            font=("Segoe UI Semibold", 10),
        )
        self.title_label.pack(anchor="w", pady=(5, 0))

        self.layer_label = tk.Label(
            self.header,
            text="",
            fg=TEXT,
            bg=WINDOW_BG,
            font=("Segoe UI Semibold", 17),
        )
        self.layer_label.pack(anchor="w", pady=(5, 0))

        active_app_text = self.format_active_app_label()

        self.hint_label = tk.Label(
            self.header,
            text=f"Esc или ПКМ — закрыть · {active_app_text}",
            fg=TEXT_MUTED,
            bg=WINDOW_BG,
            font=("Segoe UI", 9),
        )
        self.hint_label.pack(anchor="w", pady=(4, 0))

        self.body_wrap = tk.Frame(self.outer, bg=WINDOW_BG)
        self.body_wrap.pack(fill="both", expand=True, padx=18, pady=(6, 12))

        self.body = tk.Canvas(
            self.body_wrap,
            width=BODY_WIDTH,
            height=BODY_HEIGHT,
            bg=WINDOW_BG,
            highlightthickness=0,
            bd=0,
        )
        self.body.pack(anchor="nw")

        self.position_window()
        self.refresh()

    def format_active_app_label(self) -> str:
        exe = self.active_window.get("exe", "")
        title = self.active_window.get("title", "")

        if exe:
            return exe

        if title:
            return compact_label(title, 24)

        return "no app context"

    def position_window(self):
        self.root.update_idletasks()
        screen_w = self.root.winfo_screenwidth()
        x = (screen_w - WINDOW_WIDTH) // 2
        y = 72
        self.root.geometry(f"{WINDOW_WIDTH}x{WINDOW_HEIGHT}+{x}+{y}")

    def draw_rounded_rect(self, canvas, x1, y1, x2, y2, r, fill, outline=None, width=1):
        canvas.create_rectangle(x1 + r, y1, x2 - r, y2, fill=fill, outline=fill)
        canvas.create_rectangle(x1, y1 + r, x2, y2 - r, fill=fill, outline=fill)

        canvas.create_oval(x1, y1, x1 + 2 * r, y1 + 2 * r, fill=fill, outline=fill)
        canvas.create_oval(x2 - 2 * r, y1, x2, y1 + 2 * r, fill=fill, outline=fill)
        canvas.create_oval(x1, y2 - 2 * r, x1 + 2 * r, y2, fill=fill, outline=fill)
        canvas.create_oval(x2 - 2 * r, y2 - 2 * r, x2, y2, fill=fill, outline=fill)

        if outline:
            canvas.create_arc(
                x1, y1, x1 + 2 * r, y1 + 2 * r,
                start=90, extent=90, style="arc", outline=outline, width=width
            )
            canvas.create_arc(
                x2 - 2 * r, y1, x2, y1 + 2 * r,
                start=0, extent=90, style="arc", outline=outline, width=width
            )
            canvas.create_arc(
                x1, y2 - 2 * r, x1 + 2 * r, y2,
                start=180, extent=90, style="arc", outline=outline, width=width
            )
            canvas.create_arc(
                x2 - 2 * r, y2 - 2 * r, x2, y2,
                start=270, extent=90, style="arc", outline=outline, width=width
            )

            canvas.create_line(x1 + r, y1, x2 - r, y1, fill=outline, width=width)
            canvas.create_line(x1 + r, y2, x2 - r, y2, fill=outline, width=width)
            canvas.create_line(x1, y1 + r, x1, y2 - r, fill=outline, width=width)
            canvas.create_line(x2, y1 + r, x2, y2 - r, fill=outline, width=width)

    def draw_key(self, canvas, x, y, w, h, raw_label, ahk_bindings: dict):
        binding = binding_for_label(raw_label, ahk_bindings, self.active_window)

        self.draw_rounded_rect(
            canvas,
            x, y, x + w, y + h,
            CARD_RADIUS,
            fill=CARD_BG,
            outline=CARD_BORDER,
            width=1,
        )

        if binding:
            title = compact_label(str(binding.get("title", raw_label)), 14)

            canvas.create_text(
                x + w / 2,
                y + h / 2 - 5,
                text=title,
                fill=TEXT,
                font=("Segoe UI Semibold", 8),
                width=w - 8,
                justify="center",
            )

            canvas.create_text(
                x + w / 2,
                y + h - 10,
                text=raw_label,
                fill=TEXT_MUTED,
                font=("Segoe UI", 7),
                width=w - 8,
                justify="center",
            )
        else:
            canvas.create_text(
                x + w / 2,
                y + h / 2,
                text=raw_label,
                fill=TEXT,
                font=("Segoe UI Semibold", 13),
                width=w - 10,
                justify="center",
            )

    def draw_encoder_card(self, canvas, x, y, press_label, ccw_label, cw_label, ahk_bindings: dict):
        w = ENC_CARD_W
        h = ENC_CARD_H

        ccw_display = compact_label(
            action_title_for_label(
                ccw_label,
                ahk_bindings,
                self.active_window,
                fallback=ccw_label,
            ),
            10,
        )
        cw_display = compact_label(
            action_title_for_label(
                cw_label,
                ahk_bindings,
                self.active_window,
                fallback=cw_label,
            ),
            10,
        )

        self.draw_rounded_rect(
            canvas,
            x, y, x + w, y + h,
            CARD_RADIUS,
            fill=ENC_CARD_BG,
            outline="",
        )

        cx = x + w / 2
        cy = y + 32
        knob = ENC_KNOB_SIZE
        k1 = knob / 2
        k2 = knob / 2 - 10

        canvas.create_oval(
            cx - k1, cy - k1, cx + k1, cy + k1,
            fill="#45506a",
            outline="#9db1d7",
            width=1,
        )
        canvas.create_oval(
            cx - k2, cy - k2, cx + k2, cy + k2,
            fill="#5d6d8a",
            outline="#d8e1f4",
            width=1,
        )

        canvas.create_text(
            cx,
            cy,
            text=press_label,
            fill=TEXT,
            font=("Segoe UI Semibold", 10),
            width=30,
            justify="center",
        )

        canvas.create_text(
            x + 10,
            y + h - 16,
            text=f"↺ {ccw_display}",
            fill=ACCENT_BLUE,
            font=("Segoe UI", 7),
            anchor="w",
        )
        canvas.create_text(
            x + w - 10,
            y + h - 16,
            text=f"{cw_display} ↻",
            fill=ACCENT_BLUE,
            font=("Segoe UI", 7),
            anchor="e",
        )

    def draw_panel_title(self, canvas, x, y, title):
        canvas.create_text(
            x + DETAILS_PAD,
            y + DETAILS_TITLE_Y,
            text=title,
            fill=ACCENT,
            font=("Segoe UI Semibold", 9),
            anchor="w",
        )

    def draw_empty_panel_line(self, canvas, x, y, text):
        canvas.create_text(
            x + DETAILS_PAD,
            y,
            text=text,
            fill=TEXT_MUTED,
            font=("Segoe UI", 9),
            anchor="w",
        )

    def draw_combo_panel(self, canvas, x, y, combos: list, ahk_bindings: dict):
        self.draw_rounded_rect(
            canvas,
            x, y,
            x + DETAILS_PANEL_W,
            y + DETAILS_PANEL_H,
            PANEL_RADIUS,
            fill=PANEL_BG,
            outline="",
        )

        self.draw_panel_title(canvas, x, y, "COMBOS")

        active_combos = active_entries(combos)

        if not active_combos:
            self.draw_empty_panel_line(canvas, x, y + 54, "No active combos")
            return

        row_y = y + 50

        for combo in active_combos[:MAX_COMBO_ROWS]:
            inputs = compact_label(format_combo_inputs(combo), 18)
            output = compact_label(
                format_combo_output(combo, ahk_bindings, self.active_window),
                11,
            )

            canvas.create_text(
                x + DETAILS_PAD,
                row_y,
                text=inputs,
                fill=TEXT,
                font=("Segoe UI Semibold", 9),
                anchor="w",
            )

            canvas.create_text(
                x + DETAILS_PANEL_W - DETAILS_PAD,
                row_y,
                text=f"→ {output}",
                fill=ACCENT_BLUE,
                font=("Segoe UI", 9),
                anchor="e",
            )

            row_y += 22

        hidden = len(active_combos) - MAX_COMBO_ROWS
        if hidden > 0:
            canvas.create_text(
                x + DETAILS_PAD,
                y + DETAILS_PANEL_H - 18,
                text=f"+{hidden} more",
                fill=TEXT_MUTED,
                font=("Segoe UI", 8),
                anchor="w",
            )

    def draw_tap_dance_panel(self, canvas, x, y, tap_dances: list, ahk_bindings: dict):
        self.draw_rounded_rect(
            canvas,
            x, y,
            x + DETAILS_PANEL_W,
            y + DETAILS_PANEL_H,
            PANEL_RADIUS,
            fill=PANEL_BG,
            outline="",
        )

        self.draw_panel_title(canvas, x, y, "TAP DANCE")

        if not tap_dances:
            self.draw_empty_panel_line(canvas, x, y + 54, "No Tap Dance on this layer")
            return

        row_y = y + 48

        for entry in tap_dances[:MAX_TAP_DANCE_ROWS]:
            line1 = compact_label(
                format_tap_dance_line(entry, ahk_bindings, self.active_window),
                38,
            )
            line2 = compact_label(
                format_tap_dance_extra(entry, ahk_bindings, self.active_window),
                38,
            )

            canvas.create_text(
                x + DETAILS_PAD,
                row_y,
                text=line1,
                fill=TEXT,
                font=("Segoe UI Semibold", 8),
                anchor="w",
            )

            if line2:
                canvas.create_text(
                    x + DETAILS_PAD,
                    row_y + 14,
                    text=line2,
                    fill=ACCENT_BLUE,
                    font=("Segoe UI", 8),
                    anchor="w",
                )
                row_y += 34
            else:
                row_y += 24

        hidden = len(tap_dances) - MAX_TAP_DANCE_ROWS
        if hidden > 0:
            canvas.create_text(
                x + DETAILS_PAD,
                y + DETAILS_PANEL_H - 18,
                text=f"+{hidden} more",
                fill=TEXT_MUTED,
                font=("Segoe UI", 8),
                anchor="w",
            )

    def render_layer(self, layer_index: int, state: dict, layout: dict, ahk_data: dict):
        self.body.delete("all")

        ahk_bindings = ahk_bindings_map(ahk_data)

        layer_names = layout.get("layer_names", {})
        layer_name = layer_names.get(str(layer_index), f"L{layer_index}")
        self.layer_label.config(text=f"{layer_name} · Layer {layer_index}")

        rows = layout.get("layers", {}).get(str(layer_index), [])
        encoders = layout.get("encoders", {}).get(str(layer_index), [])

        rows = [list(row) for row in rows]

        while len(rows) < 4:
            rows.append([])

        top_rows = [list(reversed(row)) for row in rows[:3]]

        row4 = rows[3]

        bottom_keys = []
        if len(row4) >= 4:
            bottom_keys = [row4[3], row4[2]]
        elif len(row4) >= 2:
            bottom_keys = list(reversed(row4[:2]))

        encoder_presses = row4[:2] if len(row4) >= 2 else []

        main_panel_x_rel = 0
        main_panel_y = 6
        main_panel_w = 4 * KEY_W + 3 * KEY_GAP + 2 * PANEL_PAD
        main_panel_h = 3 * KEY_H + 2 * KEY_GAP + 2 * PANEL_PAD

        bottom_panel_x_rel = 98
        bottom_panel_y = main_panel_y + main_panel_h + 10
        bottom_panel_w = 2 * BOTTOM_KEY_W + KEY_GAP + 2 * 10
        bottom_panel_h = BOTTOM_KEY_H + 2 * 10

        enc_panel_x_rel = main_panel_w + 18
        enc_panel_y = 6
        enc_panel_w = ENC_CARD_W + 2 * 10
        enc_panel_h = 2 * ENC_CARD_H + ENC_CARD_GAP + 2 * 10

        content_w = max(
            main_panel_w,
            bottom_panel_x_rel + bottom_panel_w,
            enc_panel_x_rel + enc_panel_w,
        )

        offset_x = (BODY_WIDTH - content_w) // 2
        if offset_x < 0:
            offset_x = 0

        main_panel_x = offset_x + main_panel_x_rel
        bottom_panel_x = offset_x + bottom_panel_x_rel
        enc_panel_x = offset_x + enc_panel_x_rel

        self.draw_rounded_rect(
            self.body,
            main_panel_x, main_panel_y,
            main_panel_x + main_panel_w,
            main_panel_y + main_panel_h,
            PANEL_RADIUS,
            fill=PANEL_BG,
            outline="",
        )

        self.draw_rounded_rect(
            self.body,
            bottom_panel_x, bottom_panel_y,
            bottom_panel_x + bottom_panel_w,
            bottom_panel_y + bottom_panel_h,
            PANEL_RADIUS,
            fill=PANEL_BG,
            outline="",
        )

        self.draw_rounded_rect(
            self.body,
            enc_panel_x, enc_panel_y,
            enc_panel_x + enc_panel_w,
            enc_panel_y + enc_panel_h,
            PANEL_RADIUS,
            fill=PANEL_BG,
            outline="",
        )

        for r, row in enumerate(top_rows):
            for c, key in enumerate(row):
                raw_label = label_of(key)
                kx = main_panel_x + PANEL_PAD + c * (KEY_W + KEY_GAP)
                ky = main_panel_y + PANEL_PAD + r * (KEY_H + KEY_GAP)
                self.draw_key(self.body, kx, ky, KEY_W, KEY_H, raw_label, ahk_bindings)

        for idx in range(2):
            raw_label = "—"
            if idx < len(bottom_keys):
                raw_label = label_of(bottom_keys[idx])

            kx = bottom_panel_x + 10 + idx * (BOTTOM_KEY_W + KEY_GAP)
            ky = bottom_panel_y + 10
            self.draw_key(self.body, kx, ky, BOTTOM_KEY_W, BOTTOM_KEY_H, raw_label, ahk_bindings)

        for visual_idx in range(2):
            press_label = "—"
            ccw = "—"
            cw = "—"

            if visual_idx < len(encoder_presses):
                press_label = label_of(encoder_presses[visual_idx])

            encoder_data_idx = 1 - visual_idx

            if 0 <= encoder_data_idx < len(encoders):
                ccw = label_of(encoders[encoder_data_idx].get("ccw"))
                cw = label_of(encoders[encoder_data_idx].get("cw"))

            ex = enc_panel_x + 10
            ey = enc_panel_y + 10 + visual_idx * (ENC_CARD_H + ENC_CARD_GAP)
            self.draw_encoder_card(
                self.body,
                ex,
                ey,
                press_label,
                ccw,
                cw,
                ahk_bindings,
            )

        all_combos = layout.get("combos", [])
        all_tap_dances = layout.get("tap_dances", [])

        used_td_indexes = collect_used_tap_dance_indexes(rows, encoder_presses, encoders)
        layer_tap_dances = filter_tap_dances_for_layer(all_tap_dances, used_td_indexes)

        combo_panel_x = 0
        tap_panel_x = DETAILS_PANEL_W + DETAILS_GAP

        self.draw_combo_panel(
            self.body,
            combo_panel_x,
            DETAILS_TOP,
            all_combos,
            ahk_bindings,
        )

        self.draw_tap_dance_panel(
            self.body,
            tap_panel_x,
            DETAILS_TOP,
            layer_tap_dances,
            ahk_bindings,
        )

    def refresh(self):
        state = read_json(STATE_FILE, {})
        layout = read_json(LAYOUT_FILE, {})
        ahk_data = read_json(AHK_BINDINGS_FILE, {})

        layer_index = state.get("top", 0)
        if layer_index is None or layer_index < 0:
            layer_index = 0

        state_mtime = file_mtime_ns(STATE_FILE)
        layout_mtime = file_mtime_ns(LAYOUT_FILE)
        ahk_mtime = file_mtime_ns(AHK_BINDINGS_FILE)

        should_rerender = (
            layer_index != self.last_layer
            or state_mtime != self.last_state_mtime
            or layout_mtime != self.last_layout_mtime
            or ahk_mtime != self.last_ahk_mtime
        )

        if should_rerender:
            self.render_layer(layer_index, state, layout, ahk_data)
            self.last_layer = layer_index
            self.last_state_mtime = state_mtime
            self.last_layout_mtime = layout_mtime
            self.last_ahk_mtime = ahk_mtime

        self.root.after(100, self.refresh)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    LayoutOverlay().run()
