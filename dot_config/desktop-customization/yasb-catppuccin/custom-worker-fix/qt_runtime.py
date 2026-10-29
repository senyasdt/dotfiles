"""Test-only loader for the same frozen PyQt/Qt DLLs as installed YASB."""
import os
import importlib.abc
import importlib.machinery
import importlib.util
from pathlib import Path
import sys

_dlls = []


def load(yasb_root, archive=None):
    if sys.version_info[:2] != (3, 14):
        raise RuntimeError("Standalone tests require Python 3.14 matching frozen YASB")
    lib = Path(yasb_root) / "lib"
    _dlls.extend(os.add_dll_directory(str(path)) for path in
                 (lib / "PyQt6/Qt6/bin", lib / "PyQt6", lib))
    sys.path[:0] = [str(archive or lib / "library.zip"), str(lib)]
    # cx_Freeze normally joins zipped Python packages to their adjacent native
    # extension directories. Standalone Python needs the same test-only lookup.
    class FrozenPaths(importlib.abc.MetaPathFinder):
        def find_spec(self, fullname, path=None, target=None):
            for suffix in importlib.machinery.EXTENSION_SUFFIXES:
                flat = lib / (fullname + suffix)
                if flat.is_file():
                    return importlib.util.spec_from_file_location(fullname, flat)
            spec = importlib.machinery.PathFinder.find_spec(fullname, path)
            native = lib.joinpath(*fullname.split("."))
            if spec and spec.submodule_search_locations is not None and native.is_dir():
                spec.submodule_search_locations.append(str(native))
            return spec
    sys.meta_path.insert(0, FrozenPaths())
    import PyQt6
    PyQt6.__path__.append(str(lib / "PyQt6"))
