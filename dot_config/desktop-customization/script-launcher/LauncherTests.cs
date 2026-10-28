using System;
using System.Collections.Generic;
using System.Linq;
using System.Web.Script.Serialization;
internal sealed class FakeHost:IProcessHost
{
    public List<ObservedProcess> Items=new List<ObservedProcess>();
    public int Starts,Stops,Attempts,FailStarts;
    public Action<ObservedProcess> BeforeStop=delegate{};
    int next=100;
    public List<ObservedProcess> Snapshot(Configuration config){return new List<ObservedProcess>(Items);}
    public ObservedProcess Start(ScriptSpec spec){Attempts++;if(FailStarts-->0)throw new Exception("simulated start error");Starts++;var p=new ObservedProcess{Id=next++,Name="AutoHotkey64.exe",Script=spec.Path,Path=spec.Interpreter,Ahk=true};Items.Add(p);return p;}
    public void Stop(ObservedProcess p){BeforeStop(p);Stops++;Items.Remove(p);}
    public void Program(string name,string path=null){Items.Add(new ObservedProcess{Id=next++,Name=name,Path=path});}
    public void Close(string name){Items.RemoveAll(p=>p.Name==name);}
    public bool Has(string path){return Items.Any(p=>String.Equals(p.Script,path,StringComparison.OrdinalIgnoreCase));}
}
internal static class LauncherTests
{
    const string A=@"C:\Tests\alpha.ahk",B=@"C:\Tests\beta.ahk",C=@"C:\Tests\unmanaged.ahk";
    static int assertions;
    static void Assert(bool value,string message){assertions++;if(!value)throw new Exception(message);}
    static Configuration Config(params object[] groups)
    {
        var map=new Dictionary<string,object>();for(int i=0;i<groups.Length;i++)map["group"+i]=groups[i];
        return Configuration.Parse(new JavaScriptSerializer().Serialize(new { defaultInterpreter=@"C:\Tests\AutoHotkey64.exe",pollIntervalMs=1000,resumeDelaySeconds=15,groups=map }));
    }
    static object Group(string[] scripts,params string[] programs){return new {scripts=scripts,closeWhileRunning=programs};}
    static LauncherEngine Engine(FakeHost host,Configuration config){var engine=new LauncherEngine(host);engine.SetConfig(config);return engine;}
    static int Main()
    {
        try {
            DateTime now=DateTime.UtcNow;
            var config=Config(Group(new[]{A,B},"GameA.exe"),Group(new[]{A},"GameB.exe"));
            Assert(config.Scripts.Count==2 && config.Rules.Count==2,"Shared script not deduplicated");
            var host=new FakeHost();var engine=Engine(host,config);
            engine.Step(now,true);engine.Step(now.AddSeconds(1),true);
            Assert(host.Starts==2,"Startup duplicated scripts");
            host.Items.Add(new ObservedProcess{Id=20,Name="AutoHotkey64.exe",Ahk=true,Script=C});
            bool savedBeforeStop=false;engine.Save=delegate{savedBeforeStop=engine.Pending.Contains(A);};
            host.BeforeStop=delegate(ObservedProcess p){Assert(savedBeforeStop,"Blocked state not saved before stop");};
            host.Program("GameA.exe");host.Program("GameB.exe");engine.Step(now.AddSeconds(2),true);
            Assert(!host.Has(A)&&!host.Has(B)&&host.Has(C),"Scoped blocking affected wrong scripts");
            host.BeforeStop=delegate{};
            host.Close("GameA.exe");engine.Step(now.AddSeconds(3),true);
            engine.Step(now.AddSeconds(17),true);Assert(!host.Has(B),"Delay too short");
            engine.Step(now.AddSeconds(18),true);Assert(host.Has(B)&&!host.Has(A),"Independent group resume failed");
            host.Close("GameB.exe");engine.Step(now.AddSeconds(19),true);
            host.Program("GameB.exe");engine.Step(now.AddSeconds(25),true);
            host.Close("GameB.exe");engine.Step(now.AddSeconds(26),true);
            engine.Step(now.AddSeconds(40),true);Assert(!host.Has(A),"Reopen did not reset delay");
            engine.Step(now.AddSeconds(41),true);Assert(host.Has(A),"Script did not resume");
            engine.Control("disable","alpha.ahk");engine.Step(now.AddSeconds(42),true);Assert(!host.Has(A),"Manual disable failed");
            host.Program("GameB.exe");engine.Step(now.AddSeconds(43),true);host.Close("GameB.exe");engine.Step(now.AddSeconds(44),true);engine.Step(now.AddSeconds(80),true);
            Assert(!host.Has(A),"Game exit overrode manual disable");
            var recovered=new LauncherEngine(host);recovered.Overrides=new Dictionary<string,bool>(engine.Overrides,StringComparer.OrdinalIgnoreCase);recovered.SetConfig(config);recovered.Step(now.AddSeconds(81),true);
            Assert(!host.Has(A),"Restart forgot manual disable");
            recovered.Control("enable","alpha.ahk");recovered.Step(now.AddSeconds(82),true);Assert(host.Has(A),"Manual enable failed");
            int before=host.Starts;recovered.Control("restart","alpha.ahk");recovered.Step(now.AddSeconds(83),true);Assert(host.Starts==before+1,"Restart failed");
            recovered.SetConfig(Config(Group(new[]{A},"GameB.exe")));recovered.Step(now.AddSeconds(84),true);
            Assert(!host.Has(B)&&host.Has(A)&&host.Has(C),"Removal cleanup affected wrong process");
            var changedWhileStopped=new LauncherEngine(host);changedWhileStopped.Remembered.Add(A);changedWhileStopped.SetConfig(Config());changedWhileStopped.Step(now.AddSeconds(85),true);
            Assert(!host.Has(A)&&host.Has(C),"Startup forgot ownership of removed script");

            host=new FakeHost();engine=Engine(host,Config(Group(new[]{A},@"C:\Games\Apex\Launcher.exe")));
            host.Program("Launcher.exe",@"C:\Games\Other\Launcher.exe");engine.Step(now,true);Assert(host.Has(A),"Full-path match blocked another app");
            host.Close("Launcher.exe");host.Program("Launcher.exe",@"C:\Games\Apex\Launcher.exe");engine.Step(now.AddSeconds(1),true);Assert(!host.Has(A),"Full-path match failed");
            host.Close("Launcher.exe");host.Program("Launcher.exe");engine.Step(now.AddSeconds(2),true);Assert(!host.Has(A),"Unreadable launcher path was not conservative");

            host=new FakeHost();engine=new LauncherEngine(host);engine.Pending.Add(A);engine.SetConfig(Config(Group(new[]{A})));
            engine.Step(now,true);Assert(!host.Has(A),"Recovery skipped grace period");engine.Step(now.AddSeconds(15),true);Assert(host.Has(A),"Recovery did not resume");

            host=new FakeHost();engine=Engine(host,Config(Group(new[]{A},"Game.exe")));
            engine.Step(now,false);Assert(host.Starts==0,"Invalid-config hold started a script");
            engine.Step(now.AddSeconds(1),true);host.Program("Game.exe");engine.Step(now.AddSeconds(2),false);Assert(!host.Has(A),"Invalid-config hold prevented necessary stop");

            host=new FakeHost{FailStarts=2};engine=Engine(host,Config(Group(new[]{A})));
            engine.Step(now,true);engine.Step(now.AddSeconds(1),true);Assert(host.Attempts==1,"Retry has no backoff");
            engine.Step(now.AddSeconds(2),true);engine.Step(now.AddSeconds(5),true);Assert(host.Attempts==2,"Retry backoff failed");
            engine.Step(now.AddSeconds(6),true);Assert(host.Has(A),"Error recovery failed");
            host.Items.RemoveAll(p=>p.Script==A);engine.Step(now.AddSeconds(7),true);Assert(!host.Has(A)&&engine.Overrides[A]==false,"External/manual AHK exit was immediately undone");
            engine.Control("enable","all");engine.Step(now.AddSeconds(8),true);Assert(host.Has(A),"Enable after external exit failed");

            host=new FakeHost();engine=Engine(host,Config(Group(new[]{A,B},"Game.exe")));
            engine.Step(now,true);engine.Control("disable",B);engine.Step(now.AddSeconds(1),true);
            engine.Control("restart","all");engine.Step(now.AddSeconds(2),true);
            Assert(host.Has(A)&&!host.Has(B)&&!engine.Overrides[B],"Group restart re-enabled a manually disabled script");
            engine.Control("pause","all");var paused=engine.Step(now.AddSeconds(3),true);
            Assert(!host.Has(A)&&!host.Has(B)&&(string)paused["mode"]=="paused","Global pause did not stop managed scripts");
            Assert((bool)((List<Dictionary<string,object>>)paused["scripts"])[0]["enabled"],"Pause destroyed the enabled selection");
            host.Program("Game.exe");engine.Control("restart","all");engine.Step(now.AddSeconds(4),true);
            Assert(engine.Suspended&&!host.Has(A),"Restart bypassed global pause");
            engine.Control("resume","all");engine.Control("restart","all");engine.Step(now.AddSeconds(5),true);
            Assert(!host.Has(A)&&!host.Has(B),"Resume/restart bypassed a game blocker");
            host.Close("Game.exe");engine.Step(now.AddSeconds(6),true);engine.Step(now.AddSeconds(20),true);
            Assert(!host.Has(A),"Resume bypassed the game grace period");
            engine.Step(now.AddSeconds(21),true);
            Assert(host.Has(A)&&!host.Has(B),"Resume forgot manual selection or failed after game exit");
            engine.Control("pause","all");engine.Step(now.AddSeconds(22),true);
            engine.Control("resume","all");engine.Step(now.AddSeconds(23),true);
            Assert(host.Has(A)&&!host.Has(B),"Pause/resume changed manual overrides");

            host=new FakeHost();engine=Engine(host,Config(Group(new[]{A,B},"Game.exe")));
            engine.Control("disable","all");engine.Step(now,true);
            engine.Control("toggle-global","all");engine.Step(now.AddSeconds(1),true);
            Assert(engine.GlobalEnabled&&host.Has(A)&&host.Has(B),"Global on did not enable every script");
            engine.Control("toggle-global","all");engine.Step(now.AddSeconds(2),true);
            Assert(!engine.GlobalEnabled&&!host.Has(A)&&!host.Has(B),"Global off left scripts enabled");
            engine.Control("toggle-global","all");engine.Control("toggle-global","all");
            Assert(!engine.GlobalEnabled,"Rapid global toggles used stale status");
            engine.Control("enable",A);engine.Step(now.AddSeconds(3),true);
            engine.Control("toggle-global","all");engine.Step(now.AddSeconds(4),true);
            Assert(!host.Has(A)&&!host.Has(B),"Mixed selection did not switch fully off");
            engine.Control("pause","all");host.Program("Game.exe");engine.Step(now.AddSeconds(5),true);
            engine.Control("toggle-global","all");var blocked=engine.Step(now.AddSeconds(6),true);
            Assert(engine.GlobalEnabled&&!engine.Suspended&&!host.Has(A)&&!host.Has(B)&&(string)blocked["mode"]=="blocked","Global on bypassed game blocking or did not resume");
            host.Close("Game.exe");engine.Step(now.AddSeconds(7),true);engine.Step(now.AddSeconds(21),true);
            Assert(!host.Has(A)&&!host.Has(B),"Global on bypassed game resume delay");
            engine.Step(now.AddSeconds(22),true);Assert(host.Has(A)&&host.Has(B),"All scripts did not return after game delay");
            host.Program("Game.exe");engine.Step(now.AddSeconds(23),true);engine.Control("toggle-global","all");
            host.Close("Game.exe");engine.Step(now.AddSeconds(24),true);engine.Step(now.AddSeconds(50),true);
            Assert(!engine.GlobalEnabled&&!host.Has(A)&&!host.Has(B),"Game exit undid explicit global off");

            bool rejected=false;try{Configuration.Parse("{}");}catch{rejected=true;}Assert(rejected,"Invalid config accepted");
            rejected=false;try{Config(Group(new[]{"relative.ahk"}));}catch{rejected=true;}Assert(rejected,"Relative script accepted");
            rejected=false;try{Config(Group(new[]{A},"*.exe"));}catch{rejected=true;}Assert(rejected,"Wildcard process accepted");
            string[] quoted={"C:\\Path with spaces\\a.ahk","a\"b",@"C:\folder\",""};
            string[] parsed=Native.Arguments("test.exe "+String.Join(" ",quoted.Select(WindowsProcessHost.Quote))).Skip(1).ToArray();
            Assert(quoted.SequenceEqual(parsed),"Command argument quoting failed");
            Console.WriteLine("PASS: "+assertions+" assertions — groups, overlap, scoped stopping, delays, manual state, recovery, hot reload, paths, error backoff and quoting.");
            return 0;
        }catch(Exception e){Console.WriteLine(e);return 1;}
    }
}
