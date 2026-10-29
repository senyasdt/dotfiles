"""Experimental YASB 2.0.7 custom-worker lifecycle correction; no resident helper."""

import json
import logging
import subprocess

from PyQt6.QtCore import QCoreApplication, QThread, pyqtSignal, pyqtSlot


class CustomWorker(QThread):
    # QThread owns/emits finished after run() returns. Never emit it ourselves.
    data_ready = pyqtSignal(object)

    def __init__(self, cmd, use_shell, encoding, return_type, hide_empty):
        app = QCoreApplication.instance()
        if app is None:
            raise RuntimeError("A Qt application is required for a custom worker")
        # The application keeps unfinished workers alive across widget replacement
        # and destruction. Finished workers delete themselves on the GUI thread.
        super().__init__(app)
        self.cmd = cmd
        self.use_shell = use_shell
        self.encoding = encoding
        self.return_type = return_type
        self.hide_empty = hide_empty
        self._is_running = True
        app.aboutToQuit.connect(self.shutdown)

    @pyqtSlot()
    def stop(self):
        # Preserve YASB's existing cancellation semantics: discard the result,
        # without terminating an arbitrary user command or its descendants.
        self._is_running = False

    @pyqtSlot()
    def shutdown(self):
        self.stop()
        # A running QThread must finish before its application parent is deleted.
        # As in the original non-daemon Python worker, the current command is
        # allowed to finish. No terminate(), process tree kill or polling timer.
        self.wait()

    def run(self):
        try:
            if not self._is_running:
                return
            exec_data = None
            if self.cmd:
                with subprocess.Popen(
                    self.cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    creationflags=subprocess.CREATE_NO_WINDOW,
                    shell=self.use_shell,
                    encoding=self.encoding,
                ) as proc:
                    output, _ = proc.communicate()
                if self.return_type == "json":
                    try:
                        exec_data = json.loads(output)
                    except json.JSONDecodeError:
                        pass
                else:
                    text = output if isinstance(output, str) else output.decode("utf-8")
                    exec_data = text.strip()
            if self._is_running:
                self.data_ready.emit(exec_data)
        except Exception:
            # Exceptions escaping a Python QThread virtual method can abort Qt.
            logging.getLogger(__name__).exception("Custom widget command failed")


def _exec_callback(self):
    if not self._exec_cmd:
        self._update_label()
        return
    if self._worker:
        self._worker.stop()
    options = self.config.exec_options
    worker = CustomWorker(
        self._exec_cmd, options.use_shell, options.encoding,
        options.return_format, options.hide_empty,
    )
    self._worker = worker
    worker.data_ready.connect(self._handle_exec_data)
    self.destroyed.connect(worker.stop)
    worker.finished.connect(worker.deleteLater)
    worker.start()


def install(namespace):
    namespace["CustomWorker"] = CustomWorker
    namespace["CustomWidget"]._exec_callback = _exec_callback
