param(
    [string]$Ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$IndicatorScript = ''
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entry = Join-Path $root 'EnglishAutocomplete.ahk'
$indicatorEntry = if ($IndicatorScript) { [IO.Path]::GetFullPath($IndicatorScript) } else { '' }
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class EacNativeProbe {
    delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wp, IntPtr lp, uint flags, uint timeout, out UIntPtr result);
    public static IntPtr Window(uint targetPid) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((hwnd,p) => {
            uint pid; GetWindowThreadProcessId(hwnd,out pid);
            if(pid==targetPid) {
                var name=new StringBuilder(128); GetClassName(hwnd,name,128);
                if(name.ToString()=="AutoHotkey") {found=hwnd; return false;}
            }
            return true;
        },IntPtr.Zero);
        return found;
    }
    public static bool Responds(IntPtr hwnd) {
        UIntPtr result;
        return hwnd!=IntPtr.Zero && SendMessageTimeout(hwnd,0,UIntPtr.Zero,IntPtr.Zero,2,200,out result)!=IntPtr.Zero;
    }
}
'@
function Get-AhkProcesses {
    @(Get-CimInstance Win32_Process -Filter "name LIKE 'AutoHotkey%'" | Select-Object ProcessId,ExecutablePath,CommandLine)
}
function Sample-Cpu([int[]]$ProcessIds) {
    $initial = @{}
    foreach ($processId in $ProcessIds) { $initial[$processId]=(Get-Process -Id $processId).TotalProcessorTime.TotalSeconds }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 3000
    $seconds=$watch.Elapsed.TotalSeconds
    $result=@{}
    foreach ($processId in $ProcessIds) {
        $current=Get-Process -Id $processId
        $result[[string]$processId]=[math]::Round(($current.TotalProcessorTime.TotalSeconds-$initial[$processId])/$seconds*100,4)
    }
    return $result
}
$before=Get-AhkProcesses
$oldTarget=@($before | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($entry) })
$indicator=@($before | Where-Object { $indicatorEntry -and $_.CommandLine -and $_.CommandLine.Contains($indicatorEntry) })
$baseline=@{}
if ($indicator.Count -eq 1 -and $oldTarget.Count -eq 0) { $baseline=Sample-Cpu @([int]$indicator[0].ProcessId) }
$watch=[Diagnostics.Stopwatch]::StartNew()
$child=Start-Process -FilePath $Ahk -ArgumentList @('/restart',('"'+$entry+'"')) -WindowStyle Hidden -PassThru
$hwnd=[IntPtr]::Zero
while ($watch.Elapsed.TotalSeconds -lt 10) {
    $hwnd=[EacNativeProbe]::Window([uint32]$child.Id)
    if ([EacNativeProbe]::Responds($hwnd)) { break }
    Start-Sleep -Milliseconds 50
}
$responsiveMs=$watch.Elapsed.TotalMilliseconds
if (![EacNativeProbe]::Responds($hwnd)) { throw 'New autocomplete process is not responding' }
Start-Sleep -Milliseconds 500
$after=Get-AhkProcesses
$target=@($after | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($entry) })
if ($target.Count -ne 1) { throw "Expected one autocomplete process, got $($target.Count)" }
$targetId=[int]$target[0].ProcessId
if ($targetId -ne $child.Id) { throw 'Unexpected autocomplete PID after restart' }
$ids=@($targetId)
if ($indicator.Count -eq 1) { $ids+=[int]$indicator[0].ProcessId }
$coexist=Sample-Cpu $ids
$alive=Get-Process -Id $targetId
$missing=@($before | Where-Object { $_.ProcessId -notin @($after.ProcessId) -and $_.ProcessId -notin @($oldTarget.ProcessId) })
if ($missing.Count) { throw 'An unrelated AHK process exited during measurement; investigate before reporting preservation' }
$result=[ordered]@{
    measured=(Get-Date -Format o)
    executable=$Ahk
    version=(Get-Item -LiteralPath $Ahk).VersionInfo.FileVersion
    os=[Environment]::OSVersion.VersionString
    cpu_unit='percent of one logical CPU, process CPU seconds / wall seconds, 3-second idle sample'
    target=$target[0]
    target_count=$target.Count
    responds_to_WM_NULL=[EacNativeProbe]::Responds($hwnd)
    delayed_survival=$true
    process_to_responsive_window_ms=[math]::Round($responsiveMs,2)
    working_set_mb=[math]::Round($alive.WorkingSet64/1MB,2)
    private_mb=[math]::Round($alive.PrivateMemorySize64/1MB,2)
    baseline_indicator_cpu=$baseline
    coexist_cpu=$coexist
    indicator=$indicator
    unrelated_ahk_pids_preserved=@($before.ProcessId | Where-Object { $_ -notin @($oldTarget.ProcessId) })
    note='Leaves only the new autocomplete resident running. Does not stop/restart existing scripts. Other apps/AHK scripts remain active; no whole-system CPU claim.'
}
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $root 'docs/resident-metrics.json') -Encoding utf8
$result | ConvertTo-Json -Depth 7
