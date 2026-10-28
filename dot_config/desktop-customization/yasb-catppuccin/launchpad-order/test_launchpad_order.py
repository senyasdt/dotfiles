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
    from PyQt6.QtGui import QDrag, QKeyEvent, QMouseEvent
    from PyQt6.QtWidgets import QApplication, QDialog, QLineEdit, QVBoxLayout
    import core.config
    with tempfile.TemporaryDirectory() as directory:
        core.config.HOME_CONFIGURATION_DIR = directory
        from core.validation.widgets.yasb.launchpad import LaunchpadConfig
        from core.widgets.yasb.launchpad import LaunchpadWidget
        install(LaunchpadWidget)
        # Surface Python exceptions from Qt virtual callbacks in this isolated
        # test instead of YASB's application-level exit/error-dialog handler.
        import traceback
        callback_errors = []
        def callback_error(kind, value, trace):
            callback_errors.append(value)
            traceback.print_exception(kind, value, trace)
        sys.excepthook = callback_error
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

        # Show the real popup: its queued show callback must focus the search,
        # not an icon. Send typing to whichever widget actually owns focus.
        popup = second._launchpad_popup
        popup.show()
        popup.activateWindow()
        process()
        assert popup.search_input.hasFocus(), 'Opening Launchpad focused an icon instead of search'
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_2, Qt.KeyboardModifier.NoModifier, '2'))
        process()
        assert popup.search_input.text() == '2'
        assert [w._manual_key for w in second._app_icons] == [('app', '2')]
        # Enter from the real line edit launches exactly the first displayed
        # match, using the standard launch callback without changing the catalog.
        enter_catalog = path.read_bytes()
        enter_launched = []
        second._launch_app = lambda item: enter_launched.append(item['id'])
        for key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            popup.search_input.setText('group:Alpha')
            process()
            popup.search_input.setFocus()
            expected = second._app_icons[0].app_data['id']
            count = len(enter_launched)
            QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
                QEvent.Type.KeyPress, key, Qt.KeyboardModifier.NoModifier, '\r'))
            process()
            assert enter_launched[count:] == [expected], 'Search Enter did not launch first match exactly once'
        for query in ('', '   ', 'no application matches this query'):
            popup.search_input.setText(query)
            process()
            popup.search_input.setFocus()
            count = len(enter_launched)
            QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
                QEvent.Type.KeyPress, Qt.Key.Key_Return, Qt.KeyboardModifier.NoModifier, '\r'))
            process()
            assert len(enter_launched) == count, 'Empty/no-match Enter launched an app'
        popup.search_input.setText('group:Alpha')
        process()
        popup.search_input.setFocus()
        count = len(enter_launched)
        for modifiers in (Qt.KeyboardModifier.ControlModifier, Qt.KeyboardModifier.AltModifier,
                          Qt.KeyboardModifier.MetaModifier):
            QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
                QEvent.Type.KeyPress, Qt.Key.Key_Return, modifiers, '\r'))
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Return, Qt.KeyboardModifier.NoModifier, '\r', True, 1))
        process()
        assert len(enter_launched) == count, 'Modified/repeated Enter launched an app'
        # Explicit navigation into the results keeps the chosen icon behavior.
        second._focus_icon(1)
        expected = second._app_icons[1].app_data['id']
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Return, Qt.KeyboardModifier.NoModifier, '\r'))
        process()
        assert enter_launched[count:] == [expected], 'Icon Enter lost selected result'
        assert path.read_bytes() == enter_catalog, 'Enter changed the app catalog'
        popup.search_input.setText('2')
        process()
        popup.search_input.setFocus()
        # Arrow navigation still deliberately transfers focus into results.
        second._handle_popup_key_press(QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Down, Qt.KeyboardModifier.NoModifier))
        assert second._app_icons[0].hasFocus()
        focused = QApplication.focusWidget()
        process()
        assert QApplication.focusWidget() is focused, 'Search stole focus back after navigation'

        # Backspace is non-printable, but must also resume search from an icon.
        backspace_catalog = path.read_bytes()
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Backspace, Qt.KeyboardModifier.NoModifier, '\b'))
        process()
        assert popup.search_input.hasFocus() and popup.search_input.text() == '', 'Backspace on an icon did not edit search'
        second._focus_icon(0)
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Backspace, Qt.KeyboardModifier.NoModifier, '\b'))
        process()
        assert popup.search_input.hasFocus() and popup.search_input.text() == '', 'Empty search lost focus on Backspace'
        popup.search_input.setText('2')
        process()
        second._focus_icon(0)
        icon = QApplication.focusWidget()
        QApplication.sendEvent(icon, QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Backspace, Qt.KeyboardModifier.ControlModifier, '\b'))
        process()
        assert popup.search_input.text() == '2' and QApplication.focusWidget() is icon, 'Ctrl+Backspace was intercepted'
        popup.search_input.setFocus()
        popup.search_input.setText('23')
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Backspace, Qt.KeyboardModifier.NoModifier, '\b'))
        process()
        assert popup.search_input.text() == '2', 'Focused search deleted twice'
        assert path.read_bytes() == backspace_catalog, 'Backspace modified app catalog'
        second._focus_icon(0)

        # Typing on an icon must resume the existing query, including the first
        # character, exactly once. Drive the actual focused widget/event chain.
        catalog_before_typing = path.read_bytes()
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_3, Qt.KeyboardModifier.NoModifier, '3'))
        process()
        assert popup.search_input.hasFocus() and popup.search_input.text() == '23', 'Typing on an icon did not resume search'
        assert not second._app_icons
        popup.search_input.clear()
        process()
        second._focus_icon(0)
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Z, Qt.KeyboardModifier.NoModifier, 'я'))
        process()
        assert popup.search_input.hasFocus() and popup.search_input.text() == 'я', 'Unicode text was lost'
        popup.search_input.clear()
        process()
        second._focus_icon(0)
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_A, Qt.KeyboardModifier.ShiftModifier, 'A'))
        process()
        assert popup.search_input.hasFocus() and popup.search_input.text() == 'A', 'Shift typing was lost'

        # Modified shortcuts must not become search text or steal focus.
        for modifiers in (Qt.KeyboardModifier.ControlModifier, Qt.KeyboardModifier.AltModifier,
                          Qt.KeyboardModifier.MetaModifier):
            popup.search_input.clear()
            process()
            second._focus_icon(0)
            icon = QApplication.focusWidget()
            QApplication.sendEvent(icon, QKeyEvent(QEvent.Type.KeyPress, Qt.Key.Key_X, modifiers, 'x'))
            process()
            assert popup.search_input.text() == '' and QApplication.focusWidget() is icon, 'Shortcut was redirected to search'

        # Inside a folder, typing returns to the global search rather than
        # sending text to the hidden line edit or changing folder membership.
        second._open_group('Alpha', [a for a in second._load_apps() if a.get('group') == 'Alpha'])
        process()
        second._focus_icon(0)
        assert QApplication.focusWidget() is not None, 'Folder icons did not become visible/focusable'
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_2, Qt.KeyboardModifier.NoModifier, '2'))
        process()
        assert not hasattr(second, '_current_group') and popup.search_input.hasFocus(), (
            hasattr(second, '_current_group'), popup.search_input.text(), popup.isVisible(), popup.isActiveWindow(),
            second._is_closing, type(QApplication.focusWidget()).__name__,
            QApplication.focusWidget().window() is popup if QApplication.focusWidget() else None)
        assert popup.search_input.text() == '2'
        assert [w._manual_key for w in second._app_icons] == [('app', '2')]
        assert path.read_bytes() == catalog_before_typing, 'Typing changed catalog data'

        # Text typed in another editor/dialog stays there, with no global hook.
        dialog = QDialog(popup)
        dialog.setModal(True)
        editor = QLineEdit(dialog)
        layout = QVBoxLayout(dialog)
        layout.addWidget(editor)
        dialog.show()
        dialog.activateWindow()
        editor.setFocus()
        process()
        QApplication.sendEvent(QApplication.focusWidget(), QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_X, Qt.KeyboardModifier.NoModifier, 'x'))
        process()
        assert editor.text() == 'x' and popup.search_input.text() == '2'
        QApplication.sendEvent(editor, QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Backspace, Qt.KeyboardModifier.NoModifier, '\b'))
        process()
        assert editor.text() == '' and popup.search_input.text() == '2', 'Dialog Backspace escaped into search'
        count = len(enter_launched)
        QApplication.sendEvent(editor, QKeyEvent(
            QEvent.Type.KeyPress, Qt.Key.Key_Return, Qt.KeyboardModifier.NoModifier, '\r'))
        process()
        assert len(enter_launched) == count, 'Dialog Enter launched a search result'
        dialog.close()
        process()
        # Upstream disposes the popup on close; reopen a new instance, as the
        # real shortcut and dock do, rather than re-showing a closing window.
        second._cleanup_popup()
        process()
        second._launchpad_popup = second._create_launchpad_popup()
        second._populate_grid()
        popup = second._launchpad_popup
        popup.show()
        popup.activateWindow()
        process()
        assert popup.search_input.hasFocus(), 'Reopening Launchpad lost search focus'
        popup.search_input.setText('no application matches this query')
        process()
        assert not second._app_icons and popup.search_input.hasFocus(), 'Empty results lost focus'
        # A queued initial-focus callback must not focus a hidden/closing popup.
        popup.hide()
        third = LaunchpadWidget(config)
        third._launchpad_popup = third._create_launchpad_popup()
        third._populate_grid()
        third._launchpad_popup.show()
        third._launchpad_popup.activateWindow()
        process()
        second._focus_first_icon()
        assert third._launchpad_popup.search_input.hasFocus(), 'Hidden popup stole focus'
        third._launchpad_popup.close()
        second._launchpad_popup.close()
        owner._launchpad_popup.close()
        process()
        assert not callback_errors, callback_errors
        print('PASS: real YASB/Qt callbacks, folder/app ordering, in-folder ordering, gap drop, search guard and reopened widget')
        print('PASS: popup search focus, immediate typing/filtering, arrow navigation, reopen, empty results and no hidden-popup focus stealing')
        print('PASS: typing on icons resumes search, Unicode, preserved query, folder exit, shortcut exclusions and independent text fields')
        print('PASS: Backspace resumes/deletes search, empty query, normal editor behavior, Ctrl exclusion and unchanged app catalog')
        print('PASS: search Enter/numpad Enter launches first displayed match once; empty results, shortcuts, repeat, dialogs and selected-icon navigation')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--qt', action='store_true')
    parser.add_argument('--yasb-root', type=Path, default=Path(os.environ.get('ProgramFiles', 'C:/Program Files'))/'YASB')
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    pure_checks()
    if args.qt:
        qt_checks(args.yasb_root, args.archive)
