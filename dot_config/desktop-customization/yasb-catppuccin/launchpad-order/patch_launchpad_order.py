"""Install/remove one version-pinned Launchpad extension in cx_Freeze's archive."""
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

ORIGINAL_SHA256 = '1c1c009e31654dd3602c0c33580f60e8fa969d7588938a22eab99e74a9953313'
ENTRY = 'core/widgets/yasb/launchpad.pyc'
EXTENSION = 'core/widgets/yasb/launchpad_order.pyc'
BACKUP = 'core/widgets/yasb/_launchpad_order_original.pyc'
MANIFEST = 'launchpad-manual-order.json'
sha = lambda data: hashlib.sha256(data).hexdigest()


def build(original, source):
    if sys.version_info[:2] != (3, 14) or original[:4] != importlib.util.MAGIC_NUMBER:
        raise RuntimeError('Python 3.14 matching YASB bytecode is required')
    wrapper = compile("exec(b'ORIGINAL_CODE', globals())\nfrom core.widgets.yasb.launchpad_order import install as _install_manual_order\n_install_manual_order(LaunchpadWidget)\n", 'launchpad-manual-order-wrapper', 'exec')
    wrapper = wrapper.replace(co_consts=tuple(marshal.loads(original[16:]) if c == b'ORIGINAL_CODE' else c for c in wrapper.co_consts))
    extension = compile(source, 'core/widgets/yasb/launchpad_order.py', 'exec')
    header = importlib.util.MAGIC_NUMBER + b'\0' * 12
    return header + marshal.dumps(wrapper), header + marshal.dumps(extension)


def patch(archive, action, source):
    before = archive.read_bytes()
    with zipfile.ZipFile(archive) as z:
        if len(z.namelist()) != len(set(z.namelist())):
            raise RuntimeError('Archive has duplicate entries')
        current = z.read(ENTRY)
        installed = MANIFEST in z.namelist()
        manifest = json.loads(z.read(MANIFEST)) if installed else None
        if installed:
            original = z.read(BACKUP)
            if (sha(original) != ORIGINAL_SHA256 or sha(current) != manifest['wrapper_sha256']
                    or sha(z.read(EXTENSION)) != manifest['extension_sha256']):
                raise RuntimeError('Installed patch changed; refusing to overwrite')
        else:
            original = current
            if sha(original) != ORIGINAL_SHA256:
                raise RuntimeError('Unsupported Launchpad build; expected official YASB 2.0.7. Nothing changed.')
            if EXTENSION in z.namelist() or BACKUP in z.namelist():
                raise RuntimeError('Unexpected extension entries')
        if action == 'status':
            print(json.dumps({'installed': installed, 'supported': True, 'manifest': manifest}))
            return
        if action == 'undo' and not installed:
            print('Already unpatched')
            return
        replacements = {ENTRY: original}
        if action == 'apply':
            wrapper, extension = build(original, source)
            replacements = {ENTRY: wrapper, EXTENSION: extension, BACKUP: original,
                            MANIFEST: json.dumps({'version': 1, 'original_sha256': sha(original),
                                'wrapper_sha256': sha(wrapper), 'extension_sha256': sha(extension),
                                'source_sha256': sha(source)}).encode('utf-8')}
            if installed and manifest['source_sha256'] == sha(source):
                print('Already installed')
                return
        fd, name = tempfile.mkstemp(prefix='launchpad-order-', suffix='.zip', dir=archive.parent)
        os.close(fd)
        temp = Path(name)
        try:
            with zipfile.ZipFile(temp, 'w') as out:
                for info in z.infolist():
                    if info.filename not in {ENTRY, EXTENSION, BACKUP, MANIFEST}:
                        out.writestr(copy.copy(info), z.read(info.filename))
                    elif info.filename == ENTRY:
                        out.writestr(copy.copy(info), replacements.pop(ENTRY))
                for name, content in replacements.items():
                    out.writestr(name, content, compress_type=zipfile.ZIP_DEFLATED)
            with zipfile.ZipFile(temp) as check:
                if check.testzip():
                    raise RuntimeError('Archive verification failed')
                for info in z.infolist():
                    if info.filename not in {ENTRY, EXTENSION, BACKUP, MANIFEST}:
                        assert check.read(info.filename) == z.read(info.filename), info.filename
        except BaseException:
            temp.unlink(missing_ok=True)
            raise
    try:
        if archive.read_bytes() != before:
            raise RuntimeError('Archive changed concurrently; nothing installed')
        os.replace(temp, archive)
    finally:
        temp.unlink(missing_ok=True)
    print('Launchpad manual order ' + ('installed' if action == 'apply' else 'removed'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['apply', 'undo', 'status'])
    parser.add_argument('--archive', required=True, type=Path)
    args = parser.parse_args()
    patch(args.archive, args.action, Path(__file__).with_name('launchpad_order.py').read_bytes())
