using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

// Per-user layout cleanup. No hooks, game access, key capture or layout installation.
internal static class LayoutGuard
{
    private const string MutexName = @"Local\TechnicalAltGrLayoutGuard.v1";
    private const string StopName = @"Local\TechnicalAltGrLayoutGuard.Stop.v1";
    private static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    private static string previousState = "";

    [DllImport("user32.dll")]
    private static extern int GetKeyboardLayoutList(int count, [Out] IntPtr[] layouts);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnloadKeyboardLayout(IntPtr layout);

    private static uint Id(IntPtr value)
    {
        return unchecked((uint)value.ToInt64());
    }

    private static IntPtr[] Loaded()
    {
        int count = GetKeyboardLayoutList(0, null);
        IntPtr[] items = new IntPtr[count];
        int actual = GetKeyboardLayoutList(items.Length, items);
        if (actual != items.Length) Array.Resize(ref items, actual);
        return items;
    }

    private static bool Registered(string klid, string dll, string layoutId)
    {
        using (RegistryKey key = Registry.LocalMachine.OpenSubKey(
            @"SYSTEM\CurrentControlSet\Control\Keyboard Layouts\" + klid))
        {
            return key != null &&
                String.Equals(key.GetValue("Layout File") as string, dll, StringComparison.OrdinalIgnoreCase) &&
                String.Equals(key.GetValue("Layout Id") as string, layoutId, StringComparison.OrdinalIgnoreCase);
        }
    }

    private static bool GameRunning()
    {
        foreach (string name in new string[] { "r5apex", "r5apex_dx12" })
        {
            Process[] processes = Process.GetProcessesByName(name);
            bool found = processes.Length != 0;
            foreach (Process process in processes) process.Dispose();
            if (found) return true;
        }
        return false;
    }

    private static void Report(string state, IntPtr[] layouts, string detail)
    {
        List<string> ids = new List<string>();
        foreach (IntPtr layout in layouts) ids.Add(Id(layout).ToString("X8"));
        string signature = state + "|" + String.Join(",", ids.ToArray()) + "|" + detail;
        if (signature == previousState) return;
        string message = DateTimeOffset.Now.ToString("o") + " state=" + state +
            " pid=" + Process.GetCurrentProcess().Id + " layouts=" + String.Join(",", ids.ToArray()) +
            " " + detail + Environment.NewLine;
        try
        {
            File.WriteAllText(Path.Combine(Root, "status.txt"), message);
            string log = Path.Combine(Root, "events.log");
            if (File.Exists(log) && new FileInfo(log).Length > 65536)
                File.WriteAllText(log, "");
            File.AppendAllText(log, message);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        previousState = signature;
    }

    private static int Clean()
    {
        IntPtr[] layouts = Loaded();
        HashSet<uint> ids = new HashSet<uint>();
        foreach (IntPtr layout in layouts) ids.Add(Id(layout));
        // Fail closed if either approved custom layout is absent or its registration changed.
        if (!ids.Contains(0xF0010409u) || !ids.Contains(0xF0020419u) ||
            !Registered("a0010409", "ENTECH.dll", "a001") ||
            !Registered("a0020419", "RUTECH.dll", "a002"))
        {
            Report("missing-custom", layouts, "No changes; both approved custom layouts are required.");
            return 2;
        }
        if (!ids.Contains(0x04090409u) && !ids.Contains(0x04190419u))
        {
            Report("healthy", layouts, "Approved custom layouts present; no standard duplicates.");
            return 0;
        }
        if (GameRunning())
        {
            Report("deferred-game", layouts, "Apex is running; cleanup will resume after exit.");
            return 3;
        }
        List<string> results = new List<string>();
        foreach (IntPtr layout in layouts)
        {
            uint id = Id(layout);
            if (id != 0x04090409u && id != 0x04190419u) continue;
            bool success = UnloadKeyboardLayout(layout);
            int error = success ? 0 : Marshal.GetLastWin32Error();
            results.Add(id.ToString("X8") + (success ? " removed" : " retry error=" + error));
        }
        IntPtr[] remaining = Loaded();
        bool duplicate = false;
        foreach (IntPtr layout in remaining)
            if (Id(layout) == 0x04090409u || Id(layout) == 0x04190419u) duplicate = true;
        Report(duplicate ? "cleanup-retry" : "cleaned", remaining, String.Join("; ", results.ToArray()));
        return duplicate ? 4 : 0;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--stop")
        {
            try { using (EventWaitHandle stop = EventWaitHandle.OpenExisting(StopName)) stop.Set(); }
            catch (WaitHandleCannotBeOpenedException) { }
            return 0;
        }
        if (args.Length == 1 && args[0] == "--once") return Clean();
        bool created;
        using (Mutex mutex = new Mutex(true, MutexName, out created))
        {
            if (!created) return 0;
            using (EventWaitHandle stop = new EventWaitHandle(false, EventResetMode.ManualReset, StopName))
            {
                do
                {
                    try { Clean(); }
                    catch (Exception error) { Report("error", new IntPtr[0], error.GetType().Name + ": " + error.Message); }
                } while (!stop.WaitOne(2000));
            }
            mutex.ReleaseMutex();
        }
        return 0;
    }
}
