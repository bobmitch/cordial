# Builds the Cordial VST on Windows using the Visual Studio 2022 toolchain
# and the Ninja generator. Run from any directory; paths resolve to the
# plugin/ root automatically.
#
#   pwsh -File scripts/build-windows.ps1               # Release build
#   pwsh -File scripts/build-windows.ps1 -Config Debug
#
# Prereqs (see docs/TOOLS.md):
#   * CMake >= 3.22
#   * Ninja
#   * MSVC Build Tools 2022 (run from a "x64 Native Tools Command Prompt"
#     OR ensure VsDevShell.ps1 has been sourced)
#   * Git

param(
    [ValidateSet('Debug','Release','RelWithDebInfo')]
    [string]$Config = 'Release',
    [string]$BuildDir = 'build'
)

$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $pluginRoot
try {
    Write-Host "Configuring Cordial VST ($Config) in $BuildDir" -ForegroundColor Cyan
    cmake -S . -B $BuildDir -G Ninja "-DCMAKE_BUILD_TYPE=$Config"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

    Write-Host "Building..." -ForegroundColor Cyan
    cmake --build $BuildDir --config $Config
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }

    Write-Host ""
    Write-Host "Built artifacts under: $pluginRoot\$BuildDir\CordialVST_artefacts\$Config" -ForegroundColor Green
}
finally {
    Pop-Location
}
