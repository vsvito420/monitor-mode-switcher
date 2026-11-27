<#
  Monitor Mode Switcher - zwischen gespeicherten Monitor-Layouts per Infobereich-Symbol umschalten.
  Fenster auf einem Monitor, der ausgeschaltet wird, wandern auf einen Monitor, der an bleibt.

  Aufruf:
    MonitorModeSwitcher.ps1                    Tray-App starten
    MonitorModeSwitcher.ps1 -List              Angeschlossene Monitore als JSON
    MonitorModeSwitcher.ps1 -Modes             Gespeicherte Modi als JSON
    MonitorModeSwitcher.ps1 -Audio             Audio-Ausgabegeräte als JSON
    MonitorModeSwitcher.ps1 -Mode "Desk"       Auf einen Modus umschalten
    MonitorModeSwitcher.ps1 -Toggle            Zwischen den beiden Umschalt-Modi wechseln
    MonitorModeSwitcher.ps1 -Capture "Desk"    Aktuelles Windows-Layout als Modus speichern
    MonitorModeSwitcher.ps1 -Delete "Desk"     Modus löschen
    MonitorModeSwitcher.ps1 -Settings          Einstellungsfenster öffnen
#>
param(
  [string]$Mode, [string]$Capture, [string]$Delete,
  [switch]$List, [switch]$Modes, [switch]$Settings, [switch]$Audio, [switch]$Toggle
)

$ErrorActionPreference = 'Stop'
$AppName = 'Monitor Mode Switcher'
$AppVersion = '1.2.0'
$CfgPath = Join-Path $PSScriptRoot 'config.json'
$LogPath = Join-Path $env:APPDATA 'MonitorModeSwitcher\log.txt'

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

  // Alle angeschlossenen Monitore (aktiv oder nicht). Id = Modell-Code aus dem EDID, z. B. "ACR0915".
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

  // ---- Fenster mitnehmen ----
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
      if(ww<=0||wh<=0) return true;
      string id; devToId.TryGetValue(mi.szDevice,out id);
      list.Add(new Win{H=h,Id=id,Max=IsZoomed(h),Full=r.L<=m.L&&r.T<=m.T&&r.R>=m.R&&r.B>=m.B,
        FX=(r.L-wa.L)/ww,FY=(r.T-wa.T)/wh,FW=(r.R-r.L)/ww,FH=(r.B-r.T)/wh});
      return true; },IntPtr.Zero);
    return list; }

  static Dictionary<string,MONITORINFOEX> Monitors(){
    var d=new Dictionary<string,MONITORINFOEX>();
    EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,(IntPtr m,IntPtr dc,ref RECT r,IntPtr l)=>{ var i=Info(m); d[i.szDevice]=i; return true; },IntPtr.Zero);
    return d; }

  // Fenster auf einem Monitor, der an bleibt, bleiben dort. Fenster auf einem ausgeschalteten Monitor gehen:
  //   alter Hauptmonitor -> neuer Hauptmonitor;  alter Seitenmonitor -> ein Seitenmonitor, der an bleibt (sonst Hauptmonitor).
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

  // ---- Fensterpositionen pro Modus merken ----
  [StructLayout(LayoutKind.Sequential)] struct POINT{public int X,Y;}
  [StructLayout(LayoutKind.Sequential)] struct WINDOWPLACEMENT{public int length,flags,showCmd; public POINT min,max; public RECT normal;}
  [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h,ref WINDOWPLACEMENT p);
  [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h,ref WINDOWPLACEMENT p);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  static bool Normal(IntPtr h){
    if(!IsWindowVisible(h)||GetWindowTextLength(h)==0) return false;
    if(GetWindow(h,4)!=IntPtr.Zero) return false;
    if((GetWindowLong(h,-20)&0x80)!=0) return false;
    int cl; if(DwmGetWindowAttribute(h,14,out cl,4)==0&&cl!=0) return false;
    return true; }
  // Eine Zeile pro Fenster: "hwnd flags showCmd L T R B" (normale Position + maximiert/minimiert)
  public static string[] CaptureWindows(){
    InitDpi(); var res=new List<string>();
    EnumWindows((h,l)=>{ if(!Normal(h)) return true;
      var p=new WINDOWPLACEMENT(); p.length=Marshal.SizeOf(p); if(!GetWindowPlacement(h,ref p)) return true;
      res.Add(h.ToInt64()+" "+p.flags+" "+p.showCmd+" "+p.normal.L+" "+p.normal.T+" "+p.normal.R+" "+p.normal.B);
      return true; },IntPtr.Zero);
    return res.ToArray(); }
  // Fenster, die es noch gibt, an ihre gemerkte Stelle setzen. Liefert die Anzahl.
  public static int PlaceWindows(string[] lines){
    InitDpi(); int n=0;
    foreach(var s in lines){ var a=s.Split(' '); long hv; if(a.Length<7||!long.TryParse(a[0],out hv)) continue;
      var h=new IntPtr(hv); if(!IsWindow(h)||!Normal(h)) continue;
      var p=new WINDOWPLACEMENT(); p.length=Marshal.SizeOf(p); if(!GetWindowPlacement(h,ref p)) continue;
      int show=int.Parse(a[2]); bool max=show==3, min=IsIconic(h);
      p.flags=int.Parse(a[1])&2; // nur WPF_RESTORETOMAXIMIZED übernehmen
      p.normal=new RECT{L=int.Parse(a[3]),T=int.Parse(a[4]),R=int.Parse(a[5]),B=int.Parse(a[6])};
      p.showCmd=min?7:4;  // jetzt minimiert bleibt minimiert; sonst normal ohne Aktivieren
      if(!SetWindowPlacement(h,ref p)) continue;
      if(max&&!min) ShowWindow(h,3);
      n++; }
    return n; }

  // Layout anwenden. Nicht aufgeführte Monitore werden ausgeschaltet.
  public static string Apply(string[] ids,bool[] prim,int[] x,int[] y,int[] w,int[] h,int[] hz,bool move,int delay){
    var before=List(); var devToId=new Dictionary<string,string>();
    string oldPrim=null; var wasActive=new HashSet<string>();
    foreach(var d in before) if(d.Active){ devToId[d.Dev]=d.Id; wasActive.Add(d.Id); if(d.Primary) oldPrim=d.Id; }
    var used=new HashSet<string>(); var devs=new string[ids.Length];
    // Erst prüfen, ob alle Monitore da sind - dann erst etwas ändern
    for(int i=0;i<ids.Length;i++){
      var d=before.Find(z=>z.Id.Equals(ids[i],StringComparison.OrdinalIgnoreCase)&&!used.Contains(z.Dev));
      if(d==null) return "Monitor nicht angeschlossen: "+ids[i];
      used.Add(d.Dev); devs[i]=d.Dev; }
    var wins=move?Snapshot(devToId):null; int r=0;
    for(int i=0;i<ids.Length;i++) r|=Set(devs[i],x[i],y[i],w[i],h[i],hz[i],prim[i]);
    foreach(var d in before) if(d.Active&&!used.Contains(d.Dev)) r|=Set(d.Dev,0,0,0,0,0,false);
    int c=ChangeDisplaySettingsEx(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
    if(r!=0||c!=0) return "Windows hat das Layout abgelehnt (Code "+r+"/"+c+")";
    if(move&&wins.Count>0){ Thread.Sleep(delay); Restore(wins,oldPrim,wasActive); Thread.Sleep(1500); Restore(wins,oldPrim,wasActive); }
    return null; }

  // ---- Xbox / XInput-Controller ----
  [StructLayout(LayoutKind.Sequential)] struct XSTATE{ public uint Packet; public ushort Buttons; public byte LT,RT; public short LX,LY,RX,RY; }
  [DllImport("xinput1_4.dll")] static extern int XInputGetState(int i,out XSTATE s);
  // -1 = kein Controller. Sonst Tasten-Bits; der linke Stick wird auf die Steuerkreuz-Bits gelegt
  // (Hoch 0x1, Runter 0x2, Links 0x4, Rechts 0x8, Start 0x10, Back/Ansicht 0x20, A 0x1000, B 0x2000).
  public static int Pad(){
    try{ for(int i=0;i<4;i++){ XSTATE s; if(XInputGetState(i,out s)!=0) continue;
      int b=s.Buttons; if(s.LY>16000)b|=1; if(s.LY<-16000)b|=2; if(s.LX<-16000)b|=4; if(s.LX>16000)b|=8; return b; } }catch{}
    return -1; }
}
'@

# Audio-Ausgabe umschalten (Core Audio; IPolicyConfig ist undokumentiert, wird aber von Windows selbst benutzt)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class MMSAudio {
  [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY{ public Guid fmtid; public int pid; }
  [StructLayout(LayoutKind.Explicit)] struct PROPVARIANT{ [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
  [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT v);
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
    IPropertyStore ps; if(d.OpenPropertyStore(0,out ps)!=0||ps==null) return null;
    var k=new PROPERTYKEY{fmtid=new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),pid=14}; PROPVARIANT v;
    if(ps.GetValue(ref k,out v)!=0) return null;
    string n=v.vt==31&&v.p!=IntPtr.Zero?Marshal.PtrToStringUni(v.p):null;
    PropVariantClear(ref v);   // gibt den String frei - die Liste wird alle 2 s abgefragt
    return n; }

  // Aktive Wiedergabegeräte
  public static List<Dev> List(){
    var res=new List<Dev>(); var en=(IMMDeviceEnumerator)new MMDeviceEnumerator();
    IMMDevice def; string defId=null; if(en.GetDefaultAudioEndpoint(0,1,out def)==0&&def!=null) def.GetId(out defId);
    IMMDeviceCollection col; if(en.EnumAudioEndpoints(0,1,out col)!=0||col==null) return res;
    int n; if(col.GetCount(out n)!=0) return res;
    for(int i=0;i<n;i++){ IMMDevice d; if(col.Item(i,out d)!=0||d==null) continue; string id; if(d.GetId(out id)!=0) continue;
      res.Add(new Dev{Id=id,Name=Name(d),Default=id==defId}); }
    return res; }

  // Standardausgabe (alle Rollen) auf das erste Gerät setzen, dessen Name `match` enthält. Gibt den Namen zurück oder null.
  public static string SetDefault(string match){
    foreach(var d in List()) if(d.Name!=null&&d.Name.IndexOf(match,StringComparison.OrdinalIgnoreCase)>=0){
      var pc=(IPolicyConfig)new PolicyConfigClient(); for(int r=0;r<3;r++) pc.SetDefaultEndpoint(d.Id,r); return d.Name; }
    return null; }
}
'@

# ---------------- Log ----------------
# %APPDATA%\MonitorModeSwitcher\log.txt (wie bei den anderen Tools in C:\Tools)
function Write-Log([string]$text) {
  try {
    $dir = Split-Path $LogPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 256KB) { Remove-Item $LogPath -Force }
    [IO.File]::AppendAllText($LogPath, ('{0:yyyy-MM-dd HH:mm:ss.fff}  {1}' -f (Get-Date), $text) + "`r`n", [Text.Encoding]::UTF8)
  } catch {}
}

# ---------------- Konfiguration ----------------
function Get-Config {
  $c = $null
  $stamp = if (Test-Path $CfgPath) { (Get-Item $CfgPath).LastWriteTimeUtc.Ticks } else { 0 }
  if ($script:cfgCache -and ($script:cfgStamp -eq $stamp -or $script:cfgBadStamp -eq $stamp)) {
    return $script:cfgCache   # Datei unverändert (oder kaputt und schon gemeldet)
  }
  if ($stamp) {
    try { $c = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
      # z. B. gerade halb geschrieben oder von Hand falsch bearbeitet: mit dem letzten guten Stand weitermachen
      if ($script:cfgBadStamp -ne $stamp) { Write-Log "config.json ist fehlerhaft: $($_.Exception.Message)" }
      $script:cfgBadStamp = $stamp
      if ($script:cfgCache) { return $script:cfgCache }
      throw "config.json ist fehlerhaft: $($_.Exception.Message)"
    }
  }
  if (-not $c) { $c = [pscustomobject]@{} }
  $defaults = @{
    moveWindows = $true; settleDelayMs = 3000; modes = @()
    rememberWindows = $true     # Fensterpositionen pro Modus merken und beim Zurückwechseln wiederherstellen
    startupAction = 'last'      # none | last | mode
    startupMode = ''            # wird bei startupAction = mode benutzt
    lastMode = ''               # wird bei jedem Umschalten automatisch geschrieben
    lastSwitch = 0              # Zeitpunkt des letzten Umschaltens (UTC-Ticks), automatisch
    controllerPrompt = $false   # beim Verbinden eines Xbox-Controllers fragen, ob umgeschaltet werden soll
    controllerMode = ''         # in dieser Abfrage vorausgewählter Modus
    controllerViewA = ''        # Ansicht halten + 2x A schaltet auf diesen Modus ('' = aus)
    controllerViewB = ''        # Ansicht halten + 2x B schaltet auf diesen Modus ('' = aus)
    toggleModes = @()           # -Toggle wechselt zwischen diesen zwei Modi (Standard: die ersten zwei)
    toggleHotkey = 'Ctrl+#'     # globales Tastenkürzel zum Umschalten, solange die Tray-App läuft ('' = aus)
  }
  foreach ($k in $defaults.GetEnumerator()) {
    if (-not ($c.PSObject.Properties.Name -contains $k.Key)) { $c | Add-Member $k.Key $k.Value }
  }
  $c.modes = @($c.modes | Where-Object { $_ })
  $script:cfgCache = $c; $script:cfgStamp = $stamp; $script:cfgBadStamp = $null
  $c
}

# Erst in eine Temp-Datei schreiben und dann ersetzen: so liest ein zweiter Prozess (Toggle.vbs, CLI)
# nie eine halb geschriebene config.json.
function Save-Config($c) {
  $json = $c | ConvertTo-Json -Depth 6
  $tmp = "$CfgPath.tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $true))
  try {
    if (Test-Path $CfgPath) { [IO.File]::Replace($tmp, $CfgPath, $null) } else { [IO.File]::Move($tmp, $CfgPath) }
  } catch { Move-Item $tmp $CfgPath -Force }
}

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
  Write-Log "Modus '$name' gespeichert ($($disp.Count) Monitor(e))"
  "Modus '$name' mit $($disp.Count) Monitor(en) gespeichert."
}

# Verweise auf einen Modus in den Einstellungen umbenennen ($new) oder entfernen ($new = '')
function Update-ModeRefs($c, [string]$old, [string]$new) {
  foreach ($k in 'lastMode', 'startupMode', 'controllerMode', 'controllerViewA', 'controllerViewB') { if ($c.$k -eq $old) { $c.$k = $new } }
  $c.toggleModes = @($c.toggleModes | ForEach-Object { if ($_ -eq $old) { $new } else { $_ } } | Where-Object { $_ })
}

function Rename-Mode([string]$old, [string]$new) {
  $c = Get-Config
  if ($old -eq $new) { return $null }
  if ($c.modes | Where-Object { $_.name -eq $new }) { return "Es gibt schon einen Modus '$new'." }
  $m = $c.modes | Where-Object { $_.name -eq $old } | Select-Object -First 1
  if (-not $m) { return "Modus '$old' nicht gefunden." }
  $m.name = $new; Update-ModeRefs $c $old $new; Save-Config $c
  Write-Log "Modus '$old' umbenannt in '$new'"
  $null
}

function Remove-Mode([string]$name) {
  $c = Get-Config; $c.modes = @($c.modes | Where-Object { $_.name -ne $name }); Update-ModeRefs $c $name ''; Save-Config $c
  Write-Log "Modus '$name' gelöscht"
}

# Gemerkte Fensterpositionen pro Modus (Fenster-Handles gelten nur bis zur Abmeldung - veraltete werden übersprungen)
$WinPath = Join-Path (Split-Path $LogPath) 'windows.json'
function Get-WindowLayout([string]$mode) {
  if (-not (Test-Path $WinPath)) { return @() }
  try { $all = Get-Content $WinPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return @() }
  @($all.$mode | Where-Object { $_ })
}
function Save-WindowLayout([string]$mode, [string[]]$lines) {
  $all = $null
  if (Test-Path $WinPath) { try { $all = Get-Content $WinPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
  if (-not $all) { $all = [pscustomobject]@{} }
  $all | Add-Member -NotePropertyName $mode -NotePropertyValue @($lines) -Force
  New-Item -ItemType Directory -Force (Split-Path $WinPath) | Out-Null
  [IO.File]::WriteAllText($WinPath, ($all | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
}

function Invoke-Mode([string]$name) {
  # Nur eine Umschaltung gleichzeitig - auch über Prozesse hinweg (Tray, Toggle.vbs, CLI)
  $lock = New-Object System.Threading.Mutex($false, 'Local\MonitorModeSwitcherSwitch')
  $got = $false
  try { $got = $lock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
  if (-not $got) { $lock.Dispose(); return 'Es läuft gerade schon eine Umschaltung.' }
  try {
    $c = Get-Config
    $m = $c.modes | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $m) { return "Modus '$name' nicht gefunden." }
    $d = @($m.displays | Where-Object { $_ })
    if (-not $d) { return "Modus '$name' enthält keine Monitore." }
    # Fensterpositionen des bisherigen Modus merken - nur wenn gerade wirklich dessen Monitore an sind
    $remember = [bool]$c.rememberWindows
    if ($remember -and $c.lastMode -and $c.lastMode -ne $name) {
      $cur = $c.modes | Where-Object { $_.name -eq $c.lastMode } | Select-Object -First 1
      $want = @($cur.displays | ForEach-Object id | Sort-Object) -join ','
      $have = @([MMS]::List() | Where-Object Active | ForEach-Object Id | Sort-Object) -join ','
      if ($cur -and $want -eq $have) { Save-WindowLayout $c.lastMode ([MMS]::CaptureWindows()) }
    }
    $c.lastSwitch = [DateTime]::UtcNow.Ticks; Save-Config $c   # Audio-Wechsel während des Umschaltens sind keine Nutzerwahl
    $prim = [bool[]]($d | ForEach-Object { [bool]$_.primary })
    if ($prim -notcontains $true) { $prim[0] = $true }
    $err = [MMS]::Apply(
      [string[]]($d | ForEach-Object id), $prim,
      [int[]]($d | ForEach-Object x), [int[]]($d | ForEach-Object y),
      [int[]]($d | ForEach-Object width), [int[]]($d | ForEach-Object height),
      [int[]]($d | ForEach-Object { if ($_.refresh) { $_.refresh } else { 0 } }),
      [bool]$c.moveWindows, [int]$c.settleDelayMs)
    if ($err) { Write-Log "Umschalten auf '$name' fehlgeschlagen: $err"; return $err }
    $moved = $c.moveWindows; $delay = [int]$c.settleDelayMs
    $c = Get-Config; $c.lastMode = $name; $c.lastSwitch = [DateTime]::UtcNow.Ticks; Save-Config $c
    $msg = "Umgeschaltet auf '$name'."
    # Fenster dorthin zurück, wo sie in diesem Modus zuletzt waren
    $saved = if ($remember) { Get-WindowLayout $name } else { @() }
    if ($saved) {
      if (-not $moved) { Start-Sleep -Milliseconds $delay }   # sonst hat Apply schon gewartet
      $n = [MMS]::PlaceWindows([string[]]$saved); Start-Sleep -Milliseconds 1500; [void][MMS]::PlaceWindows([string[]]$saved)
      if ($n) { $msg += " $n Fenster zurückgesetzt." }
    }
    if ($m.audio) {
      # Die zuletzt in diesem Modus gewählte Ausgabe wiederherstellen, falls vorhanden. Das HDMI-Audiogerät
      # eines gerade eingeschalteten Monitors taucht oft erst nach ein paar Sekunden auf. Fehlt es: Audio nicht anfassen.
      $set = $null
      for ($i = 0; $i -lt 16 -and -not $set; $i++) { try { $set = [MMSAudio]::SetDefault($m.audio) } catch {}; if (-not $set) { Start-Sleep -Milliseconds 500 } }
      if ($set) { $msg += " Audio: $set" }
      $c = Get-Config; $c.lastSwitch = [DateTime]::UtcNow.Ticks; Save-Config $c
    }
    Write-Log $msg
    $msg
  } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

# ---------------- Autostart ----------------
# Wie bei den anderen Tools: HKCU\...\Run. Ältere Versionen legten eine Verknüpfung im Autostart-Ordner an.
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'MonitorModeSwitcher'
$OldStartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Monitor Mode Switcher.lnk'
function Test-Autostart {
  ($null -ne (Get-ItemProperty $RunKey -Name $RunName -ErrorAction SilentlyContinue)) -or (Test-Path $OldStartupLnk)
}
function Set-Autostart([bool]$on) {
  if ($on) {
    $cmd = '"' + "$env:WINDIR\System32\wscript.exe" + '" "' + (Join-Path $PSScriptRoot 'MonitorModeSwitcher.vbs') + '"'
    Set-ItemProperty $RunKey $RunName $cmd
  } else { Remove-ItemProperty $RunKey $RunName -ErrorAction SilentlyContinue }
  if (Test-Path $OldStartupLnk) { Remove-Item $OldStartupLnk -ErrorAction SilentlyContinue }
}

# ---------------- Kommandozeile ----------------
if ($List)    { Get-Monitors | ConvertTo-Json -Depth 4; return }
if ($Audio)   { [MMSAudio]::List() | Select-Object Name, Default | ConvertTo-Json; return }
if ($Modes)   { (Get-Config).modes | ConvertTo-Json -Depth 6; return }
if ($Capture) { Save-CurrentLayout $Capture; return }
if ($Delete)  { Remove-Mode $Delete; "Modus '$Delete' gelöscht."; return }
if ($Mode)    { Invoke-Mode $Mode; return }
function Get-ToggleTarget {
  $c = Get-Config; $names = @($c.modes | ForEach-Object name)
  $t = @($c.toggleModes | Where-Object { $_ -and ($names -contains $_) })
  if ($t.Count -lt 2) { $t = @($names | Select-Object -First 2) }
  if ($t.Count -lt 2) { return $null }
  if ($c.lastMode -eq $t[0]) { $t[1] } else { $t[0] }
}
if ($Toggle) {
  $target = Get-ToggleTarget
  if (-not $target) { 'Zum Umschalten werden mindestens zwei Modi gebraucht.'; return }
  Invoke-Mode $target; return
}

# ---------------- Oberfläche ----------------
[System.Windows.Forms.Application]::EnableVisualStyles()

# Symbol: zwei Monitore mit Wechselpfeil. In jeder Größe gezeichnet; icon.ico wird neben dem Skript erzeugt.
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
  try { if (-not (Test-Path $ico)) { Save-IconFile $ico } } catch {}   # .ico für Verknüpfungen; das Tray nutzt die Bitmap direkt
  [System.Drawing.Icon]::FromHandle((New-IconBitmap 32).GetHicon())
}

function Show-Message([string]$text) { [void][System.Windows.Forms.MessageBox]::Show($text, $AppName) }

function Show-Settings {
  $f = New-Object System.Windows.Forms.Form
  $f.Text = "$AppName $AppVersion - Einstellungen"; $f.ClientSize = New-Object System.Drawing.Size(460, 526)
  $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.StartPosition = 'CenterScreen'
  $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $f.Icon = $script:icon

  $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = 'Modi'; $lbl.SetBounds(12, 10, 200, 18); $f.Controls.Add($lbl)
  $lb = New-Object System.Windows.Forms.ListBox; $lb.SetBounds(12, 30, 280, 160); $f.Controls.Add($lb)
  $info = New-Object System.Windows.Forms.Label; $info.SetBounds(12, 196, 286, 64); $info.ForeColor = [System.Drawing.Color]::DimGray; $f.Controls.Add($info)

  # Audio-Ausgabe pro Modus
  $la = New-Object System.Windows.Forms.Label; $la.Text = 'Audio (gemerkt):'; $la.SetBounds(302, 200, 146, 18); $f.Controls.Add($la)
  $cbAudio = New-Object System.Windows.Forms.ComboBox; $cbAudio.DropDownStyle = 'DropDownList'; $cbAudio.SetBounds(302, 220, 146, 24)
  $cbAudio.DropDownWidth = 380; $f.Controls.Add($cbAudio)
  $script:audioLoading = $false
  $cbAudio.Add_SelectedIndexChanged({
    if ($script:audioLoading -or -not $lb.SelectedItem) { return }
    $c = Get-Config; $mm = $c.modes | Where-Object { $_.name -eq $lb.SelectedItem } | Select-Object -First 1
    if (-not $mm) { return }
    $val = if ($cbAudio.SelectedIndex -le 0) { '' } else { [string]$cbAudio.SelectedItem -replace '^\d+ - ', '' }  # das "1 - "-Präfix kann sich ändern
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
    $info.Text = if ($m) { ($m.displays | ForEach-Object { "$($_.name)  $($_.width)x$($_.height) @ $($_.x),$($_.y)$(if($_.primary){'  [Haupt]'})" }) -join "`n" } else { '' }
    $script:audioLoading = $true; $cbAudio.Items.Clear(); [void]$cbAudio.Items.Add('(keine - nicht ändern)')
    $names = @(try { [MMSAudio]::List() | ForEach-Object Name } catch { })
    if ($m -and $m.audio -and -not ($names | Where-Object { $_ -like "*$($m.audio)*" })) { $names += $m.audio }
    foreach ($n in $names) { [void]$cbAudio.Items.Add($n) }
    $cbAudio.SelectedIndex = 0
    if ($m -and $m.audio) { for ($i = 1; $i -lt $cbAudio.Items.Count; $i++) { if ($cbAudio.Items[$i] -like "*$($m.audio)*") { $cbAudio.SelectedIndex = $i; break } } }
    $script:audioLoading = $false
  })

  # Jeder Knopf fängt seine Fehler selbst ab, damit das Fenster nicht mit einer Fehlermeldung abstürzt.
  # Die Aktion liegt im Tag des Knopfs (keine Closure: die Aktionen brauchen $lb, $refresh usw. aus diesem Fenster).
  $btn = { param($t, $y, $a) $b = New-Object System.Windows.Forms.Button; $b.Text = $t; $b.SetBounds(302, $y, 146, 28); $b.Tag = $a
    $b.Add_Click({ param($s) try { & $s.Tag } catch { Write-Log "FEHLER (Einstellungen): $_"; Show-Message "Fehler: $($_.Exception.Message)" } }); $f.Controls.Add($b) }
  & $btn 'Diesen Modus aktivieren' 30 { if ($lb.SelectedItem) { Show-Message (Invoke-Mode $lb.SelectedItem) } }
  & $btn 'Aktuelles neu speichern...' 64 {
    $n = [Microsoft.VisualBasic.Interaction]::InputBox("Ordne die Monitore zuerst in den Windows-Anzeigeeinstellungen an.`nName für diesen Modus:", $AppName, 'Neuer Modus')
    if ($n) { Save-CurrentLayout $n | Out-Null; & $refresh; $lb.SelectedItem = $n }
  }
  & $btn 'Mit aktuellem überschreiben' 98 { if ($lb.SelectedItem) { Save-CurrentLayout $lb.SelectedItem | Out-Null; & $refresh } }
  & $btn 'Umbenennen...' 132 {
    if (-not $lb.SelectedItem) { return }
    $old = [string]$lb.SelectedItem
    $n = [Microsoft.VisualBasic.Interaction]::InputBox('Neuer Name:', $AppName, $old)
    if ($n -and $n -ne $old) { $e = Rename-Mode $old $n; if ($e) { Show-Message $e } else { & $refresh; $lb.SelectedItem = $n } }
  }
  & $btn 'Löschen' 166 {
    if (-not $lb.SelectedItem) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show("Modus '$($lb.SelectedItem)' löschen?", $AppName, 'YesNo', 'Question')
    if ($ans -eq 'Yes') { Remove-Mode $lb.SelectedItem; & $refresh }
  }

  $c = Get-Config
  $cbMove = New-Object System.Windows.Forms.CheckBox; $cbMove.Text = 'Fenster beim Umschalten auf die neuen Monitore mitnehmen'
  $cbMove.SetBounds(12, 266, 436, 22); $cbMove.Checked = [bool]$c.moveWindows; $f.Controls.Add($cbMove)
  $cbAuto = New-Object System.Windows.Forms.CheckBox; $cbAuto.Text = 'Mit Windows starten'
  $cbAuto.SetBounds(12, 292, 436, 22); $cbAuto.Checked = (Test-Autostart); $f.Controls.Add($cbAuto)
  $l2 = New-Object System.Windows.Forms.Label; $l2.Text = 'Wartezeit nach dem Umschalten, bevor Fenster wandern (ms):'; $l2.SetBounds(12, 322, 300, 20); $f.Controls.Add($l2)
  $nd = New-Object System.Windows.Forms.NumericUpDown; $nd.SetBounds(312, 320, 80, 22); $nd.Minimum = 500; $nd.Maximum = 15000; $nd.Increment = 500
  $nd.Value = [Math]::Min(15000, [Math]::Max(500, [int]$c.settleDelayMs)); $f.Controls.Add($nd)

  $modeNames = @($c.modes | ForEach-Object name)
  $newCombo = { param($x, $y, $w, $sel) $cb = New-Object System.Windows.Forms.ComboBox; $cb.DropDownStyle = 'DropDownList'; $cb.SetBounds($x, $y, $w, 24)
    foreach ($n in $modeNames) { [void]$cb.Items.Add($n) }; if ($sel -and $cb.Items.Contains($sel)) { $cb.SelectedItem = $sel } elseif ($cb.Items.Count) { $cb.SelectedIndex = 0 }
    $f.Controls.Add($cb); $cb }

  $l3 = New-Object System.Windows.Forms.Label; $l3.Text = 'Beim Start (nach dem Booten):'; $l3.SetBounds(12, 356, 140, 20); $f.Controls.Add($l3)
  $cbStart = New-Object System.Windows.Forms.ComboBox; $cbStart.DropDownStyle = 'DropDownList'; $cbStart.SetBounds(152, 352, 150, 24)
  [void]$cbStart.Items.AddRange(@('Nichts tun', 'Letzten Modus herstellen', 'Immer diesen:')); $f.Controls.Add($cbStart)
  $cbStart.SelectedIndex = switch ($c.startupAction) { 'none' { 0 } 'mode' { 2 } default { 1 } }
  $cbStartMode = & $newCombo 308 352 140 $c.startupMode
  $cbStartMode.Enabled = ($cbStart.SelectedIndex -eq 2); $cbStart.Add_SelectedIndexChanged({ $cbStartMode.Enabled = ($cbStart.SelectedIndex -eq 2) })

  $cbPad = New-Object System.Windows.Forms.CheckBox; $cbPad.Text = 'Wenn ein Xbox-Controller verbunden wird, fragen nach:'
  $cbPad.SetBounds(12, 388, 300, 22); $cbPad.Checked = [bool]$c.controllerPrompt; $f.Controls.Add($cbPad)
  $cbPadMode = & $newCombo 308 386 140 $c.controllerMode
  $cbVA = New-Object System.Windows.Forms.CheckBox; $cbVA.Text = 'Controller: Ansicht halten + 2x A schaltet auf:'
  $cbVA.SetBounds(12, 414, 296, 22); $cbVA.Checked = [bool]$c.controllerViewA; $f.Controls.Add($cbVA)
  $cbVAMode = & $newCombo 308 412 140 $c.controllerViewA
  $cbVB = New-Object System.Windows.Forms.CheckBox; $cbVB.Text = 'Controller: Ansicht halten + 2x B schaltet auf:'
  $cbVB.SetBounds(12, 440, 296, 22); $cbVB.Checked = [bool]$c.controllerViewB; $f.Controls.Add($cbVB)
  $cbVBMode = & $newCombo 308 438 140 $c.controllerViewB

  $open = New-Object System.Windows.Forms.LinkLabel; $open.Text = 'config.json öffnen'; $open.SetBounds(12, 476, 200, 20)
  $open.Add_Click({ if (-not (Test-Path $CfgPath)) { Save-Config (Get-Config) }; Start-Process notepad.exe $CfgPath }); $f.Controls.Add($open)
  $openLog = New-Object System.Windows.Forms.LinkLabel; $openLog.Text = 'Diagnose-Log öffnen'; $openLog.SetBounds(12, 498, 200, 20)
  $openLog.Add_Click({ if (-not (Test-Path $LogPath)) { Write-Log 'Log angelegt' }; Start-Process notepad.exe $LogPath }); $f.Controls.Add($openLog)
  $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Speichern && Schließen'; $ok.SetBounds(312, 484, 136, 30); $f.Controls.Add($ok)
  $ok.Add_Click({
    try {
      $c = Get-Config; $c.moveWindows = $cbMove.Checked; $c.settleDelayMs = [int]$nd.Value
      $c.startupAction = @('none', 'last', 'mode')[$cbStart.SelectedIndex]; $c.startupMode = [string]$cbStartMode.SelectedItem
      $c.controllerPrompt = $cbPad.Checked; $c.controllerMode = [string]$cbPadMode.SelectedItem
      $c.controllerViewA = if ($cbVA.Checked) { [string]$cbVAMode.SelectedItem } else { '' }
      $c.controllerViewB = if ($cbVB.Checked) { [string]$cbVBMode.SelectedItem } else { '' }
      Save-Config $c
      Set-Autostart $cbAuto.Checked; $f.Close()
    } catch { Write-Log "FEHLER (Einstellungen speichern): $_"; Show-Message "Fehler beim Speichern: $($_.Exception.Message)" }
  })
  $f.AcceptButton = $ok
  & $refresh
  [void]$f.ShowDialog()
}
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class MMSHotkey : NativeWindow {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h,int id,int mod,int vk);
  public event EventHandler Pressed;
  public MMSHotkey(){ CreateHandle(new CreateParams()); }
  public bool Register(int mod,int vk){ return RegisterHotKey(Handle,1,mod|0x4000,vk); }  // 0x4000 = MOD_NOREPEAT
  protected override void WndProc(ref Message m){ if(m.Msg==0x312&&Pressed!=null) Pressed(this,EventArgs.Empty); base.WndProc(ref m); }
}
'@

$script:icon = New-TrayIcon
if ($Settings) { Show-Settings; return }

# nur eine Tray-Instanz
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MonitorModeSwitcherTray', [ref]$created)
if (-not $created) { Show-Message "$AppName läuft bereits (Symbol im Infobereich)."; return }

try { $cfg0 = Get-Config }
catch { Show-Message "$($_.Exception.Message)`n`nBitte config.json reparieren (Einstellungen > config.json öffnen)."; return }
Write-Log "$AppName $AppVersion gestartet"

# Ältere Versionen: Autostart-Verknüpfung -> Registry (wie die anderen Tools)
if (Test-Path $OldStartupLnk) { try { Set-Autostart $true; Write-Log 'Autostart auf HKCU\...\Run umgestellt' } catch { Write-Log "Autostart umstellen: $_" } }

# ---- Controller-taugliche Modusauswahl (Maus, Tastatur oder Xbox-Controller) ----
function Show-ModePicker([string]$title, [string]$preselect) {
  $modes = @((Get-Config).modes | ForEach-Object name)
  if (-not $modes) { return $null }
  $f = New-Object System.Windows.Forms.Form
  $f.FormBorderStyle = 'None'; $f.TopMost = $true; $f.StartPosition = 'CenterScreen'; $f.ShowInTaskbar = $false
  $f.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28); $f.KeyPreview = $true
  $rowH = 64; $f.ClientSize = New-Object System.Drawing.Size(520, (110 + ($modes.Count + 1) * ($rowH + 8)))
  $t = New-Object System.Windows.Forms.Label; $t.Text = $title; $t.ForeColor = [System.Drawing.Color]::White
  $t.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold); $t.SetBounds(24, 18, 472, 40); $f.Controls.Add($t)
  $h = New-Object System.Windows.Forms.Label; $h.Text = 'Controller: hoch/runter + A bestätigt, B bricht ab'
  $h.ForeColor = [System.Drawing.Color]::Gray; $h.Font = New-Object System.Drawing.Font('Segoe UI', 10); $h.SetBounds(24, 58, 472, 24); $f.Controls.Add($h)
  $items = @($modes) + 'Abbrechen'
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
$script:busy = $false

# Umschalten aus der Tray-App: nie doppelt, Fehler als Hinweis statt Absturz
function Switch-WithTip([string]$m) {
  if ($script:busy) { return }
  $script:busy = $true
  try { $ni.ShowBalloonTip(2500, $AppName, (Invoke-Mode $m), 'Info') }
  catch { Write-Log "FEHLER (Umschalten auf '$m'): $_"; $ni.ShowBalloonTip(4000, $AppName, "Fehler: $($_.Exception.Message)", 'Error') }
  finally { $script:busy = $false }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Add_Opening({
  $menu.Items.Clear()
  $title = $menu.Items.Add("$AppName $AppVersion"); $title.Enabled = $false
  [void]$menu.Items.Add('-')
  $cfgM = Get-Config; $modes = $cfgM.modes
  if (-not $modes) { $i = $menu.Items.Add('(noch keine Modi - Einstellungen öffnen)'); $i.Enabled = $false }
  foreach ($m in $modes) {
    $it = $menu.Items.Add($m.name); $it.Tag = $m.name; $it.Checked = ($m.name -eq $cfgM.lastMode)
    $it.Add_Click({ param($s) Switch-WithTip $s.Tag })
  }
  [void]$menu.Items.Add('-')
  [void]$menu.Items.Add('Einstellungen...', $null, { try { Show-Settings } catch { Write-Log "FEHLER (Einstellungen): $_" } })
  [void]$menu.Items.Add('Diagnose-Log öffnen', $null, { if (-not (Test-Path $LogPath)) { Write-Log 'Log angelegt' }; Start-Process notepad.exe $LogPath })
  [void]$menu.Items.Add('Beenden', $null, { $ni.Visible = $false; [System.Windows.Forms.Application]::Exit() })
  $_.Cancel = $false
})
[void]$menu.Items.Add('...')   # Platzhalter, damit Opening ausgelöst wird
$ni.ContextMenuStrip = $menu
$ni.Add_MouseClick({ param($s, $e)
  if ($e.Button -eq 'Left') { $mi = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic'); $mi.Invoke($ni, $null) }
})

if (-not $cfg0.modes) { $ni.ShowBalloonTip(4000, $AppName, 'Noch keine Modi. Rechtsklick aufs Symbol > Einstellungen, um das erste Layout zu speichern.', 'Info') }

# Beim Start: letzten Modus oder einen festen Modus herstellen
$startMode = switch ($cfg0.startupAction) { 'last' { $cfg0.lastMode } 'mode' { $cfg0.startupMode } default { '' } }
if ($startMode -and ($cfg0.modes | Where-Object { $_.name -eq $startMode })) {
  $st = New-Object System.Windows.Forms.Timer; $st.Interval = 2000
  $st.Add_Tick({ $st.Stop(); Switch-WithTip $startMode }); $st.Start()
}

# Globales Tastenkürzel zum Umschalten (Standard Strg+#)
function Get-HotkeyParts([string]$s) {
  $mod = 0; $vk = 0
  foreach ($part in ($s -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    switch -regex ($part) {
      '^(ctrl|strg|control)$' { $mod = $mod -bor 2; continue }
      '^alt$' { $mod = $mod -bor 1; continue }
      '^(shift|umschalt)$' { $mod = $mod -bor 4; continue }
      '^win$' { $mod = $mod -bor 8; continue }
      default {
        if ($part -eq '#') { $vk = 0xBF }   # '#'-Taste auf deutscher Tastatur (VK_OEM_2)
        else { try { $vk = [int][System.Windows.Forms.Keys]$part } catch { $vk = 0 } }
      }
    }
  }
  @($mod, $vk)
}
$hk = Get-HotkeyParts $cfg0.toggleHotkey
if ($hk[1]) {
  $script:hotkey = New-Object MMSHotkey
  if ($script:hotkey.Register($hk[0], $hk[1])) {
    $script:hotkey.add_Pressed({
      try { $tg = Get-ToggleTarget; if ($tg) { Switch-WithTip $tg } } catch { Write-Log "FEHLER (Tastenkürzel): $_" }
    })
  } else {
    Write-Log "Tastenkürzel $($cfg0.toggleHotkey) ist schon belegt"
    $ni.ShowBalloonTip(4000, $AppName, "Tastenkürzel $($cfg0.toggleHotkey) wird schon von einem anderen Programm benutzt.", 'Warning')
  }
}

# Controller-Wächter: optional Abfrage beim Verbinden; Ansicht halten + 2x A / B schaltet um
$script:padWas = ([MMS]::Pad() -ge 0); $script:padPrev = 0
$script:tapA = [DateTime]::MinValue; $script:tapB = [DateTime]::MinValue
$script:tickErr = $false
$pt = New-Object System.Windows.Forms.Timer; $pt.Interval = 50
$pt.Add_Tick({
  if ($script:busy) { return }
  try {
    $p = [MMS]::Pad(); $c = Get-Config; $choice = $null; $ask = $false; $title = ''
    if ($p -ge 0 -and -not $script:padWas -and $c.controllerPrompt -and $c.controllerMode -and $c.lastMode -ne $c.controllerMode) {
      $ask = $true; $title = 'Controller verbunden - Modus wechseln?'
    }
    $now = [DateTime]::Now; $target = $null
    if ($p -ge 0 -and ($p -band 0x20)) {   # Ansicht gehalten
      $new = $p -band (-bnot $script:padPrev)
      if ($new -band 0x1000) {
        if (($now - $script:tapA).TotalMilliseconds -le 500) { $target = $c.controllerViewA; $script:tapA = [DateTime]::MinValue } else { $script:tapA = $now }
      }
      if ($new -band 0x2000) {
        if (($now - $script:tapB).TotalMilliseconds -le 500) { $target = $c.controllerViewB; $script:tapB = [DateTime]::MinValue } else { $script:tapB = $now }
      }
    } else { $script:tapA = [DateTime]::MinValue; $script:tapB = [DateTime]::MinValue }
    $script:padWas = ($p -ge 0); $script:padPrev = [Math]::Max(0, $p)
    if ($target) { Switch-WithTip $target; return }
    if ($ask) {
      $script:busy = $true
      try {
        $pre = if ($c.controllerMode) { $c.controllerMode } else { $c.lastMode }
        $choice = Show-ModePicker $title $pre
        $script:padPrev = [Math]::Max(0, [MMS]::Pad())
      } finally { $script:busy = $false }
      if ($choice) { Switch-WithTip $choice }
    }
    $script:tickErr = $false
  } catch {
    if (-not $script:tickErr) { Write-Log "FEHLER (Controller): $_" }   # nur einmal loggen, der Timer läuft 20x pro Sekunde
    $script:tickErr = $true
  }
})
$pt.Start()

# Audio-Wächter: wählt der Nutzer eine andere Standardausgabe, wird sie für den aktuellen Modus gemerkt.
# Ignoriert: Wechsel innerhalb von 20 s nach einem Umschalten, und Wechsel, weil das alte Gerät verschwunden ist
# (Monitor aus / abgesteckt) - das ist Windows' Rückfall, keine Wahl.
function Get-AudioState { $l = @(try { [MMSAudio]::List() } catch { }); @{ ids = @($l | ForEach-Object Id); def = ($l | Where-Object Default | Select-Object -First 1) } }
$script:aud = Get-AudioState
$at = New-Object System.Windows.Forms.Timer; $at.Interval = 2000
$at.Add_Tick({
  if ($script:busy) { return }
  try {
    $now = Get-AudioState; $prev = $script:aud; $script:aud = $now
    if (-not $now.def -or -not $prev.def -or $now.def.Id -eq $prev.def.Id) { return }
    if ($now.ids -notcontains $prev.def.Id) { return }                       # altes Gerät verschwunden
    $c = Get-Config
    if (([DateTime]::UtcNow.Ticks - [long]$c.lastSwitch) -lt 20 * 10000000L) { return }
    $m = $c.modes | Where-Object { $_.name -eq $c.lastMode } | Select-Object -First 1
    if (-not $m -or -not $now.def.Name) { return }
    $val = $now.def.Name -replace '^\d+ - ', ''   # das "1 - "-Präfix kann sich ändern
    if ($m.audio -eq $val) { return }
    if ($m.PSObject.Properties.Name -contains 'audio') { $m.audio = $val } else { $m | Add-Member audio $val }
    Save-Config $c
    Write-Log "Audio für Modus '$($m.name)' gemerkt: $val"
  } catch { Write-Log "FEHLER (Audio): $_" }
})
$at.Start()

[System.Windows.Forms.Application]::Run()
$ni.Dispose(); $mutex.ReleaseMutex()
