using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

[assembly:AssemblyTitle("AHK Script Launcher")]
[assembly:AssemblyProduct("AHK Script Launcher")]
[assembly:AssemblyVersion("1.0.0.0")]

internal sealed class ScriptSpec
{
    public string Path, Interpreter;
    public string[] Arguments=new string[0];
    public bool Enabled=true;
}
internal sealed class Rule
{
    public string Name;
    public List<string> Scripts=new List<string>();
    public List<string> Programs=new List<string>();
}
internal sealed class Configuration
{
    public int PollMs=1000;
    public double Delay=15;
    public Dictionary<string,ScriptSpec> Scripts=new Dictionary<string,ScriptSpec>(StringComparer.OrdinalIgnoreCase);
    public List<Rule> Rules=new List<Rule>();
    public HashSet<string> PathNames=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    static Dictionary<string,object> Map(object value) { return value as Dictionary<string,object>; }
    static object Get(Dictionary<string,object> value,string key,object fallback=null) { object found; return value.TryGetValue(key,out found)?found:fallback; }
    static object[] ArrayOf(object value,string name) { var array=value as object[]; if(array==null)throw new InvalidDataException(name+" must be an array."); return array; }
    static string FullPath(string value)
    {
        if(String.IsNullOrWhiteSpace(value))throw new InvalidDataException("Empty file path.");
        string path=Environment.ExpandEnvironmentVariables(value);
        if(!System.IO.Path.IsPathRooted(path) || path.Contains("%"))throw new InvalidDataException("Use an absolute path or a defined environment variable: "+value);
        return System.IO.Path.GetFullPath(path);
    }
    public static Configuration Parse(string json)
    {
        var root=Map(new JavaScriptSerializer().DeserializeObject(json));
        if(root==null)throw new InvalidDataException("Configuration must be an object.");
        var result=new Configuration();
        result.PollMs=Convert.ToInt32(Get(root,"pollIntervalMs",1000));
        result.Delay=Convert.ToDouble(Get(root,"resumeDelaySeconds",15));
        if(result.PollMs<250 || result.PollMs>30000 || result.Delay<0 || result.Delay>300)throw new InvalidDataException("Invalid polling interval or resume delay.");
        string interpreter=FullPath(Convert.ToString(Get(root,"defaultInterpreter")));
        var groups=Map(Get(root,"groups")); if(groups==null)throw new InvalidDataException("groups must be an object.");
        foreach(var entry in groups)
        {
            var group=Map(entry.Value); if(group==null)throw new InvalidDataException("Invalid group: "+entry.Key);
            if(!Convert.ToBoolean(Get(group,"enabled",true)))continue;
            var rule=new Rule { Name=entry.Key };
            foreach(object item in ArrayOf(Get(group,"scripts"),"scripts"))
            {
                var spec=new ScriptSpec { Interpreter=interpreter };
                if(item is string)spec.Path=FullPath((string)item);
                else {
                    var settings=Map(item); if(settings==null)throw new InvalidDataException("Invalid script definition.");
                    spec.Path=FullPath(Convert.ToString(Get(settings,"path")));
                    spec.Enabled=Convert.ToBoolean(Get(settings,"enabled",true));
                    if(settings.ContainsKey("interpreter"))spec.Interpreter=FullPath(Convert.ToString(settings["interpreter"]));
                    if(settings.ContainsKey("arguments"))spec.Arguments=ArrayOf(settings["arguments"],"arguments").Select(Convert.ToString).ToArray();
                }
                if(!spec.Path.EndsWith(".ahk",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Script path must end in .ahk.");
                ScriptSpec prior;
                if(result.Scripts.TryGetValue(spec.Path,out prior)) {
                    if(!String.Equals(prior.Interpreter,spec.Interpreter,StringComparison.OrdinalIgnoreCase) || prior.Enabled!=spec.Enabled || !prior.Arguments.SequenceEqual(spec.Arguments))throw new InvalidDataException("Conflicting definitions for "+spec.Path);
                } else result.Scripts.Add(spec.Path,spec);
                rule.Scripts.Add(spec.Path);
            }
            foreach(object item in ArrayOf(Get(group,"closeWhileRunning",new object[0]),"closeWhileRunning"))
            {
                if(!(item is string))throw new InvalidDataException("Program entries must be executable names or full paths.");
                string program=Environment.ExpandEnvironmentVariables((string)item);
                if(String.IsNullOrWhiteSpace(program) || program.IndexOfAny(new char[]{'*','?','"','\n','\r'})>=0 || !program.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Use an exact .exe name or path: "+program);
                if(program.Contains("\\") || program.Contains("/") || program.Contains(":")) {
                    program=FullPath(program); result.PathNames.Add(System.IO.Path.GetFileName(program));
                }
                rule.Programs.Add(program);
            }
            result.Rules.Add(rule);
        }
        return result;
    }
}
internal sealed class ObservedProcess
{
    public int Id;
    public string Name,Path,Script;
    public long Created;
    public bool Ahk;
}
internal interface IProcessHost
{
    List<ObservedProcess> Snapshot(Configuration config);
    ObservedProcess Start(ScriptSpec script);
    void Stop(ObservedProcess process);
}
internal sealed class ScriptState
{
    public bool WasBlocked;
    public DateTime? ClearSince;
    public DateTime RetryAfter;
    public int Failures;
    public bool Restart;
    public bool PreviouslyRunning;
    public string Error="";
}
internal sealed class LauncherEngine
{
    public Configuration Config;
    public Dictionary<string,bool> Overrides=new Dictionary<string,bool>(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> Pending=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    readonly Dictionary<string,ScriptState> states=new Dictionary<string,ScriptState>(StringComparer.OrdinalIgnoreCase);
    readonly HashSet<string> retired=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> Remembered=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    public IEnumerable<string> KnownScripts { get { return Config.Scripts.Keys.Concat(retired).Distinct(StringComparer.OrdinalIgnoreCase); } }
    readonly IProcessHost host;
    public Action Save=delegate{};
    public Action<string> Log=delegate{};
    public LauncherEngine(IProcessHost host) { this.host=host; }
    public void SetConfig(Configuration config)
    {
        if(Config!=null)foreach(string path in Config.Scripts.Keys)if(!config.Scripts.ContainsKey(path))retired.Add(path);
        foreach(string path in Remembered)if(!config.Scripts.ContainsKey(path))retired.Add(path);
        Remembered.Clear();
        foreach(string path in config.Scripts.Keys)retired.Remove(path);
        Config=config;
        foreach(string path in config.Scripts.Keys)if(!states.ContainsKey(path))states.Add(path,new ScriptState { WasBlocked=Pending.Contains(path) });
        Save();
    }
    public void Control(string operation,string selector)
    {
        var paths=Config.Scripts.Keys.Where(p=>selector=="all" || String.Equals(p,selector,StringComparison.OrdinalIgnoreCase) || String.Equals(System.IO.Path.GetFileName(p),selector,StringComparison.OrdinalIgnoreCase)).ToArray();
        if(paths.Length==0)throw new ArgumentException("No configured script matches "+selector);
        if(selector!="all" && paths.Length>1)throw new ArgumentException("Ambiguous filename; use the full script path.");
        foreach(string path in paths) {
            bool current; bool wanted=Config.Scripts[path].Enabled && (!Overrides.TryGetValue(path,out current) || current);
            Overrides[path]=operation=="disable"?false:operation=="toggle"?!wanted:true;
            if(operation=="restart")states[path].Restart=true;
            states[path].RetryAfter=DateTime.MinValue; states[path].Failures=0; states[path].Error="";
        }
        Save();
    }
    static bool Same(string first,string second) { return String.Equals(first,second,StringComparison.OrdinalIgnoreCase); }
    bool Stop(ObservedProcess process,List<ObservedProcess> observed,ScriptState state)
    {
        try { host.Stop(process); observed.Remove(process); Log("Stopped managed AHK pid="+process.Id); return true; }
        catch(Exception e) { state.Error="Stop failed: "+e.Message; return false; }
    }
    public Dictionary<string,object> Step(DateTime now,bool allowStart)
    {
        var observed=host.Snapshot(Config);
        foreach(string path in retired.ToArray()) {
            bool stopped=true;
            foreach(var process in observed.Where(p=>p.Ahk && Same(p.Script,path)).ToArray())stopped &= Stop(process,observed,new ScriptState());
            if(stopped) { retired.Remove(path); Save(); }
        }
        var blocked=new Dictionary<string,HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        foreach(string path in Config.Scripts.Keys)blocked[path]=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(Rule rule in Config.Rules)foreach(string program in rule.Programs)
        {
            bool full=System.IO.Path.IsPathRooted(program);
            string name=System.IO.Path.GetFileName(program);
            // An unreadable matching launcher's path is treated conservatively.
            bool active=observed.Any(p=>Same(p.Name,name) && (!full || String.IsNullOrEmpty(p.Path) || Same(p.Path,program)));
            if(active)foreach(string path in rule.Scripts)blocked[path].Add(program);
        }
        var scripts=new List<Dictionary<string,object>>();
        var allBlockers=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        bool pendingChanged=false;
        foreach(var pair in Config.Scripts)
        {
            string path=pair.Key; ScriptSpec spec=pair.Value; ScriptState state=states[path];
            bool manual; bool wanted=spec.Enabled && (!Overrides.TryGetValue(path,out manual) || manual);
            var processes=observed.Where(p=>p.Ahk && Same(p.Script,path)).ToArray();
            var blockers=blocked[path]; foreach(string item in blockers)allBlockers.Add(item);
            if(state.PreviouslyRunning && processes.Length==0 && blockers.Count==0 && wanted && !state.Restart) {
                Overrides[path]=false; wanted=false; Save();
                Log("Script exited outside a blocking rule; left disabled: "+System.IO.Path.GetFileName(path));
            }
            if(blockers.Count>0) {
                state.WasBlocked=true; state.ClearSince=null;
                if(wanted && Pending.Add(path)) { Save(); pendingChanged=false; }
            } else if(state.WasBlocked) { state.WasBlocked=false; state.ClearSince=now; }
            bool waiting=state.ClearSince.HasValue && (now-state.ClearSince.Value).TotalSeconds<Config.Delay;
            if(!waiting && blockers.Count==0 && Pending.Remove(path))pendingChanged=true;
            bool mustStop=!wanted || blockers.Count>0 || state.Restart;
            if(mustStop)foreach(var process in processes)Stop(process,observed,state);
            bool running=observed.Any(p=>p.Ahk && Same(p.Script,path));
            if(!running)state.Restart=false;
            if(wanted && !running && blockers.Count==0 && !waiting && allowStart && now>=state.RetryAfter) {
                try {
                    var started=host.Start(spec); observed.Add(started); running=true;
                    state.Failures=0; state.Error=""; Log("Started "+System.IO.Path.GetFileName(path));
                } catch(Exception e) {
                    state.Failures++; state.RetryAfter=now.AddSeconds(Math.Min(60,Math.Pow(2,Math.Min(6,state.Failures))));
                    state.Error=e.Message;
                }
            }
            string mode=!wanted?"disabled":blockers.Count>0?"blocked":waiting?"waiting":running?"running":state.Error.Length>0?"error":"stopped";
            state.PreviouslyRunning=running;
            scripts.Add(new Dictionary<string,object> {
                {"path",path},{"name",System.IO.Path.GetFileNameWithoutExtension(path)},{"enabled",wanted},{"running",running},
                {"mode",mode},{"blockedBy",blockers.ToArray()},{"error",state.Error},
                {"resumeInSeconds",waiting?Math.Max(0,(int)Math.Ceiling(Config.Delay-(now-state.ClearSince.Value).TotalSeconds)):0}
            });
        }
        if(pendingChanged)Save();
        var ahk=observed.Where(p=>p.Ahk).ToArray();
        string overall=scripts.Any(s=>(string)s["mode"]=="blocked")?"blocked":scripts.Any(s=>(string)s["mode"]=="waiting")?"waiting":scripts.Any(s=>(string)s["mode"]=="error")?"error":"idle";
        return new Dictionary<string,object> {
            {"mode",overall},{"blockedBy",allBlockers.ToArray()},{"ahkProcessCount",ahk.Length},
            {"managedRunning",scripts.Count(s=>(bool)s["running"])},
            {"unmanagedAhkCount",ahk.Count(p=>p.Script==null || !Config.Scripts.ContainsKey(p.Script))},
            {"scripts",scripts},{"groupCount",Config.Rules.Count}
        };
    }
}

internal static class Native
{
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] internal struct Entry {
        public uint Size,Usage,Id; public IntPtr Heap; public uint Module,Threads,Parent; public int Priority; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string Name;
    }
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] internal static extern bool Process32FirstW(IntPtr snapshot,ref Entry entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] internal static extern bool Process32NextW(IntPtr snapshot,ref Entry entry);
    [DllImport("kernel32.dll")] internal static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] internal static extern bool ProcessIdToSessionId(uint pid,out uint session);
    [DllImport("kernel32.dll")] internal static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
    [DllImport("kernel32.dll")] internal static extern bool GetProcessTimes(IntPtr process,out long created,out long exited,out long kernel,out long user);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] internal static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder path,ref int length);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CommandLineToArgvW(string command,out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    internal static string[] Arguments(string command) {
        if(String.IsNullOrEmpty(command))return new string[0];
        int count; IntPtr memory=CommandLineToArgvW(command,out count); if(memory==IntPtr.Zero)return new string[0];
        try { var result=new string[count]; for(int i=0;i<count;i++)result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size)); return result; }
        finally { LocalFree(memory); }
    }
    internal static void Details(int id,out string path,out long created) {
        path=null; created=0; IntPtr handle=OpenProcess(0x1000,false,id); if(handle==IntPtr.Zero)return;
        try { long e,k,u; GetProcessTimes(handle,out created,out e,out k,out u); int size=32768; var buffer=new StringBuilder(size); if(QueryFullProcessImageNameW(handle,0,buffer,ref size))path=buffer.ToString(); }
        finally { CloseHandle(handle); }
    }
}
internal sealed class WindowsProcessHost:IProcessHost
{
    readonly uint session=(uint)Process.GetCurrentProcess().SessionId;
    readonly Dictionary<int,ObservedProcess> cache=new Dictionary<int,ObservedProcess>();
    readonly Dictionary<int,Process> owned=new Dictionary<int,Process>();
    readonly Action<string> log;
    public WindowsProcessHost(Action<string> log) { this.log=log; }
    public List<ObservedProcess> Snapshot(Configuration config)
    {
        var result=new List<ObservedProcess>(); var present=new HashSet<int>();
        IntPtr snapshot=Native.CreateToolhelp32Snapshot(2,0);
        if(snapshot==new IntPtr(-1))throw new IOException("Cannot enumerate processes.");
        try {
            var entry=new Native.Entry { Size=(uint)Marshal.SizeOf(typeof(Native.Entry)) };
            if(Native.Process32FirstW(snapshot,ref entry))do {
                uint owner; if(!Native.ProcessIdToSessionId(entry.Id,out owner) || owner!=session)continue;
                bool ahk=entry.Name.StartsWith("AutoHotkey",StringComparison.OrdinalIgnoreCase) && entry.Name.EndsWith(".exe",StringComparison.OrdinalIgnoreCase);
                var item=new ObservedProcess { Id=(int)entry.Id,Name=entry.Name,Ahk=ahk };
                if(ahk || config.PathNames.Contains(entry.Name))Native.Details(item.Id,out item.Path,out item.Created);
                if(ahk) {
                    present.Add(item.Id); ObservedProcess prior;
                    if(cache.TryGetValue(item.Id,out prior) && prior.Created==item.Created)item.Script=prior.Script;
                    else {
                        try {
                            using(var query=new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE ProcessId="+item.Id))
                            using(var rows=query.Get())foreach(ManagementObject row in rows) {
                                foreach(string arg in Native.Arguments(Convert.ToString(row["CommandLine"])).Skip(1))
                                    if(arg.EndsWith(".ahk",StringComparison.OrdinalIgnoreCase) && System.IO.Path.IsPathRooted(arg)) { item.Script=System.IO.Path.GetFullPath(arg); break; }
                            }
                        } catch(ManagementException) { }
                        cache[item.Id]=item;
                    }
                }
                result.Add(item);
            } while(Native.Process32NextW(snapshot,ref entry));
        } finally { Native.CloseHandle(snapshot); }
        foreach(int id in cache.Keys.Where(id=>!present.Contains(id)).ToArray())cache.Remove(id);
        foreach(int id in owned.Keys.Where(id=>!present.Contains(id)).ToArray()) { owned[id].Dispose(); owned.Remove(id); }
        return result;
    }
    public static string Quote(string text)
    {
        var result=new StringBuilder("\""); int slashes=0;
        foreach(char ch in text) {
            if(ch=='\\') { slashes++; continue; }
            if(ch=='"')result.Append('\\',slashes*2+1).Append('"'); else result.Append('\\',slashes).Append(ch);
            slashes=0;
        }
        return result.Append('\\',slashes*2).Append('"').ToString();
    }
    public ObservedProcess Start(ScriptSpec script)
    {
        if(!File.Exists(script.Path) || !File.Exists(script.Interpreter))throw new FileNotFoundException("Script or interpreter is missing: "+script.Path);
        string arguments="/ErrorStdOut "+Quote(script.Path)+String.Concat(script.Arguments.Select(a=>" "+Quote(a)));
        var process=new Process();
        try {
            process.StartInfo=new ProcessStartInfo(script.Interpreter,arguments) { UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,
                WorkingDirectory=System.IO.Path.GetDirectoryName(script.Path),RedirectStandardError=true,RedirectStandardOutput=true };
            process.Start();
            if(process.WaitForExit(150)) {
                string error=process.StandardError.ReadToEnd()+process.StandardOutput.ReadToEnd();
                throw new InvalidOperationException("AHK exited immediately ("+process.ExitCode+"): "+error.Substring(0,Math.Min(1000,error.Length)));
            }
            // Persistent AHK scripts do not write output normally; drain asynchronously if they do.
            process.OutputDataReceived+=delegate(object s,DataReceivedEventArgs e){if(e.Data!=null)log(e.Data);};
            process.ErrorDataReceived+=delegate(object s,DataReceivedEventArgs e){if(e.Data!=null)log(e.Data);};
            process.BeginOutputReadLine(); process.BeginErrorReadLine();
            owned[process.Id]=process;
            string path; long created; Native.Details(process.Id,out path,out created);
            return new ObservedProcess { Id=process.Id,Name=System.IO.Path.GetFileName(script.Interpreter),Path=script.Interpreter,Script=script.Path,Created=created,Ahk=true };
        } catch { process.Dispose(); throw; }
    }
    public void Stop(ObservedProcess item)
    {
        string path; long created; Native.Details(item.Id,out path,out created);
        if(created!=item.Created || !String.Equals(path,item.Path,StringComparison.OrdinalIgnoreCase))return;
        try { using(var process=Process.GetProcessById(item.Id)) { process.Kill(); if(!process.WaitForExit(1500))throw new IOException("AHK did not stop."); } }
        catch(ArgumentException) { }
    }
}

internal static class ScriptLauncher
{
    static readonly string Root=AppDomain.CurrentDomain.BaseDirectory;
    static readonly string Runtime=System.IO.Path.Combine(Root,"runtime");
    static readonly string ConfigPath=System.IO.Path.Combine(Root,"config.json");
    static readonly string StatePath=System.IO.Path.Combine(Runtime,"state.json");
    static readonly string PipeName="DruzhScriptLauncher."+Process.GetCurrentProcess().SessionId;
    static readonly EventWaitHandle StopEvent=new EventWaitHandle(false,EventResetMode.ManualReset);
    static readonly ConcurrentQueue<Request> Requests=new ConcurrentQueue<Request>();
    static readonly object LogLock=new object();
    static NamedPipeServerStream activePipe;
    sealed class Request { public string Operation,Selector,Error=""; public ManualResetEvent Done=new ManualResetEvent(false); }
    static string ReadText(string path) { using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var reader=new StreamReader(stream,Encoding.UTF8))return reader.ReadToEnd(); }
    static void Atomic(string path,object value)
    {
        string temp=path+".tmp"; File.WriteAllText(temp,new JavaScriptSerializer().Serialize(value),new UTF8Encoding(false));
        for(int i=0;;i++)try { if(File.Exists(path))File.Replace(temp,path,path+".previous"); else File.Move(temp,path); return; }
        catch(IOException) { if(i>=9)throw; Thread.Sleep(20); }
    }
    static void Log(string text)
    {
        lock(LogLock)try {
            string path=System.IO.Path.Combine(Runtime,"events.log");
            if(File.Exists(path) && new FileInfo(path).Length>262144) { string old=path+".previous"; if(File.Exists(old))File.Delete(old); File.Move(path,old); }
            File.AppendAllText(path,DateTimeOffset.Now.ToString("o")+" "+text+Environment.NewLine);
        } catch { }
    }
    static int Send(string operation,string selector)
    {
        try {
            using(var pipe=new NamedPipeClientStream(".",PipeName,PipeDirection.InOut)) {
                pipe.Connect(2500);
                using(var writer=new StreamWriter(pipe,new UTF8Encoding(false),1024,true))using(var reader=new StreamReader(pipe,Encoding.UTF8,false,1024,true)) {
                    writer.AutoFlush=true; writer.WriteLine(new JavaScriptSerializer().Serialize(new { operation=operation,selector=selector }));
                    string reply=reader.ReadLine(); Console.WriteLine(reply); return reply!=null && reply.StartsWith("OK")?0:1;
                }
            }
        } catch(Exception e) { Console.WriteLine("Launcher unavailable: "+e.Message); return 1; }
    }
    static void PipeLoop()
    {
        var security=new PipeSecurity(); security.SetAccessRuleProtection(true,false);
        security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User,PipeAccessRights.FullControl,AccessControlType.Allow));
        while(!StopEvent.WaitOne(0))try {
            using(var pipe=new NamedPipeServerStream(PipeName,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,4096,4096,security)) {
                activePipe=pipe; IAsyncResult wait=pipe.BeginWaitForConnection(null,null);
                while(!wait.AsyncWaitHandle.WaitOne(250))if(StopEvent.WaitOne(0))return;
                pipe.EndWaitForConnection(wait);
                using(var reader=new StreamReader(pipe,Encoding.UTF8,false,1024,true))using(var writer=new StreamWriter(pipe,new UTF8Encoding(false),1024,true)) {
                    string line=reader.ReadLine(); if(line==null || line.Length>32768)continue;
                    var body=new JavaScriptSerializer().Deserialize<Dictionary<string,string>>(line);
                    var request=new Request { Operation=body["operation"],Selector=body["selector"] };
                    Requests.Enqueue(request);
                    if(!request.Done.WaitOne(10000))request.Error="Control request timed out.";
                    writer.AutoFlush=true; writer.WriteLine(request.Error.Length==0?"OK":"ERROR: "+request.Error);
                }
            }
        } catch(Exception e) { if(!StopEvent.WaitOne(0)) { Log("Control: "+e.Message); Thread.Sleep(500); } }
        finally { activePipe=null; }
    }
    static void Save(LauncherEngine engine) { Atomic(StatePath,new { overrides=engine.Overrides,resumeAfterBlock=engine.Pending.ToArray(),knownScripts=engine.KnownScripts.ToArray() }); }
    static void Load(LauncherEngine engine)
    {
        if(!File.Exists(StatePath))return;
        var data=new JavaScriptSerializer().DeserializeObject(ReadText(StatePath)) as Dictionary<string,object>;
        if(data==null)throw new InvalidDataException("Invalid state.json; saved state retained.");
        object value;
        if(data.TryGetValue("overrides",out value))foreach(var entry in (Dictionary<string,object>)value)engine.Overrides[entry.Key]=Convert.ToBoolean(entry.Value);
        if(data.TryGetValue("resumeAfterBlock",out value))foreach(object path in (object[])value)engine.Pending.Add(Convert.ToString(path));
        if(data.TryGetValue("knownScripts",out value))foreach(object path in (object[])value)engine.Remembered.Add(Convert.ToString(path));
    }
    [STAThread] static int Main(string[] args)
    {
        if(args.Length>0 && args[0]=="--check") {
            try { var config=Configuration.Parse(ReadText(ConfigPath)); Console.WriteLine("OK: "+config.Scripts.Count+" scripts, "+config.Rules.Count+" groups"); return 0; }
            catch(Exception e) { Console.WriteLine(e.Message); return 1; }
        }
        if(args.Length>0 && args[0]!="--run") {
            string op=args[0].TrimStart('-'); string selector=args.Length>1?args[1]:"all";
            if(op.EndsWith("-all"))op=op.Substring(0,op.Length-4);
            if(!new string[]{"enable","disable","toggle","restart","stop"}.Contains(op))return 2;
            return Send(op,selector);
        }
        bool created;
        using(var mutex=new Mutex(true,@"Local\Druzh.ScriptLauncher.v1",out created)) {
            if(!created)return 0;
            Directory.CreateDirectory(Runtime);
            try {
                var engine=new LauncherEngine(new WindowsProcessHost(Log)); engine.Log=Log; engine.Save=delegate { Save(engine); };
                Load(engine); engine.SetConfig(Configuration.Parse(ReadText(ConfigPath)));
                ThreadPool.QueueUserWorkItem(delegate { PipeLoop(); });
                DateTime stamp=File.GetLastWriteTimeUtc(ConfigPath),lastStatus=DateTime.MinValue;
                string configError="",priorError="",signature="";
                Log("Started.");
                do {
                    try {
                        DateTime modified=File.GetLastWriteTimeUtc(ConfigPath);
                        if(modified!=stamp || configError.Length>0)try {
                            engine.SetConfig(Configuration.Parse(ReadText(ConfigPath))); stamp=modified; configError="";
                        } catch(Exception e) { configError=e.Message; }
                        Request request;
                        while(Requests.TryDequeue(out request)) {
                            try {
                                if(request.Operation=="stop")StopEvent.Set();
                                else if(!new string[]{"enable","disable","toggle","restart"}.Contains(request.Operation))throw new ArgumentException("Unsupported operation");
                                else engine.Control(request.Operation,request.Selector);
                            } catch(Exception e) { request.Error=e.Message; }
                            finally { request.Done.Set(); }
                        }
                        var status=engine.Step(DateTime.UtcNow,configError.Length==0 && !StopEvent.WaitOne(0));
                        status["error"]=configError; status["helperPid"]=Process.GetCurrentProcess().Id;
                        if(configError.Length>0)status["mode"]="error";
                        if(StopEvent.WaitOne(0))status["mode"]="stopped";
                        string next=new JavaScriptSerializer().Serialize(status);
                        if(next!=signature || (DateTime.UtcNow-lastStatus).TotalSeconds>=15) {
                            status["updatedAt"]=DateTimeOffset.Now.ToString("o"); Atomic(System.IO.Path.Combine(Runtime,"status.json"),status);
                            signature=next; lastStatus=DateTime.UtcNow;
                        }
                        if(configError!=priorError) { if(configError.Length>0)Log("Config: "+configError); priorError=configError; }
                    } catch(Exception e) { if(priorError!=e.Message) { Log("Error: "+e.Message); priorError=e.Message; } }
                } while(!StopEvent.WaitOne(engine.Config.PollMs));
                Save(engine); Log("Stopped; script states retained.");
            } catch(Exception e) { Log(e.ToString()); return 1; }
            finally { StopEvent.Set(); try { if(activePipe!=null)activePipe.Dispose(); } catch { } mutex.ReleaseMutex(); }
        }
        return 0;
    }
}
