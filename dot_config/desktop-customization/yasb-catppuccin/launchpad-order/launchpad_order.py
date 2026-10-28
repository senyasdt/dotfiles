"""Manual ordering and search-first opening for YASB 2.0.7. No resident helper."""
import json
import logging
import os
import tempfile
from pathlib import Path

PATCH_VERSION = 5
MIME = 'application/x-yasb-manual-order'


def key_for(app):
    return ('group', app['group']) if app.get('group') else ('app', str(app['id']))


def root_blocks(apps):
    blocks = {}
    for app in apps:
        blocks.setdefault(key_for(app), []).append(app)
    return blocks


def reordered(apps, source, target, after=False, scope='root'):
    """Only change list order, never membership, identifiers or launch fields."""
    if source == target:
        return list(apps)
    if scope == 'root':
        blocks = root_blocks(apps)
        keys = list(blocks)
    else:
        selected = [a for a in apps if scope == 'flat' or a.get('group') == scope[6:]]
        blocks = {('app', str(a['id'])): [a] for a in selected}
        keys = list(blocks)
        if len(keys) != len(selected):
            raise ValueError('Duplicate application IDs')
    if source not in blocks or target not in blocks:
        raise ValueError('Dragged item no longer exists in this view')
    keys.remove(source)
    keys.insert(keys.index(target) + bool(after), source)
    moved = [app for key in keys for app in blocks[key]]
    if scope == 'root' or scope == 'flat':
        return moved
    iterator = iter(moved)
    return [next(iterator) if a.get('group') == scope[6:] else a for a in apps]


def persist(path, original, apps):
    """Atomically publish order, refusing concurrent catalog edits."""
    path = Path(path)
    payload = json.dumps(apps, ensure_ascii=False, indent=2).encode('utf-8')
    if path.read_bytes() != original:
        raise RuntimeError('Library changed during drag; retry the move')
    fd, temp = tempfile.mkstemp(prefix='.manual-order-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        if path.read_bytes() != original:
            raise RuntimeError('Library changed during drag; retry the move')
        # One local recovery snapshot, never included in dotfiles.
        path.with_name('apps.before-manual-order.json').write_bytes(original)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def install(cls):
    if getattr(cls, '_manual_order_version', None) == PATCH_VERSION:
        return
    from PyQt6.QtCore import QMimeData, Qt, QTimer
    from PyQt6.QtGui import QColor, QDrag, QPainter
    from PyQt6.QtWidgets import QApplication, QLineEdit, QPlainTextEdit, QTextEdit

    original_app = cls._create_app_icon_widget
    original_group = cls._create_group_widget
    original_grouped = cls._populate_grouped_grid
    original_flat = cls._populate_flat_grid
    original_first_icon = cls._focus_first_icon
    original_key_press = cls._handle_popup_key_press

    def popup_key_press(owner, event):
        # This is a local fallback for keys an icon/background did not consume,
        # never a system-wide hook. Editors and shortcuts keep their own input.
        popup = owner._launchpad_popup
        text = event.text()
        backspace = event.key() == Qt.Key.Key_Backspace
        modifiers = event.modifiers()
        shortcut = modifiers & (Qt.KeyboardModifier.ControlModifier
                                | Qt.KeyboardModifier.AltModifier
                                | Qt.KeyboardModifier.MetaModifier)
        focused = QApplication.focusWidget()
        modal = QApplication.activeModalWidget()
        menu = QApplication.activePopupWidget()
        if (popup and popup.isVisible() and popup.isActiveWindow() and not owner._is_closing
                and event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter) and not shortcut
                and focused is popup.search_input and popup.search_input.isVisible()
                and modal in (None, popup) and menu in (None, popup)):
            # Use the displayed filtered order, including group: searches.
            # Leave explicit icon selection to the upstream keyboard handler.
            if (not event.isAutoRepeat() and popup.search_input.text().strip()
                    and not hasattr(owner, '_current_group') and owner._app_icons):
                first = owner._app_icons[0]
                if not getattr(first, 'is_group', False):
                    owner._launch_app(first.app_data)
            event.accept()
            return
        if (popup and popup.isVisible() and popup.isActiveWindow() and not owner._is_closing
                and (backspace or (text and text.isprintable())) and not shortcut
                and modal in (None, popup) and menu in (None, popup)
                and (focused is None or focused.window() is popup)
                and not isinstance(focused, (QLineEdit, QPlainTextEdit, QTextEdit))):
            def forward_text():
                if (owner._launchpad_popup is not popup or owner._is_closing
                        or not popup.isVisible() or not popup.isActiveWindow()
                        or QApplication.activeModalWidget() not in (None, popup)
                        or QApplication.activePopupWidget() not in (None, popup)):
                    return
                was_group = hasattr(owner, '_current_group')
                if was_group:
                    # Move focus off the old icon before the grid reparents it;
                    # otherwise that detached frame can become the active window.
                    popup.search_input.show()
                    popup.search_input.setFocus(Qt.FocusReason.OtherFocusReason)
                    owner._close_group()
                popup.search_input.setFocus(Qt.FocusReason.OtherFocusReason)
                if backspace:
                    popup.search_input.backspace()
                else:
                    popup.search_input.insert(text)
                if was_group:
                    def finish_group_focus():
                        active = QApplication.activeWindow()
                        if (owner._launchpad_popup is popup and not owner._is_closing
                                and popup.isVisible() and QApplication.activeModalWidget() in (None, popup)
                                and QApplication.activePopupWidget() in (None, popup)
                                and (active is popup or getattr(active, '_manual_owner', None) is owner)):
                            popup.activateWindow()
                            popup.search_input.setFocus(Qt.FocusReason.OtherFocusReason)
                    # Upstream reparents old icons into detached frames. Finish
                    # their pending focus events, without stealing from other apps.
                    QTimer.singleShot(0, finish_group_focus)

            if hasattr(owner, '_current_group'):
                # Closing a group rebuilds/reparents the receiving icon. Wait
                # until its current key event has finished before doing that.
                QTimer.singleShot(0, forward_text)
            else:
                forward_text()
            event.accept()
            return
        original_key_press(owner, event)

    def initial_focus(owner):
        # In 2.0.7 only the popup show callback queues _focus_first_icon.
        # Change that initial choice; keep explicit arrow/Tab navigation intact.
        popup = owner._launchpad_popup
        if not popup or not popup.isVisible() or owner._is_closing:
            return
        if popup.search_input.isVisible():
            popup.search_input.setFocus(Qt.FocusReason.PopupFocusReason)
        elif hasattr(owner, '_current_group'):
            original_first_icon(owner)

    def scope_for(owner):
        popup = owner._launchpad_popup
        if hasattr(owner, '_current_group'):
            return 'group:' + owner._current_group
        if popup and popup.search_input.text():
            return None  # Search never silently changes hidden items.
        return 'root' if owner._group_apps else 'flat'

    def clear_marks(owner):
        for icon in owner._app_icons:
            icon._manual_marker = None
            icon.update()

    def drag_payload(owner, event):
        if not event.mimeData().hasFormat(MIME):
            return None
        source_widget = event.source()
        if getattr(source_widget, '_manual_owner', None) is not owner:
            return None
        try:
            payload = json.loads(bytes(event.mimeData().data(MIME)))
            if payload['scope'] != scope_for(owner) or payload['scope'] is None:
                return None
            key = tuple(payload['key'])
            if len(key) != 2 or key[0] not in ('group', 'app'):
                return None
            return key
        except (KeyError, ValueError, TypeError):
            return None

    def refresh(owner):
        if not owner._launchpad_popup:
            return
        if hasattr(owner, '_current_group'):
            group = owner._current_group
            owner._open_group(group, [a for a in owner._load_apps() if a.get('group') == group])
        else:
            owner._populate_grid(owner._launchpad_popup.search_input.text())

    def drop(owner, event, target, after):
        source = drag_payload(owner, event)
        clear_marks(owner)
        if source is None:
            event.ignore()
            return
        try:
            path = Path(owner._data_file)
            original = path.read_bytes()
            apps = json.loads(original.decode('utf-8-sig'))
            result = reordered(apps, source, target, after, scope_for(owner))
            if result != apps:
                persist(path, original, result)
                QTimer.singleShot(0, lambda: refresh(owner))
            event.setDropAction(Qt.DropAction.MoveAction)
            event.accept()
        except Exception:
            logging.exception('Launchpad manual order: move not saved')
            event.ignore()

    def bind(owner, widget, key):
        widget._manual_owner = owner
        widget._manual_key = key
        widget._manual_marker = None
        widget._manual_start = None
        widget._manual_dragged = False
        widget.setAcceptDrops(True)
        press, release, paint = widget.mousePressEvent, widget.mouseReleaseEvent, widget.paintEvent
        old_enter, old_leave = widget.dragEnterEvent, widget.dragLeaveEvent

        def on_press(event):
            if event.button() == Qt.MouseButton.LeftButton:
                widget._manual_start = event.pos()
                widget._manual_dragged = False
            press(event)

        def on_move(event):
            start = widget._manual_start
            scope = scope_for(owner)
            if (start is None or scope is None or not event.buttons() & Qt.MouseButton.LeftButton
                    or (event.pos() - start).manhattanLength() < QApplication.startDragDistance()
                    or widget._manual_dragged):
                return
            widget._manual_dragged = True
            drag = QDrag(widget)
            mime = QMimeData()
            mime.setData(MIME, json.dumps({'key': key, 'scope': scope}).encode('utf-8'))
            drag.setMimeData(mime)
            drag.setPixmap(widget.grab())
            drag.setHotSpot(start)
            drag.exec(Qt.DropAction.MoveAction)
            clear_marks(owner)

        def on_release(event):
            start = widget._manual_start
            if event.button() == Qt.MouseButton.LeftButton:
                if (start is None or widget._manual_dragged
                        or (event.pos() - start).manhattanLength() >= QApplication.startDragDistance()):
                    widget._manual_start = None
                    return
            release(event)
            widget._manual_start = None

        def on_enter(event):
            if drag_payload(owner, event) is not None:
                on_drag_move(event)
            elif event.mimeData().hasUrls():
                old_enter(event)
            else:
                event.ignore()

        def on_drag_move(event):
            if drag_payload(owner, event) is None:
                event.ignore()
                return
            clear_marks(owner)
            widget._manual_marker = event.position().x() >= widget.width() / 2
            widget.update()
            event.setDropAction(Qt.DropAction.MoveAction)
            event.accept()

        def on_leave(event):
            clear_marks(owner)
            old_leave(event)

        def on_paint(event):
            paint(event)
            if widget._manual_marker is not None:
                painter = QPainter(widget)
                pen = painter.pen()
                pen.setColor(QColor('#a9bbce'))
                pen.setWidth(2)
                painter.setPen(pen)
                x = widget.width() - 2 if widget._manual_marker else 2
                painter.drawLine(x, 6, x, max(6, widget.height() - 6))
                painter.end()

        widget.mousePressEvent = on_press
        widget.mouseMoveEvent = on_move
        widget.mouseReleaseEvent = on_release
        widget.dragEnterEvent = on_enter
        widget.dragMoveEvent = on_drag_move
        widget.dragLeaveEvent = on_leave
        widget.dropEvent = lambda event: drop(owner, event, key, event.position().x() >= widget.width() / 2)
        widget.paintEvent = on_paint
        return widget

    def bind_grid(owner):
        grid = owner._launchpad_popup.grid_container
        if getattr(grid, '_manual_bound', False):
            return
        grid._manual_bound = True
        grid.setAcceptDrops(True)

        def destination(event):
            if drag_payload(owner, event) is None or not owner._app_icons:
                return None
            pos = event.position().toPoint()
            icon = min(owner._app_icons, key=lambda w: (w.geometry().center() - pos).manhattanLength())
            rect = icon.geometry()
            after = pos.y() > rect.bottom() or (pos.y() >= rect.top() and pos.x() >= rect.center().x())
            return icon, after

        def move(event):
            hit = destination(event)
            clear_marks(owner)
            if hit:
                icon, after = hit
                icon._manual_marker = after
                icon.update()
                event.setDropAction(Qt.DropAction.MoveAction)
                event.accept()
            else:
                event.ignore()

        def on_drop(event):
            hit = destination(event)
            if hit:
                icon, after = hit
                drop(owner, event, icon._manual_key, after)
            else:
                event.ignore()

        grid.dragEnterEvent = move
        grid.dragMoveEvent = move
        grid.dragLeaveEvent = lambda event: clear_marks(owner)
        grid.dropEvent = on_drop

    def create_app(owner, app):
        return bind(owner, original_app(owner, app), ('app', str(app['id'])))

    def create_group(owner, name, apps):
        return bind(owner, original_group(owner, name, apps), ('group', name))

    def grouped(owner, apps):
        original_grouped(owner, apps)
        ranks = {key: rank for rank, key in enumerate(root_blocks(apps))}
        owner._app_icons.sort(key=lambda widget: ranks[widget._manual_key])
        layout = owner._launchpad_popup.grid_layout
        for widget in owner._app_icons:
            layout.removeWidget(widget)
        for i, widget in enumerate(owner._app_icons):
            layout.addWidget(widget, i // max(1, owner._grid_columns), i % max(1, owner._grid_columns))
        bind_grid(owner)

    def flat(owner, apps):
        original_flat(owner, apps)
        bind_grid(owner)

    cls._create_app_icon_widget = create_app
    cls._create_group_widget = create_group
    cls._populate_grouped_grid = grouped
    cls._populate_flat_grid = flat
    cls._focus_first_icon = initial_focus
    cls._handle_popup_key_press = popup_key_press
    cls._manual_order_version = PATCH_VERSION
    logging.info('Launchpad manual order/search focus patch v%s loaded', PATCH_VERSION)
