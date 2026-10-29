"""Exercise patch/undo and preservation of other extensions in temporary archives."""
import argparse
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch as mock
import zipfile

sys.dont_write_bytecode = True
import patch_custom_worker as patcher

parser = argparse.ArgumentParser()
parser.add_argument("--yasb-root", default=os.path.join(os.environ["ProgramFiles"], "YASB"))
parser.add_argument("--temp-root", type=Path)
args, unittest_args = parser.parse_known_args()
with zipfile.ZipFile(Path(args.yasb_root) / "lib/library.zip") as installed:
    original = installed.read(patcher.BACKUP if patcher.BACKUP in installed.namelist() else patcher.ENTRY)
assert patcher.sha(original) == patcher.ORIGINAL_SHA256
source = Path(__file__).with_name("custom_worker_lifecycle.py").read_bytes()


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yasb-archive-test-", dir=args.temp_root)
        if args.temp_root:
            assert Path(self.temp.name).resolve().parent == args.temp_root.resolve()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "library.zip"
        self.other = {"core/widgets/yasb/launchpad.pyc": b"other installed wrapper",
                      "launchpad-manual-order.json": b"preserve other patch",
                      "unrelated.dat": bytes(range(256))}
        with zipfile.ZipFile(self.archive, "w") as out:
            out.writestr(patcher.ENTRY, original)
            for name, data in self.other.items(): out.writestr(name, data)

    def apply(self, action="apply", body=source):
        with redirect_stdout(io.StringIO()):
            return patcher.patch(self.archive, action, body)

    def assert_other(self):
        with zipfile.ZipFile(self.archive) as archive:
            self.assertIsNone(archive.testzip())
            for name, data in self.other.items(): self.assertEqual(archive.read(name), data)

    def test_apply_idempotence_update_undo(self):
        self.assertFalse(self.apply("status")["installed"])
        self.apply(); self.assert_other()
        before = self.archive.read_bytes()
        self.apply(); self.assertEqual(self.archive.read_bytes(), before)
        self.assertTrue(self.apply("status")["installed"])
        self.apply(body=source+b"\n# revised test build\n"); self.assert_other()
        self.apply("undo"); self.assert_other()
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(archive.read(patcher.ENTRY), original)
            self.assertFalse(set(archive.namelist()) & (patcher.OWN - {patcher.ENTRY}))
        before = self.archive.read_bytes()
        self.apply("undo"); self.assertEqual(self.archive.read_bytes(), before)

    def test_unknown_original(self):
        with zipfile.ZipFile(self.archive, "w") as out: out.writestr(patcher.ENTRY, b"unknown")
        before = self.archive.read_bytes()
        with self.assertRaises(RuntimeError): self.apply()
        self.assertEqual(self.archive.read_bytes(), before)

    def test_modified_extension(self):
        self.apply()
        with zipfile.ZipFile(self.archive) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries[patcher.EXTENSION] = b"unexpected changes"
        with zipfile.ZipFile(self.archive, "w") as out:
            for name, data in entries.items(): out.writestr(name, data)
        before = self.archive.read_bytes()
        for action in ["status", "apply", "undo"]:
            with self.assertRaises(RuntimeError): self.apply(action)
            self.assertEqual(self.archive.read_bytes(), before)

    def test_concurrent_archive_change(self):
        build = patcher.build
        changed = self.archive.read_bytes() + b"concurrent update"
        def concurrent(*args):
            result = build(*args)
            self.archive.write_bytes(changed)
            return result
        with mock.object(patcher, "build", concurrent):
            with self.assertRaisesRegex(RuntimeError, "concurrently"): self.apply()
        self.assertEqual(self.archive.read_bytes(), changed)
        self.assertEqual(list(Path(self.temp.name).glob("*.zip")), [self.archive])


unittest.main(argv=[sys.argv[0], *unittest_args])
