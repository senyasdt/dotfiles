import json
import os
import time
from pathlib import Path

import hid

VID = 0xFEED
PID = 0x4079

RAW_USAGE_PAGE = 0xFF60
RAW_USAGE = 0x61

RAW_REPORT_SIZE = 32

# Helper API commands
CMD_CAPABILITIES = 0x40
CMD_LAYER_STATE = 0x42
CMD_ENCODER_ACTION = 0x43
CMD_COMBO_ENTRY = 0x44
CMD_TAP_DANCE_ENTRY = 0x45
CMD_MACRO = 0x46
CMD_KEY_OVERRIDE = 0x47
CMD_ALT_REPEAT = 0x48
CMD_QMK_SETTING = 0x49

HELPER_PROTOCOL_VERSION = 0x02

MACRO_INFO = 0x00
MACRO_CHUNK = 0x01

FEATURE_LAYER_STATE = 1 << 0
FEATURE_ENCODERS = 1 << 1
FEATURE_COMBOS = 1 << 2
FEATURE_TAP_DANCE = 1 << 3
FEATURE_MACROS = 1 << 4
FEATURE_KEY_OVERRIDES = 1 << 5
FEATURE_ALT_REPEAT = 1 << 6
FEATURE_QMK_SETTINGS = 1 << 7

# VIA commands
VIA_GET_KEYCODE = 0x04

POLL_INTERVAL = 0.05

YASB_DIR = Path(os.environ["USERPROFILE"]) / ".config" / "yasb"

STATE_FILE = YASB_DIR / "vial_layer.json"
STATE_TEMP_FILE = YASB_DIR / "vial_layer.json.tmp"

LAYOUT_FILE = YASB_DIR / "vial_layout.json"
LAYOUT_TEMP_FILE = YASB_DIR / "vial_layout.json.tmp"

REFRESH_LAYOUT_FLAG = YASB_DIR / "vial_layout_refresh.flag"

MATRIX_ROWS = 4
MATRIX_COLS = 4

LAYER_NAMES = {
    0: "BASE",
    1: "L1",
    2: "L2",
    3: "L3",
    4: "L4",
    5: "L5",
    6: "L6",
    7: "L7",
    8: "L8",
    9: "L9",
    10: "L10",
    11: "L11",
    12: "L12",
    13: "L13",
    14: "L14",
    15: "L15",
}


# ============================================================
# JSON helpers
# ============================================================

def atomic_write_json(path: Path, temp_path: Path, payload: dict) -> None:
    YASB_DIR.mkdir(parents=True, exist_ok=True)

    temp_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temp_path.replace(path)


def write_state(payload: dict) -> None:
    atomic_write_json(STATE_FILE, STATE_TEMP_FILE, payload)


def write_layout(payload: dict) -> None:
    atomic_write_json(LAYOUT_FILE, LAYOUT_TEMP_FILE, payload)


# ============================================================
# HID helpers
# ============================================================

def find_raw_hid_path():
    devices = hid.enumerate(VID, PID)

    for dev in devices:
        if (
            dev.get("usage_page") == RAW_USAGE_PAGE
            and dev.get("usage") == RAW_USAGE
        ):
            return dev["path"]

    return None


def open_device():
    path = find_raw_hid_path()

    if path is None:
        return None

    device = hid.device()
    device.open_path(path)
    device.set_nonblocking(False)
    return device


def normalize_read_data(data):
    if data is None:
        return []

    data = list(data)

    if len(data) == RAW_REPORT_SIZE + 1 and data[0] == 0x00:
        return data[1:]

    return data


def send_hid_command(device, payload, expected_cmd, timeout_ms=500):
    packet = bytearray(RAW_REPORT_SIZE)

    for i, value in enumerate(payload):
        packet[i] = value

    device.write(bytes([0x00]) + bytes(packet))

    response = normalize_read_data(
        device.read(RAW_REPORT_SIZE, timeout_ms=timeout_ms)
    )

    if not response:
        raise RuntimeError(f"No HID response for command 0x{expected_cmd:02X}")

    if response[0] != expected_cmd:
        raise RuntimeError(
            f"Unexpected HID response: expected 0x{expected_cmd:02X}, "
            f"got 0x{response[0]:02X}"
        )

    return response


# ============================================================
# Binary helpers
# ============================================================

def read_u16_le(data, offset):
    return data[offset] | (data[offset + 1] << 8)


def read_u32_le(data, offset):
    return (
        data[offset]
        | (data[offset + 1] << 8)
        | (data[offset + 2] << 16)
        | (data[offset + 3] << 24)
    )


def chunks(data, size):
    for i in range(0, len(data), size):
        yield data[i:i + size]


# ============================================================
# Capabilities
# ============================================================

def get_capabilities(device) -> dict:
    response = send_hid_command(
        device,
        payload=[CMD_CAPABILITIES],
        expected_cmd=CMD_CAPABILITIES,
    )

    feature_flags = read_u16_le(response, 11)

    return {
        "helper_protocol_version": response[1],
        "layer_count": response[2],
        "encoder_count": response[3],
        "tap_dance_entries": response[4],
        "combo_entries": response[5],
        "key_override_entries": response[6],
        "alt_repeat_entries": response[7],
        "macro_count": response[8],
        "macro_buffer_size": read_u16_le(response, 9),
        "feature_flags": feature_flags,
        "features": {
            "layer_state": bool(feature_flags & FEATURE_LAYER_STATE),
            "encoders": bool(feature_flags & FEATURE_ENCODERS),
            "combos": bool(feature_flags & FEATURE_COMBOS),
            "tap_dance": bool(feature_flags & FEATURE_TAP_DANCE),
            "macros": bool(feature_flags & FEATURE_MACROS),
            "key_overrides": bool(feature_flags & FEATURE_KEY_OVERRIDES),
            "alt_repeat": bool(feature_flags & FEATURE_ALT_REPEAT),
            "qmk_settings": bool(feature_flags & FEATURE_QMK_SETTINGS),
        },
        "vial_protocol_version": read_u32_le(response, 13),
    }


# ============================================================
# Current layer state
# ============================================================

def mask_to_layers(mask, max_layers=16):
    return [layer for layer in range(max_layers) if mask & (1 << layer)]


def format_layers(layers):
    if not layers:
        return "—"
    return ", ".join(str(layer) for layer in layers)


def offline_state(message: str = "OFF") -> dict:
    return {
        "label": message,
        "top": -1,
        "name": "Keyboard disconnected",
        "effective": "—",
        "temp": "—",
        "default": "—",
        "tooltip": "Vial macropad is not connected",
    }


def query_layer_state(device):
    response = send_hid_command(
        device,
        payload=[CMD_LAYER_STATE],
        expected_cmd=CMD_LAYER_STATE,
        timeout_ms=250,
    )

    if len(response) < 15:
        return None

    highest_layer = response[2]
    effective_state = read_u32_le(response, 3)
    temporary_state = read_u32_le(response, 7)
    default_state = read_u32_le(response, 11)

    effective_layers = mask_to_layers(effective_state)
    temporary_layers = mask_to_layers(temporary_state)
    default_layers = mask_to_layers(default_state)

    layer_name = LAYER_NAMES.get(highest_layer, f"L{highest_layer}")

    return {
        "label": layer_name,
        "top": highest_layer,
        "name": layer_name,
        "effective": format_layers(effective_layers),
        "temp": format_layers(temporary_layers),
        "default": format_layers(default_layers),
        "tooltip": (
            f"Top: {layer_name}\n"
            f"Effective: {format_layers(effective_layers)}\n"
            f"Temporary: {format_layers(temporary_layers)}\n"
            f"Default: {format_layers(default_layers)}"
        ),
    }


# ============================================================
# Keycode labels
# ============================================================

BASIC_KEYCODES = {
    0x0000: "NO",
    0x0001: "TRNS",

    0x0028: "Enter",
    0x0029: "Esc",
    0x002A: "Backsp",
    0x002B: "Tab",
    0x002C: "Space",
    0x002D: "-",
    0x002E: "=",
    0x002F: "[",
    0x0030: "]",
    0x0031: "\\",
    0x0033: ";",
    0x0034: "'",
    0x0035: "`",
    0x0036: ",",
    0x0037: ".",
    0x0038: "/",

    0x0049: "Ins",
    0x004A: "Home",
    0x004B: "PgUp",
    0x004C: "Del",
    0x004D: "End",
    0x004E: "PgDn",
    0x004F: "→",
    0x0050: "←",
    0x0051: "↓",
    0x0052: "↑",

    0x00E0: "LCtrl",
    0x00E1: "LShift",
    0x00E2: "LAlt",
    0x00E3: "LWin",
    0x00E4: "RCtrl",
    0x00E5: "RShift",
    0x00E6: "RAlt",
    0x00E7: "RWin",
}

for i, letter in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
    BASIC_KEYCODES[0x0004 + i] = letter

digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
for i, digit in enumerate(digits):
    BASIC_KEYCODES[0x001E + i] = digit

for i in range(12):
    BASIC_KEYCODES[0x003A + i] = f"F{i + 1}"

for i in range(12, 24):
    BASIC_KEYCODES[0x0068 + (i - 12)] = f"F{i + 1}"


def basic_key_label(code: int) -> str:
    return BASIC_KEYCODES.get(code, f"KC_{code:02X}")


def keycode_label(code: int) -> str:
    if 0x0000 <= code <= 0x00FF:
        return basic_key_label(code)

    if 0x4000 <= code <= 0x4FFF:
        layer = (code >> 8) & 0x0F
        tapped = code & 0xFF
        return f"LT({layer},{basic_key_label(tapped)})"

    if 0x5200 <= code <= 0x521F:
        return f"TO({code & 0x1F})"

    if 0x5220 <= code <= 0x523F:
        return f"MO({code & 0x1F})"

    if 0x5240 <= code <= 0x525F:
        return f"DF({code & 0x1F})"

    if 0x5260 <= code <= 0x527F:
        return f"TG({code & 0x1F})"

    if 0x5280 <= code <= 0x529F:
        return f"OSL({code & 0x1F})"

    if 0x52C0 <= code <= 0x52DF:
        return f"TT({code & 0x1F})"

    if 0x52E0 <= code <= 0x52FF:
        return f"PDF({code & 0x1F})"

    if 0x5700 <= code <= 0x57FF:
        return f"TD({code & 0xFF})"

    if 0x2000 <= code <= 0x3FFF:
        tapped = code & 0xFF
        return f"MT(…,{basic_key_label(tapped)})"

    return f"0x{code:04X}"


def keycode_payload(code: int) -> dict:
    return {
        "code": code,
        "hex": f"0x{code:04X}",
        "label": keycode_label(code),
    }


# ============================================================
# Keymap and encoders
# ============================================================

def get_dynamic_keycode(device, layer: int, row: int, col: int) -> int:
    response = send_hid_command(
        device,
        payload=[VIA_GET_KEYCODE, layer, row, col],
        expected_cmd=VIA_GET_KEYCODE,
    )

    hi = response[4]
    lo = response[5]
    return (hi << 8) | lo


def get_encoder_keycode(device, layer: int, encoder_id: int, clockwise: bool) -> int:
    response = send_hid_command(
        device,
        payload=[
            CMD_ENCODER_ACTION,
            layer,
            encoder_id,
            1 if clockwise else 0,
        ],
        expected_cmd=CMD_ENCODER_ACTION,
    )

    hi = response[4]
    lo = response[5]
    return (hi << 8) | lo


def read_layers(device, layer_count: int) -> dict:
    layers = {}

    for layer in range(layer_count):
        rows = []

        for row in range(MATRIX_ROWS):
            rendered_row = []

            for col in range(MATRIX_COLS):
                code = get_dynamic_keycode(device, layer, row, col)
                rendered_row.append(keycode_payload(code))

            rows.append(rendered_row)

        layers[str(layer)] = rows

    return layers


def read_encoders(device, layer_count: int, encoder_count: int) -> dict:
    encoders = {}

    for layer in range(layer_count):
        layer_encoders = []

        for encoder_id in range(encoder_count):
            ccw_code = get_encoder_keycode(device, layer, encoder_id, clockwise=False)
            cw_code = get_encoder_keycode(device, layer, encoder_id, clockwise=True)

            layer_encoders.append(
                {
                    "id": encoder_id,
                    "ccw": keycode_payload(ccw_code),
                    "cw": keycode_payload(cw_code),
                }
            )

        encoders[str(layer)] = layer_encoders

    return encoders


# ============================================================
# Combos
# ============================================================

def read_combo_entry(device, index: int) -> dict | None:
    response = send_hid_command(
        device,
        payload=[CMD_COMBO_ENTRY, index],
        expected_cmd=CMD_COMBO_ENTRY,
    )

    status = response[2]
    if status != 0:
        return None

    inputs = [
        read_u16_le(response, 3),
        read_u16_le(response, 5),
        read_u16_le(response, 7),
        read_u16_le(response, 9),
    ]
    output = read_u16_le(response, 11)

    return {
        "index": index,
        "inputs": [keycode_payload(code) for code in inputs],
        "output": keycode_payload(output),
        "active": any(code not in (0x0000, 0x0001) for code in inputs) or output not in (0x0000, 0x0001),
    }


def read_combos(device, count: int) -> list[dict]:
    result = []

    for index in range(count):
        entry = read_combo_entry(device, index)
        if entry is not None:
            result.append(entry)

    return result


# ============================================================
# Tap Dance
# ============================================================

def read_tap_dance_entry(device, index: int) -> dict | None:
    response = send_hid_command(
        device,
        payload=[CMD_TAP_DANCE_ENTRY, index],
        expected_cmd=CMD_TAP_DANCE_ENTRY,
    )

    status = response[2]
    if status != 0:
        return None

    on_tap = read_u16_le(response, 3)
    on_hold = read_u16_le(response, 5)
    on_double_tap = read_u16_le(response, 7)
    on_tap_hold = read_u16_le(response, 9)
    tapping_term = read_u16_le(response, 11)

    return {
        "index": index,
        "on_tap": keycode_payload(on_tap),
        "on_hold": keycode_payload(on_hold),
        "on_double_tap": keycode_payload(on_double_tap),
        "on_tap_hold": keycode_payload(on_tap_hold),
        "custom_tapping_term": tapping_term,
        "active": any(
            code not in (0x0000, 0x0001)
            for code in (on_tap, on_hold, on_double_tap, on_tap_hold)
        ),
    }


def read_tap_dances(device, count: int) -> list[dict]:
    result = []

    for index in range(count):
        entry = read_tap_dance_entry(device, index)
        if entry is not None:
            result.append(entry)

    return result


# ============================================================
# Macros
# ============================================================

def read_macro_info(device) -> tuple[int, int]:
    response = send_hid_command(
        device,
        payload=[CMD_MACRO, MACRO_INFO],
        expected_cmd=CMD_MACRO,
    )

    count = response[2]
    buffer_size = read_u16_le(response, 3)
    return count, buffer_size


def read_macro_buffer(device, buffer_size: int) -> bytes:
    raw = bytearray()
    offset = 0

    while offset < buffer_size:
        requested = min(27, buffer_size - offset)

        response = send_hid_command(
            device,
            payload=[
                CMD_MACRO,
                MACRO_CHUNK,
                offset & 0xFF,
                (offset >> 8) & 0xFF,
                requested,
            ],
            expected_cmd=CMD_MACRO,
        )

        returned = response[4]
        if returned == 0:
            break

        raw.extend(response[5:5 + returned])
        offset += returned

    return bytes(raw)


def split_macro_entries(buffer: bytes, count: int) -> list[dict]:
    entries = []
    current = bytearray()

    for byte in buffer:
        if byte == 0:
            entries.append(
                {
                    "index": len(entries),
                    "raw_hex": current.hex(" ").upper(),
                    "bytes": list(current),
                    "active": len(current) > 0,
                }
            )
            current.clear()

            if len(entries) >= count:
                break
        else:
            current.append(byte)

    while len(entries) < count:
        entries.append(
            {
                "index": len(entries),
                "raw_hex": "",
                "bytes": [],
                "active": False,
            }
        )

    return entries


def read_macros(device) -> dict:
    count, buffer_size = read_macro_info(device)
    buffer = read_macro_buffer(device, buffer_size)

    return {
        "count": count,
        "buffer_size": buffer_size,
        "buffer_hex": buffer.hex(" ").upper(),
        "entries": split_macro_entries(buffer, count),
    }


# ============================================================
# Key Overrides
# ============================================================

def read_key_override_entry(device, index: int) -> dict | None:
    response = send_hid_command(
        device,
        payload=[CMD_KEY_OVERRIDE, index],
        expected_cmd=CMD_KEY_OVERRIDE,
    )

    status = response[2]
    if status != 0:
        return None

    trigger = read_u16_le(response, 3)
    replacement = read_u16_le(response, 5)
    layers = read_u16_le(response, 7)
    trigger_mods = response[9]
    negative_mod_mask = response[10]
    suppressed_mods = response[11]
    options = response[12]

    return {
        "index": index,
        "trigger": keycode_payload(trigger),
        "replacement": keycode_payload(replacement),
        "layers_mask": layers,
        "trigger_mods": trigger_mods,
        "negative_mod_mask": negative_mod_mask,
        "suppressed_mods": suppressed_mods,
        "options": options,
        "active": trigger not in (0x0000, 0x0001) or replacement not in (0x0000, 0x0001),
    }


def read_key_overrides(device, count: int) -> list[dict]:
    result = []

    for index in range(count):
        entry = read_key_override_entry(device, index)
        if entry is not None:
            result.append(entry)

    return result


# ============================================================
# Alt Repeat
# ============================================================

def read_alt_repeat_entry(device, index: int) -> dict | None:
    response = send_hid_command(
        device,
        payload=[CMD_ALT_REPEAT, index],
        expected_cmd=CMD_ALT_REPEAT,
    )

    status = response[2]
    if status != 0:
        return None

    keycode = read_u16_le(response, 3)
    alt_keycode = read_u16_le(response, 5)
    allowed_mods = response[7]
    options = response[8]

    return {
        "index": index,
        "keycode": keycode_payload(keycode),
        "alt_keycode": keycode_payload(alt_keycode),
        "allowed_mods": allowed_mods,
        "options": options,
        "active": keycode not in (0x0000, 0x0001) or alt_keycode not in (0x0000, 0x0001),
    }


def read_alt_repeats(device, count: int) -> list[dict]:
    result = []

    for index in range(count):
        entry = read_alt_repeat_entry(device, index)
        if entry is not None:
            result.append(entry)

    return result


# ============================================================
# Layout cache
# ============================================================

def refresh_layout_cache(device) -> None:
    capabilities = get_capabilities(device)

    layer_count = capabilities["layer_count"]
    encoder_count = capabilities["encoder_count"]

    payload = {
        "helper": capabilities,
        "layer_count": layer_count,
        "matrix": {
            "rows": MATRIX_ROWS,
            "cols": MATRIX_COLS,
        },
        "layer_names": {
            str(layer): LAYER_NAMES.get(layer, f"L{layer}")
            for layer in range(layer_count)
        },
        "layers": read_layers(device, layer_count),
        "encoders": read_encoders(device, layer_count, encoder_count),
        "combos": read_combos(device, capabilities["combo_entries"]),
        "tap_dances": read_tap_dances(device, capabilities["tap_dance_entries"]),
        "macros": read_macros(device),
        "key_overrides": read_key_overrides(device, capabilities["key_override_entries"]),
        "alt_repeat_keys": read_alt_repeats(device, capabilities["alt_repeat_entries"]),
        "qmk_settings": {
            "supported": capabilities["features"]["qmk_settings"],
            "api_available": True,
            "decoded": False,
        },
    }

    write_layout(payload)


# ============================================================
# Main daemon loop
# ============================================================

def main():
    device = None
    last_state = None

    write_state(offline_state("INIT"))

    while True:
        try:
            if device is None:
                device = open_device()

                if device is None:
                    state = offline_state("OFF")

                    if state != last_state:
                        write_state(state)
                        last_state = state

                    time.sleep(1.0)
                    continue

                refresh_layout_cache(device)

            if REFRESH_LAYOUT_FLAG.exists():
                refresh_layout_cache(device)
                REFRESH_LAYOUT_FLAG.unlink(missing_ok=True)

            state = query_layer_state(device)

            if state is not None and state != last_state:
                write_state(state)
                last_state = state

            time.sleep(POLL_INTERVAL)

        except Exception:
            try:
                if device is not None:
                    device.close()
            except Exception:
                pass

            device = None

            state = offline_state("OFF")
            if state != last_state:
                write_state(state)
                last_state = state

            time.sleep(1.0)


if __name__ == "__main__":
    main()
