<#
  Monitor Mode Switcher - switch between saved multi-monitor layouts from the tray.
  Windows on a monitor that gets turned off are moved to the new primary monitor.

  Usage:
    MonitorModeSwitcher.ps1                    Start tray app
    MonitorModeSwitcher.ps1 -List              Print connected monitors as JSON
    MonitorModeSwitcher.ps1 -Modes             Print saved modes as JSON
    MonitorModeSwitcher.ps1 -Mode "Desk"       Switch to a saved mode
    MonitorModeSwitcher.ps1 -Capture "Desk"    Save the current Windows layout as a mode
    MonitorModeSwitcher.ps1 -Delete "Desk"     Delete a mode
    MonitorModeSwitcher.ps1 -Settings          Open the settings window
#>
param(
  [string]$Mode, [string]$Capture, [string]$Delete,
  [switch]$List, [switch]$Modes, [switch]$Settings, [switch]$Audio, [switch]$Toggle
)

$ErrorActionPreference = 'Stop'
$AppName = 'Monitor Mode Switcher'
$CfgPath = Join-Path $PSScriptRoot 'config.json'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Threading;
public static class MMS {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct DISPLAY_DEVICE{public int cb;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string DeviceName;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string DeviceString;public int StateFlags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string DeviceID;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string DeviceKey;}
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct DEVMODE{
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string dmDeviceName; public short dmSpecVersion,dmDriverVersion,dmSize,dmDriverExtra; public int dmFields;
    public int dmPositionX,dmPositionY,dmDisplayOrientation,dmDisplayFixedOutput; public short dmColor,dmDuplex,dmYResolution,dmTTOption,dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string dmFormName; public short dmLogPixels; public int dmBitsPerPel,dmPelsWidth,dmPelsHeight,dmDisplayFlags,dmDisplayFrequency;
    public int dmICMMethod,dmICMIntent,dmMediaType,dmDitherType,dmReserved1,dmReserved2,dmPanningWidth,dmPanningHeight;}
  [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct MONITORINFOEX{public int cb;public RECT rcMonitor;public RECT rcWork;public int dwFlags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string szDevice;}
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string a,uint i,ref DISPLAY_DEVICE d,uint f);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string d,int m,ref DEVMODE dm);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string d,ref DEVMODE dm,IntPtr h,uint f,IntPtr p);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string d,IntPtr dm,IntPtr h,uint f,IntPtr p);
  delegate bool EnumWinProc(IntPtr h,IntPtr l);
  delegate bool EnumMonProc(IntPtr m,IntPtr dc,ref RECT r,IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWinProc cb,IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc,IntPtr clip,EnumMonProc cb,IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint c);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h,int i);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h,uint f);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr m,ref MONITORINFOEX i);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int w,int hh,uint f);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int a,out int v,int s);

  public static void InitDpi(){ try{ SetProcessDpiAwarenessContext(new IntPtr(-4)); }catch{} }

  public class Disp{ public string Id,DeviceId,Dev; public bool Active,Primary; public int X,Y,W,H,Hz; }

  // All connected monitors (active or not). Id = model code from the EDID, e.g. "ACR0915".
  public static List<Disp> List(){
    InitDpi(); var res=new List<Disp>();
    for(uint i=0;i<64;i++){ var a=new DISPLAY_DEVICE(); a.cb=Marshal.SizeOf(a); if(!EnumDisplayDevices(null,i,ref a,0)) continue;
      var m=new DISPLAY_DEVICE(); m.cb=Marshal.SizeOf(m); if(!EnumDisplayDevices(a.DeviceName,0,ref m,0)||string.IsNullOrEmpty(m.DeviceID)) continue;
      var parts=m.DeviceID.Split('\\'); if(parts.Length<2) continue;
      var d=new Disp{Id=parts[1],DeviceId=m.DeviceID,Dev=a.DeviceName,Active=(a.StateFlags&1)!=0,Primary=(a.StateFlags&4)!=0};
      if(d.Active){ var dm=new DEVMODE(); dm.dmSize=(short)Marshal.SizeOf(dm);
        if(EnumDisplaySettings(a.DeviceName,-1,ref dm)){ d.X=dm.dmPositionX; d.Y=dm.dmPositionY; d.W=dm.dmPelsWidth; d.H=dm.dmPelsHeight; d.Hz=dm.dmDisplayFrequency; } }
      res.Add(d); }
    return res; }

  static int BestFreq(string dev,int w,int h){ int best=60; var dm=new DEVMODE(); dm.dmSize=(short)Marshal.SizeOf(dm);
    for(int i=0;EnumDisplaySettings(dev,i,ref dm);i++) if(dm.dmPelsWidth==w&&dm.dmPelsHeight==h&&dm.dmDisplayFrequency>best) best=dm.dmDisplayFrequency; return best; }

  static int Set(string dev,int x,int y,int w,int h,int hz,bool primary){
    var dm=new DEVMODE(); dm.dmSize=(short)Marshal.SizeOf(dm); dm.dmDeviceName=dev;
    dm.dmFields=0x20|0x80000|0x100000; dm.dmPositionX=x; dm.dmPositionY=y; dm.dmPelsWidth=w; dm.dmPelsHeight=h;
    if(w>0){ dm.dmFields|=0x400000|0x40000; dm.dmDisplayFrequency=hz>0?hz:BestFreq(dev,w,h); dm.dmBitsPerPel=32; }
    return ChangeDisplaySettingsEx(dev,ref dm,IntPtr.Zero,0x10000001u|(primary?0x10u:0u),IntPtr.Zero); }

  // ---- window tracking ----
  class Win{ public IntPtr H; public string Id; public double FX,FY,FW,FH; public bool Max,Full; }
  static MONITORINFOEX Info(IntPtr m){ var i=new MONITORINFOEX(); i.cb=Marshal.SizeOf(i); GetMonitorInfo(m,ref i); return i; }
  static List<Win> Snapshot(Dictionary<string,string> devToId){
    var list=new List<Win>();
    EnumWindows((h,l)=>{
      if(!IsWindowVisible(h)||IsIconic(h)||GetWindowTextLength(h)==0) return true;
      if(GetWindow(h,4)!=IntPtr.Zero) return true;
      if((GetWindowLong(h,-20)&0x80)!=0) return true;
      int cl; if(DwmGetWindowAttribute(h,14,out cl,4)==0&&cl!=0) return true;
      RECT r; GetWindowRect(h,out r); var mi=Info(MonitorFromWindow(h,2));
      var m=mi.rcMonitor; var wa=mi.rcWork; double ww=wa.R-wa.L, wh=wa.B-wa.T;
      string id; devToId.TryGetValue(mi.szDevice,out id);
      list.Add(new Win{H=h,Id=id,Max=IsZoomed(h),Full=r.L<=m.L&&r.T<=m.T&&r.R>=m.R&&r.B>=m.B,
        FX=(r.L-wa.L)/ww,FY=(r.T-wa.T)/wh,FW=(r.R-r.L)/ww,FH=(r.B-r.T)/wh});
      return true; },IntPtr.Zero);
    return list; }

  static Dictionary<string,MONITORINFOEX> Monitors(){
    var d=new Dictionary<string,MONITORINFOEX>();
    EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,(IntPtr m,IntPtr dc,ref RECT r,IntPtr l)=>{ var i=Info(m); d[i.szDevice]=i; return true; },IntPtr.Zero);
    return d; }

  // Windows on a monitor that is still on stay there. Windows on a monitor that was turned off go to:
  //   old primary -> new primary;  old side monitor -> a side monitor that is still on (else new primary).
  static void Restore(List<Win> wins,string oldPrimId,HashSet<string> wasActive){
    var mons=Monitors(); var idToDev=new Dictionary<string,string>(); string prim=null, side=null, sideKept=null;
    foreach(var d in List()) if(d.Active){ idToDev[d.Id]=d.Dev;
      if(d.Primary) prim=d.Dev; else { if(side==null) side=d.Dev; if(sideKept==null&&wasActive.Contains(d.Id)) sideKept=d.Dev; } }
    string sideTarget=sideKept??side??prim;
    foreach(var w in wins){
      string dev; if(w.Id==null||!idToDev.TryGetValue(w.Id,out dev)) dev=(w.Id==null||w.Id==oldPrimId)?prim:sideTarget;
      MONITORINFOEX mi; if(dev==null||!mons.TryGetValue(dev,out mi)) continue;
      RECT m=mi.rcMonitor, wa=mi.rcWork; int W=wa.R-wa.L, Hh=wa.B-wa.T;
      if(w.Full){ SetWindowPos(w.H,IntPtr.Zero,m.L,m.T,m.R-m.L,m.B-m.T,0x14); }
      else if(w.Max){ ShowWindow(w.H,9); SetWindowPos(w.H,IntPtr.Zero,wa.L+50,wa.T+50,W*2/3,Hh*2/3,0x14); ShowWindow(w.H,3); }
      else { int ww=Math.Min(W,(int)(w.FW*W)), hh=Math.Min(Hh,(int)(w.FH*Hh));
        int x=wa.L+Math.Max(0,Math.Min(W-ww,(int)(w.FX*W))), y=wa.T+Math.Max(0,Math.Min(Hh-hh,(int)(w.FY*Hh)));
        SetWindowPos(w.H,IntPtr.Zero,x,y,ww,hh,0x14); } } }

  // Apply a layout. Monitors not listed are turned off.
  public static string Apply(string[] ids,bool[] prim,int[] x,int[] y,int[] w,int[] h,int[] hz,bool move,int delay){
    var before=List(); var devToId=new Dictionary<string,string>();
    string oldPrim=null; var wasActive=new HashSet<string>();
    foreach(var d in before) if(d.Active){ devToId[d.Dev]=d.Id; wasActive.Add(d.Id); if(d.Primary) oldPrim=d.Id; }
    var wins=move?Snapshot(devToId):null;
    var used=new HashSet<string>(); int r=0;
    for(int i=0;i<ids.Length;i++){
      var d=before.Find(z=>z.Id.Equals(ids[i],StringComparison.OrdinalIgnoreCase)&&!used.Contains(z.Dev));
      if(d==null) return "Monitor not connected: "+ids[i];
      used.Add(d.Dev); r|=Set(d.Dev,x[i],y[i],w[i],h[i],hz[i],prim[i]); }
    foreach(var d in before) if(d.Active&&!used.Contains(d.Dev)) r|=Set(d.Dev,0,0,0,0,0,false);
    int c=ChangeDisplaySettingsEx(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
    if(r!=0||c!=0) return "Windows rejected the layout (code "+r+"/"+c+")";
    if(move&&wins.Count>0){ Thread.Sleep(delay); Restore(wins,oldPrim,wasActive); Thread.Sleep(1500); Restore(wins,oldPrim,wasActive); }
    return null; }

  // ---- Xbox / XInput controller ----
  [StructLayout(LayoutKind.Sequential)] struct XSTATE{ public uint Packet; public ushort Buttons; public byte LT,RT; public short LX,LY,RX,RY; }
  [DllImport("xinput1_4.dll")] static extern int XInputGetState(int i,out XSTATE s);
  // -1 = no controller. Otherwise button bits; left stick is folded into the D-pad bits
  // (Up 0x1, Down 0x2, Left 0x4, Right 0x8, Start 0x10, Back/View 0x20, A 0x1000, B 0x2000).
  public static int Pad(){
    try{ for(int i=0;i<4;i++){ XSTATE s; if(XInputGetState(i,out s)!=0) continue;
      int b=s.Buttons; if(s.LY>16000)b|=1; if(s.LY<-16000)b|=2; if(s.LX<-16000)b|=4; if(s.LX>16000)b|=8; return b; } }catch{}
    return -1; }
}
'@

# Audio output switching (Core Audio; IPolicyConfig is undocumented but used by Windows itself)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class MMSAudio {
  [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY{ public Guid fmtid; public int pid; }
  [StructLayout(LayoutKind.Explicit)] struct PROPVARIANT{ [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
  [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator{ [PreserveSig] int EnumAudioEndpoints(int flow,int mask,out IMMDeviceCollection c);
    [PreserveSig] int GetDefaultAudioEndpoint(int flow,int role,out IMMDevice d); }
  [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceCollection{ [PreserveSig] int GetCount(out int n); [PreserveSig] int Item(int i,out IMMDevice d); }
  [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice{ [PreserveSig] int Activate(ref Guid iid,int ctx,IntPtr p,[MarshalAs(UnmanagedType.IUnknown)] out object o);
    [PreserveSig] int OpenPropertyStore(int access,out IPropertyStore ps); [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }
  [ComImport,Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore{ [PreserveSig] int GetCount(out int n); [PreserveSig] int GetAt(int i,out PROPERTYKEY k); [PreserveSig] int GetValue(ref PROPERTYKEY k,out PROPVARIANT v); }
  [ComImport,Guid("f8679f50-850a-41cf-9c72-430f290290c8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPolicyConfig{ int a(); int b(); int c(); int d(); int e(); int f(); int g(); int h(); int i(); int j();
    [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id,int role); }
  [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator{}
  [ComImport,Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClient{}

  public class Dev{ public string Id,Name; public bool Default; }
  static string Name(IMMDevice d){
    IPropertyStore ps; if(d.OpenPropertyStore(0,out ps)!=0) return null;
    var k=new PROPERTYKEY{fmtid=new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),pid=14}; PROPVARIANT v;
    if(ps.GetValue(ref k,out v)!=0||v.vt!=31) return null; return Marshal.PtrToStringUni(v.p); }

  // Active playback devices
  public static List<Dev> List(){
    var res=new List<Dev>(); var en=(IMMDeviceEnumerator)new MMDeviceEnumerator();
    IMMDevice def; string defId=null; if(en.GetDefaultAudioEndpoint(0,1,out def)==0) def.GetId(out defId);
    IMMDeviceCollection col; if(en.EnumAudioEndpoints(0,1,out col)!=0) return res;
    int n; col.GetCount(out n);
    for(int i=0;i<n;i++){ IMMDevice d; col.Item(i,out d); string id; d.GetId(out id); res.Add(new Dev{Id=id,Name=Name(d),Default=id==defId}); }
    return res; }

  // Set default output (all roles) to the first device whose name contains `match`. Returns the name or null.
  public static string SetDefault(string match){
    foreach(var d in List()) if(d.Name!=null&&d.Name.IndexOf(match,StringComparison.OrdinalIgnoreCase)>=0){
      var pc=(IPolicyConfig)new PolicyConfigClient(); for(int r=0;r<3;r++) pc.SetDefaultEndpoint(d.Id,r); return d.Name; }
    return null; }
}
'@

# ---------------- config ----------------
function Get-Config {
  $c = $null
  $stamp = if (Test-Path $CfgPath) { (Get-Item $CfgPath).LastWriteTimeUtc.Ticks } else { 0 }
  if ($script:cfgCache -and $script:cfgStamp -eq $stamp) {
    return $script:cfgCache   # file unchanged since last read
  }
  if ($stamp) { $c = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  if (-not $c) { $c = [pscustomobject]@{} }
  $defaults = @{
    moveWindows = $true; settleDelayMs = 3000; modes = @()
    startupAction = 'last'      # none | last | mode
    startupMode = ''            # used when startupAction = mode
    lastMode = ''               # written automatically on every switch
    controllerPrompt = $false   # ask to switch when an Xbox controller connects
    controllerMode = ''         # mode preselected in that prompt
    controllerMenuCombo = $true # short press View+Menu on the controller opens the mode menu
    controllerHoldMode = ''     # hold View+Menu for 1 s to switch straight to this mode ('' = off)
    toggleModes = @()           # -Toggle switches between these two modes (default: the first two modes)
  }
  foreach ($k in $defaults.GetEnumerator()) {
    if (-not ($c.PSObject.Properties.Name -contains $k.Key)) { $c | Add-Member $k.Key $k.Value }
  }
  $c.modes = @($c.modes | Where-Object { $_ })
  $script:cfgCache = $c; $script:cfgStamp = $stamp
  $c
}
function Save-Config($c) { $c | ConvertTo-Json -Depth 6 | Set-Content $CfgPath -Encoding UTF8 }

function Get-Monitors {
  $names = @{}
  try {
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object {
      $id = ($_.InstanceName -split '\\')[1]
      $n = -join [char[]]($_.UserFriendlyName | Where-Object { $_ -ne 0 })
      if ($id -and $n) { $names[$id] = $n }
    }
  } catch {}
  [MMS]::List() | ForEach-Object {
    [pscustomobject][ordered]@{
      id = $_.Id; name = $(if ($names[$_.Id]) { $names[$_.Id] } else { $_.Id })
      active = $_.Active; primary = $_.Primary
      x = $_.X; y = $_.Y; width = $_.W; height = $_.H; refresh = $_.Hz
    }
  }
}

function Save-CurrentLayout([string]$name) {
  $c = Get-Config
  $disp = @(Get-Monitors | Where-Object active | ForEach-Object {
    [pscustomobject][ordered]@{ id = $_.id; name = $_.name; primary = $_.primary
      x = $_.x; y = $_.y; width = $_.width; height = $_.height; refresh = $_.refresh }
  })
  $old = $c.modes | Where-Object { $_.name -eq $name } | Select-Object -First 1
  $mode = [pscustomobject][ordered]@{ name = $name; audio = $(if ($old -and $old.audio) { $old.audio } else { '' }); displays = $disp }
  $c.modes = @($c.modes | Where-Object { $_.name -ne $name }) + $mode
  Save-Config $c
  "Saved mode '$name' with $($disp.Count) monitor(s)."
}

function Remove-Mode([string]$name) {
  $c = Get-Config; $c.modes = @($c.modes | Where-Object { $_.name -ne $name }); Save-Config $c
}

function Invoke-Mode([string]$name) {
  $c = Get-Config
  $m = $c.modes | Where-Object { $_.name -eq $name } | Select-Object -First 1
  if (-not $m) { return "Mode '$name' not found." }
  $d = @($m.displays)
  if (-not ($d | Where-Object primary)) { $d[0].primary = $true }
  $err = [MMS]::Apply(
    [string[]]($d | ForEach-Object id), [bool[]]($d | ForEach-Object { [bool]$_.primary }),
    [int[]]($d | ForEach-Object x), [int[]]($d | ForEach-Object y),
    [int[]]($d | ForEach-Object width), [int[]]($d | ForEach-Object height),
    [int[]]($d | ForEach-Object { if ($_.refresh) { $_.refresh } else { 0 } }),
    [bool]$c.moveWindows, [int]$c.settleDelayMs)
  if ($err) { return $err }
  $c = Get-Config; $c.lastMode = $name; Save-Config $c
  $msg = "Switched to '$name'."
  if ($m.audio) {
    # the HDMI audio device of a monitor that was just turned on can take a few seconds to show up
    $set = $null
    for ($i = 0; $i -lt 16 -and -not $set; $i++) { try { $set = [MMSAudio]::SetDefault($m.audio) } catch {}; if (-not $set) { Start-Sleep -Milliseconds 500 } }
    $msg += if ($set) { " Audio: $set" } else { " Audio device '$($m.audio)' not found." }
  }
  $msg
}

# ---------------- autostart ----------------
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Monitor Mode Switcher.lnk'
function Set-Autostart([bool]$on) {
  if ($on) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($StartupLnk)
    $s.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $s.Arguments = '"' + (Join-Path $PSScriptRoot 'MonitorModeSwitcher.vbs') + '"'
    $s.WorkingDirectory = $PSScriptRoot; $s.Save()
  } elseif (Test-Path $StartupLnk) { Remove-Item $StartupLnk }
}

# ---------------- CLI ----------------
if ($List)    { Get-Monitors | ConvertTo-Json -Depth 4; return }
if ($Audio)   { [MMSAudio]::List() | Select-Object Name, Default | ConvertTo-Json; return }
if ($Modes)   { (Get-Config).modes | ConvertTo-Json -Depth 6; return }
if ($Capture) { Save-CurrentLayout $Capture; return }
if ($Delete)  { Remove-Mode $Delete; "Deleted '$Delete'."; return }
if ($Mode)    { Invoke-Mode $Mode; return }
if ($Toggle) {
  $c = Get-Config; $t = @($c.toggleModes | Where-Object { $_ })
  if ($t.Count -lt 2) { $t = @($c.modes | Select-Object -First 2 | ForEach-Object name) }
  if ($t.Count -lt 2) { 'Need at least two modes to toggle.'; return }
  $target = if ($c.lastMode -eq $t[0]) { $t[1] } else { $t[0] }
  Invoke-Mode $target; return
}

# ---------------- UI ----------------
[System.Windows.Forms.Application]::EnableVisualStyles()

# Icon: two monitors with a swap arrow. Drawn at any size; icon.ico is generated next to the script.
function New-IconBitmap([int]$n) {
  $bmp = New-Object System.Drawing.Bitmap $n, $n
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $k = $n / 32.0
  $r = { param($x, $y, $w, $h) New-Object System.Drawing.RectangleF ($x * $k), ($y * $k), ($w * $k), ($h * $k) }
  $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 44, 52))
  $a = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(64, 140, 255))
  $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 95, 230))
  $g.FillRectangle($dark, (& $r 0 3 20 14)); $g.FillRectangle($a, (& $r 1.5 4.5 17 11)); $g.FillRectangle($dark, (& $r 8 17 4 3))
  $g.FillRectangle($dark, (& $r 12 12 20 14)); $g.FillRectangle($b, (& $r 13.5 13.5 17 11)); $g.FillRectangle($dark, (& $r 20 26 4 3))
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([Math]::Max(1.5, 2.2 * $k))
  $pen.EndCap = 'ArrowAnchor'; $pen.StartCap = 'Round'
  $g.DrawArc($pen, (& $r 5 6 14 14), 200, 120)
  $g.Dispose(); $bmp
}
function Save-IconFile([string]$path) {
  $sizes = 16, 24, 32, 48, 64, 256; $pngs = foreach ($n in $sizes) { $ms = New-Object IO.MemoryStream; (New-IconBitmap $n).Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); , $ms.ToArray() }
  $out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $out
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
  $off = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$sz); $w.Write([byte]$sz); $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$off); $off += $pngs[$i].Length
  }
  foreach ($p in $pngs) { $w.Write($p) }
  [IO.File]::WriteAllBytes($path, $out.ToArray())
}
function New-TrayIcon {
  $ico = Join-Path $PSScriptRoot 'icon.ico'
  try { if (-not (Test-Path $ico)) { Save-IconFile $ico } } catch {}   # .ico for shortcuts; tray uses the bitmap directly
  [System.Drawing.Icon]::FromHandle((New-IconBitmap 32).GetHicon())
}

function Show-Settings {
  $f = New-Object System.Windows.Forms.Form
  $f.Text = "$AppName - Settings"; $f.ClientSize = New-Object System.Drawing.Size(460, 420)
  $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.StartPosition = 'CenterScreen'
  $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $f.Icon = $script:icon

  $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = 'Modes'; $lbl.SetBounds(12, 10, 200, 18); $f.Controls.Add($lbl)
  $lb = New-Object System.Windows.Forms.ListBox; $lb.SetBounds(12, 30, 280, 160); $f.Controls.Add($lb)
  $info = New-Object System.Windows.Forms.Label; $info.SetBounds(12, 196, 286, 64); $info.ForeColor = [System.Drawing.Color]::DimGray; $f.Controls.Add($info)

  # per-mode audio output
  $la = New-Object System.Windows.Forms.Label; $la.Text = 'Audio output for this mode:'; $la.SetBounds(302, 200, 146, 18); $f.Controls.Add($la)
  $cbAudio = New-Object System.Windows.Forms.ComboBox; $cbAudio.DropDownStyle = 'DropDownList'; $cbAudio.SetBounds(302, 220, 146, 24)
  $cbAudio.DropDownWidth = 380; $f.Controls.Add($cbAudio)
  $script:audioLoading = $false
  $cbAudio.Add_SelectedIndexChanged({
    if ($script:audioLoading -or -not $lb.SelectedItem) { return }
    $c = Get-Config; $mm = $c.modes | Where-Object { $_.name -eq $lb.SelectedItem } | Select-Object -First 1
    $val = if ($cbAudio.SelectedIndex -le 0) { '' } else { [string]$cbAudio.SelectedItem -replace '^\d+ - ', '' }  # "1 - " prefix can change
    if ($mm.PSObject.Properties.Name -contains 'audio') { $mm.audio = $val } else { $mm | Add-Member audio $val }
    Save-Config $c
  })

  $refresh = {
    $sel = $lb.SelectedItem; $lb.Items.Clear()
    foreach ($m in (Get-Config).modes) { [void]$lb.Items.Add($m.name) }
    if ($sel -and $lb.Items.Contains($sel)) { $lb.SelectedItem = $sel } elseif ($lb.Items.Count) { $lb.SelectedIndex = 0 }
  }
  $lb.Add_SelectedIndexChanged({
    $m = (Get-Config).modes | Where-Object { $_.name -eq $lb.SelectedItem } | Select-Object -First 1
    $info.Text = if ($m) { ($m.displays | ForEach-Object { "$($_.name)  $($_.width)x$($_.height) @ $($_.x),$($_.y)$(if($_.primary){'  [primary]'})" }) -join "`n" } else { '' }
    $script:audioLoading = $true; $cbAudio.Items.Clear(); [void]$cbAudio.Items.Add('(don''t change)')
    $names = @(try { [MMSAudio]::List() | ForEach-Object Name } catch { })
    if ($m -and $m.audio -and -not ($names | Where-Object { $_ -like "*$($m.audio)*" })) { $names += $m.audio }
    foreach ($n in $names) { [void]$cbAudio.Items.Add($n) }
    $cbAudio.SelectedIndex = 0
    if ($m -and $m.audio) { for ($i = 1; $i -lt $cbAudio.Items.Count; $i++) { if ($cbAudio.Items[$i] -like "*$($m.audio)*") { $cbAudio.SelectedIndex = $i; break } } }
    $script:audioLoading = $false
  })

  $btn = { param($t, $y, $a) $b = New-Object System.Windows.Forms.Button; $b.Text = $t; $b.SetBounds(302, $y, 146, 28); $b.Add_Click($a); $f.Controls.Add($b) }
  & $btn 'Switch to selected' 30 { if ($lb.SelectedItem) { [System.Windows.Forms.MessageBox]::Show((Invoke-Mode $lb.SelectedItem), $AppName) | Out-Null } }
  & $btn 'Save current as new...' 64 {
    $n = [Microsoft.VisualBasic.Interaction]::InputBox("Arrange your monitors in Windows display settings first.`nName for this mode:", $AppName, 'New mode')
    if ($n) { Save-CurrentLayout $n | Out-Null; & $refresh; $lb.SelectedItem = $n }
  }
  & $btn 'Overwrite with current' 98 { if ($lb.SelectedItem) { Save-CurrentLayout $lb.SelectedItem | Out-Null; & $refresh } }
  & $btn 'Rename...' 132 {
    if (-not $lb.SelectedItem) { return }
    $n = [Microsoft.VisualBasic.Interaction]::InputBox('New name:', $AppName, $lb.SelectedItem)
    if ($n) { $c = Get-Config; $old = $lb.SelectedItem; ($c.modes | Where-Object { $_.name -eq $old }).name = $n
      foreach ($k in 'lastMode', 'startupMode', 'controllerMode') { if ($c.$k -eq $old) { $c.$k = $n } }
      Save-Config $c; & $refresh; $lb.SelectedItem = $n }
  }
  & $btn 'Delete' 166 { if ($lb.SelectedItem) { Remove-Mode $lb.SelectedItem; & $refresh } }

  $c = Get-Config
  $cbMove = New-Object System.Windows.Forms.CheckBox; $cbMove.Text = 'Move windows to the new monitors when switching'
  $cbMove.SetBounds(12, 266, 436, 22); $cbMove.Checked = [bool]$c.moveWindows; $f.Controls.Add($cbMove)
  $cbAuto = New-Object System.Windows.Forms.CheckBox; $cbAuto.Text = 'Start with Windows'
  $cbAuto.SetBounds(12, 292, 436, 22); $cbAuto.Checked = (Test-Path $StartupLnk); $f.Controls.Add($cbAuto)
  $l2 = New-Object System.Windows.Forms.Label; $l2.Text = 'Wait after switching before moving windows (ms):'; $l2.SetBounds(12, 322, 300, 20); $f.Controls.Add($l2)
  $nd = New-Object System.Windows.Forms.NumericUpDown; $nd.SetBounds(312, 320, 80, 22); $nd.Minimum = 500; $nd.Maximum = 15000; $nd.Increment = 500
  $nd.Value = [Math]::Min(15000, [Math]::Max(500, [int]$c.settleDelayMs)); $f.Controls.Add($nd)

  $modeNames = @($c.modes | ForEach-Object name)
  $newCombo = { param($x, $y, $w, $sel) $cb = New-Object System.Windows.Forms.ComboBox; $cb.DropDownStyle = 'DropDownList'; $cb.SetBounds($x, $y, $w, 24)
    foreach ($n in $modeNames) { [void]$cb.Items.Add($n) }; if ($sel -and $cb.Items.Contains($sel)) { $cb.SelectedItem = $sel } elseif ($cb.Items.Count) { $cb.SelectedIndex = 0 }
    $f.Controls.Add($cb); $cb }

  $l3 = New-Object System.Windows.Forms.Label; $l3.Text = 'On start (after boot):'; $l3.SetBounds(12, 356, 140, 20); $f.Controls.Add($l3)
  $cbStart = New-Object System.Windows.Forms.ComboBox; $cbStart.DropDownStyle = 'DropDownList'; $cbStart.SetBounds(152, 352, 150, 24)
  [void]$cbStart.Items.AddRange(@('Do nothing', 'Restore last mode', 'Always use:')); $f.Controls.Add($cbStart)
  $cbStart.SelectedIndex = switch ($c.startupAction) { 'none' { 0 } 'mode' { 2 } default { 1 } }
  $cbStartMode = & $newCombo 308 352 140 $c.startupMode
  $cbStartMode.Enabled = ($cbStart.SelectedIndex -eq 2); $cbStart.Add_SelectedIndexChanged({ $cbStartMode.Enabled = ($cbStart.SelectedIndex -eq 2) })

  $cbPad = New-Object System.Windows.Forms.CheckBox; $cbPad.Text = 'When an Xbox controller connects, ask to switch to:'
  $cbPad.SetBounds(12, 388, 300, 22); $cbPad.Checked = [bool]$c.controllerPrompt; $f.Controls.Add($cbPad)
  $cbPadMode = & $newCombo 308 386 140 $c.controllerMode
  $cbCombo = New-Object System.Windows.Forms.CheckBox; $cbCombo.Text = 'Controller: tap View + Menu to open the mode menu'
  $cbCombo.SetBounds(12, 414, 436, 22); $cbCombo.Checked = [bool]$c.controllerMenuCombo; $f.Controls.Add($cbCombo)
  $cbHold = New-Object System.Windows.Forms.CheckBox; $cbHold.Text = 'Hold View + Menu (1 s) to switch to:'
  $cbHold.SetBounds(12, 440, 290, 22); $cbHold.Checked = [bool]$c.controllerHoldMode; $f.Controls.Add($cbHold)
  $cbHoldMode = & $newCombo 308 438 140 $c.controllerHoldMode

  $open = New-Object System.Windows.Forms.LinkLabel; $open.Text = 'Open config.json'; $open.SetBounds(12, 490, 200, 20)
  $open.Add_Click({ if (-not (Test-Path $CfgPath)) { Save-Config (Get-Config) }; Start-Process notepad.exe $CfgPath }); $f.Controls.Add($open)
  $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Save && Close'; $ok.SetBounds(332, 484, 116, 30); $f.Controls.Add($ok)
  $f.ClientSize = New-Object System.Drawing.Size(460, 526)
  $ok.Add_Click({
    $c = Get-Config; $c.moveWindows = $cbMove.Checked; $c.settleDelayMs = [int]$nd.Value
    $c.startupAction = @('none', 'last', 'mode')[$cbStart.SelectedIndex]; $c.startupMode = [string]$cbStartMode.SelectedItem
    $c.controllerPrompt = $cbPad.Checked; $c.controllerMode = [string]$cbPadMode.SelectedItem; $c.controllerMenuCombo = $cbCombo.Checked
    $c.controllerHoldMode = if ($cbHold.Checked) { [string]$cbHoldMode.SelectedItem } else { '' }
    Save-Config $c
    Set-Autostart $cbAuto.Checked; $f.Close()
  })
  $f.AcceptButton = $ok
  & $refresh
  [void]$f.ShowDialog()
}
Add-Type -AssemblyName Microsoft.VisualBasic

$script:icon = New-TrayIcon
if ($Settings) { Show-Settings; return }

# single instance
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MonitorModeSwitcherTray', [ref]$created)
if (-not $created) { [System.Windows.Forms.MessageBox]::Show("$AppName is already running in the tray.", $AppName) | Out-Null; return }

# ---- controller-friendly mode picker (mouse, keyboard or Xbox controller) ----
function Show-ModePicker([string]$title, [string]$preselect) {
  $modes = @((Get-Config).modes | ForEach-Object name)
  if (-not $modes) { return $null }
  $f = New-Object System.Windows.Forms.Form
  $f.FormBorderStyle = 'None'; $f.TopMost = $true; $f.StartPosition = 'CenterScreen'; $f.ShowInTaskbar = $false
  $f.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28); $f.KeyPreview = $true
  $rowH = 64; $f.ClientSize = New-Object System.Drawing.Size(520, (110 + ($modes.Count + 1) * ($rowH + 8)))
  $t = New-Object System.Windows.Forms.Label; $t.Text = $title; $t.ForeColor = [System.Drawing.Color]::White
  $t.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold); $t.SetBounds(24, 18, 472, 40); $f.Controls.Add($t)
  $h = New-Object System.Windows.Forms.Label; $h.Text = 'Controller: up/down + A to confirm, B to cancel'
  $h.ForeColor = [System.Drawing.Color]::Gray; $h.Font = New-Object System.Drawing.Font('Segoe UI', 10); $h.SetBounds(24, 58, 472, 24); $f.Controls.Add($h)
  $items = @($modes) + 'Cancel'
  $btns = @()
  for ($i = 0; $i -lt $items.Count; $i++) {
    $b = New-Object System.Windows.Forms.Label; $b.Text = $items[$i]; $b.TextAlign = 'MiddleCenter'
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 15); $b.ForeColor = [System.Drawing.Color]::White
    $b.SetBounds(24, (92 + $i * ($rowH + 8)), 472, $rowH); $b.Tag = $i; $b.Cursor = 'Hand'
    $b.Add_Click({ param($s) $script:pick = $s.Tag; $f.Close() })
    $f.Controls.Add($b); $btns += $b
  }
  $script:sel = [Math]::Max(0, [array]::IndexOf($modes, $preselect)); $script:pick = -1
  $paint = { for ($i = 0; $i -lt $btns.Count; $i++) {
      $btns[$i].BackColor = if ($i -eq $script:sel) { [System.Drawing.Color]::FromArgb(45, 120, 220) } else { [System.Drawing.Color]::FromArgb(48, 48, 56) } } }
  & $paint
  $move = { param($d) $script:sel = ($script:sel + $d + $btns.Count) % $btns.Count; & $paint }
  $f.Add_KeyDown({ param($s, $e)
    switch ($e.KeyCode) { 'Up' { & $move -1 } 'Down' { & $move 1 } 'Enter' { $script:pick = $script:sel; $f.Close() } 'Escape' { $f.Close() } } })
  $script:prevPad = [MMS]::Pad()
  $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 50
  $tm.Add_Tick({
    $p = [MMS]::Pad(); if ($p -lt 0) { return }
    $new = $p -band (-bnot [Math]::Max(0, $script:prevPad)); $script:prevPad = $p
    if ($new -band 0x1) { & $move -1 }; if ($new -band 0x2) { & $move 1 }
    if ($new -band 0x1000) { $script:pick = $script:sel; $f.Close() }
    if ($new -band 0x2000) { $f.Close() }
  })
  $f.Add_Shown({ $f.Activate(); $tm.Start() }); $f.Add_FormClosed({ $tm.Stop() })
  [void]$f.ShowDialog()
  if ($script:pick -ge 0 -and $script:pick -lt $modes.Count) { $modes[$script:pick] } else { $null }
}

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $script:icon; $ni.Text = $AppName; $ni.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Add_Opening({
  $menu.Items.Clear()
  $cfgM = Get-Config; $modes = $cfgM.modes
  if (-not $modes) { $i = $menu.Items.Add('(no modes yet - open Settings)'); $i.Enabled = $false }
  foreach ($m in $modes) {
    $it = $menu.Items.Add($m.name); $it.Tag = $m.name; $it.Checked = ($m.name -eq $cfgM.lastMode)
    $it.Add_Click({ param($s) $r = Invoke-Mode $s.Tag; $ni.ShowBalloonTip(2500, $AppName, $r, 'Info') })
  }
  [void]$menu.Items.Add('-')
  [void]$menu.Items.Add('Settings...', $null, { Show-Settings })
  [void]$menu.Items.Add('Exit', $null, { $ni.Visible = $false; [System.Windows.Forms.Application]::Exit() })
  $_.Cancel = $false
})
[void]$menu.Items.Add('...')   # placeholder so Opening fires
$ni.ContextMenuStrip = $menu
$ni.Add_MouseClick({ param($s, $e)
  if ($e.Button -eq 'Left') { $mi = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic'); $mi.Invoke($ni, $null) }
})
function Switch-WithTip([string]$m) { $ni.ShowBalloonTip(2500, $AppName, (Invoke-Mode $m), 'Info') }

$cfg0 = Get-Config
if (-not $cfg0.modes) { $ni.ShowBalloonTip(4000, $AppName, 'No modes yet. Right-click the tray icon > Settings to save your first layout.', 'Info') }

# Startup: restore last mode or a fixed default mode
$startMode = switch ($cfg0.startupAction) { 'last' { $cfg0.lastMode } 'mode' { $cfg0.startupMode } default { '' } }
if ($startMode -and ($cfg0.modes | Where-Object { $_.name -eq $startMode })) {
  $st = New-Object System.Windows.Forms.Timer; $st.Interval = 2000
  $st.Add_Tick({ $st.Stop(); Switch-WithTip $startMode }); $st.Start()
}

# Controller watcher: prompt on connect, View+Menu opens the picker
$script:padWas = ([MMS]::Pad() -ge 0); $script:padPrev = 0; $script:busy = $false
$pt = New-Object System.Windows.Forms.Timer; $pt.Interval = 200
$pt.Add_Tick({
  if ($script:busy) { return }
  $p = [MMS]::Pad(); $c = Get-Config; $choice = $null; $ask = $false; $title = ''
  if ($p -ge 0 -and -not $script:padWas -and $c.controllerPrompt -and $c.controllerMode -and $c.lastMode -ne $c.controllerMode) {
    $ask = $true; $title = 'Controller connected - switch mode?'
  }
  # View + Menu: hold 1 s = switch straight to controllerHoldMode, short press = open the menu
  $combo = ($p -ge 0) -and (($p -band 0x30) -eq 0x30)
  if ($combo -and -not $script:holdStart) { $script:holdStart = [DateTime]::Now; $script:holdDone = $false }
  if ($combo -and -not $script:holdDone -and $c.controllerHoldMode -and ([DateTime]::Now - $script:holdStart).TotalMilliseconds -ge 1000) {
    $script:holdDone = $true; $script:busy = $true; Switch-WithTip $c.controllerHoldMode; $script:busy = $false
  }
  if (-not $combo -and $script:holdStart) {
    if (-not $script:holdDone -and $c.controllerMenuCombo) { $ask = $true; $title = 'Switch monitor mode' }
    $script:holdStart = $null
  }
  $script:padWas = ($p -ge 0); $script:padPrev = [Math]::Max(0, $p)
  if ($ask) {
    $script:busy = $true
    $pre = if ($c.controllerMode) { $c.controllerMode } else { $c.lastMode }
    $choice = Show-ModePicker $title $pre
    $script:padPrev = [Math]::Max(0, [MMS]::Pad())
    if ($choice) { Switch-WithTip $choice }
    $script:busy = $false
  }
})
$pt.Start()

[System.Windows.Forms.Application]::Run()
$ni.Dispose(); $mutex.ReleaseMutex()
