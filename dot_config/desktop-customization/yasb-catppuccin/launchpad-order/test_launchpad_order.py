"""Behavior and real Qt callback checks; uses temporary catalogs only."""
import argparse
import importlib.abc
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

from launchpad_order import MIME, install, key_for, persist, reordered, root_blocks


def fixture():
    return [dict(id=i, title=str(i), group=g, path=f'C:/test/{i}.exe', icon='', extra=i * 10)
            for i, g in [(1, 'Alpha'), (2, ''), (3, 'Alpha'), (4, 'Beta'), (5, ''), (6, 'Beta')]]


def pure_checks():
    apps = fixture()
    result = reordered(apps, ('group', 'Beta'), ('app', '2'))
    assert list(root_blocks(result)) == [('group', 'Alpha'), ('group', 'Beta'), ('app', '2'), ('app', '5')]
    result = reordered(result, ('app', '5'), ('group', 'Alpha'))
    assert list(root_blocks(result))[0] == ('app', '5')
    result = reordered(result, ('app', '5'), ('app', '2'), True)
    assert list(root_blocks(result))[-1] == ('app', '5')
    assert sorted(result, key=lambda a: a['id']) == sorted(apps, key=lambda a: a['id'])
    inside = reordered(apps, ('app', '1'), ('app', '3'), True, 'group:Alpha')
    assert [a['id'] for a in inside] == [3, 2, 1, 4, 5, 6]
    assert reordered(apps, ('app', '2'), ('app', '2')) == apps
    try:
        reordered(apps, ('group', 'Missing'), ('app', '2'))
    except ValueError:
        pass
    else:
        raise AssertionError('Missing item accepted')
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'apps.json'
        original = json.dumps(apps).encode()
        path.write_bytes(original)
        persist(path, original, result)
        assert json.loads(path.read_bytes()) == result
        assert path.with_name('apps.before-manual-order.json').read_bytes() == original
        try:
            persist(path, original, apps)
        except RuntimeError:
            pass
        else:
            raise AssertionError('Concurrent edit overwritten')
        assert json.loads(path.read_bytes()) == result
    print('PASS: mixed moves, group member order, first/last placement, unchanged launch fields, atomic persistence and concurrent edits')


def qt_checks(root, archive=None):
    os.environ['QT_QPA_PLATFORM'] = 'offscreen'
    lib = root / 'lib'
    sys.path[:0] = [str(lib.resolve()), str((archive or lib / 'library.zip').resolve())]
    dll_handles = [os.add_dll_directory(str(p)) for p in [root, lib, lib / 'PyQt6/Qt6/bin'] if p.is_dir()]

    class Flat(importlib.abc.MetaPathFinder):
        def find_spec(self, fullname, path, target=None):
            if fullname in ('pythoncom', 'pywintypes'):
                dll = lib / (fullname + '314.dll')
                return importlib.util.spec_from_file_location(fullname, dll,
                    loader=importlib.machinery.ExtensionFileLoader(fullname, str(dll)))
            candidates = list(lib.glob(fullname + '.cp*.pyd')) + list(lib.glob(fullname + '.pyd'))
            return importlib.util.spec_from_file_location(fullname, candidates[0]) if candidates else None

    sys.meta_path.insert(0, Flat())
    from PyQt6.QtCore import QEvent, QMimeData, QPointF, Qt, QTimer
    from PyQt6.QtGui import QDrag, QMouseEvent
    from PyQt6.QtWidgets import QApplication
    import core.config
    with tempfile.TemporaryDirectory() as directory:
        core.config.HOME_CONFIGURATION_DIR = directory
        from core.validation.widgets.yasb.launchpad import LaunchpadConfig
        from core.widgets.yasb.launchpad import LaunchpadWidget
        install(LaunchpadWidget)
        app = QApplication.instance() or QApplication([])
        app.setStyleSheet('QFrame[class="app-icon"], QFrame[class="group-icon"] { min-width:120px; max-width:120px; min-height:130px; max-height:130px; }')
        config = LaunchpadConfig(group_apps=True, window={'width':800, 'height':600, 'overlay_block':False},
                                window_style={'enable_blur':False}, window_animation={'fade_in_duration':0,'fade_out_duration':0})
        owner = LaunchpadWidget(config)
        path = Path(owner._data_file)
        path.write_text(json.dumps(fixture()), encoding='utf-8')
        owner._launchpad_popup = owner._create_launchpad_popup()
        owner._populate_grid()

        def keys():
            return [w._manual_key for w in owner._app_icons]

        assert keys() == [('group', 'Alpha'), ('app', '2'), ('group', 'Beta'), ('app', '5')], keys()
        launched = []
        owner._launch_app = lambda item: launched.append(item['id'])
        icon = owner._app_icons[1]
        def mouse(kind, x, button, buttons):
            return QMouseEvent(kind, QPointF(x, 10), QPointF(x, 10), button, buttons, Qt.KeyboardModifier.NoModifier)
        icon.mousePressEvent(mouse(QEvent.Type.MouseButtonPress, 5, Qt.MouseButton.LeftButton, Qt.MouseButton.LeftButton))
        icon.mouseReleaseEvent(mouse(QEvent.Type.MouseButtonRelease, 5, Qt.MouseButton.LeftButton, Qt.MouseButton.NoButton))
        assert launched == [2]
        icon.mousePressEvent(mouse(QEvent.Type.MouseButtonPress, 5, Qt.MouseButton.LeftButton, Qt.MouseButton.LeftButton))
        QTimer.singleShot(0, QDrag.cancel)
        icon.mouseMoveEvent(mouse(QEvent.Type.MouseMove, 50, Qt.MouseButton.NoButton, Qt.MouseButton.LeftButton))
        icon.mouseReleaseEvent(mouse(QEvent.Type.MouseButtonRelease, 5, Qt.MouseButton.LeftButton, Qt.MouseButton.NoButton))
        assert icon._manual_dragged and launched == [2], 'Drag launched an app'

        class Event:
            def __init__(self, source, scope, x=0, y=20, has_mime=True):
                self.widget, self.point, self.accepted = source, QPointF(x,y), False
                self.mime = QMimeData()
                if has_mime:
                    self.mime.setData(MIME, json.dumps({'key':source._manual_key, 'scope':scope}).encode())
            def source(self): return self.widget
            def mimeData(self): return self.mime
            def position(self): return self.point
            def setDropAction(self, action): assert action == Qt.DropAction.MoveAction
            def accept(self): self.accepted = True
            def ignore(self): self.accepted = False

        def process():
            for _ in range(5): app.processEvents()

        # Folder before application, then application after folder through actual callbacks.
        source, target = owner._app_icons[2], owner._app_icons[1]
        event = Event(source, 'root')
        target.dragEnterEvent(event)
        assert event.accepted and target._manual_marker is False
        target.dropEvent(event)
        assert event.accepted
        process()
        assert keys() == [('group','Alpha'),('group','Beta'),('app','2'),('app','5')]
        source, target = owner._app_icons[-1], owner._app_icons[0]
        event = Event(source, 'root', x=target.width())
        target.dropEvent(event)
        process()
        assert keys() == [('group','Alpha'),('app','5'),('group','Beta'),('app','2')]
        before = path.read_bytes()
        owner._populate_grid()
        assert keys() == [('group','Alpha'),('app','5'),('group','Beta'),('app','2')]
        # Move inside a folder, retaining the root position.
        owner._open_group('Alpha', [a for a in owner._load_apps() if a.get('group') == 'Alpha'])
        source, target = owner._app_icons[0], owner._app_icons[1]
        event = Event(source, 'group:Alpha', x=target.width())
        target.dropEvent(event)
        process()
        assert keys() == [('app','3'),('app','1')]
        owner._close_group()
        assert keys() == [('group','Alpha'),('app','5'),('group','Beta'),('app','2')]
        # Malformed/external drags and filtered search cannot mutate order.
        before = path.read_bytes()
        event = Event(owner._app_icons[0], 'root', has_mime=False)
        owner._app_icons[1].dropEvent(event)
        assert not event.accepted and path.read_bytes() == before
        owner._launchpad_popup.search_input.setText('2')
        process()
        event = Event(owner._app_icons[0], 'root')
        owner._app_icons[0].dropEvent(event)
        assert not event.accepted and path.read_bytes() == before
        owner._launchpad_popup.search_input.clear()
        process()
        # Empty area after the final row accepts placement at the end.
        source = owner._app_icons[0]
        last = owner._app_icons[-1]
        owner._launchpad_popup.grid_layout.activate()
        event = Event(source, 'root', x=last.geometry().center().x(), y=last.geometry().bottom()+200)
        owner._launchpad_popup.grid_container.dropEvent(event)
        assert event.accepted
        process()
        assert keys()[-1] == ('group','Alpha'), keys()
        # New widget instance observes the persisted order (no in-memory-only order).
        second = LaunchpadWidget(config)
        second._launchpad_popup = second._create_launchpad_popup()
        second._populate_grid()
        assert [w._manual_key for w in second._app_icons] == keys()
        assert sorted(owner._load_apps(), key=lambda a:a['id']) == sorted(fixture(), key=lambda a:a['id'])
        second._launchpad_popup.close()
        owner._launchpad_popup.close()
        process()
        print('PASS: real YASB/Qt callbacks, folder/app ordering, in-folder ordering, gap drop, search guard and reopened widget')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--qt', action='store_true')
    parser.add_argument('--yasb-root', type=Path, default=Path(os.environ.get('ProgramFiles', 'C:/Program Files'))/'YASB')
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    pure_checks()
    if args.qt:
        qt_checks(args.yasb_root, args.archive)
