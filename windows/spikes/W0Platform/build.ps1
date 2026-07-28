Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root "bin"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$vcvars = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    throw "Could not find Visual Studio Build Tools vcvars64.bat at $vcvars"
}

$sdkVersion = "10.0.26100.0"
$include = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVersion"
$lib = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib\$sdkVersion"
if (-not (Test-Path $include) -or -not (Test-Path $lib)) {
    throw "Could not find Windows SDK $sdkVersion"
}

$common = @(
    "/nologo", "/std:c++20", "/EHsc", "/W4", "/DUNICODE", "/D_UNICODE", "/DNOMINMAX",
    "/I`"$include\cppwinrt`"", "/I`"$include\shared`"", "/I`"$include\um`"", "/I`"$include\ucrt`""
)

function Invoke-Cl([string]$Source, [string]$Exe, [string[]]$Libs) {
    $src = Join-Path $root $Source
    $target = Join-Path $out $Exe
    $libArgs = $Libs -join " "
    $cmd = "call `"$vcvars`" >nul && cl $($common -join ' ') `"$src`" /Fe:`"$target`" /link /LIBPATH:`"$lib\um\x64`" /LIBPATH:`"$lib\ucrt\x64`" $libArgs"
    cmd /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "cl failed for $Source"
    }
}

Invoke-Cl "wgc_capture_probe.cpp" "wgc_capture_probe.exe" @("windowsapp.lib", "d3d11.lib", "dxgi.lib", "runtimeobject.lib", "user32.lib")
Invoke-Cl "wasapi_mf_sync_probe.cpp" "wasapi_mf_sync_probe.exe" @("mfplat.lib", "mfreadwrite.lib", "mfuuid.lib", "d3d11.lib", "dxgi.lib", "gdi32.lib", "ole32.lib", "avrt.lib")
Invoke-Cl "clipboard_png_probe.cpp" "clipboard_png_probe.exe" @("user32.lib", "gdi32.lib", "windowscodecs.lib", "ole32.lib")

Write-Host "Built probes in $out"
