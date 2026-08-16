<#
.SYNOPSIS
Export unmodified upstream MO2 sources into a directory the superbuild can build.

.DESCRIPTION
Each fork under repos/ keeps `master` as an untouched mirror of upstream (ADR-001), so upstream's
tree is already in the objects you cloned -- no network, no second clone of several GB. This walks
every submodule and exports one ref per repository with `git archive`.

Nothing under repos/ is touched: no checkout, no branch switch, no fetch. The submodules stay
exactly where the gitlinks put them, so an interrupted run leaves nothing to clean up.

.PARAMETER Destination
Where to write the exported tree. Defaults to ..\mo2-upstream beside the repository.

.PARAMETER Ref
Which ref to export from each submodule. Defaults to origin/master -- the upstream mirror. Use
upstream/master if you have added upstream remotes and fetched them, which is the only way to get
anything newer than the last sync.

.PARAMETER Force
Overwrite Destination if it already exists.

.EXAMPLE
.\scripts\export-upstream.ps1
Exports to ..\mo2-upstream and prints the cmake command to build it.

.EXAMPLE
.\scripts\export-upstream.ps1 -Destination D:\mo2-og -Ref upstream/master -Force
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [string]$Ref = "origin/master",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path (Join-Path $repoRoot ".gitmodules"))) {
    throw "Not the superbuild root: $repoRoot"
}

if (-not $Destination) { $Destination = Join-Path (Split-Path $repoRoot -Parent) "mo2-upstream" }

if (Test-Path $Destination) {
    if (-not $Force) {
        throw "$Destination already exists. Pass -Force to overwrite, or choose another -Destination."
    }
    Remove-Item -Recurse -Force $Destination
}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$Destination = (Resolve-Path $Destination).Path

Write-Host "Exporting '$Ref' from every repository under repos/ into:"
Write-Host "  $Destination`n"

$repos = Get-ChildItem (Join-Path $repoRoot "repos") -Directory | Sort-Object Name
$exported = 0
$skipped = @()

foreach ($r in $repos) {
    # Resolve first: a repository whose fork has no master (or no upstream mirror) should be named,
    # not silently produce an empty directory that fails much later inside CMake.
    $sha = & git -C $r.FullName rev-parse --verify --quiet "$Ref^{commit}" 2>$null
    if (-not $sha) {
        $skipped += $r.Name
        Write-Host ("  {0,-32} SKIPPED -- no '{1}'" -f $r.Name, $Ref) -ForegroundColor Yellow
        continue
    }

    $out = Join-Path $Destination $r.Name
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    # archive|tar rather than a checkout: it writes a clean tree with no .git, and cannot disturb
    # the submodule's own working tree or index.
    & git -C $r.FullName archive $sha | & tar -x -C $out
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for $($r.Name)" }

    $exported++
    Write-Host ("  {0,-32} {1}" -f $r.Name, $sha.Substring(0, 8))
}

Write-Host "`n$exported repositories exported$(if ($skipped) { ", $($skipped.Count) skipped: $($skipped -join ', ')" })"

if (-not (Test-Path (Join-Path $Destination "uibase/CMakeLists.txt"))) {
    throw "Export looks wrong: no uibase/CMakeLists.txt under $Destination"
}

# The one deviation upstream forces, reported rather than patched: patching it would mean the tree
# is no longer what the label says. See ADR-028 and the ARCHITECTURE note on fork-independence.
$versions = Join-Path $Destination "cmake_common/mo2_versions.cmake"
if (Test-Path $versions) {
    $pin = [regex]::Match((Get-Content $versions -Raw),
        'mo2_set_if_not_defined\(MO2_PYTHON_VERSION\s+"([0-9.]+)"').Groups[1].Value
    $have = @(& py --list 2>$null | Select-String -Pattern '^\s*-V:(\d+\.\d+)' -AllMatches |
              ForEach-Object { $_.Matches[0].Groups[1].Value })
    Write-Host "`nUpstream pins Python $pin (plugin_python requires it EXACT)."
    if ($have -and ($have -notcontains $pin)) {
        Write-Host "  You have: $($have -join ', ') -- configure will stop at the preflight." -ForegroundColor Yellow
        Write-Host "  Install $pin from python.org, or edit MO2_PYTHON_VERSION in the exported"
        Write-Host "  cmake_common (which makes the tree no longer strictly upstream)."
    }
}

$build = Join-Path $Destination ".build"
$install = Join-Path $Destination ".install"

Write-Host "`nBuild it with a SEPARATE build and install directory, so your own tree is untouched:`n"
Write-Host "  cmake -S `"$repoRoot`" -B `"$build`" ``"
Write-Host "    -G `"Visual Studio 18 2026`" -T v145 -A x64 ``"
Write-Host "    -DCMAKE_TOOLCHAIN_FILE=`"$repoRoot/vcpkg/scripts/buildsystems/vcpkg.cmake`" ``"
Write-Host "    -DVCPKG_TARGET_TRIPLET=x64-windows-static-md ``"
Write-Host "    -DCMAKE_CONFIGURATION_TYPES=RelWithDebInfo ``"
Write-Host "    -DCMAKE_INSTALL_PREFIX=`"$install`" ``"
Write-Host "    -DCMAKE_DISABLE_FIND_PACKAGE_WrapVulkanHeaders=ON ``"
Write-Host "    -DMO2_SOURCE_ROOT=`"$Destination`""
Write-Host "`n  cmake --build `"$build`" --config RelWithDebInfo"
Write-Host "  cmake --install `"$build`" --config RelWithDebInfo"
Write-Host "`nNote: --preset vs2026 cannot be used here -- the preset hardcodes binaryDir, which would"
Write-Host "point the upstream build at your own build/ tree."
