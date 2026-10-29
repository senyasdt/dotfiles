"""Reversible, hash-pinned patch of one cx_Freeze module (YASB 2.0.7 only)."""
import argparse
import copy
import hashlib
import importlib.util
import json
import marshal
import os
from pathlib import Path
import sys
import tempfile
import zipfile

ENTRY = "core/widgets/yasb/custom.pyc"
EXTENSION = "core/widgets/yasb/custom_worker_lifecycle.pyc"
BACKUP = "core/widgets/yasb/_custom_worker_original.pyc"
MANIFEST = "custom-worker-lifecycle.json"
ORIGINAL_SHA256 = "b732aa9018a31f6cb06cee2fcd08416ba24409f9f4796624e1b6291020ff0fda"
OWN = {ENTRY, EXTENSION, BACKUP, MANIFEST}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(original, source):
    if sys.version_info[:2] != (3, 14) or original[:4] != importlib.util.MAGIC_NUMBER:
        raise RuntimeError("Python 3.14 matching YASB bytecode is required")
    wrapper = compile(
        "exec(b'ORIGINAL_CODE', globals())\n"
        "from core.widgets.yasb.custom_worker_lifecycle import install as _install_worker_fix\n"
        "_install_worker_fix(globals())\n", "custom-worker-lifecycle-wrapper", "exec")
    wrapper = wrapper.replace(co_consts=tuple(
        marshal.loads(original[16:]) if c == b"ORIGINAL_CODE" else c for c in wrapper.co_consts))
    extension = compile(source, "core/widgets/yasb/custom_worker_lifecycle.py", "exec")
    header = importlib.util.MAGIC_NUMBER + b"\0" * 12
    return header + marshal.dumps(wrapper), header + marshal.dumps(extension)


def patch(archive, action, source):
    before = archive.read_bytes()
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        if len(names) != len(z.namelist()):
            raise RuntimeError("Duplicate archive entries; nothing changed")
        current = z.read(ENTRY)
        installed = MANIFEST in names
        manifest = json.loads(z.read(MANIFEST)) if installed else None
        if installed:
            original = z.read(BACKUP)
            if (manifest.get("version") != 1 or sha(original) != ORIGINAL_SHA256
                    or sha(current) != manifest["wrapper_sha256"]
                    or sha(z.read(EXTENSION)) != manifest["extension_sha256"]):
                raise RuntimeError("Installed worker patch changed; nothing overwritten")
        else:
            original = current
            if sha(original) != ORIGINAL_SHA256 or names & {EXTENSION, BACKUP}:
                raise RuntimeError("Unsupported custom module; only verified YASB 2.0.7 is supported")
        if action == "status":
            result = {"installed": installed, "supported": True, "manifest": manifest}
            print(json.dumps(result))
            return result
        if action == "undo" and not installed:
            print("Already unpatched")
            return
        replacements = {ENTRY: original}
        if action == "apply":
            if installed and manifest["source_sha256"] == sha(source):
                print("Already installed")
                return
            wrapper, extension = build(original, source)
            replacements.update({ENTRY: wrapper, EXTENSION: extension, BACKUP: original,
                MANIFEST: json.dumps({"version": 1, "original_sha256": sha(original),
                    "wrapper_sha256": sha(wrapper), "extension_sha256": sha(extension),
                    "source_sha256": sha(source)}).encode("utf-8")})
        fd, name = tempfile.mkstemp(prefix="custom-worker-", suffix=".zip", dir=archive.parent)
        os.close(fd)
        temp = Path(name)
        try:
            with zipfile.ZipFile(temp, "w") as out:
                for info in z.infolist():
                    if info.filename not in OWN:
                        out.writestr(copy.copy(info), z.read(info.filename))
                    elif info.filename == ENTRY:
                        out.writestr(copy.copy(info), replacements.pop(ENTRY))
                for entry, data in replacements.items():
                    out.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED)
            with zipfile.ZipFile(temp) as check:
                if check.testzip():
                    raise RuntimeError("Archive verification failed")
                for entry in names - OWN:
                    if check.read(entry) != z.read(entry):
                        raise RuntimeError("Unrelated entry changed: " + entry)
        except BaseException:
            temp.unlink(missing_ok=True)
            raise
    try:
        if archive.read_bytes() != before:
            raise RuntimeError("Archive changed concurrently; nothing installed")
        os.replace(temp, archive)
    finally:
        temp.unlink(missing_ok=True)
    print("Custom worker lifecycle " + ("installed" if action == "apply" else "removed"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["apply", "undo", "status"])
    parser.add_argument("--archive", type=Path, required=True)
    args = parser.parse_args()
    patch(args.archive, args.action, Path(__file__).with_name("custom_worker_lifecycle.py").read_bytes())
