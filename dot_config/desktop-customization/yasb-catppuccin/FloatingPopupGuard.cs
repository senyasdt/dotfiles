using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// Opt-in application rules, inside DesktopBridge. No keyboard/mouse hooks or WM patches.
internal sealed class FloatingPopupGuard : IDisposable {
    internal sealed class Rule {
        internal string Executable;
        internal Regex Class;
    }
    internal sealed class Settings {
        internal bool Enabled;
        internal double MaxWidth=.8,MaxHeight=.95;
        internal List<Rule> Rules=new List<Rule>();
        internal HashSet<string> SuspendWhileRunning=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        internal static Settings Parse(string text) {
            var d=Object(new JavaScriptSerializer().DeserializeObject(text));
            var s=new Settings();object v;
            if(!d.TryGetValue("enabled",out v)||!(v is bool))throw new IOException("enabled must be boolean");
            s.Enabled=(bool)v;
            if(d.TryGetValue("maximumWidthFraction",out v))s.MaxWidth=Convert.ToDouble(v);
            if(d.TryGetValue("maximumHeightFraction",out v))s.MaxHeight=Convert.ToDouble(v);
            if(s.MaxWidth<=0||s.MaxWidth>.9||s.MaxHeight<=0||s.MaxHeight>1)throw new IOException("Invalid popup size limits");
            foreach(var item in Array(d,"applications")) {
                var rule=Object(item);string exe=Text(rule,"executable");
                if(exe.Length==0||exe.IndexOfAny(new[]{'\\','/','*','?'})>=0||!exe.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new IOException("Use exact executable filenames");
                string cls=Text(rule,"windowClass");
                s.Rules.Add(new Rule{Executable=exe,Class=cls.Length==0?null:new Regex(cls,RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(50))});
            }
            if(s.Rules.Count==0||s.Rules.Count>32)throw new IOException("Configure 1 to 32 applications");
            if(d.TryGetValue("suspendWhileRunning",out v)&&!(v is object[]))throw new IOException("suspendWhileRunning must be an array");
            foreach(var raw in Array(d,"suspendWhileRunning")) {
                if(!(raw is string))throw new IOException("Excluded executables must be strings");
                string name=Convert.ToString(raw);
                if(name.Length==0||name.IndexOfAny(new[]{'\\','/','*','?'})>=0||!name.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new IOException("Use exact excluded executable filenames");
                s.SuspendWhileRunning.Add(name);
            }
            return s;
        }
    }
    internal sealed class Window {
        internal IntPtr Handle;
        internal uint Pid;
        internal long Birth;
        internal string Executable,Class;
        internal Rectangle Bounds,Screen;
        internal bool Visible,Minimized,Cloaked,Topmost;
    }
    internal static bool Matches(Settings s,Window w) {
        if(!w.Visible||w.Minimized||w.Cloaked||w.Bounds.Width<100||w.Bounds.Height<100||w.Screen.Width<=0||w.Screen.Height<=0)return false;
        if(w.Bounds.Width>w.Screen.Width*s.MaxWidth||w.Bounds.Height>w.Screen.Height*s.MaxHeight)return false;
        var intersection=Rectangle.Intersect(w.Bounds,w.Screen);
        if((long)intersection.Width*intersection.Height<(long)w.Bounds.Width*w.Bounds.Height*.95)return false;
        return s.Rules.Any(r=>String.Equals(r.Executable,w.Executable,StringComparison.OrdinalIgnoreCase)&&(r.Class==null||r.Class.IsMatch(w.Class)));
    }
    internal static bool Fullscreen(Rectangle window,Rectangle screen) {
        return screen.Width>0&&screen.Height>0&&window.Left<=screen.Left+2&&window.Top<=screen.Top+2&&window.Right>=screen.Right-2&&window.Bottom>=screen.Bottom-2;
    }
    internal static HashSet<string> Blockers(string text) {
        var d=Object(new JavaScriptSerializer().DeserializeObject(text));object groups;
        if(!d.TryGetValue("groups",out groups)||!(groups is Dictionary<string,object>))throw new IOException("Game rules unavailable");
        var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var raw in Object(groups).Values) {
            if(!(raw is Dictionary<string,object>))throw new IOException("Game rule group must be an object");
            var group=Object(raw);object entries;
            if(!group.TryGetValue("closeWhileRunning",out entries)||!(entries is object[]))throw new IOException("closeWhileRunning must be an array");
            foreach(var value in (object[])entries) {
                if(!(value is string)||String.IsNullOrWhiteSpace((string)value))throw new IOException("Game executables must be strings");
                string name=Path.GetFileName(Environment.ExpandEnvironmentVariables((string)value));
                if(name.Length==0)throw new IOException("Empty game executable");
                names.Add(name);
            }
        }
        if(names.Count==0)throw new IOException("No game exclusions configured; automatic pins remain off");
        return names;
    }
    internal sealed class ConfigurationCache {
        readonly Func<string> readSettings,readGames;
        internal Settings Settings;
        internal HashSet<string> Blocked;
        internal bool Valid;
        DateTime nextRead;
        string signature="",error="Configuration unavailable";
        internal ConfigurationCache(Func<string> settings,Func<string> games){readSettings=settings;readGames=games;}
        internal void Refresh(DateTime now) {
            if(now<nextRead){if(!Valid)throw new IOException(error);return;}
            nextRead=now.AddSeconds(1);Valid=false;
            try {
                string text=readSettings(),games=readGames(),next=text+"\n"+games;
                if(next!=signature||Settings==null) {
                    var parsed=FloatingPopupGuard.Settings.Parse(text);var blocked=Blockers(games);blocked.UnionWith(parsed.SuspendWhileRunning);
                    Settings=parsed;Blocked=blocked;signature=next;
                }
                Valid=true;error="";
            }catch(Exception e){error=e.Message;throw;}
        }
    }
    internal interface Host {
        bool Owned(Window window);
        bool Pin(Window window);
        bool Release(Window window);
    }
    internal sealed class Engine {
        readonly Host host;
        readonly Dictionary<IntPtr,Window> owned=new Dictionary<IntPtr,Window>();
        internal Engine(Host value){host=value;}
        internal int Count {get{return owned.Count;}}
        internal bool Contains(IntPtr handle){return owned.ContainsKey(handle);}
        internal void Adopt(Window window){owned[window.Handle]=window;}
        internal void Step(bool allowed,IEnumerable<Window> candidates) {
            var desired=allowed?candidates.ToDictionary(w=>w.Handle):new Dictionary<IntPtr,Window>();
            foreach(var pair in owned.ToArray()) {
                Window current;
                if(!desired.TryGetValue(pair.Key,out current)||current.Pid!=pair.Value.Pid||current.Birth!=pair.Value.Birth) {
                    if(host.Release(pair.Value))owned.Remove(pair.Key);
                }else if(!host.Owned(pair.Value))owned.Remove(pair.Key);
                else if(!current.Topmost)host.Pin(current);
            }
            if(!allowed)return;
            foreach(var window in desired.Values)if(!owned.ContainsKey(window.Handle)&&!window.Topmost&&host.Pin(window))owned[window.Handle]=window;
        }
        internal void ReleaseAll(){Step(false,new Window[0]);}
    }

    const string Marker="Druzh.DesktopBridge.FloatingPopup.v1";
    const uint PositionFlags=0x4213; // ASYNCWINDOWPOS, NOOWNERZORDER, NOACTIVATE, NOMOVE, NOSIZE
    readonly string configPath,gameConfig,statusPath;
    readonly Thread thread;
    readonly ManualResetEvent finished=new ManualResetEvent(false);
    readonly WinEvent callback;
    readonly IntPtr token=new IntPtr(Process.GetCurrentProcess().Id);
    volatile bool stopping;
    uint threadId;
    Engine engine;
    readonly ConfigurationCache configuration;
    Settings settings {get{return configuration.Settings;}}
    HashSet<string> blockers {get{return configuration.Blocked;}}
    Dictionary<uint,string> processes;
    DateTime nextProcesses,nextStatus;
    string mode="starting",lastStatus="";
    IntPtr foregroundHook,windowHook;
    bool busy;
    internal FloatingPopupGuard(string config,string games,string runtime) {
        configPath=config;gameConfig=games;statusPath=Path.Combine(runtime,"floating-popups-status.json");callback=OnEvent;
        configuration=new ConfigurationCache(()=>Read(configPath),()=>Read(gameConfig));
        thread=new Thread(Listen){IsBackground=true,Name="Floating popup guard"};
        thread.SetApartmentState(ApartmentState.STA);thread.Start();
    }
    static Dictionary<string,object> Object(object value){return value as Dictionary<string,object>??new Dictionary<string,object>();}
    static object[] Array(Dictionary<string,object> d,string key){object v;return d.TryGetValue(key,out v)?v as object[]??new object[0]:new object[0];}
    static string Text(Dictionary<string,object> d,string key){object v;return d.TryGetValue(key,out v)?Convert.ToString(v):"";}
    static string Read(string path){using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){if(stream.Length>65536)throw new IOException("Configuration is too large");using(var reader=new StreamReader(stream,Encoding.UTF8))return reader.ReadToEnd();}}
    internal static bool Enabled(string path){try{return Settings.Parse(Read(path)).Enabled;}catch{return false;}}
    internal static void Toggle(string path) {
        string text=Read(path);var d=Object(new JavaScriptSerializer().DeserializeObject(text));d["enabled"]=!Settings.Parse(text).Enabled;
        string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{File.WriteAllText(temporary,new JavaScriptSerializer().Serialize(d),new UTF8Encoding(false));File.Replace(temporary,path,null);}finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
    void LoadConfig() {
        var prior=settings;configuration.Refresh(DateTime.UtcNow);
        if(!System.Object.ReferenceEquals(prior,settings))nextProcesses=DateTime.MinValue;
    }
    void Evaluate() {
        if(busy||stopping)return;busy=true;
        try {
            LoadConfig();
            if(!settings.Enabled){Suspend("disabled");return;}
            if(foregroundHook==IntPtr.Zero||windowHook==IntPtr.Zero){Suspend("hook-error");return;}
            IntPtr foreground=GetForegroundWindow();Window active=Describe(foreground);
            if(active==null||!active.Visible||active.Cloaked){Suspend("suspended-desktop");return;}
            if(blockers.Contains(active.Executable)){Suspend("suspended-game");return;}
            if(Fullscreen(active.Bounds,active.Screen)){Suspend("suspended-fullscreen");return;}
            int notification;
            if(SHQueryUserNotificationState(out notification)!=0||notification==3||notification==4||notification==7){Suspend("suspended-fullscreen");return;}
            if(DateTime.UtcNow>=nextProcesses) {
                processes=ProcessNames();nextProcesses=DateTime.UtcNow.AddSeconds(1);
            }
            if(processes.Values.Any(name=>blockers.Contains(name))){Suspend("suspended-game");return;}
            var candidates=new List<Window>();
            EnumWindows(delegate(IntPtr handle,IntPtr unused) {
                if(!IsWindowVisible(handle)||IsIconic(handle))return true;
                uint pid;GetWindowThreadProcessId(handle,out pid);string name;
                if(!processes.TryGetValue(pid,out name)||!settings.Rules.Any(r=>String.Equals(r.Executable,name,StringComparison.OrdinalIgnoreCase)))return true;
                Window window=Describe(handle);if(window!=null&&Matches(settings,window))candidates.Add(window);
                return true;
            },IntPtr.Zero);
            engine.Step(true,candidates);WriteStatus("active","");
        }catch(Exception e){Suspend("configuration-error",e.Message);}
        finally{busy=false;}
    }
    void Suspend(string reason,string error=""){try{engine.ReleaseAll();}catch(Exception e){error=e.Message;}WriteStatus(reason,error);}
    void WriteStatus(string state,string error) {
        mode=state;string text=new JavaScriptSerializer().Serialize(new{mode=state,owned=engine.Count,error=error});
        if(text==lastStatus&&DateTime.UtcNow<nextStatus)return;
        lastStatus=text;nextStatus=DateTime.UtcNow.AddSeconds(15);
        try{File.WriteAllText(statusPath,text,new UTF8Encoding(false));}catch{}
    }
    void OnEvent(IntPtr hook,uint kind,IntPtr hwnd,int obj,int child,uint eventThread,uint time) {
        // Out-of-context accessibility events: never injected into another process.
        try {
            if(kind==3){Evaluate();return;}
            if(obj!=0||child!=0||settings==null)return;
            if(engine.Contains(hwnd)){Evaluate();return;}
            uint pid;GetWindowThreadProcessId(hwnd,out pid);string name;
            if(processes==null||!processes.TryGetValue(pid,out name)) {
                Window window=Describe(hwnd);if(window==null)return;name=window.Executable;
                if(processes!=null)processes[pid]=name;
            }
            // A tray refresh in an unrelated application needs no full scan.
            if(settings.Rules.Any(r=>String.Equals(r.Executable,name,StringComparison.OrdinalIgnoreCase)))Evaluate();
        }catch{WriteStatus("error","Window event could not be reconciled");}
    }
    bool SafeAtPin() {
        if(stopping||!configuration.Valid||settings==null||!settings.Enabled)return false;
        Window active=Describe(GetForegroundWindow());int notification;
        if(active==null||!active.Visible||active.Cloaked||blockers.Contains(active.Executable)||Fullscreen(active.Bounds,active.Screen)||SHQueryUserNotificationState(out notification)!=0||notification==3||notification==4||notification==7)return false;
        // Promotions are rare. Re-read running programs immediately before each
        // promotion rather than relying on the periodic discovery snapshot.
        return !ProcessNames().Values.Any(name=>blockers.Contains(name));
    }
    void Listen() {
        var host=new NativeHost(this);engine=new Engine(host);
        try {
            threadId=GetCurrentThreadId();
            using(var timer=new System.Windows.Forms.Timer{Interval=1000}) {
                // Create the pump before registering callbacks/accepting shutdown.
                using(var pump=new Control()){IntPtr handle=pump.Handle;
                    host.Recover();
                    foregroundHook=SetWinEventHook(3,3,IntPtr.Zero,callback,0,0,2);
                    windowHook=SetWinEventHook(0x8002,0x8003,IntPtr.Zero,callback,0,0,2);
                    timer.Tick+=delegate{Evaluate();};timer.Start();Evaluate();
                    if(!stopping)Application.Run();
                }
            }
        }catch(Exception e){WriteStatus("error",e.Message);}
        finally {
            if(foregroundHook!=IntPtr.Zero)UnhookWinEvent(foregroundHook);
            if(windowHook!=IntPtr.Zero)UnhookWinEvent(windowHook);
            try {
                var cleanup=Stopwatch.StartNew();
                do{engine.ReleaseAll();if(engine.Count==0)break;Thread.Sleep(40);}while(cleanup.ElapsedMilliseconds<1000);
                WriteStatus(engine.Count==0?"stopped":"cleanup-pending","");
            }finally{finished.Set();}
        }
    }
    public void Dispose(){stopping=true;if(threadId!=0)PostThreadMessage(threadId,0x12,UIntPtr.Zero,IntPtr.Zero);if(finished.WaitOne(3000)){thread.Join();finished.Dispose();}}

    sealed class NativeHost : Host {
        readonly FloatingPopupGuard owner;
        internal NativeHost(FloatingPopupGuard value){owner=value;}
        static bool Same(Window before,Window after){return after!=null&&before.Pid==after.Pid&&before.Birth==after.Birth;}
        public bool Owned(Window window){return GetProp(window.Handle,Marker)==owner.token&&Same(window,Describe(window.Handle));}
        public bool Pin(Window window) {
            Window current=Describe(window.Handle);
            if(!owner.SafeAtPin()||!Same(window,current)||!Matches(owner.settings,current))return false;
            IntPtr marker=GetProp(window.Handle,Marker);
            if(marker==owner.token)return current.Topmost||SetWindowPos(window.Handle,new IntPtr(-1),0,0,0,0,PositionFlags);
            if(current.Topmost||marker!=IntPtr.Zero||!SetProp(window.Handle,Marker,owner.token))return false;
            if(SetWindowPos(window.Handle,new IntPtr(-1),0,0,0,0,PositionFlags))return true;
            Release(window);return false;
        }
        public bool Release(Window window){return Restore(window,owner.token);}
        static bool Restore(Window window,IntPtr marker) {
            if(GetProp(window.Handle,Marker)!=marker||!Same(window,Describe(window.Handle)))return true;
            if(!SetWindowPos(window.Handle,new IntPtr(-2),0,0,0,0,PositionFlags))return false;
            // NOTOPMOST alone can leave a normal window above the game. Also put
            // it behind the actual foreground, without touching the game's window.
            IntPtr foreground=GetForegroundWindow();
            if(foreground!=IntPtr.Zero&&foreground!=window.Handle&&(GetWindowLong(foreground,-20)&8)==0)
                if(!SetWindowPos(window.Handle,foreground,0,0,0,0,PositionFlags))return false;
            // ASYNCWINDOWPOS can still be pending; retain our marker for retry/recovery.
            if((GetWindowLong(window.Handle,-20)&8)!=0)return false;
            RemoveProp(window.Handle,Marker);return GetProp(window.Handle,Marker)==IntPtr.Zero;
        }
        internal void Recover() {
            EnumWindows(delegate(IntPtr handle,IntPtr unused) {
                IntPtr marker=GetProp(handle,Marker);if(marker==IntPtr.Zero)return true;
                Window window=Describe(handle);if(window!=null&&SetProp(handle,Marker,owner.token))owner.engine.Adopt(window);
                return true;
            },IntPtr.Zero);
            owner.engine.ReleaseAll();
        }
    }
    static Window Describe(IntPtr handle) {
        if(handle==IntPtr.Zero||!IsWindow(handle))return null;
        uint pid;GetWindowThreadProcessId(handle,out pid);
        IntPtr process=OpenProcess(0x1000,false,pid);if(process==IntPtr.Zero)return null;
        try {
            var path=new StringBuilder(32768);uint length=(uint)path.Capacity;long birth,exit,kernel,user;
            if(!QueryFullProcessImageName(process,0,path,ref length)||!GetProcessTimes(process,out birth,out exit,out kernel,out user))return null;
            Rect rect;if(!GetWindowRect(handle,out rect))return null;
            var cls=new StringBuilder(256);GetClassName(handle,cls,cls.Capacity);
            int cloak;bool cloaked=DwmGetWindowAttribute(handle,14,out cloak,4)!=0||cloak!=0;
            return new Window{Handle=handle,Pid=pid,Birth=birth,Executable=Path.GetFileName(path.ToString()),Class=cls.ToString(),Bounds=rect.Value,Screen=System.Windows.Forms.Screen.FromHandle(handle).Bounds,Visible=IsWindowVisible(handle),Minimized=IsIconic(handle),Cloaked=cloaked,Topmost=(GetWindowLong(handle,-20)&8)!=0};
        }finally{CloseHandle(process);}
    }
    static Dictionary<uint,string> ProcessNames() {
        var result=new Dictionary<uint,string>();IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
        if(snapshot==new IntPtr(-1))throw new IOException("Process snapshot unavailable");
        try {
            var entry=new ProcessEntry();entry.Size=(uint)Marshal.SizeOf(typeof(ProcessEntry));
            if(!Process32First(snapshot,ref entry))throw new IOException("Process enumeration unavailable");
            do{result[entry.Pid]=entry.Executable;}while(Process32Next(snapshot,ref entry));
            if(Marshal.GetLastWin32Error()!=18)throw new IOException("Incomplete process snapshot");
        }finally{CloseHandle(snapshot);}
        return result;
    }
    [StructLayout(LayoutKind.Sequential)] struct Rect {internal int Left,Top,Right,Bottom;internal Rectangle Value{get{return Rectangle.FromLTRB(Left,Top,Right,Bottom);}}}
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct ProcessEntry {internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Executable;}
    delegate bool EnumProc(IntPtr hwnd,IntPtr data);
    delegate void WinEvent(IntPtr hook,uint kind,IntPtr hwnd,int obj,int child,uint thread,uint time);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder text,int count);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr hwnd,int index);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool SetProp(IntPtr hwnd,string name,IntPtr data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetProp(IntPtr hwnd,string name);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr RemoveProp(IntPtr hwnd,string name);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,WinEvent callback,uint pid,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread,uint message,UIntPtr wParam,IntPtr lParam);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder name,ref uint size);
    [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr process,out long birth,out long exit,out long kernel,out long user);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32First(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32Next(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd,int attr,out int value,int size);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);

    sealed class FakeHost : Host {
        internal HashSet<IntPtr> Markers=new HashSet<IntPtr>();
        internal int Pins,Releases;
        internal bool FailRelease;
        public bool Owned(Window w){return Markers.Contains(w.Handle);}
        public bool Pin(Window w){Markers.Add(w.Handle);Pins++;return true;}
        public bool Release(Window w){Releases++;if(FailRelease)return false;Markers.Remove(w.Handle);return true;}
    }
    internal static bool SelfTest() {
        var s=Settings.Parse("{\"enabled\":true,\"applications\":[{\"executable\":\"AmneziaVPN.exe\",\"windowClass\":\"^Qt[0-9]+QWindowIcon$\"}]}");
        var w=new Window{Handle=new IntPtr(123),Pid=10,Birth=20,Executable="AmneziaVPN.exe",Class="Qt6102QWindowIcon",Bounds=new Rectangle(100,100,424,733),Screen=new Rectangle(0,0,2560,1440),Visible=true};
        if(!Matches(s,w))return false;
        w.Minimized=true;if(Matches(s,w))return false;w.Minimized=false;
        w.Cloaked=true;if(Matches(s,w))return false;w.Cloaked=false;
        w.Visible=false;if(Matches(s,w))return false;w.Visible=true;
        w.Bounds=new Rectangle(-1000,100,424,733);if(Matches(s,w))return false;
        w.Bounds=new Rectangle(0,0,2560,1440);if(Matches(s,w))return false;
        w.Bounds=new Rectangle(100,100,424,733);w.Class="Qt6102QWindowPopup";if(Matches(s,w))return false;w.Class="Qt6102QWindowIcon";
        w.Executable="other.exe";if(Matches(s,w))return false;w.Executable="AMNEZIAVPN.EXE";
        if(!Matches(s,w)||!Fullscreen(w.Screen,w.Screen)||Fullscreen(new Rectangle(0,50,2560,1390),w.Screen))return false;
        var games=Blockers("{\"groups\":{\"desktop\":{\"closeWhileRunning\":[\"r5apex_dx12.exe\",\"C:\\\\Games\\\\bf6.exe\"]}}}");
        if(!games.Contains("R5APEX_DX12.EXE")||!games.Contains("bf6.exe")||games.Contains("chrome.exe"))return false;
        var host=new FakeHost();var engine=new Engine(host);
        engine.Step(true,new[]{w});w.Topmost=true;engine.Step(true,new[]{w});if(engine.Count!=1||host.Pins!=1)return false;
        engine.Step(false,new[]{w});if(engine.Count!=0||host.Markers.Count!=0)return false;
        w.Topmost=true;engine.Step(true,new[]{w});if(engine.Count!=0||host.Pins!=1)return false;w.Topmost=false;
        engine.Step(true,new[]{w});host.FailRelease=true;engine.ReleaseAll();if(engine.Count!=1)return false;
        host.FailRelease=false;engine.ReleaseAll();if(engine.Count!=0)return false;
        engine.Step(true,new[]{w});host.Markers.Clear();engine.Step(false,new Window[0]);if(engine.Count!=0)return false;
        bool rejected=false;try{Settings.Parse("{\"enabled\":true,\"applications\":[{\"executable\":\"*.exe\"}]}");}catch{rejected=true;}
        if(!rejected)return false;
        foreach(string bad in new[]{"{\"groups\":{}}","{\"groups\":{\"desktop\":{\"closeWhileRunning\":\"r5apex.exe\"}}}","{\"groups\":{\"desktop\":false}}","{\"groups\":{\"desktop\":{\"closeWhileRunning\":[false]}}}"}) {
            rejected=false;try{Blockers(bad);}catch{rejected=true;}if(!rejected)return false;
        }
        string good="{\"enabled\":true,\"applications\":[{\"executable\":\"AmneziaVPN.exe\"}]}";
        string mutable=good;string gameRules="{\"groups\":{\"desktop\":{\"closeWhileRunning\":[\"r5apex.exe\"]}}}";
        var cache=new ConfigurationCache(()=>mutable,()=>gameRules);var time=new DateTime(2026,10,29,0,0,0,DateTimeKind.Utc);
        cache.Refresh(time);if(!cache.Valid)return false;
        mutable="{invalid";rejected=false;try{cache.Refresh(time.AddSeconds(1));}catch{rejected=true;}if(!rejected||cache.Valid)return false;
        mutable=good;rejected=false;try{cache.Refresh(time.AddMilliseconds(1100));}catch{rejected=true;}if(!rejected||cache.Valid)return false;
        cache.Refresh(time.AddSeconds(2));if(!cache.Valid)return false;
        rejected=false;try{Settings.Parse(good.Replace("\"enabled\":true","\"enabled\":true,\"suspendWhileRunning\":\"bf6.exe\""));}catch{rejected=true;}
        return rejected;
    }
}
