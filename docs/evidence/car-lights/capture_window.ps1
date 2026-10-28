param([Parameter(Mandatory = $true)][string]$Out)
# Captures Roblox Studio's 3D viewport without bringing the window forward: PrintWindow with
# PW_RENDERFULLCONTENT, cropped to the viewport (camera ViewportSize 1721 x 865 at window offset 11, 215).
# Fails (exit 1) when the window is minimized or the capture is not the expected size.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
if (-not ("PWin3" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PWin3 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
}
$p = Get-Process RobloxStudioBeta | Select-Object -First 1
$h = $p.MainWindowHandle
# The owner agreed (2026-10-28) to restoring a minimized Studio without focus (SW_SHOWNOACTIVATE).
if ([PWin3]::IsIconic($h)) {
  [void][PWin3]::ShowWindow($h, 4)
  Start-Sleep -Milliseconds 1500
  Write-Output "restored Studio without focus"
}
if ([PWin3]::IsIconic($h)) { Write-Output "FAILED: Studio is minimized"; exit 1 }
$r = New-Object PWin3+RECT
[void][PWin3]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T
if ($w -lt 1740 -or $hh -lt 1085) { Write-Output "FAILED: window is ${w}x${hh}, smaller than the viewport crop"; exit 1 }
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [PWin3]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$crop = New-Object System.Drawing.Bitmap 1721, 865
$g2 = [System.Drawing.Graphics]::FromImage($crop)
$g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, 1721, 865), (New-Object System.Drawing.Rectangle 11, 215, 1721, 865), [System.Drawing.GraphicsUnit]::Pixel)
$g2.Dispose()
$dir = Split-Path $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $bmp.Dispose()
if (-not (Test-Path $Out)) { Write-Output "FAILED: nothing written"; exit 1 }
"saved $Out printwindow=$ok"
