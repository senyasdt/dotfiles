import hid
from pprint import pprint

VID = 0xFEED
PID = 0x4079

RAW_USAGE_PAGE = 0xFF60
RAW_USAGE = 0x61
RAW_REPORT_SIZE = 32

CMD_CAPABILITIES = 0x40
CMD_LAYER_STATE = 0x42
CMD_ENCODER_ACTION = 0x43
CMD_COMBO_ENTRY = 0x44
CMD_TAP_DANCE_ENTRY = 0x45
CMD_MACRO = 0x46
CMD_KEY_OVERRIDE = 0x47
CMD_ALT_REPEAT = 0x48

MACRO_INFO = 0x00
MACRO_CHUNK = 0x01


# ============================================================
# Low-level helpers
# ============================================================

def find_raw_hid_path():
    devices = hid.enumerate(VID, PID)

    for dev in devices:
        if (
            dev.get("usage_page") == RAW_USAGE_PAGE
            and dev.get("usage") == RAW_USAGE
        ):
            return dev["path"]

    print("❌ Raw HID interface not found.")
    print("Found matching VID/PID devices:")
    for dev in devices:
        print(
            f"  usage_page={dev.get('usage_page')}, "
            f"usage={dev.get('usage')}, "
            f"interface={dev.get('interface_number')}, "
            f"product={dev.get('product_string')}"
        )
    raise SystemExit(1)


def open_device():
    path = find_raw_hid_path()
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


def send(device, payload, expected_cmd, timeout_ms=500):
    packet = bytearray(RAW_REPORT_SIZE)

    for i, value in enumerate(payload):
        packet[i] = value

    device.write(bytes([0x00]) + bytes(packet))

    response = normalize_read_data(
        device.read(RAW_REPORT_SIZE, timeout_ms=timeout_ms)
    )

    if not response:
        raise RuntimeError(f"No response for command 0x{expected_cmd:02X}")

    if response[0] != expected_cmd:
        raise RuntimeError(
            f"Unexpected response. Expected 0x{expected_cmd:02X}, got 0x{response[0]:02X}"
        )

    return response


def hexline(data):
    return " ".join(f"{byte:02X}" for byte in data)


def read_u16_le(data, offset):
    return data[offset] | (data[offset + 1] << 8)


def read_u32_le(data, offset):
    return (
        data[offset]
        | (data[offset + 1] << 8)
        | (data[offset + 2] << 16)
        | (data[offset + 3] << 24)
    )


# ============================================================
# Pretty keycode labels
# ============================================================

BASIC = {
    0x0000: "NO",
    0x0001: "TRNS",
    0x0028: "Enter",
    0x0029: "Esc",
    0x002A: "Backspace",
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
}

for i, letter in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
    BASIC[0x0004 + i] = letter

digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
for i, digit in enumerate(digits):
    BASIC[0x001E + i] = digit

for i in range(12):
    BASIC[0x003A + i] = f"F{i + 1}"

for i in range(12, 24):
    BASIC[0x0068 + (i - 12)] = f"F{i + 1}"


def key_label(code: int) -> str:
    if code in BASIC:
        return BASIC[code]

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

    return f"0x{code:04X}"


# ============================================================
# Individual checks
# ============================================================

def check_capabilities(device):
    print("\n" + "=" * 72)
    print("0x40 — GET_HELPER_CAPABILITIES")
    print("=" * 72)

    response = send(device, [CMD_CAPABILITIES], CMD_CAPABILITIES)

    print("RAW:")
    print(hexline(response))

    feature_flags = read_u16_le(response, 11)

    parsed = {
        "helper_protocol_version": response[1],
        "layer_count": response[2],
        "encoder_count": response[3],
        "tap_dance_entries": response[4],
        "combo_entries": response[5],
        "key_override_entries": response[6],
        "alt_repeat_entries": response[7],
        "macro_count": response[8],
        "macro_buffer_size": read_u16_le(response, 9),
        "feature_flags": f"0x{feature_flags:04X}",
        "vial_protocol_version": read_u32_le(response, 13),
    }

    print("\nPARSED:")
    pprint(parsed)

    return parsed


def check_layer_state(device):
    print("\n" + "=" * 72)
    print("0x42 — GET_LAYER_STATE")
    print("=" * 72)

    response = send(device, [CMD_LAYER_STATE], CMD_LAYER_STATE)

    print("RAW:")
    print(hexline(response))

    parsed = {
        "protocol_version": response[1],
        "highest_effective_layer": response[2],
        "effective_mask": f"0x{read_u32_le(response, 3):08X}",
        "temporary_mask": f"0x{read_u32_le(response, 7):08X}",
        "default_mask": f"0x{read_u32_le(response, 11):08X}",
    }

    print("\nPARSED:")
    pprint(parsed)


def check_encoders(device, layer_count, encoder_count):
    print("\n" + "=" * 72)
    print("0x43 — GET_ENCODER_ACTION")
    print("=" * 72)

    # Достаточно проверить base layer 0
    layer = 0

    for encoder_id in range(encoder_count):
        for direction, name in [(0, "CCW"), (1, "CW")]:
            response = send(
                device,
                [CMD_ENCODER_ACTION, layer, encoder_id, direction],
                CMD_ENCODER_ACTION,
            )

            code = (response[4] << 8) | response[5]

            print(
                f"layer={layer}, encoder={encoder_id}, direction={name}: "
                f"{key_label(code)} / 0x{code:04X}"
            )
            print("  RAW:", hexline(response))


def check_combos(device, combo_count):
    print("\n" + "=" * 72)
    print("0x44 — GET_COMBO_ENTRY")
    print("=" * 72)

    active = []

    for index in range(combo_count):
        response = send(
            device,
            [CMD_COMBO_ENTRY, index],
            CMD_COMBO_ENTRY,
        )

        status = response[2]
        if status != 0:
            print(f"combo[{index}] status={status}")
            continue

        inputs = [
            read_u16_le(response, 3),
            read_u16_le(response, 5),
            read_u16_le(response, 7),
            read_u16_le(response, 9),
        ]
        output = read_u16_le(response, 11)

        is_active = any(code not in (0x0000, 0x0001) for code in inputs) or output not in (0x0000, 0x0001)

        if is_active:
            active.append(
                {
                    "index": index,
                    "inputs": [key_label(code) for code in inputs],
                    "output": key_label(output),
                    "raw": hexline(response),
                }
            )

    if not active:
        print("No active combos configured. API responded correctly.")
    else:
        for item in active:
            print(f"combo[{item['index']}]: {item['inputs']} -> {item['output']}")
            print("  RAW:", item["raw"])


def check_tap_dance(device, tap_dance_count):
    print("\n" + "=" * 72)
    print("0x45 — GET_TAP_DANCE_ENTRY")
    print("=" * 72)

    active = []

    for index in range(tap_dance_count):
        response = send(
            device,
            [CMD_TAP_DANCE_ENTRY, index],
            CMD_TAP_DANCE_ENTRY,
        )

        status = response[2]
        if status != 0:
            print(f"tap_dance[{index}] status={status}")
            continue

        on_tap = read_u16_le(response, 3)
        on_hold = read_u16_le(response, 5)
        on_double = read_u16_le(response, 7)
        on_tap_hold = read_u16_le(response, 9)
        tapping_term = read_u16_le(response, 11)

        is_active = any(
            code not in (0x0000, 0x0001)
            for code in (on_tap, on_hold, on_double, on_tap_hold)
        )

        if is_active:
            active.append(
                {
                    "index": index,
                    "tap": key_label(on_tap),
                    "hold": key_label(on_hold),
                    "double": key_label(on_double),
                    "tap_hold": key_label(on_tap_hold),
                    "term": tapping_term,
                    "raw": hexline(response),
                }
            )

    if not active:
        print("No active Tap Dance entries configured. API responded correctly.")
    else:
        for item in active:
            print(
                f"TD[{item['index']}]: "
                f"tap={item['tap']}, hold={item['hold']}, "
                f"double={item['double']}, tap+hold={item['tap_hold']}, "
                f"term={item['term']}"
            )
            print("  RAW:", item["raw"])


def check_macros(device):
    print("\n" + "=" * 72)
    print("0x46 — GET_MACRO_INFO / GET_MACRO_CHUNK")
    print("=" * 72)

    info = send(
        device,
        [CMD_MACRO, MACRO_INFO],
        CMD_MACRO,
    )

    macro_count = info[2]
    macro_buffer_size = read_u16_le(info, 3)

    print("INFO RAW:")
    print(hexline(info))

    print("\nPARSED:")
    pprint(
        {
            "macro_count": macro_count,
            "macro_buffer_size": macro_buffer_size,
        }
    )

    if macro_buffer_size == 0:
        print("Macro buffer size is 0.")
        return

    requested = min(27, macro_buffer_size)
    chunk = send(
        device,
        [CMD_MACRO, MACRO_CHUNK, 0x00, 0x00, requested],
        CMD_MACRO,
    )

    returned = chunk[4]
    payload = chunk[5:5 + returned]

    print("\nFIRST CHUNK RAW:")
    print(hexline(chunk))

    print("\nFIRST CHUNK DATA:")
    print(hexline(payload) if payload else "(empty)")


def check_key_overrides(device, count):
    print("\n" + "=" * 72)
    print("0x47 — GET_KEY_OVERRIDE_ENTRY")
    print("=" * 72)

    active = []

    for index in range(count):
        response = send(
            device,
            [CMD_KEY_OVERRIDE, index],
            CMD_KEY_OVERRIDE,
        )

        status = response[2]
        if status != 0:
            print(f"key_override[{index}] status={status}")
            continue

        trigger = read_u16_le(response, 3)
        replacement = read_u16_le(response, 5)

        is_active = trigger not in (0x0000, 0x0001) or replacement not in (0x0000, 0x0001)

        if is_active:
            active.append(
                {
                    "index": index,
                    "trigger": key_label(trigger),
                    "replacement": key_label(replacement),
                    "raw": hexline(response),
                }
            )

    if not active:
        print("No active Key Overrides configured. API responded correctly.")
    else:
        for item in active:
            print(
                f"override[{item['index']}]: "
                f"{item['trigger']} -> {item['replacement']}"
            )
            print("  RAW:", item["raw"])


def check_alt_repeat(device, count):
    print("\n" + "=" * 72)
    print("0x48 — GET_ALT_REPEAT_ENTRY")
    print("=" * 72)

    active = []

    for index in range(count):
        response = send(
            device,
            [CMD_ALT_REPEAT, index],
            CMD_ALT_REPEAT,
        )

        status = response[2]
        if status != 0:
            print(f"alt_repeat[{index}] status={status}")
            continue

        keycode = read_u16_le(response, 3)
        alt_keycode = read_u16_le(response, 5)

        is_active = keycode not in (0x0000, 0x0001) or alt_keycode not in (0x0000, 0x0001)

        if is_active:
            active.append(
                {
                    "index": index,
                    "keycode": key_label(keycode),
                    "alt_keycode": key_label(alt_keycode),
                    "raw": hexline(response),
                }
            )

    if not active:
        print("No active Alt Repeat entries configured. API responded correctly.")
    else:
        for item in active:
            print(
                f"alt_repeat[{item['index']}]: "
                f"{item['keycode']} -> {item['alt_keycode']}"
            )
            print("  RAW:", item["raw"])


# ============================================================
# Main
# ============================================================

def main():
    print("Connecting to macropad Raw HID...")
    device = open_device()
    print("✅ Connected.")

    try:
        capabilities = check_capabilities(device)
        check_layer_state(device)
        check_encoders(
            device,
            capabilities["layer_count"],
            capabilities["encoder_count"],
        )
        check_combos(
            device,
            capabilities["combo_entries"],
        )
        check_tap_dance(
            device,
            capabilities["tap_dance_entries"],
        )
        check_macros(device)
        check_key_overrides(
            device,
            capabilities["key_override_entries"],
        )
        check_alt_repeat(
            device,
            capabilities["alt_repeat_entries"],
        )

        print("\n" + "=" * 72)
        print("PROBE FINISHED")
        print("=" * 72)
        print("Скинь сюда весь вывод, особенно если где-то есть status != 0 или traceback.")

    finally:
        device.close()


if __name__ == "__main__":
    main()
