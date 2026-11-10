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
$taskEvents = "id,title,tag_id,start,end,notes`r`ncoverage,合成整日覆盖,work,${taskPreviousDay}T00:00:00,${taskPreviousDay}T22:00:00,`r`nvideo,视频,work,${taskPreviousDay}T22:00:00,${taskPreviousDay}T23:50:00,`r`nsleep,睡觉,work,${taskDay}T00:06:00,${taskDay}T08:00:00,`r`nsynthetic,合成记录,work,${taskDay}T09:00:00,${taskDay}T10:00:00,隔离桌面测试`r`n"
[IO.File]::WriteAllText((Join-Path $taskDirectory 'events.csv'), $taskEvents + $taskLegacyHead, [Text.UTF8Encoding]::new($true))
$taskLedger = '{"version":2,"default_cash_account_id":"cash","balance_enabled":true,"accounts":[{"id":"cash","name":"现金","kind":"cash","opening_cents":1000000,"balance_cents":997200},{"id":"provident","name":"公积金","kind":"provident","opening_cents":0,"balance_cents":0},{"id":"investment","name":"投资","kind":"investment","opening_cents":0,"balance_cents":0}],"categories":[{"id":"lunch","name":"午餐","kind":"expense","parent_id":null}],"records":[{"id":"synthetic-money","kind":"expense","amount_cents":2800,"date":"' + $taskDay + '","category_id":"lunch","notes":"隔离测试","account_id":"cash","to_account_id":null,"affects_balance":true}],"pinned":["lunch"]}'
[IO.File]::WriteAllText((Join-Path $taskDirectory 'ledger.json'), $taskLedger, [Text.UTF8Encoding]::new($false))

# This source is synthetic and stays inside the smoke test's private data folder.
$taskObsidian = Join-Path $taskDirectory 'obsidian'
New-Item -ItemType Directory -Path $taskObsidian | Out-Null
$taskMarkdown = "---`ntags: [主业, 副业]`n---`n- [ ] 待办事项 | 描述`n- [/] 暂停事项`n- [-] 取消事项`n- [x] 完成事项 | | 结果`n"
[IO.File]::WriteAllText((Join-Path $taskObsidian '合成事项.md'), $taskMarkdown, [Text.UTF8Encoding]::new($false))
$taskSettings = @{version=1; obsidian_directory=$taskObsidian} | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $taskDirectory 'settings.json'), $taskSettings, [Text.UTF8Encoding]::new($false))

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
    static void CheckGlyphs(string fontPath, int[] codepoints) {
        var bytes = File.ReadAllBytes(fontPath);
        int cmap = -1;
        for (int table = 0; table < Read16(bytes, 4); table++) {
            int record = 12 + table * 16;
            if (Encoding.ASCII.GetString(bytes, record, 4) == "cmap") cmap = checked((int)Read32(bytes, record + 8));
        }
        foreach (int codepoint in codepoints) {
            if (cmap < 0 || !HasGlyph(bytes, cmap, codepoint)) {
                throw new Exception($"Release font {Path.GetFileName(fontPath)} is missing U+{codepoint:X4}.");
            }
        }
    }
    static void CheckFonts(string executable) {
        string assets = Path.Combine(Path.GetDirectoryName(executable), "data", "flutter_assets");
        // Incremental Windows builds can retain an older Material icon subset.
        CheckGlyphs(Path.Combine(assets, "fonts", "MaterialIcons-Regular.otf"), new[] {
            0xe556, 0xf48f, 0xf316, 0xf107, 0xef56, 0xefc4, 0xef4c,
            0xe25c, 0xf1be, 0xee33, 0xf266, 0xf37d, 0xf3ca, 0xf2ef,
            0xf336, 0xe364, 0xe44c, 0xf231, 0xe124,
            0xe168, // Material 3 heatmap chip removal (Icons.clear).
            0xf090, 0xe62f, 0xe45c, // Obsidian folder, synchronization and open-in-new.
            // Historical organizer: move, no label, date filter, undo/redo and selection.
            0xe20a, 0xf14c, 0xefa5, 0xe68c, 0xe512, 0xee6e,
            0xe156, 0xe15a, 0xe1bb, 0xef28, 0xe47f, 0xe504, 0xe6f7
        });
        CheckGlyphs(Path.Combine(assets, "assets", "fonts", "NotoSansSC.ttf"), new[] {
            0x0030, 0x0041, 0x0061, 0x00a5, 0x4e2d, 0x6587, 0x65f6, 0x95f4, 0x9910, 0x996e,
            0x677e, 0x77f3, 0x975b, 0x84dd, 0x6696, 0x6c99, 0x73ab, 0x7470
        });
        if (!File.Exists(Path.Combine(assets, "assets", "fonts", "OFL.txt"))) {
            throw new Exception("The bundled font license is missing.");
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
        // Allow cold Flutter/font initialization on an inactive desktop.
        for (int attempt = 0; attempt < 300; attempt++) {
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
        CheckFonts(executable);
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
$taskArchive = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'archive.json') | ConvertFrom-Json
if ($taskArchive.version -ne 1 -or $taskArchive.days.Count -ne 1 -or $taskArchive.days[0] -ne $taskPreviousDay -or -not ($taskArchive.events.id -contains 'coverage')) {
    throw 'Startup/normal close did not retain the completed-day archive backup.'
}
$taskTree = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskImported = @($taskTree.items | Where-Object { $_.source.kind -eq 'task' })
if ($taskTree.version -ne 1 -or $taskImported.Count -ne 4 -or @($taskImported.status | Select-Object -Unique).Count -ne 4 -or -not ($taskTree.events.id -contains 'synthetic')) {
    throw 'Startup synchronization or the complete tree backup lost imported states or saved records.'
}
$taskAnnotated = [IO.File]::ReadAllText((Join-Path $taskObsidian '合成事项.md'))
$taskIdPattern = '\^daymark-obsidian-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
$taskFileId = ($taskTree.items | Where-Object { $_.source.kind -eq 'file' }).id
$taskProperty = [regex]::Match($taskAnnotated, '(?m)^daymark-id: "(' + $taskIdPattern + ')"\s*$')
if ([regex]::Matches($taskAnnotated, $taskIdPattern).Count -ne 5 -or $taskProperty.Groups[1].Value -ne $taskFileId) {
    throw 'Note properties, task blocks and stored item IDs do not share the same complete identity.'
}
$taskRetainedId = ($taskImported | Where-Object { $_.status -eq 'active' }).id
# No editor plugin or date metadata: observe completion and reopening on startup.
$taskNotePath = Join-Path $taskObsidian '合成事项.md'
[IO.File]::WriteAllText($taskNotePath, $taskAnnotated.Replace('- [ ] 待办事项', '- [x] 待办事项'), [Text.UTF8Encoding]::new($false))
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskCompletedTree = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskCompleted = $taskCompletedTree.items | Where-Object { $_.id -eq $taskRetainedId }
if ($taskCompleted.status -ne 'done' -or $taskCompleted.completed_on -ne $taskDay) {
    throw 'Plugin-free completion did not persist the observed completion date.'
}
[IO.File]::WriteAllText($taskNotePath, $taskAnnotated, [Text.UTF8Encoding]::new($false))
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskReopenedTree = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskReopened = $taskReopenedTree.items | Where-Object { $_.id -eq $taskRetainedId }
if ($taskReopened.status -ne 'active' -or $taskReopened.completed_on) {
    throw 'Reopening a completed item did not clear the prior completion date.'
}
# A note and an inline occurrence can share one ID and contribute different children.
$taskSharedOriginal = [IO.File]::ReadAllText($taskNotePath)
$taskSharedContainer = Join-Path $taskObsidian '共享容器.md'
$taskSharedContainerId = '^daymark-obsidian-' + [Guid]::NewGuid().ToString('D')
$taskSharedChildId = '^daymark-obsidian-' + [Guid]::NewGuid().ToString('D')
$taskSharedNote = $taskSharedOriginal.Replace("daymark-id: `"$taskFileId`"", "daymark-id: `"$taskFileId`"`nparent: `"[[共享容器]]`"")
[IO.File]::WriteAllText($taskNotePath, $taskSharedNote, [Text.UTF8Encoding]::new($false))
$taskSharedInline = "---`ndaymark-id: `"$taskSharedContainerId`"`n---`n- [ ] 合成事项 #主业 #副业 $taskFileId`n  - [ ] 额外子事项 $taskSharedChildId`n"
[IO.File]::WriteAllText($taskSharedContainer, $taskSharedInline, [Text.UTF8Encoding]::new($false))
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskSharedTree = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskSharedParent = @($taskSharedTree.items | Where-Object { $_.id -eq $taskFileId })
$taskSharedChild = $taskSharedTree.items | Where-Object { $_.id -eq $taskSharedChildId }
if (@($taskSharedTree.items).Count -ne 7 -or $taskSharedParent.Count -ne 1 -or $taskSharedParent[0].parent_id -ne $taskSharedContainerId -or $taskSharedParent[0].source.kind -ne 'file' -or $taskSharedChild.parent_id -ne $taskFileId) {
    throw 'Compatible repeated identities did not merge their children under one logical node.'
}
if (@($taskSharedTree.items | Where-Object { $_.parent_id -eq $taskFileId }).Count -ne 5) {
    throw 'The shared node lost children from one of its source locations.'
}
[IO.File]::WriteAllText($taskNotePath, $taskSharedOriginal, [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $taskSharedContainer
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskAfterShared = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskSurvivingShared = $taskAfterShared.items | Where-Object { $_.id -eq $taskFileId }
if (@($taskAfterShared.items).Count -ne 5 -or $taskSurvivingShared.parent_id -or $taskSurvivingShared.source.missing) {
    throw 'Removing one shared location did not retain the surviving node correctly.'
}
# Merge a note into a task by copying its property value unchanged.
$taskCsvPath = Join-Path $taskDirectory 'events.csv'
$taskHeader = [IO.File]::ReadAllLines($taskCsvPath)[0]
if (-not $taskHeader.EndsWith(',item_id')) { throw 'The current CSV owner column is missing.' }
$taskCsvText = [IO.File]::ReadAllText($taskCsvPath).TrimEnd([char[]]"`r`n")
[IO.File]::WriteAllText($taskCsvPath, "$taskCsvText`r`nsource-ref,合成引用,work,${taskDay}T10:00:00,${taskDay}T11:00:00,保留关联,$taskRetainedId`r`nnote-ref,笔记引用,work,${taskDay}T11:00:00,${taskDay}T12:00:00,保留笔记身份,$taskFileId`r`n", [Text.UTF8Encoding]::new($true))
$taskContainerId = '^daymark-obsidian-' + [Guid]::NewGuid().ToString('D')
$taskTaskLines = [IO.File]::ReadAllLines((Join-Path $taskObsidian '合成事项.md')) | Where-Object { $_ -match '^- \[.\]' } | ForEach-Object { '    ' + $_ }
$taskMergedFile = Join-Path $taskObsidian '合并事项.md'
$taskMergedText = "---`ndaymark-id: `"$taskContainerId`"`n---`n- [ ] 合成事项 $taskFileId`n" + ($taskTaskLines -join "`n") + "`n"
[IO.File]::WriteAllText($taskMergedFile, $taskMergedText, [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath (Join-Path $taskObsidian '合成事项.md')
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskAfterMerge = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskMergedNote = $taskAfterMerge.items | Where-Object { $_.id -eq $taskFileId }
$taskMergedChild = $taskAfterMerge.items | Where-Object { $_.id -eq $taskRetainedId }
if (@($taskAfterMerge.items).Count -ne 6 -or $taskMergedNote.source.kind -ne 'task' -or $taskMergedNote.parent_id -ne $taskContainerId -or $taskMergedChild.parent_id -ne $taskFileId -or $taskMergedChild.source.missing) {
    throw 'Merging the note into a task changed its identity or lost its children.'
}
if (($taskAfterMerge.events | Where-Object { $_.id -eq 'note-ref' }).item_id -ne $taskFileId -or ($taskAfterMerge.events | Where-Object { $_.id -eq 'source-ref' }).item_id -ne $taskRetainedId) {
    throw 'Note-to-task conversion changed the saved record associations.'
}
# Deleting the source retains only the two directly referenced nodes.
Remove-Item -LiteralPath $taskMergedFile
[DaymarkPrivateDesktop]::Run($taskExecutable, $taskDirectory, "${taskPreviousDay}T23:50:00", "${taskDay}T00:06:00")
$taskAfterDeletion = Get-Content -Raw -LiteralPath (Join-Path $taskDirectory 'tree-backups/latest.json') | ConvertFrom-Json
$taskRemaining = @($taskAfterDeletion.items)
if ($taskRemaining.Count -ne 2 -or @($taskRemaining | Where-Object { $_.source.missing -and $_.status -eq 'active' }).Count -ne 2 -or -not ($taskRemaining.id -contains $taskRetainedId) -or -not ($taskRemaining.id -contains $taskFileId)) {
    throw 'Source deletion did not retain only the referenced nodes with their original states.'
}
if (($taskAfterDeletion.events | Where-Object { $_.id -eq 'note-ref' }).item_id -ne $taskFileId -or ($taskAfterDeletion.events | Where-Object { $_.id -eq 'source-ref' }).item_id -ne $taskRetainedId) {
    throw 'Source deletion changed the saved record associations.'
}
Write-Output "Native smoke passed: compatible repeated identities and child union, surviving shared source, plugin-free completion observation and reopening, unified note/task identities, note-to-task merge with unchanged record associations, four item states, source deletion and complete tree backup, Release fonts, isolated desktop, window bounds, BOM/cross-midnight gaps, archive backup, ledger preservation, single-instance rejection and lock release. Artifacts: $taskDirectory"
