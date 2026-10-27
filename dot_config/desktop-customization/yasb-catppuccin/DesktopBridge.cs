using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class DesktopBridge {
    static readonly string Root=AppDomain.CurrentDomain.BaseDirectory;
    static readonly string Home=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    static readonly string Data=Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    static readonly string EventName=@"Local\Druzh.CatppuccinDesktop.Stop";
    static readonly string Runtime=Path.Combine(Root,"runtime");
    static KomorebiFeed komorebi;
    static DateTime nextTaskbarCheck=DateTime.MinValue,nextProcessCheck=DateTime.MinValue;
    static HashSet<uint> yasbIds=new HashSet<uint>();
    static DateTime lastYasbSeen=DateTime.MinValue;
    static readonly int Session=Process.GetCurrentProcess().SessionId;
    static string LauncherRoot { get { var settings=Read(Path.Combine(Root,"settings.json")); string configured=Get(settings,"scriptLauncherRoot",""); if(configured.Length>0)configured=Environment.ExpandEnvironmentVariables(configured);if(File.Exists(Path.Combine(configured,"ScriptLauncher.exe")))return configured;return Path.Combine(Home,@".config\desktop-customization\script-launcher"); } }
    [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;public Rectangle Value {get {return Rectangle.FromLTRB(Left,Top,Right,Bottom);}}}
    [StructLayout(LayoutKind.Sequential)] struct Point {public int X,Y;}
    delegate bool EnumProc(IntPtr hwnd,IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd,StringBuilder text,int count);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder text,int count);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr hwnd,int index);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd,int command);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd,int attr,out int value,int size);
    static Dictionary<string,object> Read(string path) {try {using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var reader=new StreamReader(stream,Encoding.UTF8))return Json.DeserializeObject(reader.ReadToEnd()) as Dictionary<string,object>??new Dictionary<string,object>();}catch{return new Dictionary<string,object>();}}
    static string Get(Dictionary<string,object> d,string k,string fallback) {object v;return d.TryGetValue(k,out v)&&v!=null?Convert.ToString(v):fallback;}
    static object[] Items(Dictionary<string,object> d,string k){object v;return d.TryGetValue(k,out v)?v as object[]??new object[0]:new object[0];}
    static void Output(object value){byte[] bytes=Encoding.UTF8.GetBytes(Json.Serialize(value));using(var output=Console.OpenStandardOutput()){output.Write(bytes,0,bytes.Length);output.Flush();}}
    static string Quote(string value){return "\""+value.Replace("\"","")+"\"";}
    static void Run(string file,string args){Process.Start(new ProcessStartInfo(file,args){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden});}
    static void Command(string operation,string path=null){Run(Path.Combine(LauncherRoot,"ScriptLauncher.exe"),operation+(path==null?"":" "+Quote(path)));}
    static readonly string[][] Services={
        new[]{"","Запустить помощники","StartAll"},new[]{"","Остановить помощники","StopAll"},new[]{"","Перезапустить помощники","RestartAll"},
        new[]{"","Восстановить отрисовку ChatGPT","ChatGPTRender"},
        new[]{"ChatGPT","Запустить без GPU (тест)","ChatGPTSoftwareStart"},new[]{"ChatGPT","Запустить обычно","ChatGPTNormalStart"},
        new[]{"Komorebi и горячие клавиши","Запустить","KomorebiStart"},new[]{"Komorebi и горячие клавиши","Остановить","KomorebiStop"},new[]{"Komorebi и горячие клавиши","Перезапустить","KomorebiRestart"},
        new[]{"AHK","Включить все скрипты","AhkEnable"},new[]{"AHK","Выключить все скрипты","AhkDisable"},new[]{"AHK","Перезапустить разрешённые","AhkRestart"},new[]{"AHK","Возобновить после общей паузы","AhkResume"},
        new[]{"Vial helper","Запустить","VialStart"},new[]{"Vial helper","Остановить","VialStop"},new[]{"Vial helper","Перезапустить","VialRestart"},
        new[]{"ZMK helper","Запустить","ZmkStart"},new[]{"ZMK helper","Остановить","ZmkStop"},new[]{"ZMK helper","Перезапустить","ZmkRestart"},
        new[]{"","Открыть Vial безопасно…","OpenVial"}
    };
    static void Service(string action){if(!Services.Any(s=>s[2]==action))throw new ArgumentException("Unknown helper action");Run("powershell.exe","-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "+Quote(Path.Combine(Root,"Services.ps1"))+" -Action "+action+" -Notify");}
    static void Open(string target){Process.Start(new ProcessStartInfo(target){UseShellExecute=true});}
    static Dictionary<string,object> State(string kind){
        if(kind=="ahk"){
            var s=Read(Path.Combine(LauncherRoot,@"runtime\status.json"));var mode=Get(s,"mode","offline");var scripts=Items(s,"scripts").Select(v=>v as Dictionary<string,object>).Where(v=>v!=null).ToArray();
            string detail=String.Join("\n",scripts.Select(v=>Get(v,"name","")+": "+Get(v,"mode","?")));
            return new Dictionary<string,object>{{"label",mode=="blocked"?"AHK · игра":mode=="paused"?"AHK · стоп":mode=="waiting"?"AHK · пауза":"AHK "+Get(s,"managedRunning","—")},{"tooltip",detail+"\nЛКМ: управление скриптами; ПКМ: выключить все"}};
        }
        string folder=kind=="vial"?"vial-helper":"zmk-yasb";var state=Read(Path.Combine(Data,folder+@"\state.json"));
        string prefix=kind=="vial"?"VIAL":"ZMK";string label=Get(state,"label","OFF");
        return new Dictionary<string,object>{{"label",prefix+" · "+label},{"tooltip",Get(state,"tooltip",Get(state,"effective","Нет подключения"))+(kind=="zmk"?"\nБатареи: "+Get(state,"battery_halves","—"):"\nЛКМ: раскладка и подписи AHK")}};
    }
    static ToolStripMenuItem Item(string text,Action action){var item=new ToolStripMenuItem(text);item.Click+=delegate{try{action();}catch(Exception e){MessageBox.Show(e.Message,"Catppuccin");}};return item;}
    static bool InsideMenu(ToolStripDropDown menu,System.Drawing.Point cursor){
        if(menu.Visible&&menu.Bounds.Contains(cursor))return true;
        foreach(ToolStripItem item in menu.Items){var child=item as ToolStripMenuItem;if(child!=null&&child.HasDropDownItems&&child.DropDown.Visible&&InsideMenu(child.DropDown,cursor))return true;}
        return false;
    }
    sealed class ColdMenuColors : ProfessionalColorTable {
        public ColdMenuColors(){UseSystemColors=false;}
        public override Color ToolStripDropDownBackground {get{return Color.FromArgb(32,34,39);}}
        public override Color MenuBorder {get{return Color.FromArgb(75,81,92);}}
        public override Color MenuItemBorder {get{return Color.FromArgb(139,150,166);}}
        public override Color MenuItemSelected {get{return Color.FromArgb(52,56,64);}}
        public override Color MenuItemSelectedGradientBegin {get{return MenuItemSelected;}}
        public override Color MenuItemSelectedGradientEnd {get{return MenuItemSelected;}}
        public override Color MenuItemPressedGradientBegin {get{return MenuItemSelected;}}
        public override Color MenuItemPressedGradientMiddle {get{return MenuItemSelected;}}
        public override Color MenuItemPressedGradientEnd {get{return MenuItemSelected;}}
        public override Color SeparatorDark {get{return Color.FromArgb(75,81,92);}}
        public override Color SeparatorLight {get{return ToolStripDropDownBackground;}}
    }
    static void Menu(string kind){
        Application.EnableVisualStyles();var menu=new ContextMenuStrip{BackColor=Color.FromArgb(32,34,39),ForeColor=Color.FromArgb(214,217,223),ShowImageMargin=false,Opacity=0.94,Font=new Font("Segoe UI",10)};
        menu.Renderer=new ToolStripProfessionalRenderer(new ColdMenuColors());
        if(kind=="ahk"){
            var state=Read(Path.Combine(LauncherRoot,@"runtime\status.json"));
            foreach(var v in Items(state,"scripts")){var s=v as Dictionary<string,object>;if(s==null)continue;string path=Get(s,"path","");var item=Item(Get(s,"name","")+" · "+Get(s,"mode","?"),()=>Command("--toggle",path));item.Checked=Get(s,"enabled","False")=="True";menu.Items.Add(item);}
            menu.Items.Add(new ToolStripSeparator());menu.Items.Add(Item("Включить все",()=>Service("AhkEnable")));menu.Items.Add(Item("Выключить все",()=>Service("AhkDisable")));menu.Items.Add(Item("Перезапустить разрешённые",()=>Service("AhkRestart")));menu.Items.Add(Item("Возобновить после общей паузы",()=>Service("AhkResume")));menu.Items.Add(Item("Настроить правила…",()=>Open(Path.Combine(LauncherRoot,"config.json"))));
        }else if(kind=="services"){
            var groups=new Dictionary<string,ToolStripMenuItem>();
            foreach(var row in Services){string action=row[2];var item=Item(row[1],()=>Service(action));if(action=="ChatGPTRender")item.ToolTipText="Пересоздаёт графический слой; окно и чат остаются открыты.";if(row[0].Length==0){menu.Items.Add(item);continue;}ToolStripMenuItem group;if(!groups.TryGetValue(row[0],out group)){group=new ToolStripMenuItem(row[0]);groups.Add(row[0],group);menu.Items.Add(group);}group.DropDownItems.Add(item);}
            menu.Items.Add(new ToolStripSeparator());menu.Items.Add(Item("Скрипты AHK и правила…",()=>Run(Path.Combine(Root,"DesktopBridge.exe"),"--menu ahk")));
        }else{
            menu.Items.Add(Item("Библиотека Windows",()=>Run("explorer.exe","shell:AppsFolder")));
            menu.Items.Add(Item("Настройки Windows",()=>Open("ms-settings:")));
            menu.Items.Add(Item("Вернуть состояние перед экспериментом",()=>Run("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File "+Quote(Path.Combine(Root,"Manage.ps1"))+" -Action RestoreCurrent")));
            menu.Items.Add(Item("Вернуться к YASB до MyDockFinder",()=>Run("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File "+Quote(Path.Combine(Root,"Manage.ps1"))+" -Action RestorePreDock")));
        }
        // YASB's bar does not activate itself. Its child popup can therefore lack
        // WinForms' usual owner activation; AutoClose alone misses outside clicks.
        // This timer exists only for the lifetime of this popup, without a hook.
        menu.AutoClose=true;
        var before=GetForegroundWindow();uint own=(uint)Process.GetCurrentProcess().Id;
        bool priorLeft=(GetAsyncKeyState(1)&0x8000)!=0,priorRight=(GetAsyncKeyState(2)&0x8000)!=0;
        GetAsyncKeyState(27); // clear an Escape press from before this popup
        using(var dismiss=new System.Windows.Forms.Timer{Interval=30}){
            dismiss.Tick+=delegate{
                int leftState=GetAsyncKeyState(1),rightState=GetAsyncKeyState(2);
                bool left=(leftState&0x8000)!=0,right=(rightState&0x8000)!=0;
                // Also latch a complete quick click between timer ticks.
                bool outside=((leftState&1)!=0||(rightState&1)!=0||(left&&!priorLeft)||(right&&!priorRight))&&!InsideMenu(menu,Cursor.Position);
                priorLeft=left;priorRight=right;
                IntPtr foreground=GetForegroundWindow();uint pid;GetWindowThreadProcessId(foreground,out pid);
                bool changed=foreground!=IntPtr.Zero&&foreground!=before&&pid!=own;
                if((GetAsyncKeyState(27)&0x8001)!=0||outside||changed)menu.Close(ToolStripDropDownCloseReason.AppClicked);
            };
            menu.Closed+=delegate{dismiss.Stop();Application.ExitThread();};
            menu.Show(Cursor.Position);menu.Focus();dismiss.Start();Application.Run();
        }
        menu.Dispose();
    }
    static bool Allowed(string process){return !new[]{"yasb","DesktopBridge","Dock_64","dock","ScreenRound","FinderWidgets","SearchHost","StartMenuExperienceHost","ShellExperienceHost","TextInputHost","LockApp"}.Contains(process,StringComparer.OrdinalIgnoreCase);}
    internal static bool IsDockGeometry(Rectangle r,Rectangle screen){return r.Bottom>screen.Top+screen.Height*0.7&&r.Height<=100&&r.Width>20;}
    internal static bool AtDockEdge(int x,int y,Rectangle screen){return x>=screen.Left&&x<screen.Right&&y>=screen.Bottom-3&&y<screen.Bottom;}
    internal static int DockAnimationY(int rest,int hidden,double progress,bool show){
        double t=Math.Max(0,Math.Min(1,progress));
        double ease=show?1-Math.Pow(1-t,3):t*t*t;
        return (int)Math.Round(show?hidden+(rest-hidden)*ease:rest+(hidden-rest)*ease);
    }
    static bool DockOwnerMatches(IntPtr hwnd,uint expected){uint current;GetWindowThreadProcessId(hwnd,out current);return current==expected;}
    static bool MoveDockY(IntPtr hwnd,uint owner,int y){
        Rect current;if(!DockOwnerMatches(hwnd,owner)||!GetWindowRect(hwnd,out current))return false;
        // Keep the current X and size: Qt may recenter an auto-width dock while apps change.
        return SetWindowPos(hwnd,IntPtr.Zero,current.Left,y,0,0,0x1|0x4|0x10);
    }
    static void DockVisibility(IntPtr hwnd,bool show,bool animate){
        uint owner;GetWindowThreadProcessId(hwnd,out owner);Rect initial;
        if(owner==0||!GetWindowRect(hwnd,out initial))return;
        var display=Screen.FromRectangle(initial.Value);var screen=display.Bounds;
        var hiddenRect=new Rectangle(initial.Left,screen.Bottom,initial.Right-initial.Left,initial.Bottom-initial.Top);
        // Never slide onto another monitor positioned below this one.
        bool clear= !Screen.AllScreens.Any(s=>s.DeviceName!=display.DeviceName&&s.Bounds.IntersectsWith(hiddenRect));
        if(!animate||!clear){ShowWindow(hwnd,show?8:0);return;}
        int rest=initial.Top,hidden=screen.Bottom;
        if(show){if(!MoveDockY(hwnd,owner,hidden)){ShowWindow(hwnd,8);return;}ShowWindow(hwnd,8);}
        var clock=Stopwatch.StartNew();int duration=show?180:160;
        while(clock.ElapsedMilliseconds<duration){
            if(!MoveDockY(hwnd,owner,DockAnimationY(rest,hidden,clock.Elapsed.TotalMilliseconds/duration,show)))break;
            Thread.Sleep(15);
        }
        if(!DockOwnerMatches(hwnd,owner))return;
        if(!show)ShowWindow(hwnd,0);
        // Hidden bars retain resting geometry so discovery and future auto-width updates stay valid.
        MoveDockY(hwnd,owner,rest);
    }
    static bool TestDockEasing(){
        if(DockAnimationY(900,1000,0,true)!=1000||DockAnimationY(900,1000,1,true)!=900||DockAnimationY(900,1000,0,false)!=900||DockAnimationY(900,1000,1,false)!=1000)return false;
        int prior=1000;for(int i=0;i<=20;i++){int next=DockAnimationY(900,1000,i/20.0,true);if(next>prior||next<900)return false;prior=next;}
        if(DockAnimationY(900,1000,-1,true)!=1000||DockAnimationY(900,1000,2,false)!=1000)return false;
        return true;
    }
    static bool TestDockMotion(){
        if(!TestDockEasing())return false;
        using(var form=new Form()){
            form.FormBorderStyle=FormBorderStyle.None;form.ShowInTaskbar=false;form.Opacity=0;form.StartPosition=FormStartPosition.Manual;
            var screen=Screen.PrimaryScreen.Bounds;form.Bounds=new Rectangle(screen.Left+100,screen.Bottom-74,96,64);
            IntPtr hwnd=form.Handle;Rect before,after;if(!GetWindowRect(hwnd,out before))return false;
            DockVisibility(hwnd,true,true);if(!IsWindowVisible(hwnd)||!GetWindowRect(hwnd,out after)||after.Top!=before.Top||after.Left!=before.Left)return false;
            DockVisibility(hwnd,false,true);if(IsWindowVisible(hwnd)||!GetWindowRect(hwnd,out after)||after.Top!=before.Top||after.Left!=before.Left)return false;
        }
        return true;
    }
    internal static bool DockShouldShow(bool occupied,bool atEdge,bool hover,bool popup,bool fullscreen){return !fullscreen&&(!occupied||atEdge||hover||popup);}
    static void NativeTaskbar(bool show){if(!show&&DateTime.UtcNow<nextTaskbarCheck)return;nextTaskbarCheck=DateTime.UtcNow.AddSeconds(2);EnumWindows(delegate(IntPtr hwnd,IntPtr x){var cls=new StringBuilder(128);GetClassName(hwnd,cls,cls.Capacity);if(cls.ToString()=="Shell_TrayWnd"||cls.ToString()=="Shell_SecondaryTrayWnd") {uint pid;GetWindowThreadProcessId(hwnd,out pid);try{using(var p=Process.GetProcessById((int)pid)){if(p.ProcessName=="explorer"&&IsWindowVisible(hwnd)!=show)ShowWindow(hwnd,show?4:0);}}catch{}}return true;},IntPtr.Zero);}
    internal static bool ShouldRestoreTaskbar(bool yasbRunning,DateTime lastSeen,DateTime now){return !yasbRunning&&now-lastSeen>=TimeSpan.FromSeconds(8);}
    static void Tick(){
        if(DateTime.UtcNow>=nextProcessCheck){var next=new HashSet<uint>();foreach(var p in Process.GetProcessesByName("yasb")){using(p){if(p.SessionId==Session)next.Add((uint)p.Id);}}yasbIds=next;nextProcessCheck=DateTime.UtcNow.AddSeconds(2);}
        var ids=yasbIds;int session=Session;
        if(ids.Count==0){if(ShouldRestoreTaskbar(false,lastYasbSeen,DateTime.UtcNow))NativeTaskbar(true);return;}
        lastYasbSeen=DateTime.UtcNow;
        bool feedOnline=komorebi!=null&&Screen.AllScreens.Any(s=>komorebi.ForScreen(s.DeviceName).HasValue);
        var docks=new List<Tuple<IntPtr,Rectangle>>();var occupants=new HashSet<string>();bool occupied=false,popup=false,fullscreen=false;Point cursor;GetCursorPos(out cursor);IntPtr fg=GetForegroundWindow();
        EnumWindows(delegate(IntPtr hwnd,IntPtr data){
            uint id;GetWindowThreadProcessId(hwnd,out id);bool own=ids.Contains(id);
            // komorebi supplies workspace occupancy. Only the foreground window
            // is then needed for fullscreen detection; skip other processes.
            if(!own&&feedOnline&&hwnd!=fg)return true;
            if(!own&&(!IsWindowVisible(hwnd)||IsIconic(hwnd)||(GetWindowLong(hwnd,-20)&0x80)!=0))return true;
            Rect r;if(!GetWindowRect(hwnd,out r)||r.Right-r.Left<10||r.Bottom-r.Top<10)return true;var screen=Screen.FromRectangle(r.Value).Bounds;
            var title=new StringBuilder(512);GetWindowText(hwnd,title,title.Capacity);if(ids.Contains(id)){
                if(title.ToString()=="YasbBar"&&IsDockGeometry(r.Value,screen))docks.Add(Tuple.Create(hwnd,r.Value));
                else if(IsWindowVisible(hwnd)&&r.Bottom-r.Top>120)popup=true;return true;
            }
            if(!IsWindowVisible(hwnd)||IsIconic(hwnd)||(GetWindowLong(hwnd,-20)&0x80)!=0||title.Length==0)return true;
            var cls=new StringBuilder(128);GetClassName(hwnd,cls,cls.Capacity);if(new[]{"Progman","WorkerW","Shell_TrayWnd","Shell_SecondaryTrayWnd"}.Contains(cls.ToString()))return true;
            int cloaked;if(DwmGetWindowAttribute(hwnd,14,out cloaked,4)==0&&cloaked!=0)return true;
            if(!r.Value.IntersectsWith(screen))return true;
            try{using(var p=Process.GetProcessById((int)id)){if(p.SessionId!=session||!Allowed(p.ProcessName))return true;occupants.Add(p.ProcessName);}}
            catch{return true;}
            occupied=true;
            if(hwnd==fg&&r.Left<=screen.Left+2&&r.Top<=screen.Top+2&&r.Right>=screen.Right-2&&r.Bottom>=screen.Bottom-2)fullscreen=true;
            return true;
        },IntPtr.Zero);
        NativeTaskbar(false);
        bool? managed=null;
        foreach(var dock in docks){var display=Screen.FromRectangle(dock.Item2);var screen=display.Bounds;managed=komorebi==null?null:komorebi.ForScreen(display.DeviceName);bool edge=AtDockEdge(cursor.X,cursor.Y,screen);bool hover=IsWindowVisible(dock.Item1)&&Rectangle.Inflate(dock.Item2,12,12).Contains(cursor.X,cursor.Y);bool show=DockShouldShow(managed??occupied,edge,hover,popup,fullscreen);if(IsWindowVisible(dock.Item1)!=show)DockVisibility(dock.Item1,show,!fullscreen);}
        string state=Json.Serialize(new{mode="active",occupied=occupied,managedWorkspaceOccupied=managed,occupants=occupants.OrderBy(x=>x).ToArray(),fullscreen=fullscreen,popup=popup,docks=docks.Count,docksVisible=docks.Count(d=>IsWindowVisible(d.Item1))});if(state!=lastState||DateTime.UtcNow-lastWrite>TimeSpan.FromSeconds(10)){File.WriteAllText(Path.Combine(Runtime,"dock-status.json"),state,new UTF8Encoding(false));lastState=state;lastWrite=DateTime.UtcNow;}
    }
    static string lastState="";static DateTime lastWrite=DateTime.MinValue;
    [STAThread] static int Main(string[] args){
        try{
            if(args.Length>0&&args[0]=="--read"){Output(State(args.Length>1?args[1]:"ahk"));return 0;}
            if(args.Length>0&&args[0]=="--menu"){Menu(args.Length>1?args[1]:"main");return 0;}
            if(args.Length>0&&args[0]=="--service"){Service(args.Length>1?args[1]:"RestartAll");return 0;}
            if(args.Length>0&&args[0]=="--list-services"){Output(Services.Select(s=>new{group=s[0],label=s[1],action=s[2]}).ToArray());return 0;}
            if(args.Length>0&&args[0]=="--stop"){try{using(var e=EventWaitHandle.OpenExisting(EventName))e.Set();}catch(WaitHandleCannotBeOpenedException){}return 0;}
            if(args.Length>0&&args[0]=="--show-taskbar"){NativeTaskbar(true);return 0;}
            if(args.Length>0&&args[0]=="--test-scroll-hook")return ScrollingMouseNavigation.TestHook()?0:7;
            if(args.Length>0&&args[0]=="--test-motion")return TestDockMotion()?0:5;
            if(args.Length>0&&args[0]=="--test"){if(!ScrollingMouseNavigation.SelfTest()||!KomorebiFeed.TestScrollContext())return 6;if(!TestDockEasing())return 5;var bounds=new Rectangle(0,0,2560,1440);if(!IsDockGeometry(new Rectangle(1245,1366,70,64),bounds)||IsDockGeometry(new Rectangle(0,0,2560,40),bounds)||IsDockGeometry(new Rectangle(0,1300,10,64),bounds)||IsDockGeometry(new Rectangle(0,1100,300,300),bounds))return 3;if(!AtDockEdge(0,1439,bounds)||!AtDockEdge(2559,1439,bounds)||AtDockEdge(1280,1400,bounds)||AtDockEdge(-1,1439,bounds)||AtDockEdge(2560,1439,bounds))return 4;var now=new DateTime(2026,10,24,0,0,10,DateTimeKind.Utc);if(ShouldRestoreTaskbar(true,now.AddSeconds(-20),now)||ShouldRestoreTaskbar(false,now.AddSeconds(-2),now)||!ShouldRestoreTaskbar(false,now.AddSeconds(-8),now)||!ShouldRestoreTaskbar(false,DateTime.MinValue,now))return 2;if(!DockShouldShow(false,false,false,false,false)||DockShouldShow(true,false,false,false,false)||!DockShouldShow(true,true,false,false,false)||DockShouldShow(false,true,true,true,true))return 1;return 0;}
            bool created;using(var mutex=new Mutex(true,@"Local\Druzh.CatppuccinDesktop",out created)){if(!created)return 0;Directory.CreateDirectory(Runtime);Application.EnableVisualStyles();using(var stop=new EventWaitHandle(false,EventResetMode.ManualReset,EventName)){
                komorebi=new KomorebiFeed(Path.Combine(Home,@"scoop\apps\komorebi\current\komorebic.exe"));
                try{using(var mouse=new ScrollingMouseNavigation(Path.Combine(Home,@"scoop\apps\komorebi\current\komorebic.exe"),komorebi.ScrollingContext,Path.Combine(LauncherRoot,@"runtime\status.json"),Runtime)){int n=0;while(!stop.WaitOne(400)){try{Tick();}catch(Exception e){if(n++%20==0){string log=Path.Combine(Runtime,"bridge.log");if(File.Exists(log)&&new FileInfo(log).Length>262144)File.WriteAllText(log,"");File.AppendAllText(log,DateTime.Now.ToString("o")+" "+e.Message+"\n");}}}}}
                finally{komorebi.Dispose();NativeTaskbar(true);}
            }mutex.ReleaseMutex();}return 0;
        }catch(Exception e){try{Directory.CreateDirectory(Runtime);File.AppendAllText(Path.Combine(Runtime,"bridge.log"),e.ToString()+"\n");}catch{}return 1;}
    }
}
