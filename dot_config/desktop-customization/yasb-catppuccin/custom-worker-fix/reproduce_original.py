"""Opt-in native crash reproducer. Runs original installed bytecode in isolation."""
import argparse
import ctypes
import faulthandler
import json
import marshal
import os
from pathlib import Path
import sys
import threading
import time
import types
import zipfile

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--yasb-root", default=os.path.join(os.environ["ProgramFiles"], "YASB"))
parser.add_argument("--seconds", type=int, choices=range(1, 31), default=15)
args = parser.parse_args()
from qt_runtime import load
load(args.yasb_root)
from PyQt6.QtCore import QCoreApplication, QObject, QTimer, Qt, pyqtSignal, pyqtSlot, qVersion
from patch_custom_worker import BACKUP, ENTRY, ORIGINAL_SHA256, sha
faulthandler.enable()
kernel = ctypes.WinDLL("kernel32", use_last_error=True)
kernel.GetCurrentProcess.restype = ctypes.c_void_p
handle = ctypes.c_void_p(kernel.GetCurrentProcess())
kernel.SetPriorityClass(handle, 0x4000)
pm = ctypes.c_size_t(); sm = ctypes.c_size_t()
kernel.GetProcessAffinityMask(handle, ctypes.byref(pm), ctypes.byref(sm))
mask = pm.value & -pm.value; rest = pm.value & ~mask
kernel.SetProcessAffinityMask(handle, ctypes.c_size_t(mask | (rest & -rest)))
with zipfile.ZipFile(Path(args.yasb_root) / "lib/library.zip") as archive:
    original = archive.read(BACKUP if BACKUP in archive.namelist() else ENTRY)
assert sha(original) == ORIGINAL_SHA256, "Unsupported original module"
module = marshal.loads(original[16:])
code = next(c for c in module.co_consts if isinstance(c, types.CodeType) and c.co_name == "CustomWorker")
class Process:
    def __init__(self, *args, **kwargs): self.stdout = self
    def read(self): time.sleep(0.0008); return '{"value":1}'
namespace = {"__name__":"isolated_original", "QObject":QObject, "pyqtSignal":pyqtSignal,
             "json":json, "subprocess":types.SimpleNamespace(Popen=Process, PIPE=-1,
               DEVNULL=-3, CREATE_NO_WINDOW=0x8000000)}
Worker = __build_class__(types.FunctionType(code, namespace), "CustomWorker", QObject)
app = QCoreApplication([])
live = set(); count = 0; received = 0; started = time.monotonic()
class Widget(QObject):
    def __init__(self): super().__init__(); self.worker = None
    @pyqtSlot(object)
    def receive(self, data):
        global received
        received += 1
    def tick(self):
        global count
        if len(live) >= 4: return
        if self.worker: self.worker.stop()
        self.worker = Worker(["fake"], False, "utf-8", "json", False)
        worker = self.worker
        def execute():
            try: worker.run()
            finally: live.discard(threading.current_thread())
        thread = threading.Thread(target=execute)
        worker.data_ready.connect(self.receive)
        worker.finished.connect(worker.deleteLater)
        count += 1; live.add(thread); thread.start()
widgets = [Widget() for _ in range(4)]
timer = QTimer(); timer.setTimerType(Qt.TimerType.PreciseTimer)
def tick():
    if time.monotonic()-started >= args.seconds:
        timer.stop(); QTimer.singleShot(50, app.quit); return
    widgets[count % 4].tick()
timer.timeout.connect(tick); timer.start(1)
print(json.dumps({"originalBytecode":True,"qt":qVersion(),"seconds":args.seconds}), flush=True)
app.exec()
for thread in list(live): thread.join(1)
print(json.dumps({"created":count,"delivered":received,"crashReproduced":False}), flush=True)
