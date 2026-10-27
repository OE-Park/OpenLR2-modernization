#Requires -Version 7.0
<#
.SYNOPSIS
    WIN-01 baseline for OpenLR2 on Windows 11 x64 (see docs/preparation/ROADMAP.md).

.DESCRIPTION
    Reproduces the reference build procedure from .github/workflows/build.yml on a local
    Windows machine and records evidence under -WorkRoot:
      a. environment check          -> environment.json
      b. vcpkg at the pinned commit
      c. cmake --preset / cmake --build --preset (logs per step)
      d. PE-header + SHA-256 of OpenLR2_x64.exe and fmod.dll -> artifacts.json
      e. verify + extract LR2_100201.zip into a fresh LR2 directory
      f. stage the fork exe + fmod.dll next to the original (LR2body.exe is kept)
      g. optional launch (-Launch) with -ns by default
      h. summary table + result.json; non-zero exit if a mandatory step failed

    Assumptions (not verified by this script):
      - Visual Studio 2026 (Community is enough) with the C++ desktop workload is installed.
        The VS major is taken from the preset's generator; pass -Preset windows-vs-x64 for VS 2022.
      - CMake >= 3.29 and git are on PATH; the cmake on PATH must offer the preset's generator (upstream 4.2+ for VS 2026).
      - Network is reachable: the script itself only runs `git clone` for vcpkg, but
        vcpkg bootstrap and the vcpkg manifest install triggered by `cmake --preset`
        download the vcpkg binary and port sources on their own.
      - -WorkRoot defaults to <repo>\.local\win01, which is gitignored (/.local/).
      - Nothing in the repo is modified except out\<preset>\ created by CMake itself.

.EXAMPLE
    pwsh -ExecutionPolicy Bypass -File docs\preparation\scripts\win01-baseline.ps1 -ZipPath D:\dl\LR2_100201.zip
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
    [string]$ZipPath,
    [string]$WorkRoot,
    [string]$VcpkgRoot,
    [string]$Preset = 'windows-vs2026-x64',
    [string]$BuildPreset = 'windows-vs2026-x64-relwithdebinfo',
    [string]$ExeName = 'OpenLR2_x64.exe',
    [string]$FmodRelPath = 'dep\FMOD\bin64\fmod.dll',
    [string]$VcpkgCommit = 'cd61e1e26a038e82d6550a3ebbe0fbbfe7da78e3',
    [switch]$SkipBuild,
    [switch]$SkipExtract,
    [switch]$Force,
    [switch]$Launch,
    [string]$LaunchArgs = '-ns',
    [int]$LaunchWaitSeconds = 20,
    [switch]$StopAfterWait,
    [switch]$SeedConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Non-zero native exit codes are checked explicitly below; do not let pwsh 7.4+ turn them into exceptions.
$PSNativeCommandUseErrorActionPreference = $false

# ---------------------------------------------------------------- constants / defaults
$RepoRoot = (Resolve-Path $RepoRoot).Path
if (-not $WorkRoot) { $WorkRoot = Join-Path $RepoRoot '.local\win01' }
if (-not $VcpkgRoot) { $VcpkgRoot = Join-Path $WorkRoot 'vcpkg' }
$script:FmodRelPathExplicit = $PSBoundParameters.ContainsKey('FmodRelPath')
$script:InventoryPath = Join-Path $RepoRoot 'docs\preparation\evidence\input-inventory.json'
$script:ZipName = 'LR2_100201.zip'
$script:ZipTop = 'LR2beta3'
# Fallback constants; input-inventory.json is the primary source and is read at runtime.
$script:FallbackZipSha256 = '34294ea6661b232071688a93de31631e4e8114a82314d3386541e6875a74ff41'
$script:FallbackZipBytes = 54143938
$script:FallbackMemberSha256 = @{
    'LR2body.exe' = 'a46ef15343e41d3411771c83ac7b0c42d95e5f473db69c6b45a9584c07e94480'
    'LR2.exe'     = 'ba3c5701970ccdb1e439c6ddd07597baad2f30a0620ad9bbc8b2060e1f141372'
    'fmodex.dll'  = 'aad23230f7aac55d48d0c61424598ca4f01926e21e8e476a27b9534cd93b93b6'
}
$script:PeMachineNames = @{ 0x14c = 'x86'; 0x8664 = 'x64'; 0xAA64 = 'ARM64'; 0x1c4 = 'ARMNT' }

$script:RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogDir = Join-Path (Join-Path $WorkRoot 'logs') $script:RunStamp
$script:Lr2Fresh = Join-Path $WorkRoot 'LR2-fresh'
$script:Lr2Root = Join-Path $script:Lr2Fresh $script:ZipTop
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:StepIndex = 0

# ---------------------------------------------------------------- helpers
function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ("==> {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Info { param([string]$Message) Write-Host ("    {0}" -f $Message) }
function Write-Warn { param([string]$Message) Write-Host ("    WARN {0}" -f $Message) -ForegroundColor Yellow }

function Format-Arg {
    # Quote one argument for Start-Process -ArgumentList (which does not quote for us).
    param([string]$Value)
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function Invoke-Native {
    # Run a short native command and return [pscustomobject]@{ ExitCode; Output(string[]) }.
    # stderr is merged; with ErrorActionPreference=Continue the merged records never terminate.
    param([string]$FilePath, [string[]]$Arguments = @(), [string]$WorkingDirectory = $RepoRoot)
    $ErrorActionPreference = 'Continue'
    Push-Location $WorkingDirectory
    try {
        $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally { Pop-Location }
    return [pscustomobject]@{ ExitCode = $code; Output = $lines }
}

function Invoke-Logged {
    # Run a long native command; stdout/stderr go to <LogDir>\<nn>-<name>.{out,err}.log.
    # Returns [pscustomobject]@{ ExitCode; DurationSec; OutLog; ErrLog }.
    param([string]$Name, [string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory)
    $script:StepIndex++
    $base = Join-Path $script:LogDir ('{0:d2}-{1}' -f $script:StepIndex, $Name)
    $outLog = "$base.out.log"; $errLog = "$base.err.log"
    $argLine = ($Arguments | ForEach-Object { Format-Arg $_ }) -join ' '
    Write-Info ("run : {0} {1}" -f $FilePath, $argLine)
    Write-Info ("log : {0}" -f $outLog)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $FilePath -ArgumentList $argLine -WorkingDirectory $WorkingDirectory `
        -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    while (-not $proc.WaitForExit(30000)) {
        Write-Info ("... still running ({0:n0}s)" -f $sw.Elapsed.TotalSeconds)
    }
    $proc.WaitForExit()
    $sw.Stop()
    $code = $proc.ExitCode
    Write-Info ("exit: {0} after {1:n1}s" -f $code, $sw.Elapsed.TotalSeconds)
    if ($code -ne 0 -and (Test-Path $errLog)) {
        Get-Content $errLog -Tail 15 | ForEach-Object { Write-Warn $_ }
    }
    return [pscustomobject]@{ ExitCode = $code; DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1); OutLog = $outLog; ErrLog = $errLog }
}

function Add-Result {
    param([string]$Step, [string]$Status, [bool]$Mandatory, [double]$DurationSec, [object]$ExitCode, [hashtable]$Outputs)
    $script:Results.Add([ordered]@{
        step = $Step; status = $Status; mandatory = $Mandatory
        exitCode = $ExitCode; durationSec = [math]::Round($DurationSec, 1); outputs = $Outputs
    })
}

function Invoke-Step {
    # Runs $Body, which must return a hashtable @{ status = 'Passed'|'Failed'|'Warning'|'Skipped'; exitCode = ...; outputs = @{} }.
    # Exceptions become a Failed result. Returns $true when the pipeline may continue.
    param([string]$Name, [bool]$Mandatory, [scriptblock]$Body)
    Write-Step $Name
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = & $Body
        $sw.Stop()
        $exit = if ($r.ContainsKey('exitCode')) { $r['exitCode'] } else { $null }
        $outs = if ($r.ContainsKey('outputs')) { $r['outputs'] } else { @{} }
        Add-Result -Step $Name -Status $r['status'] -Mandatory $Mandatory -DurationSec $sw.Elapsed.TotalSeconds -ExitCode $exit -Outputs $outs
        if ($r['status'] -eq 'Failed') { Write-Warn ("step failed: {0}" -f $Name) }
        return -not ($Mandatory -and $r['status'] -eq 'Failed')
    }
    catch {
        $sw.Stop()
        Write-Warn ("exception: {0}" -f $_.Exception.Message)
        Add-Result -Step $Name -Status 'Failed' -Mandatory $Mandatory -DurationSec $sw.Elapsed.TotalSeconds -ExitCode $null -Outputs @{ error = $_.Exception.Message }
        return -not $Mandatory
    }
}

function Save-Json {
    param([string]$Name, [object]$Data)
    $path = Join-Path $script:LogDir $Name
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8
    Write-Info ("wrote {0}" -f $path)
}

function Get-PeHeaderInfo {
    # Minimal PE reader: DOS header e_lfanew -> "PE\0\0" -> COFF FileHeader -> optional header magic.
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        if ($br.ReadUInt16() -ne 0x5A4D) { throw "not an MZ file: $Path" }
        $fs.Seek(0x3C, 'Begin') | Out-Null
        $peOffset = $br.ReadUInt32()
        $fs.Seek($peOffset, 'Begin') | Out-Null
        if ($br.ReadUInt32() -ne 0x00004550) { throw "PE signature missing: $Path" }
        $machine = [int]$br.ReadUInt16()
        $null = $br.ReadUInt16()                    # NumberOfSections
        $stamp = $br.ReadUInt32()                   # TimeDateStamp (may be a reproducible-build hash)
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32()   # PointerToSymbolTable, NumberOfSymbols
        $optSize = $br.ReadUInt16()
        $chars = $br.ReadUInt16()
        $magic = if ($optSize -ge 2) { [int]$br.ReadUInt16() } else { 0 }
        $name = if ($script:PeMachineNames.ContainsKey($machine)) { $script:PeMachineNames[$machine] } else { 'unknown' }
        return [ordered]@{
            path = $Path
            bytes = (Get-Item $Path).Length
            sha256 = (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
            machineHex = ('0x{0:x}' -f $machine)
            architecture = $name
            is64Bit = ($magic -eq 0x20b)
            optionalHeaderMagicHex = ('0x{0:x}' -f $magic)
            characteristicsHex = ('0x{0:x}' -f $chars)
            timeDateStampRaw = $stamp
            timeDateStampUtc = ([DateTimeOffset]::FromUnixTimeSeconds($stamp)).UtcDateTime.ToString('o')
        }
    }
    finally { $fs.Dispose() }
}

function Get-ExpectedMember {
    # Look up a zip member's expected sha256/bytes from input-inventory.json; fall back to constants.
    param([hashtable]$Inventory, [string]$FileName)
    if ($null -ne $Inventory -and $Inventory.ContainsKey('archives')) {
        foreach ($a in $Inventory['archives']) {
            if ($a['filename'] -ne $script:ZipName) { continue }
            foreach ($m in $a['members']) {
                if ($m['path'] -eq "$($script:ZipTop)/$FileName") { return @{ sha256 = $m['sha256']; bytes = $m['bytes']; source = 'inventory' } }
            }
        }
    }
    if ($script:FallbackMemberSha256.ContainsKey($FileName)) { return @{ sha256 = $script:FallbackMemberSha256[$FileName]; bytes = $null; source = 'fallback' } }
    return $null
}

function Get-PresetGenerator {
    # Resolve the configure preset's generator, following "inherits" (string or array) depth-first.
    param([string]$Name)
    $presets = Get-Content (Join-Path $RepoRoot 'CMakePresets.json') -Raw | ConvertFrom-Json -AsHashtable
    $byName = @{}
    foreach ($p in $presets['configurePresets']) { $byName[$p['name']] = $p }
    $queue = [System.Collections.Generic.List[string]]::new(); $queue.Add($Name)
    while ($queue.Count -gt 0) {
        $n = $queue[0]; $queue.RemoveAt(0)
        if (-not $byName.ContainsKey($n)) { throw "configure preset '$n' not found in CMakePresets.json" }
        $p = $byName[$n]
        if ($p.ContainsKey('generator')) { return $p['generator'] }
        if ($p.ContainsKey('inherits')) { @($p['inherits']) | ForEach-Object { $queue.Add($_) } }
    }
    throw "configure preset '$Name' has no generator"
}

# ---------------------------------------------------------------- steps
function Step-Environment {
    $envInfo = [ordered]@{}
    $failures = [System.Collections.Generic.List[string]]::new()
    $onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $envInfo.os = [ordered]@{
        isWindows = $onWindows; version = [System.Environment]::OSVersion.VersionString
        osArchitecture = $osArch; processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        is64BitOS = [System.Environment]::Is64BitOperatingSystem
    }
    if ($onWindows) {
        try {
            $ci = Get-CimInstance Win32_OperatingSystem
            $envInfo.os.caption = $ci.Caption; $envInfo.os.build = $ci.BuildNumber; $envInfo.os.displayVersion = $ci.Version
        } catch { $envInfo.os.caption = "Get-CimInstance failed: $($_.Exception.Message)" }
    }
    if (-not $onWindows -or -not [System.Environment]::Is64BitOperatingSystem) { $failures.Add('requires 64-bit Windows') }
    if ($osArch -eq 'Arm64') { Write-Warn 'host is ARM64: an x64 build here runs under emulation and is a separate result per ACCEPTANCE.md' }
    Write-Info ("OS  : {0} / {1}" -f $envInfo.os.version, $osArch)

    $envInfo.powershell = $PSVersionTable.PSVersion.ToString()
    Write-Info ("pwsh: {0}" -f $envInfo.powershell)

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCmd) { $failures.Add('git not found on PATH'); $envInfo.git = $null }
    else {
        $envInfo.git = [ordered]@{
            path = $gitCmd.Source
            version = (Invoke-Native git @('--version')).Output -join ' '
            commit = (Invoke-Native git @('-C', $RepoRoot, 'rev-parse', 'HEAD')).Output -join ''
            branch = (Invoke-Native git @('-C', $RepoRoot, 'rev-parse', '--abbrev-ref', 'HEAD')).Output -join ''
            dirtyFiles = @((Invoke-Native git @('-C', $RepoRoot, 'status', '--porcelain')).Output | Where-Object { $_ })
        }
        Write-Info ("git : {0} @ {1} ({2} dirty)" -f $envInfo.git.branch, $envInfo.git.commit, $envInfo.git.dirtyFiles.Count)
    }

    $cmakeCmd = Get-Command cmake -ErrorAction SilentlyContinue
    if ($null -eq $cmakeCmd) { $failures.Add('cmake not found on PATH'); $envInfo.cmake = $null }
    else {
        $verLine = (Invoke-Native cmake @('--version')).Output | Select-Object -First 1
        $ver = $null
        if ($verLine -match '(\d+\.\d+\.\d+)') { $ver = [version]$Matches[1] }
        $envInfo.cmake = [ordered]@{ path = $cmakeCmd.Source; version = "$ver"; meetsMinimum = ($null -ne $ver -and $ver -ge [version]'3.29.0') }
        if (-not $envInfo.cmake.meetsMinimum) { $failures.Add("cmake >= 3.29 required, found '$verLine'") }
        Write-Info ("cmake: {0}" -f $ver)
    }

    # The preset's generator decides which VS major is required ("Visual Studio 18 2026" -> [18.0,19.0)).
    $generator = Get-PresetGenerator $Preset
    if ($generator -notmatch '^Visual Studio (\d+) (\d{4})$') { throw "preset '$Preset' uses '$generator'; this script only handles Visual Studio generators" }
    $vsMajor = [int]$Matches[1]; $vsLabel = "Visual Studio $($Matches[2])"
    $vsRange = '[{0}.0,{1}.0)' -f $vsMajor, ($vsMajor + 1)
    $envInfo.generator = [ordered]@{ preset = $Preset; name = $generator; vsVersionRange = $vsRange; supportedByCmake = $null }
    Write-Info ("gen : {0} (VS {1})" -f $generator, $vsRange)
    if ($null -ne $cmakeCmd) {
        # A CMake that predates the generator fails configure with a vague message; check up front instead.
        try {
            $caps = (Invoke-Native cmake @('-E', 'capabilities')).Output -join "`n" | ConvertFrom-Json -AsHashtable
            $envInfo.generator.supportedByCmake = [bool](@($caps['generators'] | Where-Object { $_['name'] -eq $generator }).Count)
            if (-not $envInfo.generator.supportedByCmake) { $failures.Add("cmake $($envInfo.cmake.version) does not offer generator '$generator' (upstream CMake added Visual Studio 18 2026 in 4.2)") }
        } catch { Write-Warn ("cmake -E capabilities failed: {0}" -f $_.Exception.Message) }
    }

    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    $envInfo.visualStudio = $null
    if (-not (Test-Path $vswhere)) { $failures.Add("vswhere.exe not found at $vswhere ($vsLabel not installed?)") }
    else {
        $vsJson = (Invoke-Native $vswhere @('-latest', '-products', '*', '-version', $vsRange,
            '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-format', 'json', '-utf8')).Output -join "`n"
        $vsList = @()
        if ($vsJson.Trim()) { $vsList = @($vsJson | ConvertFrom-Json -AsHashtable) }
        if ($vsList.Count -eq 0) { $failures.Add("no $vsLabel instance with Microsoft.VisualStudio.Component.VC.Tools.x86.x64 found") }
        else {
            $vs = $vsList[0]
            $envInfo.visualStudio = [ordered]@{
                installationPath = $vs['installationPath']; installationVersion = $vs['installationVersion']
                displayName = $vs['displayName']; vcToolsComponent = $true; cl = $null
            }
            Write-Info ("VS  : {0} ({1})" -f $vs['displayName'], $vs['installationVersion'])
            # cl.exe: locate the newest Hostx64\x64 toolset directly instead of sourcing vcvars64 (report only, never hard-fail).
            try {
                $cl = Get-ChildItem (Join-Path $vs['installationPath'] 'VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe') -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending | Select-Object -First 1
                if ($null -ne $cl) {
                    $clOut = (Invoke-Native $cl.FullName @()).Output | Where-Object { $_ -match 'Compiler Version' } | Select-Object -First 1
                    $envInfo.visualStudio.cl = [ordered]@{ path = $cl.FullName; banner = "$clOut"; toolsetDir = $cl.Directory.Parent.Parent.Parent.Name }
                    Write-Info ("cl  : {0}" -f $clOut)
                } else { Write-Warn 'cl.exe (Hostx64\x64) not found under VC\Tools\MSVC; reporting only' }
            } catch { Write-Warn ("cl.exe detection failed: {0}" -f $_.Exception.Message) }
        }
    }

    $driveRoot = [System.IO.Path]::GetPathRoot($WorkRoot)
    $di = [System.IO.DriveInfo]::new($driveRoot)
    $envInfo.disk = [ordered]@{ drive = $driveRoot; freeGiB = [math]::Round($di.AvailableFreeSpace / 1GB, 1); totalGiB = [math]::Round($di.TotalSize / 1GB, 1) }
    Write-Info ("disk: {0} free {1} GiB" -f $driveRoot, $envInfo.disk.freeGiB)
    if ($envInfo.disk.freeGiB -lt 20) { Write-Warn 'less than 20 GiB free; vcpkg + build typically need more' }

    $envInfo.paths = [ordered]@{ repoRoot = $RepoRoot; workRoot = $WorkRoot; vcpkgRoot = $VcpkgRoot; logDir = $script:LogDir }
    $envInfo.failures = @($failures)
    Save-Json 'environment.json' $envInfo
    $failures | ForEach-Object { Write-Warn $_ }
    return @{ status = ($(if ($failures.Count -eq 0) { 'Passed' } else { 'Failed' })); outputs = @{ failures = @($failures); osArchitecture = $osArch } }
}

function Step-Vcpkg {
    if (-not (Test-Path (Join-Path $VcpkgRoot '.git'))) {
        New-Item -ItemType Directory -Force (Split-Path -Parent $VcpkgRoot) | Out-Null
        $r = Invoke-Logged -Name 'vcpkg-clone' -FilePath 'git' -Arguments @('clone', 'https://github.com/microsoft/vcpkg', $VcpkgRoot) -WorkingDirectory $WorkRoot
        if ($r.ExitCode -ne 0) { return @{ status = 'Failed'; exitCode = $r.ExitCode; outputs = @{ log = $r.ErrLog } } }
    } else { Write-Info "vcpkg checkout exists: $VcpkgRoot" }
    $r = Invoke-Logged -Name 'vcpkg-checkout' -FilePath 'git' -Arguments @('-C', $VcpkgRoot, 'checkout', '--quiet', $VcpkgCommit) -WorkingDirectory $VcpkgRoot
    if ($r.ExitCode -ne 0) { return @{ status = 'Failed'; exitCode = $r.ExitCode; outputs = @{ log = $r.ErrLog } } }
    $actual = (Invoke-Native git @('-C', $VcpkgRoot, 'rev-parse', 'HEAD')).Output -join ''
    if ($actual -ne $VcpkgCommit) { return @{ status = 'Failed'; outputs = @{ expected = $VcpkgCommit; actual = $actual } } }
    $exe = Join-Path $VcpkgRoot 'vcpkg.exe'
    if (-not (Test-Path $exe)) {
        $bat = Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'
        $r = Invoke-Logged -Name 'vcpkg-bootstrap' -FilePath 'cmd.exe' -Arguments @('/c', $bat, '-disableMetrics') -WorkingDirectory $VcpkgRoot
        if ($r.ExitCode -ne 0 -or -not (Test-Path $exe)) { return @{ status = 'Failed'; exitCode = $r.ExitCode; outputs = @{ log = $r.ErrLog } } }
    } else { Write-Info 'vcpkg.exe already bootstrapped' }
    $env:VCPKG_ROOT = $VcpkgRoot
    Write-Info ("VCPKG_ROOT={0} @ {1}" -f $VcpkgRoot, $actual)
    return @{ status = 'Passed'; exitCode = 0; outputs = @{ vcpkgRoot = $VcpkgRoot; commit = $actual } }
}

function Step-Configure {
    if ($SkipBuild) { return @{ status = 'Skipped'; outputs = @{ reason = '-SkipBuild' } } }
    $r = Invoke-Logged -Name 'cmake-configure' -FilePath 'cmake' -Arguments @('--preset', $Preset) -WorkingDirectory $RepoRoot
    return @{ status = ($(if ($r.ExitCode -eq 0) { 'Passed' } else { 'Failed' })); exitCode = $r.ExitCode; outputs = @{ preset = $Preset; log = $r.OutLog; durationSec = $r.DurationSec } }
}

function Step-Build {
    if ($SkipBuild) { return @{ status = 'Skipped'; outputs = @{ reason = '-SkipBuild' } } }
    $r = Invoke-Logged -Name 'cmake-build' -FilePath 'cmake' -Arguments @('--build', '--preset', $BuildPreset) -WorkingDirectory $RepoRoot
    return @{ status = ($(if ($r.ExitCode -eq 0) { 'Passed' } else { 'Failed' })); exitCode = $r.ExitCode; outputs = @{ buildPreset = $BuildPreset; log = $r.OutLog; durationSec = $r.DurationSec } }
}

function Get-BuildConfiguration {
    # The output subfolder (RelWithDebInfo) comes from the build preset's "configuration" in CMakePresets.json.
    $presets = Get-Content (Join-Path $RepoRoot 'CMakePresets.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach ($bp in $presets['buildPresets']) { if ($bp['name'] -eq $BuildPreset) { return $bp['configuration'] } }
    throw "build preset '$BuildPreset' not found in CMakePresets.json"
}

function Step-Artifacts {
    $config = Get-BuildConfiguration
    $exe = Join-Path $RepoRoot ('out\{0}\{1}\{2}' -f $Preset, $config, $ExeName)
    # Debug links fmodL.dll (CMakeLists.txt FMOD IMPORTED_LOCATION_DEBUG); an explicit -FmodRelPath is kept as given.
    $fmodRel = $FmodRelPath
    if ($config -eq 'Debug' -and -not $script:FmodRelPathExplicit) { $fmodRel = $fmodRel -replace 'fmod\.dll$', 'fmodL.dll' }
    $dll = Join-Path $RepoRoot $fmodRel
    $missing = @($exe, $dll | Where-Object { -not (Test-Path $_) })
    if ($missing.Count -gt 0) { return @{ status = 'Failed'; outputs = @{ missing = $missing } } }
    $info = [ordered]@{ exe = (Get-PeHeaderInfo $exe); fmod = (Get-PeHeaderInfo $dll) }
    foreach ($k in $info.Keys) { Write-Info ("{0,-4}: {1} {2} 64bit={3} sha256={4}" -f $k, $info[$k].machineHex, $info[$k].architecture, $info[$k].is64Bit, $info[$k].sha256) }
    $script:ArtifactExe = $exe; $script:ArtifactDll = $dll
    Save-Json 'artifacts.json' $info
    $ok = ($info.exe.architecture -eq 'x64' -and $info.fmod.architecture -eq 'x64')
    if (-not $ok) { Write-Warn 'expected PE machine 0x8664 (x64) for both files' }
    return @{ status = ($(if ($ok) { 'Passed' } else { 'Failed' })); outputs = @{ exe = $exe; exeMachine = $info.exe.machineHex; fmodMachine = $info.fmod.machineHex } }
}

function Step-Extract {
    $inventory = $null
    if (Test-Path $script:InventoryPath) { $inventory = Get-Content $script:InventoryPath -Raw | ConvertFrom-Json -AsHashtable }
    else { Write-Warn "input-inventory.json not found; using fallback hashes" }
    $outputs = @{ lr2Root = $script:Lr2Root; members = @{} }

    if (-not $SkipExtract) {
        if (-not $ZipPath) { return @{ status = 'Failed'; outputs = @{ error = '-ZipPath is required unless -SkipExtract is set' } } }
        if (-not (Test-Path $ZipPath)) { return @{ status = 'Failed'; outputs = @{ error = "zip not found: $ZipPath" } } }
        $expSha = $script:FallbackZipSha256; $expBytes = $script:FallbackZipBytes
        if ($null -ne $inventory) { foreach ($a in $inventory['archives']) { if ($a['filename'] -eq $script:ZipName) { $expSha = $a['sha256']; $expBytes = $a['bytes'] } } }
        $zipItem = Get-Item $ZipPath
        $zipSha = (Get-FileHash -Algorithm SHA256 $ZipPath).Hash.ToLowerInvariant()
        $outputs.zip = @{ path = $zipItem.FullName; bytes = $zipItem.Length; sha256 = $zipSha; expectedSha256 = $expSha; expectedBytes = $expBytes }
        Write-Info ("zip : {0} bytes sha256={1}" -f $zipItem.Length, $zipSha)
        if ($zipSha -ne $expSha -or $zipItem.Length -ne $expBytes) { return @{ status = 'Failed'; outputs = $outputs + @{ error = 'zip hash/size mismatch; refusing to extract' } } }

        if (Test-Path $script:Lr2Fresh) {
            if (-not $Force) { return @{ status = 'Failed'; outputs = $outputs + @{ error = "$($script:Lr2Fresh) exists; pass -Force to replace or -SkipExtract to reuse" } } }
            Write-Warn "removing existing $($script:Lr2Fresh) (-Force)"
            Remove-Item -Recurse -Force $script:Lr2Fresh
        }
        New-Item -ItemType Directory -Force $script:Lr2Fresh | Out-Null
        # Entry names in LR2_100201.zip are not UTF-8 flagged (Shift_JIS/CP932 folder names). Decode with CP932 so
        # the on-disk names match what LR2 expects; fall back to Expand-Archive (mojibake names, still usable for WIN-01).
        try {
            [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
            $cp932 = [System.Text.Encoding]::GetEncoding(932)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipItem.FullName, $script:Lr2Fresh, $cp932)
            $outputs.entryNameEncoding = 'cp932'
        } catch {
            Write-Warn ("CP932 extraction failed ({0}); falling back to Expand-Archive" -f $_.Exception.Message)
            Expand-Archive -LiteralPath $zipItem.FullName -DestinationPath $script:Lr2Fresh -Force
            $outputs.entryNameEncoding = 'Expand-Archive default'
        }
    } else { Write-Info "-SkipExtract: reusing $($script:Lr2Root)" }

    if (-not (Test-Path $script:Lr2Root)) { return @{ status = 'Failed'; outputs = $outputs + @{ error = "missing $($script:Lr2Root)" } } }
    $allOk = $true
    foreach ($name in @('LR2body.exe', 'LR2.exe', 'fmodex.dll')) {
        $p = Join-Path $script:Lr2Root $name
        $exp = Get-ExpectedMember -Inventory $inventory -FileName $name
        $m = @{ exists = (Test-Path $p); expectedSha256 = $exp.sha256; expectedSource = $exp.source; sha256 = $null; match = $false }
        if ($m.exists) { $m.sha256 = (Get-FileHash -Algorithm SHA256 $p).Hash.ToLowerInvariant(); $m.match = ($m.sha256 -eq $exp.sha256) }
        if (-not $m.match) { $allOk = $false }
        Write-Info ("{0,-12} match={1} sha256={2}" -f $name, $m.match, $m.sha256)
        $outputs.members[$name] = $m
    }
    $outputs.configXmlPresent = Test-Path (Join-Path $script:Lr2Root 'LR2files\Config\config.xml')
    return @{ status = ($(if ($allOk) { 'Passed' } else { 'Failed' })); outputs = $outputs }
}

function Step-Stage {
    if (-not (Test-Path $script:Lr2Root)) { return @{ status = 'Failed'; outputs = @{ error = 'LR2 root missing; extract step did not succeed' } } }
    $files = @{}
    foreach ($src in @($script:ArtifactExe, $script:ArtifactDll)) {
        $dst = Join-Path $script:Lr2Root (Split-Path -Leaf $src)
        Copy-Item -LiteralPath $src -Destination $dst -Force      # LR2body.exe is intentionally left untouched
        $files[(Split-Path -Leaf $src)] = @{ from = $src; to = $dst; sha256 = (Get-FileHash -Algorithm SHA256 $dst).Hash.ToLowerInvariant(); bytes = (Get-Item $dst).Length }
        Write-Info ("staged {0}" -f $dst)
    }
    $originalKept = Test-Path (Join-Path $script:Lr2Root 'LR2body.exe')
    if ($SeedConfig) {
        # OpenLR2 exits with -1 ("JUKEBOX1 ...") when config.xml has no jukebox path. The zip ships no config.xml;
        # the original LR2.exe launcher normally writes it. -SeedConfig writes a minimal one pointing at the bundled
        # sample charts so a fresh directory can boot. ASCII only (parsed as CP932) and with a trailing newline (TinyXML quirk).
        $cfg = Join-Path $script:Lr2Root 'LR2files\Config\config.xml'
        if (Test-Path $cfg) { Write-Info 'config.xml already exists; -SeedConfig left it alone' }
        else {
            $xml = "<?xml version=`"1.0`" encoding=`"SHIFT_JIS`"?>`r`n<config>`r`n  <jukebox>`r`n    <path>LR2files/Config/</path>`r`n  </jukebox>`r`n</config>`r`n"
            [System.IO.File]::WriteAllText($cfg, $xml, [System.Text.Encoding]::ASCII)
            Write-Info "seeded minimal $cfg"
        }
        $files['config.xml'] = @{ to = $cfg; seeded = $true }
    }
    Save-Json 'staged.json' ([ordered]@{ lr2Root = $script:Lr2Root; originalLR2bodyKept = $originalKept; files = $files })
    return @{ status = 'Passed'; outputs = @{ lr2Root = $script:Lr2Root; originalLR2bodyKept = $originalKept } }
}

function Step-Launch {
    if (-not $Launch) { return @{ status = 'Skipped'; outputs = @{ reason = 'pass -Launch to start the game' } } }
    $exe = Join-Path $script:Lr2Root $ExeName
    if (-not (Test-Path $exe)) { return @{ status = 'Failed'; outputs = @{ error = "staged exe missing: $exe" } } }
    Write-Warn 'a GUI process started from an SSH/service session is not visible on the console desktop; liveness and files are the only evidence'
    if (-not (Test-Path (Join-Path $script:Lr2Root 'LR2files\Config\config.xml'))) {
        Write-Warn 'no LR2files\Config\config.xml: OpenLR2 will show a modal error (no jukebox path) and exit -1; use -SeedConfig or run LR2.exe first'
    }
    $startedAt = Get-Date
    $proc = if ($LaunchArgs) { Start-Process -FilePath $exe -ArgumentList $LaunchArgs -WorkingDirectory $script:Lr2Root -PassThru }
            else { Start-Process -FilePath $exe -WorkingDirectory $script:Lr2Root -PassThru }
    Write-Info ("pid {0}: {1} {2}" -f $proc.Id, $exe, $LaunchArgs)
    $exited = $proc.WaitForExit($LaunchWaitSeconds * 1000)
    $out = [ordered]@{ pid = $proc.Id; args = $LaunchArgs; waitSeconds = $LaunchWaitSeconds; exitedWithinWait = $exited; exitCode = $null; aliveAfterWait = (-not $exited); mainWindowTitle = $null; stopped = $false; collected = @() }
    if ($exited) { $proc.WaitForExit(); $out.exitCode = $proc.ExitCode; Write-Info ("exited with {0}" -f $out.exitCode) }
    else {
        try { $proc.Refresh(); $out.mainWindowTitle = $proc.MainWindowTitle } catch { $out.mainWindowTitle = $null }
        Write-Info ("still alive after {0}s (window: '{1}')" -f $LaunchWaitSeconds, $out.mainWindowTitle)
        if ($StopAfterWait) { Stop-Process -Id $proc.Id -Force; $out.stopped = $true; Write-Info 'stopped (-StopAfterWait)' }
    }
    # Collect config/log evidence produced by the run (openlr2-config.xml is written on normal shutdown, so it may be absent while alive).
    $dest = Join-Path $script:LogDir 'launch'
    New-Item -ItemType Directory -Force $dest | Out-Null
    $candidates = @(Get-ChildItem -LiteralPath (Join-Path $script:Lr2Root 'LR2files\Config') -Filter '*.xml' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('openlr2-config.xml', 'config.xml') })
    $candidates += @(Get-ChildItem -LiteralPath $script:Lr2Root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.log' -or $_.Name -eq 'Log.txt' })
    foreach ($f in $candidates) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -Force; $out.collected += $f.FullName }
    $out.filesWrittenAfterStart = @(Get-ChildItem -LiteralPath $script:Lr2Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $startedAt } | Select-Object -ExpandProperty FullName)
    # Main.cpp startup failures block in MessageBoxA(..., "エラー") before game init; a live process showing it is not a pass.
    $out.blockedByErrorDialog = ($out.aliveAfterWait -and $out.mainWindowTitle -eq 'エラー')
    if ($out.blockedByErrorDialog) { Write-Warn 'process is alive but showing the startup error dialog (エラー)' }
    if ($out.aliveAfterWait -and [string]::IsNullOrEmpty($out.mainWindowTitle)) {
        Write-Warn 'no window title visible (non-interactive session?); an error dialog cannot be ruled out'
    }
    Save-Json 'launch.json' $out
    $status = if ($out.blockedByErrorDialog) { 'Failed' } elseif ($out.aliveAfterWait -or $out.exitCode -eq 0) { 'Passed' } else { 'Failed' }
    return @{ status = $status; exitCode = $out.exitCode; outputs = @{ pid = $out.pid; aliveAfterWait = $out.aliveAfterWait; exitCode = $out.exitCode; window = $out.mainWindowTitle; blockedByErrorDialog = $out.blockedByErrorDialog } }
}

# ---------------------------------------------------------------- main
New-Item -ItemType Directory -Force $script:LogDir | Out-Null
if (-not (Test-Path (Join-Path $RepoRoot 'CMakePresets.json'))) { throw "RepoRoot does not look like the OpenLR2 repo: $RepoRoot" }
$script:ArtifactExe = $null; $script:ArtifactDll = $null
Write-Host ("WIN-01 baseline  repo={0}  work={1}  logs={2}" -f $RepoRoot, $WorkRoot, $script:LogDir)

$pipeline = @(
    @{ name = 'environment'; mandatory = $true;  body = ${function:Step-Environment} }
    @{ name = 'vcpkg';       mandatory = $true;  body = ${function:Step-Vcpkg} }
    @{ name = 'configure';   mandatory = $true;  body = ${function:Step-Configure} }
    @{ name = 'build';       mandatory = $true;  body = ${function:Step-Build} }
    @{ name = 'artifacts';   mandatory = $true;  body = ${function:Step-Artifacts} }
    @{ name = 'extract';     mandatory = $true;  body = ${function:Step-Extract} }
    @{ name = 'stage';       mandatory = $true;  body = ${function:Step-Stage} }
    @{ name = 'launch';      mandatory = $true;  body = ${function:Step-Launch} }
)
$continue = $true
foreach ($s in $pipeline) {
    if (-not $continue) { Add-Result -Step $s.name -Status 'Skipped' -Mandatory $s.mandatory -DurationSec 0 -ExitCode $null -Outputs @{ reason = 'earlier mandatory step failed' }; continue }
    $continue = Invoke-Step -Name $s.name -Mandatory $s.mandatory -Body $s.body
}

$failed = @($script:Results | Where-Object { $_.mandatory -and $_.status -eq 'Failed' })
$summary = [ordered]@{
    run = $script:RunStamp; repoRoot = $RepoRoot; workRoot = $WorkRoot; logDir = $script:LogDir
    preset = $Preset; buildPreset = $BuildPreset; vcpkgCommit = $VcpkgCommit
    overall = ($(if ($failed.Count -eq 0) { 'Passed' } else { 'Failed' })); steps = @($script:Results)
}
Write-Step 'summary'
$script:Results | ForEach-Object { [pscustomobject]@{ step = $_.step; status = $_.status; exit = $_.exitCode; sec = $_.durationSec } } | Format-Table -AutoSize | Out-String | Write-Host
Save-Json 'result.json' $summary
Write-Host ("overall: {0}" -f $summary.overall) -ForegroundColor ($(if ($failed.Count -eq 0) { 'Green' } else { 'Red' }))
exit ($(if ($failed.Count -eq 0) { 0 } else { 1 }))
