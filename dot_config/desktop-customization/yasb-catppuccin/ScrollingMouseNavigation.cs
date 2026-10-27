using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// Experimental Alt+wheel navigation. Runs inside the existing bridge process.
internal sealed class ScrollingMouseNavigation : IDisposable {
    internal sealed class Context {
        internal int Monitor, Workspace;
        internal long[] Windows;
        internal bool Contains(IntPtr hwnd) { return Windows != null && Array.IndexOf(Windows, hwnd.ToInt64()) >= 0; }
    }
    [StructLayout(LayoutKind.Sequential)] struct Point { internal int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MouseData { internal Point Point; internal uint Data, Flags, Time; internal UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { internal int Left, Top, Right, Bottom; }
    delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int kind, HookProc callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    readonly string cli, guardPath, statusPath;
    readonly Func<Context> current;
    readonly Func<int,bool> guardOwner;
    readonly Thread thread;
    readonly HookProc callback;
    volatile bool stopping, guardAllowed;
    IntPtr hook;
    int busy, accumulator;
    long lastStep;
    int accepted;
    string lastStatus = "";
    internal ScrollingMouseNavigation(string executable, Func<Context> context, string guard, string runtime, Func<int,bool> owner=null) {
        cli=executable; current=context; guardPath=guard; statusPath=Path.Combine(runtime,"scroll-input.json"); callback=OnMouse;
        guardOwner=owner??VerifyGuardOwner;
        thread=new Thread(Listen) { IsBackground=true, Name="Scrolling mouse input" };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
    }
    static bool Down(int key) { return (GetAsyncKeyState(key)&0x8000)!=0; }
    internal static bool ShouldCapture(bool alt, bool otherModifier, bool injected, int delta, bool scrolling, bool guard, bool fullscreen, bool managed) {
        return alt && !otherModifier && !injected && delta!=0 && scrolling && guard && !fullscreen && managed;
    }
    static bool Fullscreen(IntPtr hwnd) {
        Rect r; if(!GetWindowRect(hwnd,out r))return true;
        var b=Screen.FromHandle(hwnd).Bounds;
        return r.Left<=b.Left+2 && r.Top<=b.Top+2 && r.Right>=b.Right-2 && r.Bottom>=b.Bottom-2;
    }
    bool ReadGuard() {
        try {
            var file=new FileInfo(guardPath);
            // ScriptLauncher writes a heartbeat every 15 seconds, even when nothing changes.
            if(!file.Exists || file.Length>65536 || DateTime.UtcNow-file.LastWriteTimeUtc>TimeSpan.FromSeconds(45))return false;
            Dictionary<string,object> state;
            using(var stream=new FileStream(guardPath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
            using(var reader=new StreamReader(stream))state=new JavaScriptSerializer().DeserializeObject(reader.ReadToEnd()) as Dictionary<string,object>;
            object blocks, error, pid;
            if(state==null || !state.TryGetValue("helperPid",out pid) || !guardOwner(Convert.ToInt32(pid)) || !state.TryGetValue("blockedBy",out blocks) || !(blocks is object[]))return false;
            return ((object[])blocks).Length==0 && (!state.TryGetValue("error",out error) || String.IsNullOrEmpty(Convert.ToString(error)));
        } catch { return false; }
    }
    bool VerifyGuardOwner(int pid) {
        try {
            string expected=Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(guardPath)),"ScriptLauncher.exe");
            using(var process=Process.GetProcessById(pid))return !process.HasExited && process.SessionId==Process.GetCurrentProcess().SessionId && String.Equals(process.MainModule.FileName,expected,StringComparison.OrdinalIgnoreCase);
        } catch { return false; }
    }
    void WriteStatus(string mode, string direction) {
        try {
            string value=new JavaScriptSerializer().Serialize(new { mode=mode, gesture="Alt+wheel", direction=direction, accepted=accepted });
            if(value==lastStatus)return;
            File.WriteAllText(statusPath,value); lastStatus=value;
        } catch { }
    }
    void CheckHook() {
        guardAllowed=ReadGuard();
        bool enabled=!stopping && guardAllowed && current()!=null && File.Exists(cli);
        if(enabled && hook==IntPtr.Zero) {
            hook=SetWindowsHookEx(14,callback,GetModuleHandle(null),0);
            accumulator=0; WriteStatus(hook==IntPtr.Zero?"hook-unavailable":"ready","");
        } else if(!enabled && hook!=IntPtr.Zero) {
            UnhookWindowsHookEx(hook); hook=IntPtr.Zero; accumulator=0; WriteStatus("inactive","");
        } else if(!enabled)WriteStatus("inactive","");
    }
    void Listen() {
        using(var timer=new System.Windows.Forms.Timer { Interval=500 }) {
            timer.Tick+=delegate { if(stopping)Application.ExitThread(); else CheckHook(); };
            try { CheckHook(); timer.Start(); Application.Run(); }
            finally { timer.Stop(); if(hook!=IntPtr.Zero)UnhookWindowsHookEx(hook); hook=IntPtr.Zero; WriteStatus("stopped",""); }
        }
    }
    IntPtr OnMouse(int code, IntPtr message, IntPtr data) {
        int kind=message.ToInt32();
        if(code<0 || stopping || (kind!=0x20A && kind!=0x20E) || !Down(0x12))return CallNextHookEx(hook,code,message,data);
        try {
            var input=(MouseData)Marshal.PtrToStructure(data,typeof(MouseData));
            int delta=(short)(input.Data>>16); var context=current(); var foreground=GetForegroundWindow();
            bool modifiers=Down(0x10)||Down(0x11)||Down(0x5B)||Down(0x5C);
            if(!ShouldCapture(true,modifiers,(input.Flags&3)!=0,delta,context!=null,guardAllowed,Fullscreen(foreground),context!=null&&context.Contains(foreground)))
                return CallNextHookEx(hook,code,message,data);
            // Consume matched high-resolution wheel events, dispatch at most one step per 120 ms.
            int signed=kind==0x20E?-delta:delta;
            if(Math.Sign(signed)!=Math.Sign(accumulator))accumulator=0;
            accumulator+=signed;
            if(Math.Abs(accumulator)>=120 && Stopwatch.GetTimestamp()-lastStep>=Stopwatch.Frequency*120/1000 && Interlocked.CompareExchange(ref busy,1,0)==0) {
                string direction=accumulator>0?"left":"right"; accumulator=0; lastStep=Stopwatch.GetTimestamp();
                ThreadPool.QueueUserWorkItem(delegate { Navigate(context,foreground,direction); });
            }
            return new IntPtr(1);
        } catch { return CallNextHookEx(hook,code,message,data); }
    }
    void Navigate(Context requested, IntPtr foreground, string direction) {
        try {
            var now=current();
            if(stopping || !guardAllowed || now==null || now.Monitor!=requested.Monitor || now.Workspace!=requested.Workspace || GetForegroundWindow()!=foreground || !now.Contains(foreground) || Fullscreen(foreground))return;
            using(var process=new Process()) {
                process.StartInfo=new ProcessStartInfo(cli,"focus "+direction) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true, RedirectStandardError=true };
                process.Start(); var output=process.StandardOutput.ReadToEndAsync(); var error=process.StandardError.ReadToEndAsync();
                if(!process.WaitForExit(2000)) { try { process.Kill(); } catch { } WriteStatus("command-timeout",direction); return; }
                if(process.ExitCode==0) { Interlocked.Increment(ref accepted); WriteStatus("navigated",direction); }
                else WriteStatus("command-unavailable",direction);
            }
        } catch { WriteStatus("command-unavailable",direction); }
        finally { Interlocked.Exchange(ref busy,0); }
    }
    internal static bool SelfTest() {
        if(!ShouldCapture(true,false,false,120,true,true,false,true))return false;
        if(!ShouldCapture(true,false,false,-120,true,true,false,true))return false;
        for(int i=0;i<8;i++) {
            bool[] v={true,false,false,true,true,false,true};
            if(i==0)v[0]=false; if(i==1)v[1]=true; if(i==2)v[2]=true;
            if(i==3)v[3]=false; if(i==4)v[4]=false; if(i==5)v[5]=true; if(i==6)v[6]=false;
            if(ShouldCapture(v[0],v[1],v[2],i==7?0:120,v[3],v[4],v[5],v[6]))return false;
        }
        return true;
    }
    internal static bool TestHook() {
        // The empty HWND list makes all real input pass through during this probe.
        string root=Path.Combine(Path.GetTempPath(),"scroll-input-probe-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string guard=Path.Combine(root,"guard.json"), executable=Path.Combine(root,"unused-client");
        try {
            int own=Process.GetCurrentProcess().Id;
            string allowed="{\"helperPid\":"+own+",\"blockedBy\":[],\"error\":null}";
            File.WriteAllText(guard,allowed); File.WriteAllText(executable,"");
            Context context=new Context { Monitor=0, Workspace=0, Windows=new long[0] };
            using(var navigation=new ScrollingMouseNavigation(executable,()=>context,guard,root,pid=>pid==own)) {
                var wait=Stopwatch.StartNew(); while(navigation.hook==IntPtr.Zero&&wait.ElapsedMilliseconds<2500)Thread.Sleep(20);
                if(navigation.hook==IntPtr.Zero)return false;
                File.WriteAllText(guard,"{\"helperPid\":"+own+",\"blockedBy\":[\"test-game.exe\"],\"error\":null}");
                wait.Restart(); while(navigation.hook!=IntPtr.Zero&&wait.ElapsedMilliseconds<2500)Thread.Sleep(20);
                if(navigation.hook!=IntPtr.Zero||navigation.accepted!=0)return false;
                context=null; File.WriteAllText(guard,allowed); Thread.Sleep(650);
                return navigation.hook==IntPtr.Zero&&navigation.accepted==0;
            }
        } finally {
            foreach(string name in new[]{"guard.json","unused-client","scroll-input.json"})try{File.Delete(Path.Combine(root,name));}catch{}
            try{Directory.Delete(root);}catch{}
        }
    }
    public void Dispose() { stopping=true; if(thread.IsAlive)thread.Join(2000); }
}
