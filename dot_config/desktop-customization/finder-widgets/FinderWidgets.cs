using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Pipes;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("Finder Widgets")]
[assembly: AssemblyProduct("Finder Widgets")]
[assembly: AssemblyVersion("1.0.0.0")]

internal sealed class FinderWidgets : ApplicationContext
{
    static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    static readonly string AppData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
    static readonly string Scripts = Path.Combine(Home, @".config\yasb\scripts");
    static readonly string Komorebic = Path.Combine(Home, @"scoop\apps\komorebi\current\komorebic.exe");
    static readonly string GuardRoot = Path.Combine(Directory.GetParent(Root.TrimEnd('\\')).FullName, "script-launcher");
    static readonly int Session = Process.GetCurrentProcess().SessionId;
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 16000000 };
    readonly Dictionary<string, NotifyIcon> icons = new Dictionary<string, NotifyIcon>();
    readonly Dictionary<string, string> signatures = new Dictionary<string, string>();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly Form dispatcher = new Form();
    readonly ToolTip help = new ToolTip();
    Form dashboard;
    TextBox details;
    volatile Snapshot snapshot = new Snapshot();
    int polling;
    int ticks;
    DateTime lastKomo;
    Dictionary<string, object> zmk = new Dictionary<string, object>();
    Dictionary<string, object> vial = new Dictionary<string, object>();
    Dictionary<string, object> guard = new Dictionary<string, object>();
    EventWaitHandle stop;
    volatile Dictionary<string, object> eventState;
    volatile bool closing;
    NamedPipeServerStream eventPipe;
    static readonly object CacheLock=new object();
    static readonly Dictionary<string,ReadCache> ReadCaches=new Dictionary<string,ReadCache>();
    sealed class ReadCache { public DateTime Stamp; public long Length; public Dictionary<string,object> Value; }
    string lastHealth="";
    DateTime lastHealthWrite;

    sealed class Snapshot
    {
        public int Ahk;
        public bool Creative, Launchpad, Komorebi;
        public string Error = "";
        public Dictionary<string, object> State;
    }

    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);

    static Dictionary<string, object> Dict(object value) { return value as Dictionary<string, object> ?? new Dictionary<string, object>(); }
    static object Get(Dictionary<string, object> value, string key) { object item; return value.TryGetValue(key, out item) ? item : null; }
    static string Str(Dictionary<string, object> value, string key, string fallback) { object item = Get(value, key); return item == null ? fallback : Convert.ToString(item); }
    static int Num(Dictionary<string, object> value, string key, int fallback) { int n; return Int32.TryParse(Str(value, key, ""), out n) ? n : fallback; }
    static object[] Items(object value) { return value as object[] ?? new object[0]; }
    static Dictionary<string, object> Read(string path)
    {
        try {
            lock(CacheLock) {
                var file=new FileInfo(path); ReadCache cached;
                if(ReadCaches.TryGetValue(path,out cached) && cached.Stamp==file.LastWriteTimeUtc && cached.Length==file.Length)return cached.Value;
                string text; using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var reader=new StreamReader(stream,Encoding.UTF8))text=reader.ReadToEnd();
                var value=Dict(new JavaScriptSerializer { MaxJsonLength=16000000 }.DeserializeObject(text));
                ReadCaches[path]=new ReadCache { Stamp=file.LastWriteTimeUtc,Length=file.Length,Value=value }; return value;
            }
        }
        catch { return new Dictionary<string, object>(); }
    }
    static bool Running(string name)
    {
        bool found = false;
        foreach (Process p in Process.GetProcessesByName(name)) { try { if (p.SessionId == Session) found = true; } finally { p.Dispose(); } }
        return found;
    }
    static string Quote(string text) { return "\"" + text.Replace("\"", "\\\"") + "\""; }
    static void Launch(string file, string args)
    {
        Process.Start(new ProcessStartInfo(file, args) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = Root });
    }
    static void Open(string path) { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
    static void Vbs(string name) { Launch("wscript.exe", Quote(Path.Combine(Scripts, name))); }
    static void Action(string name)
    {
        if(name.StartsWith("Ahk",StringComparison.Ordinal)) {
            LauncherControl(name=="AhkStop"?"--disable-all":name=="AhkRestart"?"--restart-all":"--enable-all",null); return;
        }
        Launch("powershell.exe", "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " + Quote(Path.Combine(Root, "Actions.ps1")) + " -Action " + name);
    }
    static void LauncherControl(string command,string script)
    {
        string exe=Path.Combine(GuardRoot,"ScriptLauncher.exe");
        if(!Running("ScriptLauncher"))Launch(exe,"");
        Launch(exe,command+(script==null?"":" "+Quote(script)));
    }
    static string Command(string args, out int exit)
    {
        var output = new StringBuilder();
        var errors = new StringBuilder();
        using (var p = new Process())
        {
            p.StartInfo = new ProcessStartInfo(Komorebic, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8 };
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) lock(output) output.AppendLine(e.Data); };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) lock(errors) errors.AppendLine(e.Data); };
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
            if (!p.WaitForExit(2500)) { p.Kill(); p.WaitForExit(); exit = -1; return "Komorebi command timed out."; }
            p.WaitForExit(); exit = p.ExitCode;
            return exit == 0 ? output.ToString() : errors.ToString();
        }
    }
    void KomoCommand(string args)
    {
        ThreadPool.QueueUserWorkItem(delegate {
            try {
                int exit; string text = Command(args, out exit);
                if (exit != 0) dispatcher.BeginInvoke((MethodInvoker)delegate { MessageBox.Show("Нет связи с komorebi.\n" + text, "Finder Widgets", MessageBoxButtons.OK, MessageBoxIcon.Warning); });
                lastKomo = DateTime.MinValue;
            } catch(Exception e) { Log(e.Message); }
        });
    }
    static void Log(string message)
    {
        try { File.AppendAllText(Path.Combine(Root, "events.log"), DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine); } catch { }
    }

    FinderWidgets()
    {
        dispatcher.CreateControl(); IntPtr handle = dispatcher.Handle;
        stop = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\Druzh.FinderWidgets.Stop.v1");
        AddIcon("komorebi", "K"); AddIcon("ahk", "A"); AddIcon("vial", "V"); AddIcon("zmk", "Z"); AddIcon("vpn", "+"); AddIcon("services", "⋯");
        timer.Interval = 250;
        timer.Tick += delegate { if (stop.WaitOne(0)) { ExitThread(); return; } Refresh(); };
        timer.Start(); Refresh(); ThreadPool.QueueUserWorkItem(delegate { Subscribe(); }); Log("Started.");
    }
    void AddIcon(string key, string label)
    {
        var icon = new NotifyIcon(); icon.Icon = Draw(label, Color.Silver); icon.Text = "Finder Widgets: " + key;
        icon.MouseClick += delegate(object s, MouseEventArgs e) {
            if (e.Button == MouseButtons.Left) {
                if (key == "vial") Vbs("vial_layout_overlay_launcher.vbs");
                else if (key == "vpn") Vbs("vpn_domain_submit_launcher.vbs");
                else ShowMenu(key);
            }
        };
        icon.ContextMenuStrip = Menu(key); icon.Visible = true; icons.Add(key, icon);
    }
    static Icon Draw(string text, Color color)
    {
        using(var bitmap = new Bitmap(32,32)) using(var g = Graphics.FromImage(bitmap))
        using(var font = new Font("Segoe UI", text.Length > 1 ? 14 : 20, FontStyle.Bold, GraphicsUnit.Pixel))
        using(var brush = new SolidBrush(Color.White)) using(var dot = new SolidBrush(color))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using(var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString(text, font, brush, new RectangleF(0,-1,32,29), format);
            g.FillEllipse(dot, 22,23,9,9);
            IntPtr h = bitmap.GetHicon(); try { using(Icon borrowed = Icon.FromHandle(h)) return (Icon)borrowed.Clone(); } finally { DestroyIcon(h); }
        }
    }
    void Update(string key, string text, Color color, string tip)
    {
        string signature = text + "|" + color.ToArgb() + "|" + tip;
        string prior; if (signatures.TryGetValue(key, out prior) && prior == signature) return;
        NotifyIcon item = icons[key]; Icon old = item.Icon; item.Icon = Draw(text,color); if (old != null) old.Dispose();
        item.Text = tip.Length > 63 ? tip.Substring(0,60) + "…" : tip;
        signatures[key] = signature;
    }
    void Refresh()
    {
        zmk = Read(Path.Combine(AppData, @"zmk-yasb\state.json"));
        vial = Read(Path.Combine(AppData, @"vial-helper\state.json"));
        guard = Read(Path.Combine(GuardRoot, @"runtime\status.json"));
        string vl = Str(vial,"label","?"); string zl = Str(zmk,"label","?");
        Update("vial", LayerBadge("V",vial), vl == "OFF" ? Color.Gray : Color.LightSkyBlue, "Vial: " + vl + " · " + Str(vial,"effective",""));
        Update("zmk", LayerBadge("Z",zmk), Str(zmk,"status","OFF") == "OFF" ? Color.Gray : Color.LightGreen, "ZMK: " + zl + " · " + Str(zmk,"battery_halves",""));
        Snapshot s = snapshot;
        if(s.Komorebi && eventState!=null) s.State=eventState;
        string mode = Str(guard,"mode","");
        string ahk = mode == "blocked" ? "заблокирован игрой" : mode == "waiting" ? "ожидание после игры" : s.Ahk == 0 ? "выключен" : s.Creative ? "макросы включены" : s.Launchpad ? "только Launchpad" : "включён";
        Update("ahk", "A", s.Ahk == 0 ? Color.Gray : s.Creative ? Color.LightGreen : Color.Orange, "AHK: " + ahk + " (" + s.Ahk + ")");
        string komoTip = !s.Komorebi ? "Komorebi: выключен" : s.State == null ? "Komorebi: запущен, нет связи" : KomoSummary(s.State);
        Update("komorebi", s.State == null ? "K" : WorkspaceBadge(s.State), !s.Komorebi ? Color.Gray : s.State == null ? Color.Orange : Color.LightGreen, komoTip);
        Update("vpn", "+", Color.LightSkyBlue, "VPN: добавить домен; справа — меню и проверка");
        Update("services", "⋯", Color.Silver, "Службы, все виджеты и быстрые настройки");
        if (dashboard != null && !dashboard.IsDisposed) {
            string content=DashboardText();
            if(details.Text!=content) { details.Text=content; details.SelectionStart=0; details.SelectionLength=0; }
        }
        if (++ticks % 8 == 1) {
            Poll();
            try { var health=new Dictionary<string,object> {
                {"helperPid",Process.GetCurrentProcess().Id},
                {"komorebiRunning",s.Komorebi},{"komorebiConnected",s.State!=null},
                {"workspace",s.State==null?"":WorkspaceBadge(s.State)},
                {"layout",s.State==null?"":KomoSummary(s.State)},{"ahkProcesses",s.Ahk},
                {"vialLabel",vl},{"zmkLabel",zl},{"icons",icons.Count},{"liveEvents",eventState!=null}
            };
                string signature=Json.Serialize(health);
                if(signature!=lastHealth || (DateTime.UtcNow-lastHealthWrite).TotalSeconds>15) {
                    health["updatedAt"]=DateTimeOffset.Now.ToString("o");
                    File.WriteAllText(Path.Combine(Root,"status.json"),Json.Serialize(health)); lastHealth=signature; lastHealthWrite=DateTime.UtcNow;
                }
            } catch { }
        }
    }
    static string LayerBadge(string prefix, Dictionary<string,object> state)
    {
        int top = Num(state,"top",-1); return top < 0 || Str(state,"label","") == "OFF" ? prefix : prefix + top;
    }
    static Dictionary<string,object> FocusedWorkspace(Dictionary<string,object> state)
    {
        var monitors = Dict(Get(state,"monitors")); object[] list = Items(Get(monitors,"elements")); int index = Num(monitors,"focused",0);
        if (index < 0 || index >= list.Length) return new Dictionary<string,object>();
        var workspaces = Dict(Get(Dict(list[index]),"workspaces")); list = Items(Get(workspaces,"elements")); index = Num(workspaces,"focused",0);
        return index >= 0 && index < list.Length ? Dict(list[index]) : new Dictionary<string,object>();
    }
    static string WorkspaceBadge(Dictionary<string,object> state)
    {
        string name = Str(FocusedWorkspace(state),"name","K"); return name.Length > 2 ? name.Substring(0,2) : name;
    }
    static string KomoSummary(Dictionary<string,object> state)
    {
        var workspace = FocusedWorkspace(state); var layout = Get(workspace,"layout");
        string layoutName=layout is string ? (string)layout : Str(Dict(layout),"Default","Custom");
        if(Get(workspace,"monocle_container")!=null) layoutName="MONOCLE";
        if(Str(workspace,"tile","True").ToLowerInvariant()=="false") layoutName="FLOATING";
        return "Komorebi: " + Str(workspace,"name","?") + " · " + layoutName + (Str(state,"is_paused","False").ToLowerInvariant() == "true" ? " · PAUSED" : "");
    }
    void Poll()
    {
        if (Interlocked.Exchange(ref polling,1) != 0) return;
        ThreadPool.QueueUserWorkItem(delegate {
            try {
                Snapshot s = new Snapshot(); s.Komorebi = Running("komorebi");
                var launcher=Read(Path.Combine(GuardRoot,@"runtime\status.json"));
                if(Running("ScriptLauncher")) {
                    s.Ahk=Num(launcher,"ahkProcessCount",0);
                    foreach(object item in Items(Get(launcher,"scripts"))) {
                        var script=Dict(item); if(Str(script,"running","False").ToLowerInvariant()!="true")continue;
                        string path=Str(script,"path","");
                        s.Creative |= path.EndsWith("creative_macropad.ahk",StringComparison.OrdinalIgnoreCase);
                        s.Launchpad |= path.EndsWith("mydockfinder-hotkeys.ahk",StringComparison.OrdinalIgnoreCase);
                    }
                }
                else {
                    foreach(string name in new string[]{"AutoHotkey","AutoHotkey64","AutoHotkey32"})foreach(Process p in Process.GetProcessesByName(name)) { using(p)if(p.SessionId==Session)s.Ahk++; }
                }
                if (s.Komorebi && eventState==null && (DateTime.UtcNow-lastKomo).TotalSeconds > 10) {
                    lastKomo = DateTime.UtcNow; int exit; string data = Command("state",out exit);
                    if (exit == 0) s.State = Dict(new JavaScriptSerializer { MaxJsonLength=16000000 }.DeserializeObject(data)); else s.Error = "IPC недоступен (" + exit + ")";
                } else { s.State = snapshot.State; s.Error = snapshot.Error; }
                if (!s.Komorebi) s.State = null;
                snapshot = s;
            } catch(Exception e) { Log("Poll: " + e.Message); }
            finally { Interlocked.Exchange(ref polling,0); }
        });
    }
    void Subscribe()
    {
        string name="DruzhFinderWidgets-"+Process.GetCurrentProcess().Id;
        while(!closing)
        {
            try {
                using(var pipe=new NamedPipeServerStream(name,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous))
                {
                    eventPipe=pipe;
                    IAsyncResult waiting=pipe.BeginWaitForConnection(null,null);
                    int exit; Command("subscribe-pipe "+name,out exit);
                    if(exit!=0 || !waiting.AsyncWaitHandle.WaitOne(2500)) throw new IOException("Komorebi event subscription unavailable.");
                    pipe.EndWaitForConnection(waiting);
                    using(var reader=new StreamReader(pipe,Encoding.UTF8))
                    {
                        string line;
                        while(!closing && (line=reader.ReadLine())!=null) {
                            var notification=Dict(new JavaScriptSerializer { MaxJsonLength=16000000 }.DeserializeObject(line));
                            var state=Dict(Get(notification,"state"));
                            if(state.ContainsKey("monitors")) eventState=state;
                        }
                    }
                }
            } catch(Exception e) { if(!closing) Log("Events: "+e.Message); }
            finally { eventPipe=null; eventState=null; }
            for(int i=0;i<20 && !closing;i++) Thread.Sleep(250);
        }
    }
    ToolStripMenuItem Item(string text, System.Action action)
    {
        var item = new ToolStripMenuItem(text); item.Click += delegate { try { action(); } catch(Exception e) { MessageBox.Show(e.Message,"Finder Widgets"); } }; return item;
    }
    ContextMenuStrip Menu(string key)
    {
        var menu = new ContextMenuStrip(); menu.Font = new Font("Segoe UI",10); menu.ShowImageMargin = false;
        menu.Opening += delegate { Fill(menu,key); };
        return menu;
    }
    void ShowMenu(string key) { ContextMenuStrip menu = icons[key].ContextMenuStrip; Fill(menu,key); menu.Show(Cursor.Position); }
    void Header(ContextMenuStrip menu,string text) { menu.Items.Add(new ToolStripMenuItem(text) { Enabled=false }); }
    void Fill(ContextMenuStrip menu,string key)
    {
        menu.Items.Clear(); Snapshot s = snapshot;
        if(key == "ahk") {
            Header(menu,"AHK: " + s.Ahk + " процессов"); Header(menu, "Макросы: " + (s.Creative ? "включены" : "выключены") + " · Launchpad: " + (s.Launchpad ? "вкл" : "выкл"));
            string mode=Str(guard,"mode",""); bool blocked=mode=="blocked" || mode=="waiting";
            if(blocked) Header(menu,"Игра / ожидание: " + String.Join(", ",Array.ConvertAll(Items(Get(guard,"blockedBy")), Convert.ToString)));
            foreach(object item in Items(Get(guard,"scripts"))) {
                var script=Dict(item); string path=Str(script,"path",""); string state=Str(script,"mode","");
                string label=state=="running"?"включён":state=="blocked"?"программа открыта":state=="waiting"?"ожидание":state=="disabled"?"выключен":"ошибка / остановлен";
                var entry=Item(Str(script,"name",path)+" · "+label,delegate { LauncherControl("--toggle",path); });
                entry.Checked=Str(script,"enabled","False").ToLowerInvariant()=="true"; menu.Items.Add(entry);
            }
            int unknown=Num(guard,"unmanagedAhkCount",0); if(unknown>0)Header(menu,"Других AHK-процессов: "+unknown);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(Item("Включить все скрипты",delegate { Action("AhkStart"); }));
            menu.Items.Add(Item("Выключить все скрипты",delegate { Action("AhkStop"); }));
            menu.Items.Add(Item("Перезапустить все скрипты",delegate { Action("AhkRestart"); }));
            menu.Items.Add(Item("Скрипты и правила автоотключения…",delegate { Open(Path.Combine(GuardRoot,"config.json")); }));
        } else if(key == "vial" || key == "zmk") {
            var state=key=="vial" ? vial : zmk;
            Header(menu,(key=="vial" ? "Vial: " : "ZMK: ") + Str(state,"label","нет данных"));
            foreach(string line in Str(state,"tooltip","").Split('\n')) if(!String.IsNullOrWhiteSpace(line)) Header(menu,line.Trim());
            if(key=="zmk") Header(menu,"Батареи: " + Str(state,"battery_halves","нет данных"));
            if(key=="vial") {
                menu.Items.Add(Item("Показать раскладку и действия AHK",delegate { Vbs("vial_layout_overlay_launcher.vbs"); }));
                menu.Items.Add(Item("Открыть Vial",delegate { Launch("wscript.exe",Quote(Path.Combine(Home,@".config\run-hidden.vbs"))+" "+Quote(Path.Combine(Home,@".config\vial\scripts\open_vial_safely.cmd"))); }));
            }
            menu.Items.Add(Item("Перезапустить службу",delegate { Action(key=="vial" ? "VialRestart" : "ZmkRestart"); }));
        } else if(key == "komorebi") {
            Header(menu,s.Komorebi ? (s.State==null ? "Komorebi запущен · нет связи" : KomoSummary(s.State)) : "Komorebi выключен");
            if(s.State==null) Header(menu,s.Error);
            for(int i=0;i<9;i++) { int index=i; var ws=Item("Рабочее пространство " +(i+1),delegate { KomoCommand("focus-workspace " + index); }); ws.Enabled=s.State!=null; menu.Items.Add(ws); }
            menu.Items.Add(new ToolStripSeparator());
            var layouts=new ToolStripMenuItem("Расположение окон");
            foreach(string layout in new string[]{"bsp","columns","rows","grid","vertical-stack","horizontal-stack","ultrawide-vertical-stack","right-main-vertical-stack"}) { string chosen=layout; layouts.DropDownItems.Add(Item(layout,delegate { KomoCommand("change-layout " + chosen); })); }
            layouts.Enabled=s.State!=null; menu.Items.Add(layouts);
            var pause=Item("Пауза / продолжить",delegate { KomoCommand("toggle-pause"); }); pause.Enabled=s.State!=null; menu.Items.Add(pause);
            var monocle=Item("Одно окно / обычный режим",delegate { KomoCommand("toggle-monocle"); }); monocle.Enabled=s.State!=null; menu.Items.Add(monocle);
        } else if(key == "vpn") {
            menu.Items.Add(Item("Добавить / проверить домен…",delegate { Vbs("vpn_domain_submit_launcher.vbs"); }));
            menu.Items.Add(Item("Проверить домен из буфера…",delegate { Vbs("vpn_domain_check_launcher.vbs"); }));
        } else {
            foreach(string service in new string[]{"Vial","Zmk","Komorebi"}) {
                string chosen=service; var sub=new ToolStripMenuItem(service);
                sub.DropDownItems.Add(Item("Запустить",delegate { Action(chosen+"Start"); }));
                sub.DropDownItems.Add(Item("Остановить",delegate { Action(chosen+"Stop"); }));
                sub.DropDownItems.Add(Item("Перезапустить",delegate { Action(chosen+"Restart"); })); menu.Items.Add(sub);
            }
            menu.Items.Add(Item("Launchpad",delegate { SendKeys.SendWait("%{F12}"); }));
            menu.Items.Add(Item("Настройки уведомлений",delegate { Open("ms-settings:notifications"); }));
            menu.Items.Add(Item("Звук",delegate { Open("ms-settings:sound"); }));
            menu.Items.Add(Item("Обновления Windows",delegate { Open("ms-settings:windowsupdate"); }));
            menu.Items.Add(Item("Все приложения",delegate { Process.Start(new ProcessStartInfo("explorer.exe","shell:AppsFolder") { UseShellExecute=true }); }));
            menu.Items.Add(Item("Поиск файлов",delegate { Open("search-ms:"); }));
            menu.Items.Add(Item("Скрипты и правила автоотключения AHK…",delegate { Open(Path.Combine(GuardRoot,"config.json")); }));
        }
        menu.Items.Add(new ToolStripSeparator()); menu.Items.Add(Item("Все виджеты…", ShowDashboard));
        menu.Items.Add(Item("Закрыть помощник виджетов",ExitThread));
    }
    string DashboardText()
    {
        Snapshot s=snapshot;
        return "KOMOREBI\r\n" + (s.Komorebi ? s.State==null ? "Запущен, но состояние недоступно. "+s.Error : KomoSummary(s.State) : "Выключен") +
            "\r\n\r\nAHK\r\nПроцессов: " + s.Ahk + " · макросы: " + (s.Creative ? "вкл" : "выкл") + " · Launchpad: " + (s.Launchpad ? "вкл" : "выкл") +
            "\r\nАвтоотключение: " + Str(guard,"mode","нет данных") +
            "\r\n\r\nVIAL\r\n" + Str(vial,"tooltip",Str(vial,"label","Нет данных")) +
            "\r\n\r\nZMK\r\n" + Str(zmk,"tooltip",Str(zmk,"label","Нет данных")) + "\r\nБатареи: " + Str(zmk,"battery_halves","?") +
            "\r\n\r\nVPN\r\nЗначок +: добавление и проверка доменов.\r\n\r\nЧасы, язык, звук, плеер, погода и питание — в MyFinder.\r\nВсе действия доступны в меню значков правой кнопкой мыши.";
    }
    void ShowDashboard()
    {
        if(dashboard!=null && !dashboard.IsDisposed) { dashboard.Activate(); return; }
        dashboard=new Form { Text="Виджеты MyFinder", Width=570, Height=650, StartPosition=FormStartPosition.CenterScreen, BackColor=Color.FromArgb(28,30,35), ForeColor=Color.White,
            FormBorderStyle=FormBorderStyle.FixedToolWindow, ShowInTaskbar=false, MaximizeBox=false, MinimizeBox=false };
        details=new TextBox { Multiline=true, ReadOnly=true, BorderStyle=BorderStyle.None, Dock=DockStyle.Fill, ScrollBars=ScrollBars.Vertical, Font=new Font("Segoe UI",11), BackColor=dashboard.BackColor, ForeColor=Color.White, Text=DashboardText() };
        dashboard.Padding=new Padding(20); dashboard.Controls.Add(details); dashboard.Shown+=delegate { details.SelectionStart=0; details.SelectionLength=0; }; dashboard.Show();
    }
    protected override void ExitThreadCore()
    {
        closing=true; try { if(eventPipe!=null)eventPipe.Dispose(); } catch { }
        timer.Stop(); foreach(var icon in icons.Values) { icon.Visible=false; Icon image=icon.Icon; icon.Dispose(); if(image!=null)image.Dispose(); }
        if(dashboard!=null) dashboard.Dispose(); stop.Dispose(); dispatcher.Dispose(); help.Dispose(); Log("Stopped."); base.ExitThreadCore();
    }
    [STAThread] static int Main(string[] args)
    {
        if(args.Length>0 && args[0]=="--stop") { try { using(var e=EventWaitHandle.OpenExisting(@"Local\Druzh.FinderWidgets.Stop.v1")) e.Set(); } catch(WaitHandleCannotBeOpenedException){} return 0; }
        bool created; using(var mutex=new Mutex(true,@"Local\Druzh.FinderWidgets.v1",out created)) {
            if(!created) return 0;
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Application.ThreadException += delegate(object s,ThreadExceptionEventArgs e) { Log(e.Exception.ToString()); };
            using(var app=new FinderWidgets()) { if(args.Length>0 && args[0]=="--show") app.ShowDashboard(); Application.Run(app); }
            mutex.ReleaseMutex();
        }
        return 0;
    }
}
