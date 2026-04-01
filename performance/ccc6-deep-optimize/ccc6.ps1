#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CCC6: PARALLEL Deep C: Drive Space Recovery - 30 sections, LIVE progress
.NOTES
    Author: Till's automation stack | Updated: 2026-03-30
    Location: F:\study\Platforms\windows\performance\ccc6-deep-optimize\ccc6.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$t = Get-Date
$volBefore = (Get-Volume -DriveLetter C -EA 0).SizeRemaining

Write-Host '================================================================' -ForegroundColor Magenta
Write-Host '  CCC6: PARALLEL DEEP SPACE RECOVERY (30 simultaneous jobs)    ' -ForegroundColor Magenta
Write-Host '  Zero overlap with cccc/ccc1/ccc3/ccc4/ccc5/cleanc/bin/rmvol  ' -ForegroundColor Magenta
Write-Host '  ZERO network operations - all local filesystem only           ' -ForegroundColor Magenta
Write-Host '================================================================' -ForegroundColor Magenta
Write-Host "Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
Write-Host ''

# Progress tracking file
$progressFile = "$env:TEMP\ccc6-progress.txt"
'' | Set-Content $progressFile -Force

# ============================================================
# SHARED CLEANUP FUNCTION (injected into every job)
# ============================================================
$sharedFunctions = {
    $ErrorActionPreference = 'SilentlyContinue'
    $ProgressPreference = 'SilentlyContinue'
    $freed = [long]0
    $ops = 0
    $pf = $args[1]
    function SZ($p) { if (Test-Path $p -EA 0) { (Get-ChildItem $p -Recurse -Force -EA 0 | Measure-Object Length -Sum -EA 0).Sum } else { 0 } }
    function CL($path, $daysOld = 0) {
        $script:ops++
        if (Test-Path $path -EA 0) {
            $cutoff = (Get-Date).AddDays(-$daysOld)
            $items = if ($daysOld -gt 0) { Get-ChildItem $path -Force -Recurse -EA 0 | Where-Object { $_.LastWriteTime -lt $cutoff } } else { Get-ChildItem $path -Force -Recurse -EA 0 }
            $s = ($items | Measure-Object Length -Sum -EA 0).Sum
            $script:freed += $s; $items | Remove-Item -Recurse -Force -EA 0
        }
    }
    function SW($root, $patterns, $days = 0, $depth = 5) {
        $script:ops++
        if (!(Test-Path $root -EA 0)) { return }
        $cutoff = (Get-Date).AddDays(-$days)
        foreach ($pat in $patterns) {
            Get-ChildItem $root -Filter $pat -Recurse -Force -Depth $depth -EA 0 |
                Where-Object { !$_.PSIsContainer -and ($days -eq 0 -or $_.LastWriteTime -lt $cutoff) } |
                ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
        }
    }
    function RS($path, $name, $value, $type = 'DWord') {
        $script:ops++
        if (!(Test-Path $path)) { New-Item -Path $path -Force -EA 0 | Out-Null }
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -EA 0
    }
    function PG($msg) {
        Add-Content -Path $script:pf -Value $msg -EA 0
    }
}

# ============================================================
# LAUNCH ALL 30 SECTIONS AS PARALLEL JOBS
# ============================================================
$jobs = @()

# --- JOB 1: Deep FS Sweep ---
$jobs += Start-Job -Name 'S01-FSSweep' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    SW 'C:\Program Files' @('*.tmp','*.temp','*.bak','*.old','*.log.bak','*.log.old') 7 4
    SW 'C:\Program Files (x86)' @('*.tmp','*.temp','*.bak','*.old','*.log.bak','*.log.old') 7 4
    SW 'C:\ProgramData' @('*.tmp','*.temp','~*.*','*.~*') 14 4
    SW "$env:LOCALAPPDATA" @('*.tmp','*.temp','CrashReport*.xml','*.stackdump') 3 4
    SW "$env:APPDATA" @('*.tmp','*.temp','*.crash','*.crashlog') 3 4
    SW 'C:\Users\micha' @('Thumbs.db','desktop.ini','*.tmp','~$*.*') 0 3
    CL 'C:\$WINDOWS.~BT\Sources\SafeOS'; CL 'C:\$WinREAgent\Scratch'; CL 'C:\$SysReset\AppxLogs'
    CL 'C:\Recovery\Logs'; CL 'C:\Recovery\OEM'; CL 'C:\Windows\CbsTemp'
    SW 'C:\Windows\servicing\Packages' @('*.cat.bak','*.mum.bak','*.cat~*','*.mum~*') 0 1
    Get-ChildItem 'C:\Windows' -Directory -Force -EA 0 | Where-Object { $_.Name -match '^\$NtUninstall|^\$hf_mig\$|^\$NtServicePackUninstall' } | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0; $script:ops++ }
    SW 'C:\Windows\INF' @('setupapi.dev.log','setupapi.setup.log','setupapi.offline.log','setupapi.app.log') 0 1
    SW 'C:\Windows\INF' @('*.PNF') 30 1
    Get-ChildItem 'C:\Windows' -Filter '*.tmp' -Force -File -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    Get-ChildItem 'C:\' -Filter '*.dmp' -Force -File -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    Get-ChildItem 'C:\' -Filter '*.log' -Force -File -EA 0 | Where-Object { $_.Length -gt 1MB } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    CL 'C:\PerfLogs'; CL 'C:\Windows\Performance\WinSAT' 7
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 2: Dev Tool Caches ---
$jobs += Start-Job -Name 'S02-DevCaches' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $gc = & go env GOCACHE 2>$null; if ($gc -and (Test-Path $gc)) { $script:freed += (SZ $gc); Remove-Item "$gc\*" -Recurse -Force -EA 0 }
    $gm = & go env GOMODCACHE 2>$null; if ($gm -and (Test-Path $gm)) { $script:freed += (SZ $gm); & go clean -modcache 2>$null }
    CL "$env:USERPROFILE\.cargo\registry\cache"; CL "$env:USERPROFILE\.cargo\registry\src"; CL "$env:USERPROFILE\.cargo\git\checkouts"; CL "$env:USERPROFILE\.cargo\git\db"
    CL "$env:USERPROFILE\.gradle\caches\transforms-*"; CL "$env:USERPROFILE\.gradle\caches\build-cache-*"; CL "$env:USERPROFILE\.gradle\daemon"; CL "$env:USERPROFILE\.gradle\native"
    if (Get-Command conda -EA 0) { conda clean --all -y 2>$null | Out-Null }
    CL "$env:USERPROFILE\.conda\pkgs"; CL "$env:USERPROFILE\miniconda3\pkgs"; CL "$env:USERPROFILE\anaconda3\pkgs"
    CL "$env:USERPROFILE\.gem\cache"; CL "$env:LOCALAPPDATA\Composer\cache"; CL "$env:APPDATA\Composer\cache"
    CL "$env:LOCALAPPDATA\Yarn\Cache"; CL "$env:APPDATA\yarn\Cache"
    if (Get-Command pnpm -EA 0) { pnpm store prune 2>$null | Out-Null }
    CL "$env:USERPROFILE\.bun\install\cache"
    CL "$env:LOCALAPPDATA\deno\deps"; CL "$env:LOCALAPPDATA\deno\gen"; CL "$env:LOCALAPPDATA\deno\npm"; CL "$env:LOCALAPPDATA\deno\registries"
    if (Get-Command scoop -EA 0) { scoop cache rm * 2>$null | Out-Null }
    CL "$env:USERPROFILE\scoop\cache"; CL "$env:LOCALAPPDATA\vcpkg\archives"; CL "$env:LOCALAPPDATA\vcpkg\downloads"
    CL 'C:\msys64\var\cache\pacman\pkg'; CL 'C:\MinGW\var\cache'
    CL "$env:APPDATA\terraform.d\plugin-cache"; CL "$env:USERPROFILE\.terraform.d\plugin-cache"; CL "$env:USERPROFILE\.pulumi\plugins" 30
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 3: IDE Caches ---
$jobs += Start-Job -Name 'S03-IDECaches' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $jb = "$env:LOCALAPPDATA\JetBrains"
    if (Test-Path $jb) { Get-ChildItem $jb -Directory -EA 0 | ForEach-Object { foreach ($s in @('caches','index','tmp','log','tomcat','GradleUserHome')) { CL (Join-Path $_.FullName $s) } } }
    foreach ($ide in @('Cursor','Windsurf')) { foreach ($s in @('Cache','CachedData','CachedExtensionVSIXs','Code Cache','Crashpad','logs')) { CL "$env:APPDATA\$ide\$s" } }
    CL "$env:APPDATA\Sublime Text\Cache"; CL "$env:APPDATA\Sublime Text 3\Cache"
    CL "$env:APPDATA\.atom\compile-cache"; CL "$env:APPDATA\.pulsar\compile-cache"
    CL "$env:USERPROFILE\.vscode\extensions\.obsolete"
    $ext = "$env:USERPROFILE\.vscode\extensions"
    if (Test-Path $ext) {
        $exts = Get-ChildItem $ext -Directory -EA 0 | Where-Object { $_.Name -match '^(.+?)-(\d+\.\d+\.\d+.*)$' }
        $groups = @{}; foreach ($e in $exts) { $m = [regex]::Match($e.Name, '^(.+?)-(\d+\.\d+\.\d+.*)$'); $b = $m.Groups[1].Value; if (!$groups[$b]) { $groups[$b] = @() }; $groups[$b] += $e }
        foreach ($k in $groups.Keys) { if ($groups[$k].Count -gt 1) { $sorted = $groups[$k] | Sort-Object { $m = [regex]::Match($_.Name, '-(\d+\.\d+\.\d+)'); try{[version]$m.Groups[1].Value}catch{[version]'0.0.0'} }; $sorted | Select-Object -SkipLast 1 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0; $script:ops++ } } }
    }
    CL "$env:LOCALAPPDATA\Microsoft\VisualStudio\Packages\_Instances"; CL "$env:LOCALAPPDATA\Microsoft\VisualStudio\17.0\ComponentModelCache"
    CL "$env:LOCALAPPDATA\Microsoft\VisualStudio\17.0\Designer\ShadowCache"; CL "$env:LOCALAPPDATA\Microsoft\VisualStudio\17.0\IntelliTrace"
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Directory -EA 0 | Where-Object { $_.Name -match '^\d' -and $_.Name -notlike '17.*' } | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0; $script:ops++ }
    SW "$env:LOCALAPPDATA\Temp" @('MSBuild*','Temporary*','dotnet-*') 1 1
    CL "$env:LOCALAPPDATA\Microsoft\Windows\Symbols\symcache"; CL "$env:LOCALAPPDATA\Temp\SymbolCache"
    Get-ChildItem "$env:LOCALAPPDATA\JetBrains" -Directory -EA 0 | Where-Object { $_.Name -match 'Resharper|Rider' } | ForEach-Object { CL (Join-Path $_.FullName 'SolutionCaches') }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 4: Docker/WSL2 ---
$jobs += Start-Job -Name 'S04-DockerWSL' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    if (Get-Command docker -EA 0) { docker system prune -a -f --volumes 2>$null | Out-Null; $script:ops += 6 }
    CL "$env:LOCALAPPDATA\Docker\wsl\data\tmp"; CL "$env:LOCALAPPDATA\Docker\log"; CL "$env:APPDATA\Docker\log"; CL "$env:APPDATA\Docker Desktop\log"
    $vhdx = "$env:LOCALAPPDATA\Docker\wsl\data\ext4.vhdx"
    if (Test-Path $vhdx -EA 0) {
        $sz = (Get-Item $vhdx -Force -EA 0).Length
        if ($sz -gt 5GB) {
            wsl --shutdown 2>$null; Start-Sleep 3
            $dp = "$env:TEMP\compact_docker.txt"
            "select vdisk file=`"$vhdx`"`r`nattach vdisk readonly`r`ncompact vdisk`r`ndetach vdisk" | Set-Content $dp -Encoding ASCII
            Start-Process diskpart -ArgumentList ("/s",$dp) -Wait -WindowStyle Hidden -EA 0
            Remove-Item $dp -Force -EA 0
            $after = (Get-Item $vhdx -Force -EA 0).Length; $script:freed += [math]::Max(0,$sz - $after)
        }
    }
    # Also compact WSL distro VHDXs
    Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Force -EA 0 | Where-Object { $_.Name -match 'Ubuntu|Debian|Kali|SUSE|Pengwin' } | ForEach-Object {
        $v = Get-ChildItem $_.FullName -Filter 'ext4.vhdx' -Recurse -Force -EA 0 | Select-Object -First 1
        if ($v -and $v.Length -gt 2GB) {
            $sz = $v.Length; $dp = "$env:TEMP\compact_wsl_$($_.Name.Substring(0,8)).txt"
            "select vdisk file=`"$($v.FullName)`"`r`nattach vdisk readonly`r`ncompact vdisk`r`ndetach vdisk" | Set-Content $dp -Encoding ASCII
            Start-Process diskpart -ArgumentList ("/s",$dp) -Wait -WindowStyle Hidden -EA 0
            Remove-Item $dp -Force -EA 0
            $after = (Get-Item $v.FullName -Force -EA 0).Length; $script:freed += [math]::Max(0,$sz - $after)
        }
    }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 5: .NET NGen/GAC/NuGet ---
$jobs += Start-Job -Name 'S05-DotNet' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $n64 = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\ngen.exe'
    $n32 = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\ngen.exe'
    if (Test-Path $n64) { Start-Process $n64 -ArgumentList 'executeQueuedItems' -Wait -WindowStyle Hidden -EA 0 }
    if (Test-Path $n32) { Start-Process $n32 -ArgumentList 'executeQueuedItems' -Wait -WindowStyle Hidden -EA 0 }
    CL 'C:\Windows\assembly\tmp'; CL 'C:\Windows\assembly\temp'
    CL 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files'
    CL 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\Temporary ASP.NET Files'
    SW 'C:\Windows\Microsoft.NET' @('*.pdb','*.ilk') 0 4
    CL "$env:LOCALAPPDATA\NuGet\v3-cache"; CL "$env:LOCALAPPDATA\NuGet\plugins-cache"
    CL "$env:USERPROFILE\.dotnet\toolResolverCache"; CL "$env:USERPROFILE\.dotnet\TelemetryStorageService"
    CL "$env:USERPROFILE\.dotnet\.toolpackagecache"; CL "$env:LOCALAPPDATA\Temp\NuGetScratch"
    CL "$env:LOCALAPPDATA\Temp\dotnet"; CL "$env:LOCALAPPDATA\Temp\VBCSCompiler"
    SW "$env:LOCALAPPDATA\NuGet" @('*.lock','*.tmp') 1 3
    $dt = "$env:USERPROFILE\.dotnet\tools\.store"
    if (Test-Path $dt) { Get-ChildItem $dt -Directory -EA 0 | ForEach-Object { $v = Get-ChildItem $_.FullName -Directory -EA 0 | Sort-Object Name; if ($v.Count -gt 1) { $v | Select-Object -SkipLast 1 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 } } } }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 6: Hyper-V/Sandbox ---
$jobs += Start-Job -Name 'S06-HyperV' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL 'C:\ProgramData\Microsoft\Windows\Containers\BaseImages'; CL 'C:\ProgramData\Microsoft\Windows\Containers\Sandboxes'
    CL 'C:\ProgramData\Microsoft\Windows\Hyper-V\Snapshots'; CL 'C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks'
    CL "$env:LOCALAPPDATA\Microsoft\Windows\Hyper-V\Logs"
    Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Hyper-V' -Filter '*.vsv' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
    Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Hyper-V' -Filter '*.bin' -Recurse -Force -EA 0 | Where-Object { $_.Length -gt 100MB } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
    CL "$env:APPDATA\VMware\*.log"; CL "$env:LOCALAPPDATA\Temp\vmware-*"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 7: WebView2/Electron/Chrome caches ---
$jobs += Start-Job -Name 'S07-Electron' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage" 3
    CL "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\IndexedDB" 7
    Get-ChildItem "$env:LOCALAPPDATA" -Directory -Recurse -Force -Filter 'EBWebView' -Depth 3 -EA 0 | ForEach-Object {
        foreach ($s in @('Default\Cache','Default\Code Cache','Default\GPUCache','ShaderCache','GrShaderCache','BrowserMetrics')) { CL (Join-Path $_.FullName $s) }
    }
    Get-ChildItem "$env:LOCALAPPDATA" -Directory -Recurse -Force -Filter 'CefSharp' -Depth 3 -EA 0 | ForEach-Object { $script:freed += (SZ $_.FullName); Get-ChildItem $_.FullName -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    foreach ($app in @('signal','figma','postman','notion','todoist','obsidian','bitwarden','whatsapp','telegram','zoom','slack','discord','teams')) {
        Get-ChildItem "$env:APPDATA","$env:LOCALAPPDATA" -Directory -Force -EA 0 | Where-Object { $_.Name -like "*$app*" } | ForEach-Object {
            foreach ($s in @('Cache','Code Cache','GPUCache','CachedData','blob_storage','Crashpad','logs','IndexedDB')) { CL (Join-Path $_.FullName $s) }
        }
    }
    $ch = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path $ch) { Get-ChildItem $ch -Directory -Force -EA 0 | Where-Object { $_.Name -match '^(Default|Profile)' } | ForEach-Object { foreach ($s in @('IndexedDB','Local Storage\leveldb','File System','Service Worker\CacheStorage','Service Worker\ScriptCache')) { CL (Join-Path $_.FullName $s) } } }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 8: Git GC ---
$jobs += Start-Job -Name 'S08-GitGC' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $gd = Get-ChildItem 'C:\Users\micha' -Directory -Recurse -Force -Filter '.git' -Depth 5 -EA 0
    foreach ($g in $gd) {
        $r = $g.Parent.FullName; $b = SZ $g.FullName
        Push-Location $r; git reflog expire --expire=now --all 2>$null | Out-Null; git gc --prune=now 2>$null | Out-Null; Pop-Location
        $script:freed += [math]::Max(0,$b - (SZ $g.FullName)); $script:ops++
    }
    CL "$env:LOCALAPPDATA\GitCredentialManager"; CL "$env:APPDATA\GitHub Desktop\Cache"; CL "$env:APPDATA\GitHub Desktop\Code Cache"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 9: Assessment/Reliability/Diagnostics ---
$jobs += Start-Job -Name 'S09-Diagnostics' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL 'C:\ProgramData\Microsoft\RAC\PublishedData'; CL 'C:\ProgramData\Microsoft\RAC\StateData'; CL 'C:\ProgramData\Microsoft\RAC\Temp'
    CL 'C:\Windows\Performance\WinSAT\DataStore'
    CL 'C:\ProgramData\Microsoft\Diagnosis\EventTranscript'; CL 'C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings'; CL 'C:\ProgramData\Microsoft\Diagnosis\Scenarios'
    CL 'C:\Windows\Panther\UnattendGC'; CL 'C:\Windows\Panther\Rollback'
    CL 'C:\Windows\System32\SMI\Store\Machine' 30; CL 'C:\Windows\System32\wbem\AutoRecover'
    CL 'C:\Windows\appcompat\Programs' 30; CL 'C:\Windows\appcompat\appraiser' 30
    CL 'C:\Windows\Registration\CRMLog'
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 10: NTFS Journal/FS Optimization ---
$jobs += Start-Job -Name 'S10-NTFS' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    fsutil usn deletejournal /d C: 2>$null | Out-Null; fsutil usn createjournal m=33554432 a=4194304 C: 2>$null | Out-Null
    if (Test-Path 'F:\') { fsutil usn deletejournal /d F: 2>$null | Out-Null; fsutil usn createjournal m=33554432 a=4194304 F: 2>$null | Out-Null }
    fsutil behavior set mftzone 2 2>$null | Out-Null
    fsutil behavior set disable8dot3 C: 1 2>$null | Out-Null; fsutil behavior set disable8dot3 F: 1 2>$null | Out-Null
    fsutil 8dot3name strip /s /v C:\Windows\Temp 2>$null | Out-Null
    fsutil volume flush C: 2>$null | Out-Null; fsutil volume flush F: 2>$null | Out-Null
    fsutil resource setautoreset true C:\ 2>$null | Out-Null
    $script:ops = 12
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 11: Memory/Process trim (NO network ops) ---
$jobs += Start-Job -Name 'S11-Memory' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class MT { [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a, bool b, int c); [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h); [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h); }
"@ -EA 0
    Get-Process -EA 0 | Where-Object { $_.WorkingSet64 -gt 50MB -and $_.ProcessName -notin @('System','Idle','csrss','wininit','winlogon','smss','lsass','dwm') } | ForEach-Object {
        $h = [MT]::OpenProcess(0x1F0FFF,$false,$_.Id); if ($h -ne [IntPtr]::Zero) { [MT]::EmptyWorkingSet($h) | Out-Null; [MT]::CloseHandle($h) | Out-Null; $script:ops++ }
    }
    [System.GC]::Collect(2,[System.GCCollectionMode]::Forced,$true,$true); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class SC { [DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int c, ref int i, int l); }
"@ -EA 0
    $cmd = 4; try { [SC]::NtSetSystemInformation(80,[ref]$cmd,4) | Out-Null } catch {}
    $script:ops += 4
    [PSCustomObject]@{Freed=0;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 12: Credential/Token cleanup ---
$jobs += Start-Job -Name 'S12-Creds' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    cmdkey /list 2>$null | Select-String 'Target:' | ForEach-Object { $t = ($_ -replace '.*Target:\s*','').Trim(); if ($t -match 'LegacyGeneric|WindowsLive|virtualapp') { cmdkey /delete:$t 2>$null | Out-Null; $script:ops++ } }
    CL "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache"; CL "$env:APPDATA\Microsoft\Windows\AccountPictures"
    klist purge -li 0x3e7 2>$null | Out-Null; klist purge 2>$null | Out-Null
    CL "$env:LOCALAPPDATA\Microsoft\Windows\CloudAPCache"
    CL 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc'
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 13: Store Apps cleanup ---
$jobs += Start-Job -Name 'S13-StoreApps' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $cap = "$env:USERPROFILE\Videos\Captures"
    if (Test-Path $cap) { Get-ChildItem $cap -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 } }
    $pkgs = "$env:LOCALAPPDATA\Packages"
    foreach ($pattern in @('*Clipchamp*','*Photos*','*YourPhone*','*PhoneExperienceHost*','*Maps*','*BingWeather*','*BingNews*','*MSN*','*WebExperience*','*Widget*','*MicrosoftStickyNotes*','*Calculator*','*Alarms*','*Feedback*','*GetHelp*','*ScreenSketch*','*People*','*WindowsMaps*','*ZuneMusic*','*ZuneVideo*','*Xbox*','*MixedReality*','*3DViewer*','*Paint*','*PowerAutomate*','*Todos*','*Family*')) {
        Get-ChildItem $pkgs -Directory -Force -EA 0 | Where-Object { $_.Name -like $pattern } | ForEach-Object {
            foreach ($s in @('LocalCache','TempState','LocalState\Legacy','AC\INetCache','LocalState\PhotosAppTile','LocalState\MediaDb','LocalState\ELocalState','AC\TokenBroker','AC\Microsoft')) { CL (Join-Path $_.FullName $s) }
        }
    }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 14: IIS/Web Server ---
$jobs += Start-Job -Name 'S14-WebServer' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL 'C:\inetpub\logs\LogFiles' 7; CL 'C:\inetpub\logs\FailedReqLogFiles' 3; CL 'C:\inetpub\temp\IIS Temporary Compressed Files'; CL 'C:\inetpub\temp\appPools'
    CL 'C:\wamp64\tmp'; CL 'C:\xampp\tmp'; CL 'C:\xampp\apache\logs' 7; CL 'C:\nginx\temp'; CL 'C:\nginx\logs' 7
    SW 'C:\Program Files' @('error.log','access.log','error.log.*','access.log.*') 7 4
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 15: PS History/Modules ---
$jobs += Start-Job -Name 'S15-PSCleanup' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $ph = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    if (Test-Path $ph) { $sz = (Get-Item $ph -Force -EA 0).Length; if ($sz -gt 5MB) { $l = Get-Content $ph -Tail 1000 -EA 0; $script:freed += ($sz - ($l -join "`n").Length); $l | Set-Content $ph -Force } }
    foreach ($mp in @("$env:USERPROFILE\Documents\PowerShell\Modules","$env:USERPROFILE\Documents\WindowsPowerShell\Modules","C:\Program Files\PowerShell\Modules")) {
        if (Test-Path $mp) { Get-ChildItem $mp -Directory -EA 0 | ForEach-Object { $v = Get-ChildItem $_.FullName -Directory -EA 0 | Where-Object { $_.Name -match '^\d+\.\d+' } | Sort-Object { try{[version]($_.Name -replace '[^\d\.]','')}catch{[version]'0.0'} }; if ($v.Count -gt 1) { $v | Select-Object -SkipLast 1 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 } } } }
    }
    CL "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\Help"
    SW "$env:USERPROFILE\Documents" @('PowerShell_transcript*') 0 1
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 16: Media Caches ---
$jobs += Start-Job -Name 'S16-Media' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL "$env:LOCALAPPDATA\Spotify\Data"; CL "$env:LOCALAPPDATA\Spotify\Storage"; CL "$env:LOCALAPPDATA\Spotify\Browser\Cache"; CL "$env:LOCALAPPDATA\Spotify\Browser\Code Cache"
    CL "$env:APPDATA\vlc\art" 30; CL "$env:APPDATA\vlc\crashpad"
    CL "$env:APPDATA\MPC-HC\shaders_cache"; CL "$env:APPDATA\MPC-BE\shaders_cache"
    SW "$env:TEMP" @('ffmpeg*','ffprobe*','av-*') 0 1
    CL "$env:APPDATA\obs-studio\plugin_config\obs-websocket"; CL "$env:APPDATA\obs-studio\profiler_data"; CL "$env:APPDATA\obs-studio\crashes"
    CL "$env:LOCALAPPDATA\Audacity\SessionData"; CL "$env:TEMP\audacity_*"; CL "$env:TEMP\HandBrake"
    CL "$env:APPDATA\Blackmagic Design\DaVinci Resolve\cache"
    CL "$env:LOCALAPPDATA\Microsoft\Media Player\Transcoded Files Cache"
    CL "$env:PROGRAMDATA\Dolby\DolbyAtmos\cache"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 17: Gaming Platform Caches ---
$jobs += Start-Job -Name 'S17-Gaming' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL "$env:LOCALAPPDATA\Steam\htmlcache\Cache"; CL "$env:LOCALAPPDATA\Steam\htmlcache\Code Cache"; CL "$env:LOCALAPPDATA\Steam\htmlcache\GPUCache"
    foreach ($sl in @('C:\Program Files (x86)\Steam','C:\Program Files\Steam','F:\games\Steam')) { if (Test-Path $sl) { CL "$sl\steamapps\shadercache"; CL "$sl\steamapps\temp"; CL "$sl\logs"; CL "$sl\dumps"; CL "$sl\steamapps\downloading" } }
    CL "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache"; CL "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs"
    CL "$env:LOCALAPPDATA\GOG.com\Galaxy\webcache"; CL "$env:PROGRAMDATA\GOG.com\Galaxy\logs"
    CL "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\cache"; CL "$env:LOCALAPPDATA\Origin\Cache"; CL "$env:PROGRAMDATA\Origin\Logs"
    CL "$env:LOCALAPPDATA\Ubisoft Game Launcher\cache"; CL "$env:LOCALAPPDATA\Ubisoft Game Launcher\logs"
    CL "$env:LOCALAPPDATA\Battle.net\Cache"; CL "$env:LOCALAPPDATA\Blizzard Entertainment\Battle.net\Cache"; CL "$env:PROGRAMDATA\Battle.net\Setup\Cache"
    CL "$env:LOCALAPPDATA\Riot Games\Riot Client\Cache"; CL "$env:LOCALAPPDATA\Riot Games\Riot Client\Logs"
    CL "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalCache"; CL "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\TempState"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 18: Communication Apps ---
$jobs += Start-Job -Name 'S18-CommApps' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL "$env:APPDATA\Telegram Desktop\tdata\emoji"; CL "$env:APPDATA\Telegram Desktop\tdata\user_data\cache"
    foreach ($a in @('Signal','WhatsApp')) { CL "$env:APPDATA\$a\Cache"; CL "$env:APPDATA\$a\GPUCache"; CL "$env:APPDATA\$a\Code Cache"; CL "$env:APPDATA\$a\logs" }
    CL "$env:APPDATA\Zoom\data\VirtualBkgnd_Custom"; CL "$env:APPDATA\Zoom\logs"; CL "$env:LOCALAPPDATA\Zoom\Temp"
    CL "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache"
    $tb = "$env:APPDATA\Thunderbird\Profiles"
    if (Test-Path $tb) { Get-ChildItem $tb -Directory -EA 0 | ForEach-Object { CL (Join-Path $_.FullName 'cache2'); CL (Join-Path $_.FullName 'startupCache') } }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 19: Font/Printer/Scanner ---
$jobs += Start-Job -Name 'S19-FontPrint' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $fd = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (Test-Path $fd) { $uf = Get-ChildItem $fd -EA 0; $sf = Get-ChildItem 'C:\Windows\Fonts' -EA 0 | Select-Object -ExpandProperty Name; $uf | Where-Object { $_.Name -in $sf } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 } }
    Stop-Service Spooler -Force -EA 0; CL 'C:\Windows\System32\spool\PRINTERS'; Start-Service Spooler -EA 0
    CL "$env:LOCALAPPDATA\Microsoft\Windows\WFS"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 20: Security/Defender ---
$jobs += Start-Job -Name 'S20-Security' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $dp = 'C:\ProgramData\Microsoft\Windows Defender\Definition Updates'
    if (Test-Path $dp) { $dd = Get-ChildItem $dp -Directory -EA 0 | Where-Object { $_.Name -match '^\{' } | Sort-Object LastWriteTime; if ($dd.Count -gt 1) { $dd | Select-Object -SkipLast 1 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 } } }
    CL 'C:\ProgramData\Microsoft\Windows Defender\Scans\RtSigs'
    CL 'C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection\Cyber'
    CL 'C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection\Downloads'
    CL "$env:APPDATA\Microsoft\SystemCertificates\My\CRLs"
    CL 'C:\Windows\Logs\MeasuredBoot' 7
    CL "$env:LOCALAPPDATA\Microsoft\Windows\AppCache"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 21: Cloud Storage ---
$jobs += Start-Job -Name 'S21-Cloud' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL "$env:LOCALAPPDATA\Google\DriveFS\Logs"
    CL "$env:LOCALAPPDATA\Dropbox\Crashpad"; CL "$env:LOCALAPPDATA\Dropbox\*.log"
    $dc = "$env:USERPROFILE\Dropbox\.dropbox.cache"; if (Test-Path $dc) { $script:freed += (SZ $dc); Get-ChildItem $dc -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    CL "$env:LOCALAPPDATA\Microsoft\OneDrive\StandaloneSyncClient\SyncEngineDatabase" 30
    CL "$env:LOCALAPPDATA\Mega Limited\MEGAsync\cache"; CL "$env:LOCALAPPDATA\Mega Limited\MEGAsync\logs"
    CL "$env:LOCALAPPDATA\pCloud\cache"; CL "$env:LOCALAPPDATA\Box\Box\cache"; CL "$env:LOCALAPPDATA\Nextcloud\logs"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 22: Windows Temp AGGRESSIVE (replaced network job) ---
$jobs += Start-Job -Name 'S22-TempAggressive' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    # User temp - everything older than 30 min
    $cutoff = (Get-Date).AddMinutes(-30)
    Get-ChildItem "$env:LOCALAPPDATA\Temp" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        if ($_.PSIsContainer) { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 }
        else { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
        $script:ops++
    }
    # Windows temp
    Get-ChildItem 'C:\Windows\Temp' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        if ($_.PSIsContainer) { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 }
        else { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
        $script:ops++
    }
    # Windows logs
    CL 'C:\Windows\Logs\CBS' 3; CL 'C:\Windows\Logs\DISM' 3; CL 'C:\Windows\Logs\WindowsUpdate' 3
    CL 'C:\Windows\Logs\waasmedia'; CL 'C:\Windows\Logs\SIH'; CL 'C:\Windows\Logs\NetSetup'
    CL 'C:\Windows\Logs\SystemRestore'; CL 'C:\Windows\Logs\dosvc'
    # WER
    CL 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'; CL 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
    CL "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"; CL "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
    # Delivery optimization (local only, no network)
    CL 'C:\Windows\SoftwareDistribution\DeliveryOptimization'
    # Windows Update download cache
    CL 'C:\Windows\SoftwareDistribution\Download'
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 23: Scheduled Tasks ---
$jobs += Start-Job -Name 'S23-Tasks' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    CL 'C:\Windows\System32\Tasks_Migrated'
    Get-ScheduledTask -EA 0 | Where-Object { $_.State -eq 'Ready' -and !$_.Actions } | ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -EA 0; $script:ops++ }
    $tasks = @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Autochk\Proxy','\Microsoft\Windows\CloudExperienceHost\CreateObjectTask','\Microsoft\Windows\DiskFootprint\Diagnostics','\Microsoft\Windows\License Manager\TempSignedLicenseExchange','\Microsoft\Windows\Maintenance\WinSAT','\Microsoft\Windows\PI\Sqm-Tasks','\Microsoft\Windows\SettingSync\BackgroundUploadTask','\Microsoft\Windows\Shell\FamilySafetyMonitor','\Microsoft\Windows\Windows Error Reporting\QueueReporting')
    foreach ($tk in $tasks) { $p = $tk -split '\\(?=[^\\]*$)'; $t2 = Get-ScheduledTask -TaskName $p[1] -TaskPath ($p[0]+'\') -EA 0; if ($t2 -and $t2.State -ne 'Disabled') { Disable-ScheduledTask -TaskName $p[1] -TaskPath ($p[0]+'\') -EA 0 | Out-Null; $script:ops++ } }
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 24: Services to Manual ---
$jobs += Start-Job -Name 'S24-Services' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    foreach ($svc in @('WpnService','CDPSvc','DevQueryBroker','diagsvc','DsSvc','EntAppSvc','FrameServer','GraphicsPerfSvc','LicenseManager','NaturalAuthentication','PerfHost','RmSvc','SCardSvr','ScDeviceEnum','stisvc','TieringEngineService','UevAgentService','WalletService')) {
        $s = Get-Service -Name $svc -EA 0; if ($s -and $s.StartType -eq 'Automatic') { Set-Service -Name $svc -StartupType Manual -EA 0; $script:ops++ }
    }
    [PSCustomObject]@{Freed=0;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 25: WU Component Reset ---
$jobs += Start-Job -Name 'S25-WUReset' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    Stop-Service wuauserv -Force -EA 0; Stop-Service cryptSvc -Force -EA 0; Stop-Service bits -Force -EA 0; Stop-Service msiserver -Force -EA 0
    $sd = 'C:\Windows\SoftwareDistribution'
    CL "$sd\DataStore"; CL "$sd\Download"; CL "$sd\PostRebootEventCache.V2"
    foreach ($dll in @('atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll','jscript.dll','vbscript.dll','scrrun.dll','msxml3.dll','msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll','rsaenh.dll','cryptdlg.dll','oleaut32.dll','ole32.dll','shell32.dll','wuapi.dll','wuaueng.dll','wucltui.dll','wups.dll','wups2.dll','wuweb.dll','qmgr.dll','qmgrprxy.dll')) { regsvr32.exe /s $dll 2>$null; $script:ops++ }
    Start-Service bits -EA 0; Start-Service cryptSvc -EA 0; Start-Service msiserver -EA 0; Start-Service wuauserv -EA 0
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 26: Disk Cleanup + Storage Sense ---
$jobs += Start-Job -Name 'S26-DiskCleanup' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches' -EA 0 | ForEach-Object { Set-ItemProperty $_.PSPath -Name 'StateFlags0100' -Value 2 -Type DWord -EA 0; $script:ops++ }
    Start-Process cleanmgr -ArgumentList '/sagerun:100','/D','C' -WindowStyle Hidden -Wait -EA 0
    RS 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1
    RS 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '04' 1
    RS 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '08' 1
    RS 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '256' 7
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 27: Large file cleanup ---
$jobs += Start-Job -Name 'S27-LargeFiles' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    foreach ($pat in @('C:\Users\micha\AppData\Local\Temp\*.iso','C:\Users\micha\AppData\Local\Temp\*.zip','C:\Users\micha\AppData\Local\Temp\*.msi','C:\Users\micha\AppData\Local\Temp\*.exe','C:\Users\micha\AppData\Local\Temp\*.cab','C:\Users\micha\AppData\Local\Temp\*.wim')) {
        Get-ChildItem $pat -Force -EA 0 | Where-Object { $_.Length -gt 50MB -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    }
    # Large temp files anywhere in user profile
    Get-ChildItem "$env:LOCALAPPDATA\Temp" -Recurse -Force -EA 0 | Where-Object { !$_.PSIsContainer -and $_.Length -gt 10MB -and $_.LastWriteTime -lt (Get-Date).AddHours(-1) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER' -Recurse -Force -EA 0 | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
    # Old Windows installers (safe - only orphaned)
    Get-ChildItem 'C:\Windows\Installer' -Filter '*.tmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0; $script:ops++ }
    # Old crash dumps
    CL 'C:\Windows\LiveKernelReports' 3
    CL 'C:\Windows\Minidump' 7
    CL "$env:LOCALAPPDATA\CrashDumps"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 28: ADS/Zone ID removal ---
$jobs += Start-Job -Name 'S28-ADS' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    Get-ChildItem 'F:\Downloads' -Recurse -Force -EA 0 | ForEach-Object { Remove-Item "$($_.FullName):Zone.Identifier" -Force -Stream Zone.Identifier -EA 0; $script:ops++ } | Out-Null
    Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Recurse -Force -Filter '*.exe' -EA 0 | ForEach-Object { Remove-Item "$($_.FullName):Zone.Identifier" -Force -Stream Zone.Identifier -EA 0 } | Out-Null
    $script:ops += 2
    [PSCustomObject]@{Freed=0;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 29: CompactOS + TRIM ---
$jobs += Start-Job -Name 'S29-CompactTRIM' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $cs = compact /compactos:query 2>$null | Select-String 'is not'
    if ($cs) { compact /compactos:always 2>$null | Out-Null }
    Get-Volume -EA 0 | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -EA 0; $script:ops++ }
    [PSCustomObject]@{Freed=0;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# --- JOB 30: Android SDK + Dev Debris ---
$jobs += Start-Job -Name 'S30-AndroidSDK' -ScriptBlock {
    . ([ScriptBlock]::Create($args[0])); $pf = $args[1]
    $sdk = "$env:LOCALAPPDATA\Android\Sdk"
    if (Test-Path $sdk) {
        CL "$sdk\.temp"; CL "$sdk\.downloadIntermediates"; CL "$sdk\emulator\crashpad_database"
        $p = Get-ChildItem "$sdk\platforms" -Directory -EA 0 | Sort-Object Name
        if ($p.Count -gt 2) { $p | Select-Object -SkipLast 2 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 } }
    }
    Get-ChildItem 'C:\Users\micha' -Directory -Recurse -Force -Filter '.ipynb_checkpoints' -Depth 6 -EA 0 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0 }
    SW 'C:\Users\micha' @('.eslintcache','.prettiercache','*.tsbuildinfo') 0 5
    # node_modules in temp/orphaned locations
    Get-ChildItem "$env:LOCALAPPDATA\Temp" -Directory -Recurse -Force -Filter 'node_modules' -Depth 3 -EA 0 | ForEach-Object { $script:freed += (SZ $_.FullName); Remove-Item $_.FullName -Recurse -Force -EA 0; $script:ops++ }
    # pip cache
    CL "$env:LOCALAPPDATA\pip\cache"; CL "$env:LOCALAPPDATA\pip\selfcheck"
    # npm cache
    CL "$env:APPDATA\npm-cache\_cacache"; CL "$env:APPDATA\npm-cache\_logs"
    [PSCustomObject]@{Freed=$freed;Ops=$ops}
} -ArgumentList $sharedFunctions.ToString(),$progressFile

# ============================================================
# LIVE PROGRESS MONITOR (real-time updates every 1s)
# ============================================================
Write-Host '  [LIVE] Monitoring 30 jobs...' -ForegroundColor Cyan
Write-Host ''

$deadline = (Get-Date).AddMinutes(5)
$totalFreed = [long]0
$totalOps = 0
$completed = 0
$failed = 0
$doneJobs = @{}
$spinner = @('|','/','-','\')
$tick = 0

while ($true) {
    $running = @($jobs | Where-Object { $_.State -eq 'Running' })
    $justFinished = @($jobs | Where-Object { $_.State -eq 'Completed' -and !$doneJobs[$_.Id] })

    foreach ($j in $justFinished) {
        $doneJobs[$j.Id] = $true
        $name = $j.Name -replace 'S\d+-',''
        $result = Receive-Job $j -EA 0
        $jFreed = 0; $jOps = 0
        if ($result.Freed) { $jFreed = $result.Freed; $totalFreed += $jFreed }
        if ($result.Ops) { $jOps = $result.Ops; $totalOps += $jOps }
        $completed++
        $freedMB = [math]::Round($jFreed/1MB)
        $elapsed = [math]::Round(((Get-Date) - $t).TotalSeconds)
        if ($freedMB -gt 0) {
            Write-Host "  $(Get-Date -Format 'HH:mm:ss') [${completed}/30] " -NoNewline -ForegroundColor White
            Write-Host "OK " -NoNewline -ForegroundColor Green
            Write-Host "$name " -NoNewline -ForegroundColor Yellow
            Write-Host "($jOps ops, ${freedMB}MB freed) " -NoNewline -ForegroundColor Cyan
            Write-Host "| Total: $([math]::Round($totalFreed/1MB))MB | ${elapsed}s" -ForegroundColor DarkGray
        } else {
            Write-Host "  $(Get-Date -Format 'HH:mm:ss') [${completed}/30] " -NoNewline -ForegroundColor White
            Write-Host "OK " -NoNewline -ForegroundColor Green
            Write-Host "$name " -NoNewline -ForegroundColor DarkGray
            Write-Host "($jOps ops) " -NoNewline -ForegroundColor DarkGray
            Write-Host "| Total: $([math]::Round($totalFreed/1MB))MB | ${elapsed}s" -ForegroundColor DarkGray
        }
    }

    # Check for failed/timed out
    $justFailed = @($jobs | Where-Object { $_.State -eq 'Failed' -and !$doneJobs[$_.Id] })
    foreach ($j in $justFailed) {
        $doneJobs[$j.Id] = $true
        $name = $j.Name -replace 'S\d+-',''
        $failed++; $completed++
        Write-Host "  $(Get-Date -Format 'HH:mm:ss') [${completed}/30] " -NoNewline -ForegroundColor White
        Write-Host "FAIL " -NoNewline -ForegroundColor Red
        Write-Host "$name" -ForegroundColor DarkGray
    }

    if ($running.Count -eq 0) { break }

    $remaining = [int]($deadline - (Get-Date)).TotalSeconds
    if ($remaining -le 0) {
        # Timeout remaining
        foreach ($j in $running) {
            $doneJobs[$j.Id] = $true
            Stop-Job $j -EA 0
            $name = $j.Name -replace 'S\d+-',''
            $failed++; $completed++
            Write-Host "  $(Get-Date -Format 'HH:mm:ss') [${completed}/30] " -NoNewline -ForegroundColor White
            Write-Host "TIMEOUT " -NoNewline -ForegroundColor Yellow
            Write-Host "$name" -ForegroundColor DarkGray
        }
        break
    }

    # Show spinner for still-running jobs every 3 seconds
    if ($tick % 3 -eq 0 -and $running.Count -gt 0) {
        $sp = $spinner[$tick % 4]
        $names = ($running | ForEach-Object { $_.Name -replace 'S\d+-','' }) -join ', '
        $elapsed = [math]::Round(((Get-Date) - $t).TotalSeconds)
        Write-Host "  $sp Running ($($running.Count)): $names | ${elapsed}s elapsed" -ForegroundColor DarkCyan
    }

    $tick++
    Start-Sleep -Seconds 1
}

# Clean up all jobs
$jobs | Remove-Job -Force -EA 0

# Final pass (inline, fast)
[System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
fsutil volume flush C: 2>$null | Out-Null

# ============================================================
# FINAL SUMMARY
# ============================================================
$elapsed = (Get-Date) - $t
$volAfter = (Get-Volume -DriveLetter C -EA 0).SizeRemaining
$actualFreed = if ($volBefore -and $volAfter) { [math]::Max(0, $volAfter - $volBefore) } else { 0 }

Write-Host ''
Write-Host '================================================================' -ForegroundColor Green
Write-Host '  CCC6 PARALLEL OPTIMIZATION --- COMPLETE                       ' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Time:       $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
Write-Host "  Jobs:       $($completed - $failed) OK / $failed failed" -ForegroundColor White
Write-Host "  Operations: $totalOps executed" -ForegroundColor White
Write-Host ''
Write-Host "  Tracked freed:   $([math]::Round($totalFreed/1GB,2)) GB" -ForegroundColor Yellow
if ($actualFreed -gt 0) { Write-Host "  Actual disk freed: $([math]::Round($actualFreed/1GB,2)) GB" -ForegroundColor Yellow }
Write-Host ''

$vol = Get-Volume -DriveLetter C -EA 0
if ($vol) {
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($vol.Size / 1GB, 2)
    $pct = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1)
    Write-Host "  C: $freeGB GB free / $totalGB GB ($pct%)" -ForegroundColor $(if ($pct -gt 20) {'Green'} elseif ($pct -gt 10) {'Yellow'} else {'Red'})
}
$volF = Get-Volume -DriveLetter F -EA 0
if ($volF) {
    $freeGB = [math]::Round($volF.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($volF.Size / 1GB, 2)
    $pct = [math]::Round(($volF.SizeRemaining / $volF.Size) * 100, 1)
    Write-Host "  F: $freeGB GB free / $totalGB GB ($pct%)" -ForegroundColor $(if ($pct -gt 20) {'Green'} elseif ($pct -gt 10) {'Yellow'} else {'Red'})
}
Write-Host ''
