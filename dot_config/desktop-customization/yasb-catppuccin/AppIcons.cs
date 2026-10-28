using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// Extract existing application artwork from Windows, including packaged apps.
// No screenshot or desktop capture APIs are used here.
public static class AppIcons {
    [StructLayout(LayoutKind.Sequential)] struct Size {public int X,Y;}
    [StructLayout(LayoutKind.Sequential)] struct Header {public uint Size;public int Width,Height;public ushort Planes,Bits;public uint Compression,ImageSize;public int Xppm,Yppm;public uint Used,Important;}
    [ComImport,Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Factory {[PreserveSig]int GetImage(Size size,uint flags,out IntPtr bitmap);}
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SHCreateItemFromParsingName(string name,IntPtr bind,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out Factory factory);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr handle);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr dc,IntPtr bitmap,uint first,uint count,IntPtr bits,ref Header info,uint usage);
    public static bool Save(string parsingName,string output){
        Factory factory=null;IntPtr handle=IntPtr.Zero,dc=IntPtr.Zero;
        try{
            var iid=typeof(Factory).GUID;if(SHCreateItemFromParsingName(parsingName,IntPtr.Zero,ref iid,out factory)!=0)return false;
            if(factory.GetImage(new Size{X=64,Y=64},0x5,out handle)!=0||handle==IntPtr.Zero)return false;
            using(var basic=Image.FromHbitmap(handle))using(var bitmap=new Bitmap(basic.Width,basic.Height,PixelFormat.Format32bppArgb)){
                var info=new Header{Size=(uint)Marshal.SizeOf(typeof(Header)),Width=bitmap.Width,Height=-bitmap.Height,Planes=1,Bits=32};
                var bits=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
                int read;try{dc=CreateCompatibleDC(IntPtr.Zero);read=GetDIBits(dc,handle,0,(uint)bitmap.Height,bits.Scan0,ref info,0);}finally{bitmap.UnlockBits(bits);}
                if(read==0)return false;bitmap.Save(output,ImageFormat.Png);return true;
            }
        }catch{return false;}finally{if(dc!=IntPtr.Zero)DeleteDC(dc);if(handle!=IntPtr.Zero)DeleteObject(handle);if(factory!=null)Marshal.FinalReleaseComObject(factory);}
    }
}
