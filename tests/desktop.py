"""Keep the UI test process on a private, inactive Windows desktop."""

import ctypes
import os
from ctypes import wintypes
from uuid import uuid4


DESKTOP_READOBJECTS = 0x0001
DESKTOP_CREATEWINDOW = 0x0002
DESKTOP_CREATEMENU = 0x0004
DESKTOP_WRITEOBJECTS = 0x0080
UOI_NAME = 2


class IsolatedDesktop:
    """Isolate the test thread before Tk creates any windows."""

    def __init__(self):
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.GetCurrentThreadId.restype = wintypes.DWORD
        for name, arguments, result in (
            ("CreateDesktopW", (wintypes.LPCWSTR, ctypes.c_void_p, ctypes.c_void_p,
                                wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p), wintypes.HANDLE),
            ("SetThreadDesktop", (wintypes.HANDLE,), wintypes.BOOL),
            ("CloseDesktop", (wintypes.HANDLE,), wintypes.BOOL),
            ("GetThreadDesktop", (wintypes.DWORD,), wintypes.HANDLE),
            ("OpenInputDesktop", (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD), wintypes.HANDLE),
            ("GetUserObjectInformationW", (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                          wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)), wintypes.BOOL),
        ):
            function = getattr(self.user32, name)
            function.argtypes = arguments
            function.restype = result
        self.thread_id = kernel32.GetCurrentThreadId()
        self.name = f"DaymarkTests-{os.getpid()}-{uuid4().hex}"
        # Deliberately omit DESKTOP_SWITCHDESKTOP: tests can create windows,
        # menus and focus targets, but cannot activate this desktop.
        access = DESKTOP_READOBJECTS | DESKTOP_CREATEWINDOW | DESKTOP_CREATEMENU | DESKTOP_WRITEOBJECTS
        self.handle = self.user32.CreateDesktopW(self.name, None, None, 0, access, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())

        if not self.user32.SetThreadDesktop(self.handle):
            error = ctypes.WinError(ctypes.get_last_error())
            self.user32.CloseDesktop(self.handle)
            raise error
        # Keep this process-scoped handle until exit. Tk/Windows helper windows
        # can outlive test roots; Windows releases the desktop with the process.

    def _name(self, handle):
        value = ctypes.create_unicode_buffer(256)
        length = wintypes.DWORD()
        if not self.user32.GetUserObjectInformationW(handle, UOI_NAME, value, ctypes.sizeof(value),
                                                    ctypes.byref(length)):
            raise ctypes.WinError(ctypes.get_last_error())
        return value.value

    def thread_name(self):
        return self._name(self.user32.GetThreadDesktop(self.thread_id))

    def input_name(self):
        handle = self.user32.OpenInputDesktop(0, False, DESKTOP_READOBJECTS)
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            return self._name(handle)
        finally:
            if not self.user32.CloseDesktop(handle):
                raise ctypes.WinError(ctypes.get_last_error())
