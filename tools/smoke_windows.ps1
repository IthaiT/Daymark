param([string]$Executable = 'build/windows/x64/runner/Release/daymark.exe')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskExecutable = [IO.Path]::GetFullPath((Join-Path $taskRoot $Executable))
if (-not (Test-Path -LiteralPath $taskExecutable)) { throw "Build the Windows application first: $taskExecutable" }
$taskDirectory = Join-Path $taskRoot ('.test-artifacts/native-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
$taskDay = (Get-Date).ToString('yyyy-MM-dd')
$taskPreviousDay = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
$taskTags = '{"version":1,"tags":[{"id":"work","name":"主业","parent_id":null}]}'
[IO.File]::WriteAllText((Join-Path $taskDirectory 'tags.json'), $taskTags, [Text.UTF8Encoding]::new($false))
$taskLegacyHead = "undefined:legacy-leading,未定义,,${taskPreviousDay}T00:00:00,${taskPreviousDay}T22:00:00,`r`n"
$taskEvents = "id,title,tag_id,start,end,notes`r`nvideo,视频,work,${taskPreviousDay}T22:00:00,${taskPreviousDay}T23:50:00,`r`nsleep,睡觉,work,${taskDay}T00:06:00,${taskDay}T08:00:00,`r`nsynthetic,合成记录,work,${taskDay}T09:00:00,${taskDay}T10:00:00,隔离桌面测试`r`n"
[IO.File]::WriteAllText((Join-Path $taskDirectory 'events.csv'), $taskEvents + $taskLegacyHead, [Text.UTF8Encoding]::new($true))
$taskLedger = '{"version":2,"default_cash_account_id":"cash","balance_enabled":true,"accounts":[{"id":"cash","name":"现金","kind":"cash","opening_cents":1000000,"balance_cents":997200},{"id":"provident","name":"公积金","kind":"provident","opening_cents":0,"balance_cents":0},{"id":"investment","name":"投资","kind":"investment","opening_cents":0,"balance_cents":0}],"categories":[{"id":"lunch","name":"午餐","kind":"expense","parent_id":null}],"records":[{"id":"synthetic-money","kind":"expense","amount_cents":2800,"date":"' + $taskDay + '","category_id":"lunch","notes":"隔离测试","account_id":"cash","to_account_id":null,"affects_balance":true}],"pinned":["lunch"]}'
[IO.File]::WriteAllText((Join-Path $taskDirectory 'ledger.json'), $taskLedger, [Text.UTF8Encoding]::new($false))

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class DaymarkPrivateDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb;
        public string reserved, desktop, title;
        public int x, y, width, height, xChars, yChars, fill, flags;
        public short show, reservedCount;
        public IntPtr reservedBytes, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public uint processId, threadId; }
    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct MonitorInfo { public int size; public Rect monitor, work; public uint flags; }
    delegate bool WindowCallback(IntPtr window, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr mode, uint flags, uint access, IntPtr security);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr desktop, WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfoW(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr window, uint message, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, StringBuilder args, IntPtr processSecurity, IntPtr threadSecurity,
        bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo info);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);

    static int Read16(byte[] bytes, int offset) => (bytes[offset] << 8) | bytes[offset + 1];
    static uint Read32(byte[] bytes, int offset) =>
        ((uint)Read16(bytes, offset) << 16) | (uint)Read16(bytes, offset + 2);
    static bool HasGlyph(byte[] bytes, int cmap, int codepoint) {
        for (int table = 0; table < Read16(bytes, cmap + 2); table++) {
            int record = cmap + 4 + table * 8;
            int platform = Read16(bytes, record), encoding = Read16(bytes, record + 2);
            if (platform != 0 && !(platform == 3 && (encoding == 1 || encoding == 10))) continue;
            int subtable = cmap + checked((int)Read32(bytes, record + 4));
            int format = Read16(bytes, subtable);
            if (format == 4) {
                int count = Read16(bytes, subtable + 6) / 2;
                for (int segment = 0; segment < count; segment++) {
                    int end = Read16(bytes, subtable + 14 + segment * 2);
                    int start = Read16(bytes, subtable + 16 + count * 2 + segment * 2);
                    if (codepoint < start || codepoint > end) continue;
                    int delta = Read16(bytes, subtable + 16 + count * 4 + segment * 2);
                    int rangePosition = subtable + 16 + count * 6 + segment * 2;
                    int range = Read16(bytes, rangePosition);
                    int glyph = range == 0 ? codepoint : Read16(bytes, rangePosition + range + (codepoint - start) * 2);
                    if ((range == 0 || glyph != 0) && ((glyph + delta) & 0xffff) != 0) return true;
                }
            } else if (format == 12) {
                for (uint group = 0; group < Read32(bytes, subtable + 12); group++) {
                    int position = subtable + 16 + checked((int)group * 12);
                    uint start = Read32(bytes, position), end = Read32(bytes, position + 4);
                    if (codepoint >= start && codepoint <= end && Read32(bytes, position + 8) + codepoint - start != 0) return true;
                }
            }
        }
        return false;
    }
    static void CheckIconFont(string executable) {
        var bytes = File.ReadAllBytes(Path.Combine(Path.GetDirectoryName(executable), "data", "flutter_assets", "fonts", "MaterialIcons-Regular.otf"));
        int cmap = -1;
        for (int table = 0; table < Read16(bytes, 4); table++) {
            int record = 12 + table * 16;
            if (Encoding.ASCII.GetString(bytes, record, 4) == "cmap") cmap = checked((int)Read32(bytes, record + 8));
        }
        // Incremental Windows builds can retain an icon subset from older Dart code.
        // These codepoints correspond to the journal view switch's actual Material icons.
        foreach (int codepoint in new[] {0xe556, 0xf48f}) {
            if (cmap < 0 || !HasGlyph(bytes, cmap, codepoint)) {
                throw new Exception($"Release icon font is missing U+{codepoint:X4}. Regenerate Flutter assets by invalidating release_bundle_windows-x64_assets.stamp before rebuilding.");
            }
        }
    }

    static Process Launch(string executable, string directory, string desktop) {
        using var log = new FileStream(Path.Combine(directory, "native-" + Guid.NewGuid().ToString("N") + ".log"),
            FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite);
        var output = log.SafeFileHandle.DangerousGetHandle();
        if (!SetHandleInformation(output, 1, 1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var startup = new StartupInfo { cb = Marshal.SizeOf<StartupInfo>(), desktop = desktop,
            flags = 0x100, output = output, error = output };
        var args = new StringBuilder("\"" + executable + "\" --data-dir \"" + directory + "\"");
        ProcessInfo info;
        if (!CreateProcessW(executable, args, IntPtr.Zero, IntPtr.Zero, true, 0x08000000,
            IntPtr.Zero, Path.GetDirectoryName(executable), ref startup, out info)) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        CloseHandle(info.thread);
        CloseHandle(info.process);
        return Process.GetProcessById((int)info.processId);
    }
    static IntPtr WaitForWindow(IntPtr desktop, Process process) {
        for (int attempt = 0; attempt < 100; attempt++) {
            if (process.HasExited) throw new Exception("Application exited before creating a window: " + process.ExitCode);
            IntPtr found = IntPtr.Zero;
            EnumDesktopWindows(desktop, (window, _) => {
                uint pid; GetWindowThreadProcessId(window, out pid);
                if (pid == process.Id && IsWindowVisible(window)) {
                    // Input indicators may be visible under the same process.
                    var windowClass = new StringBuilder(256);
                    GetClassNameW(window, windowClass, windowClass.Capacity);
                    if (windowClass.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") found = window;
                }
                return true;
            }, IntPtr.Zero);
            if (found != IntPtr.Zero) return found;
            Thread.Sleep(100);
        }
        throw new Exception("No application window on the private desktop.");
    }
    static bool CanLock(string directory) {
        using (var stream = new FileStream(Path.Combine(directory, ".daymark.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite)) {
            try { stream.Lock(0, 1); stream.Unlock(0, 1); return true; }
            catch (IOException) { return false; }
        }
    }
    static void CheckWindowBounds(IntPtr window) {
        // Compare physical pixels even if PowerShell uses a different DPI context.
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            var info = new MonitorInfo { size = Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfoW(MonitorFromWindow(window, 2), ref info) || !GetWindowRect(window, out var bounds)) {
                throw new Exception("Cannot inspect startup window bounds.");
            }
            if (bounds.left < info.work.left || bounds.top < info.work.top ||
                bounds.right > info.work.right || bounds.bottom > info.work.bottom) {
                throw new Exception($"Startup window ({bounds.left}, {bounds.top}, {bounds.right}, {bounds.bottom}) extends beyond work area ({info.work.left}, {info.work.top}, {info.work.right}, {info.work.bottom}), including its title bar.");
            }
        } finally {
            if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
        }
    }
    public static void Run(string executable, string directory, string gapStart, string gapEnd) {
        CheckIconFont(executable);
        // No DESKTOP_SWITCHDESKTOP access; never activate or fall back to the input desktop.
        string name = "DaymarkSmoke-" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktopW(name, IntPtr.Zero, IntPtr.Zero, 0, 0x87, IntPtr.Zero);
        if (desktop == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        Process first = null, second = null;
        try {
            var ledgerBytes = File.ReadAllBytes(Path.Combine(directory, "ledger.json"));
            first = Launch(executable, directory, name);
            var firstWindow = WaitForWindow(desktop, first);
            Thread.Sleep(500);
            CheckWindowBounds(firstWindow);
            if (CanLock(directory)) throw new Exception("Application did not retain its data-directory lock.");
            if (!Convert.ToBase64String(ledgerBytes).Equals(Convert.ToBase64String(File.ReadAllBytes(Path.Combine(directory, "ledger.json"))))) {
                throw new Exception("Native launch replayed or rewrote linked money records.");
            }
            var bytes = File.ReadAllBytes(Path.Combine(directory, "events.csv"));
            var csv = Encoding.UTF8.GetString(bytes);
            if (csv.Contains("undefined:legacy-leading")) {
                throw new Exception("Native launch retained an unbounded gap before the first ordinary event.");
            }
            if (bytes.Length < 3 || bytes[0] != 0xef || bytes[1] != 0xbb || bytes[2] != 0xbf || !csv.Contains("undefined:")) {
                throw new Exception("Native launch did not preserve BOM and synchronize derived gaps.");
            }
            if (!csv.Contains("," + gapStart + "," + gapEnd + ",")) {
                throw new Exception("Native launch did not persist the complete cross-midnight gap.");
            }
            second = Launch(executable, directory, name);
            var secondWindow = WaitForWindow(desktop, second);
            Thread.Sleep(500);
            CheckWindowBounds(secondWindow);
            if (!Convert.ToBase64String(bytes).Equals(Convert.ToBase64String(File.ReadAllBytes(Path.Combine(directory, "events.csv"))))) {
                throw new Exception("The second instance changed the data file.");
            }
            if (!Convert.ToBase64String(ledgerBytes).Equals(Convert.ToBase64String(File.ReadAllBytes(Path.Combine(directory, "ledger.json"))))) {
                throw new Exception("The second instance changed ledger balances or records.");
            }
            PostMessageW(secondWindow, 0x0010, IntPtr.Zero, IntPtr.Zero);
            if (!second.WaitForExit(10000)) throw new Exception("Second instance did not close.");
            PostMessageW(firstWindow, 0x0010, IntPtr.Zero, IntPtr.Zero);
            if (!first.WaitForExit(10000)) throw new Exception("First instance did not close.");
            if (!CanLock(directory)) throw new Exception("Data-directory lock was not released.");
        } finally {
            foreach (var process in new[] {second, first}) {
                if (process != null) { if (!process.HasExited) { process.Kill(); process.WaitForExit(10000); } process.Dispose(); }
            }
            CloseDesktop(desktop);
        }
    }
}
'@
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
Write-Output "Native smoke passed: journal view icons in Release font, isolated desktop, startup window within work area, obsolete leading-gap cleanup, BOM/cross-midnight gaps, linked ledger preservation, single-instance rejection and lock release. Artifacts: $taskDirectory"
