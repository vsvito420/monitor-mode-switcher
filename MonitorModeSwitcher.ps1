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
  [switch]$List, [switch]$Modes, [switch]$Settings
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

  static void Restore(List<Win> wins){
    var mons=Monitors(); var idToDev=new Dictionary<string,string>(); string prim=null;
    foreach(var d in List()) if(d.Active){ idToDev[d.Id]=d.Dev; if(d.Primary) prim=d.Dev; }
    foreach(var w in wins){
      string dev; if(w.Id==null||!idToDev.TryGetValue(w.Id,out dev)) dev=prim;
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
    foreach(var d in before) if(d.Active) devToId[d.Dev]=d.Id;
    var wins=move?Snapshot(devToId):null;
    var used=new HashSet<string>(); int r=0;
    for(int i=0;i<ids.Length;i++){
      var d=before.Find(z=>z.Id.Equals(ids[i],StringComparison.OrdinalIgnoreCase)&&!used.Contains(z.Dev));
      if(d==null) return "Monitor not connected: "+ids[i];
      used.Add(d.Dev); r|=Set(d.Dev,x[i],y[i],w[i],h[i],hz[i],prim[i]); }
    foreach(var d in before) if(d.Active&&!used.Contains(d.Dev)) r|=Set(d.Dev,0,0,0,0,0,false);
    int c=ChangeDisplaySettingsEx(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
    if(r!=0||c!=0) return "Windows rejected the layout (code "+r+"/"+c+")";
    if(move&&wins.Count>0){ Thread.Sleep(delay); Restore(wins); Thread.Sleep(1500); Restore(wins); }
    return null; }
}
'@

# ---------------- config ----------------
function Get-Config {
  $c = $null
  if (Test-Path $CfgPath) { $c = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  if (-not $c) { $c = [pscustomobject]@{} }
  foreach ($k in @{ moveWindows = $true; settleDelayMs = 3000; modes = @() }.GetEnumerator()) {
    if (-not ($c.PSObject.Properties.Name -contains $k.Key)) { $c | Add-Member $k.Key $k.Value }
  }
  $c.modes = @($c.modes | Where-Object { $_ })
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
  $mode = [pscustomobject][ordered]@{ name = $name; displays = $disp }
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
  if ($err) { $err } else { "Switched to '$name'." }
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
if ($Modes)   { (Get-Config).modes | ConvertTo-Json -Depth 6; return }
if ($Capture) { Save-CurrentLayout $Capture; return }
if ($Delete)  { Remove-Mode $Delete; "Deleted '$Delete'."; return }
if ($Mode)    { Invoke-Mode $Mode; return }

# ---------------- UI ----------------
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-TrayIcon {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
  $blue = [System.Drawing.Color]::FromArgb(70, 150, 255); $white = [System.Drawing.Brushes]::White
  $g.FillRectangle((New-Object System.Drawing.SolidBrush $blue), 1, 5, 19, 14)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 200, 255))), 12, 11, 19, 14)
  $g.FillRectangle($white, 19, 25, 5, 3); $g.FillRectangle($white, 15, 28, 13, 3)
  $g.Dispose()
  [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Show-Settings {
  $f = New-Object System.Windows.Forms.Form
  $f.Text = "$AppName - Settings"; $f.ClientSize = New-Object System.Drawing.Size(460, 420)
  $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.StartPosition = 'CenterScreen'
  $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $f.Icon = $script:icon

  $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = 'Modes'; $lbl.SetBounds(12, 10, 200, 18); $f.Controls.Add($lbl)
  $lb = New-Object System.Windows.Forms.ListBox; $lb.SetBounds(12, 30, 280, 160); $f.Controls.Add($lb)
  $info = New-Object System.Windows.Forms.Label; $info.SetBounds(12, 196, 436, 60); $info.ForeColor = [System.Drawing.Color]::DimGray; $f.Controls.Add($info)

  $refresh = {
    $sel = $lb.SelectedItem; $lb.Items.Clear()
    foreach ($m in (Get-Config).modes) { [void]$lb.Items.Add($m.name) }
    if ($sel -and $lb.Items.Contains($sel)) { $lb.SelectedItem = $sel } elseif ($lb.Items.Count) { $lb.SelectedIndex = 0 }
  }
  $lb.Add_SelectedIndexChanged({
    $m = (Get-Config).modes | Where-Object { $_.name -eq $lb.SelectedItem } | Select-Object -First 1
    $info.Text = if ($m) { ($m.displays | ForEach-Object { "$($_.name)  $($_.width)x$($_.height) @ $($_.x),$($_.y)$(if($_.primary){'  [primary]'})" }) -join "`n" } else { '' }
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
    if ($n) { $c = Get-Config; ($c.modes | Where-Object { $_.name -eq $lb.SelectedItem }).name = $n; Save-Config $c; & $refresh; $lb.SelectedItem = $n }
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

  $open = New-Object System.Windows.Forms.LinkLabel; $open.Text = 'Open config.json'; $open.SetBounds(12, 384, 200, 20)
  $open.Add_Click({ if (-not (Test-Path $CfgPath)) { Save-Config (Get-Config) }; Start-Process notepad.exe $CfgPath }); $f.Controls.Add($open)
  $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Save && Close'; $ok.SetBounds(332, 378, 116, 30); $f.Controls.Add($ok)
  $ok.Add_Click({
    $c = Get-Config; $c.moveWindows = $cbMove.Checked; $c.settleDelayMs = [int]$nd.Value; Save-Config $c
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

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $script:icon; $ni.Text = $AppName; $ni.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Add_Opening({
  $menu.Items.Clear()
  $modes = (Get-Config).modes
  if (-not $modes) { $i = $menu.Items.Add('(no modes yet - open Settings)'); $i.Enabled = $false }
  foreach ($m in $modes) {
    $it = $menu.Items.Add($m.name); $it.Tag = $m.name
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
if (-not (Get-Config).modes) { $ni.ShowBalloonTip(4000, $AppName, 'No modes yet. Right-click the tray icon > Settings to save your first layout.', 'Info') }

[System.Windows.Forms.Application]::Run()
$ni.Dispose(); $mutex.ReleaseMutex()
