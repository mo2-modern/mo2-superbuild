<#
.SYNOPSIS
Pull upstream changes into every fork under repos/, following ADR-001.

.DESCRIPTION
Per repository: fast-forward `master` from `ModOrganizer2/*`, then merge `master` into `modern`.
Never rebases, never commits to `master` -- those are the two rules ADR-001 exists to enforce, and
this script cannot break them: `master` is advanced by a fast-forward-only ref update, so a `master`
that has been committed to fails loudly instead of being rewritten.

Reports by default and changes nothing. -Apply does the work. Conflicts are never auto-resolved:
the merge is aborted, the repository is left clean, and the name is reported so it can be handled
deliberately.

Adds a fetch-only `upstream` remote where one is missing, so it works on a fresh clone.

.PARAMETER Apply
Actually fast-forward master and merge into modern. Without it, nothing is modified.

.PARAMETER Push
With -Apply, push the updated master and modern to origin. Never pushes to upstream: the remote is
created with its push URL disabled.

.PARAMETER Only
Limit to the named repositories (directory names under repos/).

.EXAMPLE
.\scripts\sync-upstream.ps1
Fetch and report what a sync would do.

.EXAMPLE
.\scripts\sync-upstream.ps1 -Apply -Push
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Push,
    [string[]]$Only
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path (Join-Path $repoRoot ".gitmodules"))) { throw "Not the superbuild root: $repoRoot" }

# Fork name -> upstream name. Read from .gitmodules rather than assumed: the fork keeps upstream's
# repository name, which is not the same as the directory name (repos/uibase is
# ModOrganizer2/modorganizer-uibase).
$gitmodules = Get-Content (Join-Path $repoRoot ".gitmodules") -Raw
$subs = [regex]::Matches($gitmodules,
    '(?m)^\s*path\s*=\s*(?<path>repos/[^\r\n]+)\s*\r?\n\s*url\s*=\s*(?<url>[^\r\n]+)') |
    ForEach-Object {
        [pscustomobject]@{
            Name = Split-Path $_.Groups['path'].Value -Leaf
            Path = Join-Path $repoRoot ($_.Groups['path'].Value -replace '/', '\')
            Repo = ($_.Groups['url'].Value.Trim() -replace '\.git$','' -split '/')[-1]
        }
    }
if ($Only) { $subs = @($subs | Where-Object { $Only -contains $_.Name }) }
$subs = @($subs)   # a single match is a scalar, whose .Count prints as blank
if (-not $subs) { throw "No submodules matched." }

Write-Host ("{0} repositories; mode: {1}`n" -f $subs.Count, $(if ($Apply) { "APPLY" } else { "report only" }))

$behind = @(); $conflicted = @(); $advanced = @(); $problems = @()

foreach ($s in $subs) {
    # fetch-only upstream remote, created if absent so a fresh clone works
    & git -C $s.Path remote get-url upstream *> $null
    if ($LASTEXITCODE -ne 0) {
        & git -C $s.Path remote add upstream "https://github.com/ModOrganizer2/$($s.Repo)" *> $null
    }
    & git -C $s.Path remote set-url --push upstream DISABLED *> $null
    & git -C $s.Path fetch -q upstream master *> $null
    if ($LASTEXITCODE -ne 0) {
        $problems += "$($s.Name): cannot fetch upstream/master"
        Write-Host ("  {0,-32} FETCH FAILED" -f $s.Name) -ForegroundColor Red
        continue
    }

    $ahead = (& git -C $s.Path rev-list --count "origin/master..upstream/master").Trim()
    if ($ahead -eq "0") {
        Write-Host ("  {0,-32} up to date" -f $s.Name) -ForegroundColor DarkGray
        continue
    }

    # ADR-001: master is a mirror. If upstream is not a descendant, someone committed to master and
    # a "sync" would rewrite published history -- refuse rather than force.
    & git -C $s.Path merge-base --is-ancestor origin/master upstream/master *> $null
    if ($LASTEXITCODE -ne 0) {
        $problems += "$($s.Name): origin/master is NOT an ancestor of upstream/master -- master has been committed to"
        Write-Host ("  {0,-32} DIVERGED -- master is not a pure mirror" -f $s.Name) -ForegroundColor Red
        continue
    }

    $behind += $s.Name
    Write-Host ("  {0,-32} {1} new upstream commit(s)" -f $s.Name, $ahead) -ForegroundColor Yellow
    if (-not $Apply) { continue }

    # Fast-forward master without checking it out. Fails rather than rewrites if not a ff.
    & git -C $s.Path fetch upstream "master:master" *> $null
    if ($LASTEXITCODE -ne 0) { $problems += "$($s.Name): master fast-forward refused"; continue }

    & git -C $s.Path switch -q modern *> $null
    if ($LASTEXITCODE -ne 0) { $problems += "$($s.Name): cannot switch to modern"; continue }

    & git -C $s.Path merge --no-edit master *> $null
    if ($LASTEXITCODE -ne 0) {
        # Leave nothing half-merged; the human decides how to resolve, from a clean tree.
        & git -C $s.Path merge --abort *> $null
        $conflicted += $s.Name
        Write-Host ("  {0,-32} CONFLICT -- merge aborted, repository left clean" -f $s.Name) -ForegroundColor Red
        continue
    }

    $advanced += $s.Name
    if ($Push) {
        & git -C $s.Path push -q origin master modern *> $null
        if ($LASTEXITCODE -ne 0) { $problems += "$($s.Name): push failed" }
    }
}

Write-Host "`n---"
Write-Host ("behind upstream : {0}" -f $(if ($behind) { $behind -join ', ' } else { "none -- every repository is level with upstream" }))
if ($Apply) {
    Write-Host ("merged cleanly  : {0}" -f $(if ($advanced) { $advanced -join ', ' } else { "none" }))
    Write-Host ("CONFLICTED      : {0}" -f $(if ($conflicted) { $conflicted -join ', ' } else { "none" })) `
        -ForegroundColor $(if ($conflicted) { "Red" } else { "Gray" })
}
if ($problems) {
    Write-Host "`nproblems:" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

if ($Apply -and $advanced) {
    Write-Host "`nGitlinks in the superbuild now lag the submodules. Review and commit:"
    Write-Host "  git add $(($advanced | ForEach-Object { "repos/$_" }) -join ' ')"
    Write-Host "  git commit"
    Write-Host "`nThen rebuild before trusting anything -- a merge that compiles is not a merge that works."
}
if ($conflicted) { exit 1 }
