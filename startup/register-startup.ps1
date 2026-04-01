# register-startup.ps1
# Creates 6 Task Scheduler AtLogon tasks for silent startup apps
# Run as Administrator
# PowerShell v5 syntax

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$user = $env:USERNAME

function Register-StartupTask {
    param(
        [string]$TaskName,
        [string]$Execute,
        [string]$Arguments = '',
        [string]$WorkingDir = ''
    )

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        Write-Host "SKIP: $TaskName already exists (use -Force to recreate)" -ForegroundColor Yellow
        return
    }
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

    $actionParams = @{ Execute = $Execute }
    if ($Arguments) { $actionParams.Argument = $Arguments }
    if ($WorkingDir) { $actionParams.WorkingDirectory = $WorkingDir }
    $action = New-ScheduledTaskAction @actionParams

    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force:$Force | Out-Null

    Write-Host "OK: $TaskName registered" -ForegroundColor Green
}

Write-Host "=== Registering 6 Silent Startup Tasks ===" -ForegroundColor Cyan
Write-Host "User: $user"

# 1. AutoHotkey via VBS
Register-StartupTask -TaskName 'Startup_AutoHotkey' `
    -Execute 'wscript.exe' `
    -Arguments 'C:\Users\micha\startup_ahk.vbs'

# 2. ClawdBot via VBS
Register-StartupTask -TaskName 'Startup_ClawdBot' `
    -Execute 'wscript.exe' `
    -Arguments '//B "C:\Users\micha\ClawdBot_Startup.vbs"'

# 3. FullScreenSnip via VBS
Register-StartupTask -TaskName 'Startup_FullScreenSnip' `
    -Execute 'wscript.exe' `
    -Arguments 'C:\Users\micha\startup_snip.vbs'

# 4. OpenSpeedy direct
$speedyPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Game1024.OpenSpeedy_Microsoft.Winget.Source_8wekyb3d8bbwe\Speedy.exe"
Register-StartupTask -TaskName 'Startup_OpenSpeedy' `
    -Execute $speedyPath `
    -Arguments '--minimize-to-tray'

# 5. RamOptimizer via VBS
Register-StartupTask -TaskName 'Startup_RamOptimizer' `
    -Execute 'wscript.exe' `
    -Arguments 'C:\Users\micha\startup_ramopt.vbs'

# 6. Signal direct
$signalPath = "$env:LOCALAPPDATA\Programs\signal-desktop\Signal.exe"
Register-StartupTask -TaskName 'Startup_Signal' `
    -Execute $signalPath `
    -Arguments '--start-in-tray --use-tray-icon'

Write-Host "`n=== Verification ===" -ForegroundColor Cyan
Get-ScheduledTask -TaskName 'Startup_*' | Select-Object TaskName, State | Format-Table -AutoSize

Write-Host "Done. All 6 startup tasks registered." -ForegroundColor Green
