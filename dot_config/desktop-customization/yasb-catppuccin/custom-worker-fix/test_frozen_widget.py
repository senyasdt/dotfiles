"""Offscreen integration with the patched archive's real CustomWidget class."""
import argparse
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser()
parser.add_argument("--yasb-root", default=os.path.join(os.environ["ProgramFiles"], "YASB"))
parser.add_argument("--archive", type=Path, required=True)
args = parser.parse_args()
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_PLUGIN_PATH"] = str(Path(args.yasb_root) / "lib/PyQt6/Qt6/plugins")
from qt_runtime import load
load(args.yasb_root, args.archive)
from PyQt6 import sip
from PyQt6.QtCore import QCoreApplication, QEvent
from PyQt6.QtWidgets import QApplication
app = QApplication([])
from core.widgets.yasb.custom import CustomWidget, CustomWorker
from core.validation.widgets.yasb.custom import CustomConfig
import core.widgets.yasb.custom_worker_lifecycle as fix
assert CustomWorker is fix.CustomWorker

class Process:
    def __init__(self, *args, **kwargs): pass
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def communicate(self): return '{"value":"worker-integration-ok"}', None

fix.subprocess = SimpleNamespace(Popen=Process, PIPE=-1, DEVNULL=-3, CREATE_NO_WINDOW=0x8000000)
config = CustomConfig(class_name="dev-worker-test", label="{data[value]}", exec_options={
    "run_cmd":"local-test", "run_once":True, "return_format":"json", "encoding":"utf-8"})
widget = CustomWidget(config)
deadline = time.monotonic()+3
while widget._exec_data is None and time.monotonic()<deadline:
    app.processEvents(); time.sleep(0.001)
assert widget._exec_data == {"value":"worker-integration-ok"}
assert any(label.text() == "worker-integration-ok" for label in widget._widgets)
sip.delete(widget)
while app.findChildren(fix.CustomWorker) and time.monotonic()<deadline:
    app.processEvents()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
assert not app.findChildren(fix.CustomWorker)
print("PASS: patched frozen module imports, actual CustomWidget renders result offscreen, worker cleanup succeeds")
