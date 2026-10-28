using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// One subscription, no repeated komorebic polling. Independent of YASB's pipe.
internal sealed class KomorebiFeed : IDisposable {
    readonly string cli;
    readonly string name="yasb-catppuccin-"+Guid.NewGuid().ToString("N");
    readonly ManualResetEvent stop=new ManualResetEvent(false);
    readonly object gate=new object();
    Thread thread;NamedPipeServerStream pipe;
    Dictionary<string,bool> occupied;
    ScrollingMouseNavigation.Context scrolling;
    public KomorebiFeed(string executable){cli=executable;if(File.Exists(cli)){thread=new Thread(Listen){IsBackground=true};thread.Start();}}
    static Dictionary<string,object> Dict(object value){return value as Dictionary<string,object>??new Dictionary<string,object>();}
    static object Value(Dictionary<string,object> d,string key){object value;return d.TryGetValue(key,out value)?value:null;}
    static object[] Array(object value){var array=value as object[];if(array!=null)return array;return Value(Dict(value),"elements") as object[]??new object[0];}
    static int Focus(Dictionary<string,object> d){object value=Value(d,"focused");return value==null?0:Convert.ToInt32(value);}
    public bool? ForScreen(string screen){lock(gate){if(occupied==null)return null;bool value;string key=screen.Replace(@"\\.\","");if(occupied.TryGetValue(key,out value))return value;return occupied.Count==1?(bool?)occupied.Values.First():null;}}
    public ScrollingMouseNavigation.Context ScrollingContext(){lock(gate){return scrolling;}}
    internal static ScrollingMouseNavigation.Context ScrollState(Dictionary<string,object> state){
        var ring=Dict(Value(state,"monitors"));var monitors=Array(ring);
        if(monitors.Length!=1||Value(state,"is_paused") is bool&&(bool)Value(state,"is_paused"))return null;
        int mi=Focus(ring);if(mi<0||mi>=monitors.Length)return null;
        var spaces=Dict(Value(Dict(monitors[mi]),"workspaces"));var elements=Array(spaces);int wi=Focus(spaces);
        if(wi<0||wi>=elements.Length)return null;var ws=Dict(elements[wi]);
        if(!String.Equals(Convert.ToString(Value(Dict(Value(ws,"layout")),"Default")),"Scrolling",StringComparison.OrdinalIgnoreCase)||Value(ws,"monocle_container")!=null||Value(ws,"maximized_window")!=null)return null;
        if(Value(ws,"tiling_enabled") is bool&&!(bool)Value(ws,"tiling_enabled"))return null;
        var windows=new List<long>();foreach(var c in Array(Value(ws,"containers")))foreach(var w in Array(Value(Dict(c),"windows"))){object hwnd=Value(Dict(w),"hwnd");if(hwnd!=null)windows.Add(Convert.ToInt64(hwnd));}
        return new ScrollingMouseNavigation.Context{Monitor=mi,Workspace=wi,Windows=windows.ToArray()};
    }
    internal static bool TestScrollContext(){
        string fixture="{\"is_paused\":false,\"monitors\":{\"focused\":0,\"elements\":[{\"workspaces\":{\"focused\":0,\"elements\":[{\"layout\":{\"Default\":\"Scrolling\"},\"containers\":{\"focused\":0,\"elements\":[{\"windows\":{\"focused\":0,\"elements\":[{\"hwnd\":123}]}}]}}]}}]}}";
        Func<string,ScrollingMouseNavigation.Context> parse=s=>ScrollState(Dict(new JavaScriptSerializer().DeserializeObject(s)));
        var value=parse(fixture);if(value==null||value.Workspace!=0||!value.Contains(new IntPtr(123))||value.Contains(new IntPtr(999)))return false;
        if(parse(fixture.Replace("Scrolling","BSP"))!=null||parse(fixture.Replace("false","true"))!=null)return false;
        if(parse(fixture.Replace("\"layout\":","\"monocle_container\":{},\"layout\":"))!=null)return false;
        if(parse(fixture.Replace("\"layout\":","\"tiling_enabled\":false,\"layout\":"))!=null)return false;
        var dictionary=Dict(new JavaScriptSerializer().DeserializeObject(fixture));var monitors=Dict(Value(dictionary,"monitors"));var first=Array(monitors)[0];monitors["elements"]=new object[]{first,first};return ScrollState(dictionary)==null;
    }
    string Command(string args){using(var p=new Process()){p.StartInfo=new ProcessStartInfo(cli,args){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8};p.Start();var output=p.StandardOutput.ReadToEndAsync();var error=p.StandardError.ReadToEndAsync();if(!p.WaitForExit(4000)){try{p.Kill();}catch{}throw new IOException("komorebi command timed out");}if(p.ExitCode!=0)throw new IOException("komorebi unavailable");return output.Result;}}
    void Publish(string text,bool notification){
        var json=new JavaScriptSerializer{MaxJsonLength=8*1024*1024};var state=Dict(json.DeserializeObject(text));if(notification)state=Dict(Value(state,"state"));
        var monitors=Array(Value(state,"monitors"));if(monitors.Length==0)return;
        var next=new Dictionary<string,bool>(StringComparer.OrdinalIgnoreCase);
        foreach(var raw in monitors){var monitor=Dict(raw);var ring=Dict(Value(monitor,"workspaces"));var spaces=Array(ring);int index=Focus(ring);if(index<0||index>=spaces.Length)continue;var ws=Dict(spaces[index]);bool has=Array(Value(ws,"containers")).Length>0||Array(Value(ws,"floating_windows")).Length>0||Value(ws,"monocle_container")!=null||Value(ws,"maximized_window")!=null;string key=Convert.ToString(Value(monitor,"name"));if(key.Length>0)next[key]=has;}
        lock(gate){occupied=next;scrolling=ScrollState(state);}
    }
    void Listen(){
        while(!stop.WaitOne(0)){
            try{
                pipe=new NamedPipeServerStream(name,PipeDirection.InOut,1,PipeTransmissionMode.Message,PipeOptions.Asynchronous,65536,65536);
                var pending=pipe.BeginWaitForConnection(null,null);
                Command("subscribe-pipe "+name);
                if(!pending.AsyncWaitHandle.WaitOne(6000))throw new IOException("komorebi connection timed out");pipe.EndWaitForConnection(pending);
                Publish(Command("state"),false);
                var bytes=new byte[65536];
                while(!stop.WaitOne(0)&&pipe.IsConnected){using(var message=new MemoryStream()){do{int n=pipe.Read(bytes,0,bytes.Length);if(n==0)throw new EndOfStreamException();message.Write(bytes,0,n);if(message.Length>8*1024*1024)throw new IOException("Notification too large");}while(!pipe.IsMessageComplete);Publish(Encoding.UTF8.GetString(message.ToArray()),true);}}
            }catch{}finally{lock(gate){occupied=null;scrolling=null;}if(pipe!=null){try{pipe.Dispose();}catch{}pipe=null;}}
            if(stop.WaitOne(3000))break;
        }
    }
    public void Dispose(){stop.Set();if(pipe!=null){try{pipe.Dispose();}catch{}}if(thread!=null)thread.Join(2000);try{if(File.Exists(cli))Command("unsubscribe-pipe "+name);}catch{}stop.Dispose();}
}
