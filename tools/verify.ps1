param(
    [string]$Ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [switch]$Integration,
    [switch]$CaseOnly,
    [switch]$ImeIntegration,
    [switch]$Dpi,
    [switch]$SelectionIntegration
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!(Test-Path -LiteralPath $Ahk)) { throw "AHK v2 executable missing: $Ahk" }
Write-Output "AHK=$Ahk Version=$((Get-Item -LiteralPath $Ahk).VersionInfo.FileVersion)"
function Invoke-Ahk([string]$Script, [string[]]$ExtraArgs = @()) {
    $out = Join-Path $root '.verify-stdout.tmp'
    $err = Join-Path $root '.verify-stderr.tmp'
    try {
        $arguments = @('/ErrorStdOut', ('"' + $Script + '"')) + $ExtraArgs
        $proc = Start-Process -FilePath $Ahk -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (!$proc.WaitForExit(60000)) {
            # Only the exact child created by this function may be terminated.
            $proc.Kill()
            throw "AHK verification timed out: $Script"
        }
        $proc.WaitForExit()
        Get-Content -LiteralPath $out,$err
        if ($proc.ExitCode -ne 0) { throw "AHK exit $($proc.ExitCode): $Script" }
        Write-Output "PASS exit=0 $Script"
    } finally {
        Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
    }
}
foreach ($entry in @('EnglishAutocomplete.ahk','ManageDictionary.ahk','tests/fixture.ahk','tests/ime-fixture.ahk')) {
    $wrapper = Join-Path $root '.syntax-check.ahk'
    try {
        $content = '#Requires AutoHotkey v2.0+' + "`n" + 'SetTimer(() => ExitApp(0), -100)' + "`n" + '#Include "' + (Join-Path $root $entry) + '"'
        [IO.File]::WriteAllText($wrapper,$content,[Text.UTF8Encoding]::new($true))
        Invoke-Ahk $wrapper
    } finally {
        Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
    }
}
Write-Output "Temporary syntax wrappers removed=$(!(Test-Path (Join-Path $root '.syntax-check.ahk')))"
if (Test-Path (Join-Path $root 'tests/core.ahk')) { Invoke-Ahk (Join-Path $root 'tests/core.ahk') }
if (Test-Path (Join-Path $root 'tests/ime.ahk')) { Invoke-Ahk (Join-Path $root 'tests/ime.ahk') }
if (Test-Path (Join-Path $root 'tests/navigation.ahk')) { Invoke-Ahk (Join-Path $root 'tests/navigation.ahk') }
if (Test-Path (Join-Path $root 'tests/uia.ahk')) { Invoke-Ahk (Join-Path $root 'tests/uia.ahk') }
if (Test-Path (Join-Path $root 'tests/sakura.ahk')) { Invoke-Ahk (Join-Path $root 'tests/sakura.ahk') }
if ($Integration) { Invoke-Ahk (Join-Path $root 'tests/integration.ahk') }
elseif ($CaseOnly) { Invoke-Ahk -Script (Join-Path $root 'tests/integration.ahk') -ExtraArgs @('--case-only') }
if ($ImeIntegration) { Invoke-Ahk (Join-Path $root 'tests/ime-integration.ahk') }
if ($Dpi) { Invoke-Ahk (Join-Path $root 'tests/dpi.ahk') }
if ($SelectionIntegration) { Invoke-Ahk (Join-Path $root 'tests/selection-integration.ahk') }
