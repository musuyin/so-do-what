"""Resolve installed Flutter/Android tools without changing global settings."""
import os
import pathlib
import shutil


def resolve_tools():
    root = pathlib.Path(__file__).resolve().parents[1]
    flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
    adb = os.environ.get('ADB_BIN') or shutil.which('adb')
    android = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not adb and android:
        adb = str(pathlib.Path(android) / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb'))
    if not flutter or not adb or not pathlib.Path(flutter).is_file() or not pathlib.Path(adb).is_file():
        raise RuntimeError('Add Flutter and adb to PATH, or set FLUTTER_BIN and ANDROID_HOME/ADB_BIN.')
    return root, flutter, adb
