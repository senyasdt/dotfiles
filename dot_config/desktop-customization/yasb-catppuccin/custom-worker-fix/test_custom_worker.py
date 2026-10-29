"""Isolated lifecycle/stress tests; no YASB window, shell commands or network."""
import argparse
import ctypes
import gc
import io
import json
import logging
import os
import sys
import threading
import time
from types import SimpleNamespace

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser()
parser.add_argument("--yasb-root", default=os.path.join(os.environ["ProgramFiles"], "YASB"))
parser.add_argument("--stress", type=int, default=0)
parser.add_argument("--shutdown", action="store_true")
args = parser.parse_args()
from qt_runtime import load
load(args.yasb_root)
from PyQt6 import sip
from PyQt6.QtCore import QCoreApplication, QEvent, QObject, QTimer, Qt, qVersion
import custom_worker_lifecycle as fix

app = QCoreApplication([])
class Process:
    def __init__(self, cmd, **kwargs):
        self.cmd = cmd
        if cmd[0] == "error":
            raise OSError("expected test command failure")
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def communicate(self):
        if self.cmd[0] == "gate":
            entered.set()
            assert gate.wait(3), "test gate timed out"
        else:
            time.sleep(0.0008 if args.stress else 0.015)
        return self.cmd[1], None

fix.subprocess = SimpleNamespace(Popen=Process, PIPE=-1, DEVNULL=-3, CREATE_NO_WINDOW=0x8000000)
errors = io.StringIO()
handler = logging.StreamHandler(errors)
fix_logger = logging.getLogger(fix.__name__)
fix_logger.addHandler(handler)
fix_logger.propagate = False

class Widget(QObject):
    def __init__(self, command="normal", output='{"value":1}', kind="json"):
        super().__init__()
        self._worker = None
        self._exec_cmd = [command, output]
        self.config = SimpleNamespace(exec_options=SimpleNamespace(
            use_shell=False, encoding="utf-8", return_format=kind, hide_empty=False))
        self.received = []
        self.labels = 0
    def _handle_exec_data(self, data): self.received.append(data)
    def _update_label(self): self.labels += 1

fix.install({"CustomWidget": Widget})

def drain():
    app.processEvents()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)

def until(predicate, seconds=3):
    deadline = time.monotonic() + seconds
    while not predicate() and time.monotonic() < deadline:
        drain()
        time.sleep(0.001)
    drain()
    assert predicate(), "lifecycle operation timed out"

def clean():
    until(lambda: not app.findChildren(fix.CustomWorker))

if args.stress:
    # Bound stress to two logical CPUs, four Qt workers, 30 seconds, low priority.
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    handle = ctypes.c_void_p(kernel.GetCurrentProcess())
    kernel.SetPriorityClass(handle, 0x4000)
    pm = ctypes.c_size_t(); sm = ctypes.c_size_t()
    kernel.GetProcessAffinityMask(handle, ctypes.byref(pm), ctypes.byref(sm))
    mask = pm.value & -pm.value; rest = pm.value & ~mask
    mask |= rest & -rest
    kernel.SetProcessAffinityMask(handle, ctypes.c_size_t(mask))
    widgets = [Widget() for _ in range(4)]
    count = 0; peak = 0; started = time.monotonic()
    timer = QTimer(); timer.setTimerType(Qt.TimerType.PreciseTimer)
    def tick():
        global count, peak
        live = len(app.findChildren(fix.CustomWorker))
        peak = max(peak, live)
        if count >= args.stress or time.monotonic() - started >= 30:
            timer.stop(); QTimer.singleShot(30, app.quit); return
        if live < 4:
            widget = widgets[count % 4]
            old = widget._worker
            # This stress checks delivery, not deliberate cancellation of an
            # earlier slow poll (covered separately in the lifecycle tests).
            if old is not None and not sip.isdeleted(old) and old.isRunning():
                return
            widget._exec_callback(); count += 1
    timer.timeout.connect(tick); timer.start(1)
    app.exec()
    clean()
    delivered = sum(len(w.received) for w in widgets)
    assert count == args.stress and delivered == count, (count, delivered)
    print(json.dumps({"stress": "PASS", "created": count, "delivered": delivered,
                      "seconds": round(time.monotonic()-started, 3), "peakWorkers": peak,
                      "remainingWorkers": len(app.findChildren(fix.CustomWorker)), "qt": qVersion()}))
elif args.shutdown:
    widget = Widget()
    widget._exec_callback()
    worker = widget._worker
    QTimer.singleShot(1, app.quit)
    app.exec()
    assert sip.isdeleted(worker) or not worker.isRunning()
    sip.delete(app)
    print("PASS: application shutdown waits for worker before deleting its parent")
else:
    for output, kind, expected in [('{"value":1}', "json", {"value":1}),
                                   (b'{"value":2}', "json", {"value":2}),
                                   ("invalid", "json", None),
                                   (" text \n", "string", "text"),
                                   (b" text \n", "string", "text")]:
        widget = Widget(output=output, kind=kind)
        widget._exec_callback(); until(lambda: bool(widget.received)); clean()
        assert widget.received == [expected]
        # Replacement must also work when the previous C++ worker was deleted.
        widget._exec_callback(); until(lambda: len(widget.received) == 2); clean()
        sip.delete(widget)
    for command, output, kind in [("error", "", "json"), ("normal", b"\xff", "string")]:
        widget = Widget(command, output, kind)
        widget._exec_callback(); clean()
        assert not widget.received
        sip.delete(widget)
    assert errors.getvalue().count("Custom widget command failed") == 2
    gate = threading.Event(); entered = threading.Event()
    widget = Widget("gate")
    widget._exec_callback(); until(entered.is_set)
    old = widget._worker
    widget._exec_cmd = ["normal", '{"value":2}']
    widget._exec_callback(); gate.set()
    until(lambda: bool(widget.received)); clean()
    assert widget.received == [{"value":2}]
    sip.delete(widget)
    gate.clear(); entered.clear()
    widget = Widget("gate"); widget._exec_callback(); until(entered.is_set)
    worker = widget._worker
    sip.delete(widget)
    assert not worker._is_running and worker.isRunning()
    gate.set(); clean()
    worker = fix.CustomWorker(["normal", "{}"], False, "utf-8", "json", False)
    result = []; worker.data_ready.connect(result.append)
    worker.finished.connect(worker.deleteLater); worker.stop(); worker.start()
    clean(); assert not result
    widget = Widget(); widget._exec_cmd = None; widget._exec_callback()
    assert widget.labels == 1 and widget._worker is None
    gc.collect(); clean()
    print("PASS: JSON/text, replacement, errors, cancellation, widget destruction, static label and zero leaked workers")
