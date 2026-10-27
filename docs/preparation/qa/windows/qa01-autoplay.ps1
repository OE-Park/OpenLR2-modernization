#Requires -Version 7.0
# QA-01 pass 1: direct autoplay (`<chart> -a -ns`) of every synthetic chart on the original LR2body.exe and the fork.
# Runs in the interactive console session. Per run it records window/dialog state, periodic window screenshots,
# exit code and the engine's Log.txt under D:\olr2\.local\qa01\runs\<stamp>\.
param(
    [int]$TimeoutSec = 45,
    [int]$ShotEverySec = 3,
    [string[]]$Only,
    [string[]]$Engine
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$qa = 'D:\olr2\.local\qa01'
$syn = 'D:\olr2\.local\qa\synthetic'
$engines = [ordered]@{
    orig = @{ root = "$qa\orig\LR2-fresh\LR2beta3"; exe = 'LR2body.exe' }
    fork = @{ root = "$qa\fork\LR2-fresh\LR2beta3"; exe = 'OpenLR2_x64.exe' }
}
$charts = @(
    'ascii_basic/7key_core.bms', 'ascii_basic/7key_base62.bms', 'ascii_basic/7key_lnobj.bms', 'ascii_basic/7key_scroll.bms',
    'ascii_basic/7key_random.bms', 'ascii_basic/5key.bms', 'ascii_basic/9key.pms', 'ascii_basic/10key_dp.bms',
    'ascii_basic/14key_dp.bme', 'case_mismatch/7key_core_upper.bms',
    '日本語 曲名 テスト/7key_core_ja_cp932.bms', '日本語 曲名 テスト/7key_core_ja_utf8.bms', '한국어 곡 테스트/7key_core_ko_utf8.bms',
    'broken/missing_refs.bms', 'broken/truncated.bms', 'broken/bpm_zero.bms', 'broken/empty.bms'
)
if ($Engine) { $Engine = @($Engine -split ','); foreach ($k in @($engines.Keys)) { if ($k -notin $Engine) { $engines.Remove($k) } } }
if ($Only) { $Only = @($Only -split ","); $charts = $charts | Where-Object { $c = $_; $Only | Where-Object { $c -like "*$_*" } } }

Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Qa01 -Name Win -UsingNamespace System.Text, System.Collections.Generic -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
[DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, s.Capacity); return s.ToString(); }
public static string Txt(IntPtr h) { var s = new StringBuilder(1024); GetWindowText(h, s, s.Capacity); return s.ToString(); }
public static List<IntPtr> TopLevel(uint target) {
    var r = new List<IntPtr>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == target) r.Add(h); return true; }, IntPtr.Zero);
    return r;
}
public static string Statics(IntPtr h) {
    var t = new List<string>();
    EnumChildWindows(h, (c, l) => { if (Cls(c) == "Static" && Txt(c).Length > 0) t.Add(Txt(c)); return true; }, IntPtr.Zero);
    return string.Join(" | ", t);
}
'@
[void][Qa01.Win]::SetProcessDPIAware()

function Save-WindowShot([IntPtr]$h, [string]$path) {
    $r = New-Object Qa01.Win+RECT
    if (-not [Qa01.Win]::GetWindowRect($h, [ref]$r)) { return $false }
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -le 0 -or $hh -le 0) { return $false }
    $bmp = [Drawing.Bitmap]::new($w, $hh)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png); return $true }
    catch { return $false }
    finally { $g.Dispose(); $bmp.Dispose() }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $qa "runs\$stamp"
New-Item -ItemType Directory -Force $out | Out-Null
$summary = [System.Collections.Generic.List[object]]::new()
$console = [Qa01.Win]::GetConsoleWindow()
Write-Host "QA-01 autoplay: $($charts.Count) charts x $($engines.Count) engines, timeout ${TimeoutSec}s -> $out"
Write-Host 'Do not touch the keyboard or mouse until it finishes. This console minimizes itself during each run.'
Start-Sleep -Seconds 3

$i = 0
foreach ($chart in $charts) {
    $i++
    $chartPath = Join-Path $syn ($chart -replace '/', '\')
    $slug = '{0:D2}-{1}' -f $i, ([IO.Path]::GetFileNameWithoutExtension($chart) -replace '[^A-Za-z0-9_]', '_')
    $sha = (Get-FileHash -LiteralPath $chartPath -Algorithm SHA256).Hash.ToLower()
    foreach ($name in $engines.Keys) {
        $e = $engines[$name]
        $dir = Join-Path $out "$slug\$name"
        New-Item -ItemType Directory -Force $dir | Out-Null
        Remove-Item -LiteralPath (Join-Path $e.root 'Log.txt') -ErrorAction SilentlyContinue
        Write-Host ("[{0}/{1}] {2,-4} {3}" -f $i, $charts.Count, $name, $chart)
        [void][Qa01.Win]::ShowWindow($console, 6)  # SW_MINIMIZE
        $argLine = '"{0}" -a -ns' -f $chartPath
        $t0 = Get-Date
        $p = Start-Process -FilePath (Join-Path $e.root $e.exe) -ArgumentList $argLine -WorkingDirectory $e.root -PassThru
        $shots = 0; $dialog = $null; $seen = [ordered]@{}; $next = 1
        while ($true) {
            Start-Sleep -Milliseconds 500
            $elapsed = ((Get-Date) - $t0).TotalSeconds
            if ($p.HasExited) { break }
            foreach ($h in [Qa01.Win]::TopLevel([uint32]$p.Id)) {
                $key = '{0}|{1}' -f [Qa01.Win]::Cls($h), [Qa01.Win]::Txt($h)
                if (-not $seen.Contains($key)) { $seen[$key] = [ordered]@{ class = [Qa01.Win]::Cls($h); title = [Qa01.Win]::Txt($h); firstSec = [math]::Round($elapsed, 1) } }
                if ([Qa01.Win]::Cls($h) -eq '#32770' -and -not $dialog) {
                    $dialog = [ordered]@{ title = [Qa01.Win]::Txt($h); text = [Qa01.Win]::Statics($h); atSec = [math]::Round($elapsed, 1) }
                    [void][Qa01.Win]::SetForegroundWindow($h); Start-Sleep -Milliseconds 300
                    if (Save-WindowShot $h (Join-Path $dir 'dialog.png')) { $shots++ }
                }
            }
            if ($dialog) { break }
            if ($elapsed -ge $next) {
                $main = [Qa01.Win]::TopLevel([uint32]$p.Id) | Where-Object { [Qa01.Win]::IsWindowVisible($_) -and [Qa01.Win]::Cls($_) -ne 'DIEmWin' } | Select-Object -First 1
                if ($main -and (Save-WindowShot $main (Join-Path $dir ('shot_{0:D3}s.png' -f [int]$elapsed)))) { $shots++ }
                $next += $ShotEverySec
            }
            if ($elapsed -ge $TimeoutSec) { break }
        }
        $exitedSelf = $p.HasExited
        $exitCode = if ($exitedSelf) { $p.ExitCode } else { $null }
        if (-not $exitedSelf) { Stop-Process -Id $p.Id -Force; Start-Sleep -Milliseconds 800 }
        $log = Join-Path $e.root 'Log.txt'
        if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log (Join-Path $dir 'Log.txt') }
        $rec = [ordered]@{
            engine = $name; exe = $e.exe; chart = $chart; chartSha256 = $sha; args = $argLine
            start = $t0.ToString('o'); elapsedSec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
            exitedSelf = $exitedSelf; exitCode = $exitCode; stoppedByHarness = (-not $exitedSelf)
            dialog = $dialog; windows = @($seen.Values); shots = $shots; log = (Test-Path -LiteralPath (Join-Path $dir 'Log.txt'))
        }
        $rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'run.json') -Encoding utf8
        $summary.Add([pscustomobject]@{ n = $i; chart = $chart; engine = $name; exitedSelf = $exitedSelf; exitCode = $exitCode; sec = $rec.elapsedSec; dialog = if ($dialog) { "$($dialog.title): $($dialog.text)" } else { '' }; shots = $shots })
        Start-Sleep -Seconds 1
    }
}
[void][Qa01.Win]::ShowWindow($console, 9)  # SW_RESTORE
$summary | Export-Csv -LiteralPath (Join-Path $out 'summary.csv') -NoTypeInformation -Encoding utf8
$summary | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
Write-Host "Done. Results: $out"
