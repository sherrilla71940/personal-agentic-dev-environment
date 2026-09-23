# Run the managed worktree helper against disposable repositories containing non-secret
# fixtures. This script requires Windows PowerShell and Git for Windows.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$toolPath = (Resolve-Path (Join-Path $repositoryRoot "home\dot_local\share\git-worktree-provision.ps1")).Path
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\", "/")
$testRoot = Join-Path $temporaryParent ("git-worktree-provision-tests-" + [guid]::NewGuid().ToString("N"))
$passed = 0
$failed = 0

function Write-FixtureFile {
    param([string] $Path, [AllowEmptyString()][string] $Content)

    $parent = Split-Path -Parent $Path
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-TestProcess {
    param(
        [string] $WorkingDirectory,
        [string] $FilePath,
        [string[]] $Arguments
    )

    Push-Location $WorkingDirectory
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = ($output -join "`n")
        }
    } finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
}

function Invoke-FixtureGit {
    param(
        [string] $WorkingDirectory,
        [string[]] $Arguments,
        [switch] $AllowFailure
    )

    $result = Invoke-TestProcess $WorkingDirectory (Get-Command git.exe).Source $Arguments
    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($result.Output)"
    }
    return $result
}

function New-FixtureRepository {
    param([string] $Name)

    $path = Join-Path $testRoot $Name
    [IO.Directory]::CreateDirectory($path) | Out-Null
    Invoke-FixtureGit $path @("init", "--quiet", "--initial-branch=main") | Out-Null
    Invoke-FixtureGit $path @("config", "user.name", "Worktree Fixture") | Out-Null
    Invoke-FixtureGit $path @("config", "user.email", "fixture@example.invalid") | Out-Null

    $toolForShell = $toolPath.Replace("\", "/")
    $addAlias = "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$toolForShell`" add"
    $copyAlias = "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$toolForShell`" copy"
    $checkAlias = "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$toolForShell`" check"
    $readinessAlias = "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$toolForShell`" readiness"
    $provisionAlias = "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$toolForShell`" provision"
    Invoke-FixtureGit $path @("config", "alias.wt-add", $addAlias) | Out-Null
    Invoke-FixtureGit $path @("config", "alias.wt-copy", $copyAlias) | Out-Null
    Invoke-FixtureGit $path @("config", "alias.wt-check", $checkAlias) | Out-Null
    Invoke-FixtureGit $path @("config", "alias.wt-readiness", $readinessAlias) | Out-Null
    Invoke-FixtureGit $path @("config", "alias.wt-provision", $provisionAlias) | Out-Null

    Write-FixtureFile (Join-Path $path "README.md") "fixture`n"
    Invoke-FixtureGit $path @("add", "README.md") | Out-Null
    Invoke-FixtureGit $path @("commit", "--quiet", "-m", "fixture") | Out-Null
    return $path
}

function Add-Manifest {
    param(
        [string] $Repository,
        [string] $IgnoreContent,
        [string] $ManifestContent
    )

    Write-FixtureFile (Join-Path $Repository ".gitignore") $IgnoreContent
    Write-FixtureFile (Join-Path $Repository ".worktreeinclude") $ManifestContent
    Invoke-FixtureGit $Repository @("add", ".gitignore", ".worktreeinclude") | Out-Null
    Invoke-FixtureGit $Repository @("commit", "--quiet", "-m", "add worktree manifest") | Out-Null
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-OutputContains {
    param($Result, [string] $Expected, [string] $Message)
    if (-not $Result.Output.Contains($Expected)) {
        throw "$Message Output:`n$($Result.Output)"
    }
}

function Invoke-Case {
    param([string] $Name, [scriptblock] $Test)

    if ($env:WORKTREE_PROVISION_TEST_FILTER -and
        $Name -notlike "*$($env:WORKTREE_PROVISION_TEST_FILTER)*") {
        return
    }

    try {
        & $Test
        $script:passed++
        Write-Host "PASS $Name"
    } catch {
        $script:failed++
        Write-Host "FAIL $Name"
        Write-Host "  $($_.Exception.Message)"
    }
}

[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    Invoke-Case "create without manifest" {
        $repo = New-FixtureRepository "no-manifest"
        $target = Join-Path $testRoot "no-manifest-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Creation without a manifest should succeed."
        Assert-OutputContains $result "[skipped] .worktreeinclude" "The missing manifest should be reported."
        Assert-True (Test-Path -LiteralPath (Join-Path $target ".git")) "The worktree was not created."
    }

    Invoke-Case "resolve target-base manifest before creation" {
        $repo = New-FixtureRepository "target-base-manifest"
        $target = Join-Path $testRoot "target-base-manifest-target"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.local`npackages/`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "source-value`n"
        Write-FixtureFile (Join-Path $repo "packages.config") "<packages />`n"
        Invoke-FixtureGit $repo @("add", ".gitignore", "packages.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ignored prerequisites") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "-b", "target-base") | Out-Null
        Write-FixtureFile (Join-Path $repo ".worktreeinclude") ".env.local`n"
        Invoke-FixtureGit $repo @("add", ".worktreeinclude") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add target-base manifest") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "main") | Out-Null

        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "target-base") -AllowFailure
        Assert-Equal 3 $result.ExitCode "A target-base manifest and missing dependency directory must block before creation."
        Assert-OutputContains $result "Manifest: target-base" "The target-base manifest source should be reported."
        Assert-OutputContains $result "[matched] .env.local" "The target-base manifest entry should be evaluated."
        Assert-OutputContains $result "[dependency-directory] packages/: missing" "The missing ignored dependency directory should be reported."
        Assert-OutputContains $result "Provisioning verdict: cannot-determine-build-prerequisites" "The verdict should distinguish unknown build readiness."
        Assert-True (-not (Test-Path -LiteralPath $target)) "The blocked worktree was created."
    }

    Invoke-Case "copy from target-base manifest when source lacks it" {
        $repo = New-FixtureRepository "copy-target-manifest"
        $target = Join-Path $testRoot "copy-target-manifest-target"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "source-value`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ignored source") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "-b", "target-base") | Out-Null
        Write-FixtureFile (Join-Path $repo ".worktreeinclude") ".env.local`n"
        Invoke-FixtureGit $repo @("add", ".worktreeinclude") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add target manifest") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "main") | Out-Null
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "target-base") | Out-Null

        $result = Invoke-FixtureGit $target @("wt-copy", "--source", $repo) -AllowFailure
        Assert-Equal 0 $result.ExitCode "wt-copy should use the target worktree manifest."
        Assert-OutputContains $result "Manifest: target" "The target manifest should be used for copying."
        Assert-OutputContains $result "[copied] .env.local" "The target manifest entry should be copied."
        Assert-Equal "source-value" ([IO.File]::ReadAllText((Join-Path $target ".env.local")).Trim()) "The target manifest file was not copied."
    }

    Invoke-Case "report differing source and target manifests as a union" {
        $repo = New-FixtureRepository "union-manifests"
        $target = Join-Path $testRoot "union-manifests-target"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.source`n.env.target`n"
        Write-FixtureFile (Join-Path $repo ".env.source") "source`n"
        Write-FixtureFile (Join-Path $repo ".env.target") "target`n"
        Write-FixtureFile (Join-Path $repo ".worktreeinclude") ".env.source`n"
        Invoke-FixtureGit $repo @("add", ".gitignore", ".worktreeinclude") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add source manifest") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "-b", "target-base") | Out-Null
        Write-FixtureFile (Join-Path $repo ".worktreeinclude") ".env.target`n"
        Invoke-FixtureGit $repo @("add", ".worktreeinclude") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "change target manifest") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "main") | Out-Null
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "target-base") | Out-Null

        $result = Invoke-FixtureGit $target @("wt-check", "--source", $repo, "--target", $target) -AllowFailure
        Assert-Equal 0 $result.ExitCode "Source and target manifest differences should be reportable."
        Assert-OutputContains $result "[manifest-source] source" "The source manifest should be identified."
        Assert-OutputContains $result "[manifest-source] target" "The target manifest should be identified."
        Assert-OutputContains $result "[would-copy] .env.source" "The source manifest entry should be included."
        Assert-OutputContains $result "[would-copy] .env.target" "The target manifest entry should be included."
    }

    Invoke-Case "report required ignored dependency directory when present" {
        $repo = New-FixtureRepository "dependency-directory-present"
        Write-FixtureFile (Join-Path $repo ".gitignore") "packages/`n"
        Write-FixtureFile (Join-Path $repo "packages\legacy.props") "dependency`n"
        Write-FixtureFile (Join-Path $repo "packages.config") "<packages />`n"
        Invoke-FixtureGit $repo @("add", ".gitignore", "packages.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add dependency marker") | Out-Null

        $result = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 0 $result.ExitCode "A present ignored dependency directory should remain advisory."
        Assert-OutputContains $result "[dependency-directory] packages/: present" "The present ignored dependency directory should be reported."
        Assert-True (-not $result.Output.Contains("cannot-determine-build-prerequisites")) "A present dependency directory was treated as unknown."
    }

    Invoke-Case "block unlisted ignored files without explicit override" {
        $repo = New-FixtureRepository "unlisted-blocked"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "local`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ignore rule") | Out-Null
        $target = Join-Path $testRoot "unlisted-blocked-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 3 $result.ExitCode "Unlisted ignored configuration should require an explicit override."
        Assert-OutputContains $result "Decision: eligible-ignored-files-unlisted" "The unlisted decision was not reported."
        Assert-True (-not (Test-Path -LiteralPath $target)) "The blocked worktree was created."
    }

    Invoke-Case "read-only check reports unlisted ignored files" {
        $repo = New-FixtureRepository "check-unlisted"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "local`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ignore rule") | Out-Null
        $target = Join-Path $testRoot "check-unlisted-target"
        $result = Invoke-FixtureGit $repo @("wt-check", "--target", $target) -AllowFailure
        Assert-Equal 3 $result.ExitCode "The check should require a decision for an unlisted ignored file."
        Assert-OutputContains $result "[unlisted] .env.local" "The unlisted file was not reported."
        Assert-OutputContains $result "Writes: none" "The check did not declare its read-only behavior."
        Assert-True (-not (Test-Path -LiteralPath $target)) "The read-only check created the target."
    }

    Invoke-Case "redact sensitive values from provisioning records" {
        $repo = New-FixtureRepository "redaction"
        Write-FixtureFile (Join-Path $repo ".gitignore") "password=DO-NOT-PRINT`n"
        Write-FixtureFile (Join-Path $repo "password=DO-NOT-PRINT") "secret-content`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add redaction fixture") | Out-Null
        $check = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 3 $check.ExitCode "An unlisted sensitive-looking path should remain advisory."
        Assert-OutputContains $check "[unlisted] password=[REDACTED]" "The sensitive path was not redacted in preflight."
        Assert-True (-not $check.Output.Contains("DO-NOT-PRINT")) "The sensitive value leaked from preflight."
        $target = Join-Path $testRoot "redaction-target"
        $add = Invoke-FixtureGit $repo @("wt-add", "--allow-unprovisioned", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $add.ExitCode "Allowing an unprovisioned worktree should succeed."
        Assert-OutputContains $add "[unlisted] password=[REDACTED]" "The sensitive path was not redacted in provisioning output."
        Assert-True (-not $add.Output.Contains("DO-NOT-PRINT")) "The sensitive value leaked from provisioning output."
        $error = Invoke-FixtureGit $repo @("wt-provision", "--bad=password=DO-NOT-PRINT") -AllowFailure
        Assert-Equal 2 $error.ExitCode "An invalid provisioning option should fail."
        Assert-OutputContains $error "password=[REDACTED]" "The provisioning error did not redact sensitive text."
        Assert-True (-not $error.Output.Contains("DO-NOT-PRINT")) "The provisioning error leaked a sensitive value."
    }

    Invoke-Case "ignore Python cache artifacts" {
        $repo = New-FixtureRepository "python-cache"
        Write-FixtureFile (Join-Path $repo ".gitignore") "__pycache__/`n*.pyc`n"
        Write-FixtureFile (Join-Path $repo "__pycache__\module.pyc") "cache`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add cache ignore rule") | Out-Null
        $result = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Python cache artifacts should not require provisioning."
        Assert-OutputContains $result "Decision: no-manifest-needed" "The cache-only decision was not reported."
        Assert-True (-not $result.Output.Contains("[unlisted]")) "Python cache artifacts were treated as eligible."
    }

    Invoke-Case "read-only check distinguishes an empty manifest" {
        $repo = New-FixtureRepository "check-empty-manifest"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        $result = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 0 $result.ExitCode "An empty manifest should be reportable without failing."
        Assert-OutputContains $result "Manifest: tracked" "The tracked manifest was not reported."
        Assert-OutputContains $result "Decision: manifest-present-no-matches" "The empty-manifest decision was not reported."
    }

    Invoke-Case "read-only check reports raw worktree omission and conflict" {
        $repo = New-FixtureRepository "check-raw"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "source`n"
        $target = Join-Path $testRoot "check-raw-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $result = Invoke-FixtureGit $target @("wt-check", "--source", $repo, "--target", $target) -AllowFailure
        Assert-Equal 0 $result.ExitCode "A raw worktree check should succeed."
        Assert-OutputContains $result "[would-copy] .env.local" "The omitted file was not reported as a copy candidate."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target ".env.local"))) "The read-only check copied the file."
        Write-FixtureFile (Join-Path $target ".env.local") "existing`n"
        $conflict = Invoke-FixtureGit $target @("wt-check", "--source", $repo, "--target", $target) -AllowFailure
        Assert-OutputContains $conflict "[conflict] .env.local" "The existing target conflict was not reported."
    }

    Invoke-Case "read-only check reports required local configuration" {
        $repo = New-FixtureRepository "check-required"
        $result = Invoke-FixtureGit $repo @("wt-check", "--required", ".env.local") -AllowFailure
        Assert-Equal 2 $result.ExitCode "A missing required file should fail the check."
        Assert-OutputContains $result "[required-missing] .env.local" "The required missing file was not reported."
        Assert-OutputContains $result "Decision: required-local-config-missing" "The required-config decision was not reported."
    }

    Invoke-Case "readiness reports modified tracked configuration without copying it" {
        $repo = New-FixtureRepository "readiness-tracked-config"
        Write-FixtureFile (Join-Path $repo "Web.config") "branch-config`n"
        Invoke-FixtureGit $repo @("add", "Web.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add tracked configuration") | Out-Null
        Add-Manifest $repo "*.local`n" "approved.local`n"
        Write-FixtureFile (Join-Path $repo "approved.local") "approved`n"
        Write-FixtureFile (Join-Path $repo "other.local") "unlisted`n"
        Write-FixtureFile (Join-Path $repo "Web.config") "connectionString=DO-NOT-PRINT`n"
        $target = Join-Path $testRoot "readiness-tracked-config-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $result = Invoke-FixtureGit $target @("wt-readiness", "--source", $repo, "--target", $target) -AllowFailure
        Assert-Equal 0 $result.ExitCode "Tracked configuration readiness must be advisory."
        Assert-OutputContains $result "Source worktree: $repo" "The exact source worktree was not reported."
        Assert-OutputContains $result "Source branch: main" "The source branch was not reported."
        Assert-OutputContains $result "Target worktree: $target" "The exact target worktree was not reported."
        Assert-OutputContains $result "Target branch: (detached)" "The target branch was not reported."
        Assert-OutputContains $result "[authorized] approved.local" "The authorized ignored file was not reported."
        Assert-OutputContains $result "[unlisted] other.local" "The unauthorized ignored file was not reported."
        Assert-OutputContains $result "[tracked-config] Web.config: modified tracked configuration was not copied; review only if this worktree requires the local override." "The tracked configuration warning was not reported."
        Assert-True (-not $result.Output.Contains("DO-NOT-PRINT")) "Tracked configuration values were printed."
        Assert-Equal "branch-config" ([IO.File]::ReadAllText((Join-Path $target "Web.config")).Trim()) "The tracked configuration was copied or changed."
    }

    Invoke-Case "readiness reports no local configuration differences" {
        $repo = New-FixtureRepository "readiness-clean"
        $result = Invoke-FixtureGit $repo @("wt-readiness") -AllowFailure
        Assert-Equal 0 $result.ExitCode "A clean readiness check should succeed."
        Assert-OutputContains $result "[configuration] no local configuration differences" "The clean readiness state was not reported."
    }

    Invoke-Case "readiness reports explicit configuration references without values" {
        $repo = New-FixtureRepository "readiness-references"
        Write-FixtureFile (Join-Path $repo "Web.config") (
            "<configuration>`n" +
            "  <appSettings`n" +
            "      file=""config/appsettings.local.config"">`n" +
            "    <add key=""private-key"" value=""DO-NOT-PRINT"" />`n" +
            "  </appSettings>`n" +
            "  <connectionStrings configSource=""config/connections.config"" />`n" +
            "  <customSection configSource=""config/unmapped.config"" />`n" +
            "  <otherSection configSource=""config/missing.config"" />`n" +
            "  <system.web />`n" +
            "</configuration>`n"
        )
        Invoke-FixtureGit $repo @("add", "Web.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add configuration references") | Out-Null
        Add-Manifest $repo "config/appsettings.local.config`nconfig/connections.config`n" "config/appsettings.local.config`nconfig/connections.config`n"
        Write-FixtureFile (Join-Path $repo "config\appsettings.local.config") "local settings`n"
        Write-FixtureFile (Join-Path $repo "config\connections.config") "connection settings`n"
        Write-FixtureFile (Join-Path $repo "config\unmapped.config") "unmapped settings`n"
        Write-FixtureFile (Join-Path $repo "Web.config") (([IO.File]::ReadAllText((Join-Path $repo "Web.config"))) + "<!-- local override DO-NOT-PRINT: <commentedSection configSource=""config/comment-only.config"" /> -->`n")

        $target = Join-Path $testRoot "readiness-references-target"
        $preflight = Invoke-FixtureGit $repo @("wt-check", "--target", $target) -AllowFailure
        Assert-Equal 0 $preflight.ExitCode "Configuration references must not block provisioning preflight."
        Assert-OutputContains $preflight "[expected] Web.config -> config/appsettings.local.config" "The appSettings file reference was not reported by preflight."
        Assert-True (-not $preflight.Output.Contains("DO-NOT-PRINT")) "Preflight printed a configuration value."

        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $result = Invoke-FixtureGit $target @("wt-readiness", "--source", $repo, "--target", $target) -AllowFailure
        Assert-Equal 0 $result.ExitCode "Configuration readiness must be advisory."
        Assert-OutputContains $result "[expected] Web.config -> config/appsettings.local.config: explicit appSettings file reference" "The appSettings reference was not reported."
        Assert-OutputContains $result "[present] Web.config -> config/appsettings.local.config: referenced configuration file is present in the source worktree (ignored)" "The present ignored reference was not reported."
        Assert-OutputContains $result "[missing] Web.config -> config/appsettings.local.config: target worktree is missing the referenced configuration file" "The missing target reference was not reported."
        Assert-OutputContains $result "[expected] Web.config -> config/connections.config: explicit configSource reference" "The configSource reference was not reported."
        Assert-OutputContains $result "[expected] Web.config -> config/missing.config: explicit configSource reference" "The missing source reference was not reported."
        Assert-OutputContains $result "[missing] Web.config -> config/missing.config: referenced configuration file is missing from the source worktree" "The missing source reference status was not reported."
        Assert-OutputContains $result "[present] Web.config -> config/unmapped.config: referenced configuration file is present in the source worktree (unmapped)" "The unmapped reference was not reported as present."
        Assert-OutputContains $result "[unmapped] Web.config -> config/unmapped.config: referenced configuration file is present but is neither tracked nor ignored" "The unmapped reference status was not reported."
        Assert-True (-not $result.Output.Contains("comment-only.config")) "A configuration reference inside an XML comment was reported."
        Assert-OutputContains $result "[tracked-config] Web.config: modified tracked configuration was not copied; review only if this worktree requires the local override." "The tracked configuration warning was not reported."
        Assert-True (-not $result.Output.Contains("DO-NOT-PRINT")) "Configuration values were printed."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target "config\appsettings.local.config"))) "Readiness copied an ignored file."
    }

    Invoke-Case "report tracked setup contract without executing it" {
        $repo = New-FixtureRepository "setup-contract"
        Write-FixtureFile (Join-Path $repo ".worktree-provision") "schemaVersion=1`nscript=scripts/setup-worktree.ps1`ndocumentation=docs/setup-worktree.md`n"
        Write-FixtureFile (Join-Path $repo "scripts\setup-worktree.ps1") "Write-Host DO-NOT-EXECUTE`n"
        Write-FixtureFile (Join-Path $repo "docs\setup-worktree.md") "Manual setup documentation`n"
        Invoke-FixtureGit $repo @("add", ".worktree-provision", "scripts\setup-worktree.ps1", "docs\setup-worktree.md") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add setup contract") | Out-Null
        $result = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 0 $result.ExitCode "A valid setup contract should be advisory."
        Assert-OutputContains $result "[setup-contract] .worktree-provision: tracked setup contract declares scripts/setup-worktree.ps1; not executed; review docs/setup-worktree.md" "The setup contract was not reported."
        Assert-True (-not $result.Output.Contains("DO-NOT-EXECUTE")) "The setup contract script was executed or printed."
    }

    Invoke-Case "copy matching ignored file" {
        $repo = New-FixtureRepository "matching"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "fixture-value`n"
        $target = Join-Path $testRoot "matching-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Provisioning should succeed."
        Assert-Equal "fixture-value`n" ([IO.File]::ReadAllText((Join-Path $target ".env.local"))) "The ignored file was not copied exactly."
    }

    Invoke-Case "reject tracked manifest file" {
        $repo = New-FixtureRepository "unignored"
        Add-Manifest $repo "*.local`n" "local.txt`nREADME.md`n"
        Write-FixtureFile (Join-Path $repo "local.txt") "not ignored`n"
        Write-FixtureFile (Join-Path $repo "other.local") "unlisted`n"
        $target = Join-Path $testRoot "unignored-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 2 $result.ExitCode "A tracked manifest file must block provisioning. Output: $($result.Output)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target "local.txt"))) "An unignored file was copied."
        Assert-OutputContains $result "[missing] local.txt" "The ineligible manifest entry should be reported."
        Assert-OutputContains $result "[rejected] README.md: tracked files already arrive through Git and cannot be copied from another worktree" "The tracked manifest entry was not explicitly rejected."
        Assert-OutputContains $result "[unlisted] other.local" "The unlisted ignored file should be reported."
        Assert-OutputContains $result "Decision: invalid-manifest" "The tracked manifest entry did not invalidate the manifest."
    }

    Invoke-Case "classify private agent files and client settings separately" {
        $repo = New-FixtureRepository "private-client-files"
        Write-FixtureFile (Join-Path $repo "CLAUDE.md") "tracked Claude instructions`n"
        Write-FixtureFile (Join-Path $repo "AGENTS.md") "tracked Codex instructions`n"
        Invoke-FixtureGit $repo @("add", "CLAUDE.md", "AGENTS.md") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add tracked instructions") | Out-Null
        Write-FixtureFile (Join-Path $repo ".gitignore") "CLAUDE.local.md`nAGENTS.override.md`n.claude/settings.local.json`n"
        Write-FixtureFile (Join-Path $repo "CLAUDE.local.md") "private override`n"
        Write-FixtureFile (Join-Path $repo "AGENTS.override.md") "private override`n"
        Write-FixtureFile (Join-Path $repo ".claude\settings.local.json") "{`"permissions`": []}`n"
        $result = Invoke-FixtureGit $repo @("wt-check") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Private client files should be advisory and not ordinary candidates. Output: $($result.Output)"
        Assert-OutputContains $result "[agent-override] CLAUDE.local.md: private agent override affects agent behavior; not suggested as ordinary configuration" "The Claude private override was not classified explicitly."
        Assert-OutputContains $result "[agent-override] AGENTS.override.md: private agent override affects agent behavior; not suggested as ordinary configuration" "The Codex private override was not classified explicitly."
        Assert-OutputContains $result "[client-settings] .claude/settings.local.json: client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration" "The client-local settings file was not classified separately."
        Assert-OutputContains $result "[tracked-instructions] CLAUDE.md: tracked instructions arrive through Git; not copied" "Tracked Claude instructions were not identified."
        Assert-OutputContains $result "[tracked-instructions] AGENTS.md: tracked instructions arrive through Git; not copied" "Tracked Codex instructions were not identified."
        Assert-True (-not $result.Output.Contains("[unlisted] CLAUDE.local.md")) "Private Claude instructions were suggested as ordinary candidates."
        Assert-True (-not $result.Output.Contains("[unlisted] AGENTS.override.md")) "Private Codex instructions were suggested as ordinary candidates."
        Assert-True (-not $result.Output.Contains("[unlisted] .claude/settings.local.json")) "Client-local settings were suggested as ordinary candidates."
    }

    Invoke-Case "reject tracked configuration but copy approved ignored file" {
        $repo = New-FixtureRepository "tracked-config-copy-rejection"
        Write-FixtureFile (Join-Path $repo "Web.config") "branch-config`n"
        Write-FixtureFile (Join-Path $repo "Other.config") "unrelated-config`n"
        Invoke-FixtureGit $repo @("add", "Web.config", "Other.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add tracked application configuration") | Out-Null
        Add-Manifest $repo "approved.local`nOther.config`n" "approved.local`nWeb.config`n"
        Write-FixtureFile (Join-Path $repo "approved.local") "approved`n"
        $preflightTarget = Join-Path $testRoot "tracked-config-copy-rejection-preflight"
        $preflight = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $preflightTarget, "HEAD") -AllowFailure
        Assert-Equal 2 $preflight.ExitCode "A tracked configuration manifest entry must block new worktree creation."
        Assert-OutputContains $preflight "[rejected] Web.config: tracked application-owned configuration cannot be copied from another worktree" "The tracked configuration was not rejected during preflight."
        Assert-True (-not $preflight.Output.Contains("DO-NOT-PRINT")) "Preflight printed tracked configuration content."
        Assert-True (-not $preflight.Output.Contains("[rejected] Other.config")) "A repository ignore rule was mistaken for a manifest match."
        Assert-True (-not (Test-Path -LiteralPath $preflightTarget)) "The rejected preflight created a worktree."

        $target = Join-Path $testRoot "tracked-config-copy-rejection-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $copy = Invoke-FixtureGit $target @("wt-copy", "--source", $repo) -AllowFailure
        Assert-Equal 2 $copy.ExitCode "Copy should reject the tracked file while reporting the approved ignored file."
        Assert-OutputContains $copy "[rejected] Web.config: tracked application-owned configuration cannot be copied from another worktree" "The tracked configuration was not rejected by wt-copy."
        Assert-True (-not $copy.Output.Contains("[rejected] Other.config")) "A repository ignore rule was mistaken for a manifest match during copy."
        Assert-OutputContains $copy "[copied] approved.local" "The approved ignored file was not provisioned."
        Assert-True ((Test-Path -LiteralPath (Join-Path $target "approved.local"))) "The approved ignored file was not copied."
        Assert-Equal "branch-config" ([IO.File]::ReadAllText((Join-Path $target "Web.config")).Trim()) "The tracked configuration was changed."
    }

    Invoke-Case "reject an external source repository" {
        $repo = New-FixtureRepository "external-source-target"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "target-source`n"
        $target = Join-Path $testRoot "external-source-target-worktree"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null

        $external = New-FixtureRepository "external-source-repository"
        Add-Manifest $external ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $external ".env.local") "EXTERNAL-SECRET-MUST-NOT-COPY`n"
        $copy = Invoke-FixtureGit $target @("wt-copy", "--source", $external) -AllowFailure
        Assert-Equal 2 $copy.ExitCode "An external source repository must be rejected."
        Assert-OutputContains $copy "not worktrees of the same Git repository" "The external source rejection was not reported."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target ".env.local"))) "The external ignored file was copied."
        Assert-True (-not $copy.Output.Contains("EXTERNAL-SECRET-MUST-NOT-COPY")) "The external file content was printed."
    }

    Invoke-Case "do not copy ignored file outside manifest" {
        $repo = New-FixtureRepository "outside-manifest"
        Add-Manifest $repo "*.local`n" "approved.local`n"
        Write-FixtureFile (Join-Path $repo "approved.local") "approved`n"
        Write-FixtureFile (Join-Path $repo "other.local") "not approved`n"
        $target = Join-Path $testRoot "outside-manifest-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--allow-unprovisioned", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Provisioning should succeed."
        Assert-True (Test-Path -LiteralPath (Join-Path $target "approved.local")) "The approved file is missing."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target "other.local"))) "An unapproved ignored file was copied."
        Assert-OutputContains $result "[unlisted] other.local" "The unlisted ignored file was not reported."
    }

    Invoke-Case "copy nested directory pattern" {
        $repo = New-FixtureRepository "nested"
        Add-Manifest $repo "config/`n" "config/`n"
        Write-FixtureFile (Join-Path $repo "config\one\two.local") "nested`n"
        $target = Join-Path $testRoot "nested-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Nested provisioning should succeed."
        Assert-True (Test-Path -LiteralPath (Join-Path $target "config\one\two.local")) "The nested file is missing."
    }

    Invoke-Case "copy paths containing spaces and Unicode" {
        $repo = New-FixtureRepository "unicode"
        Add-Manifest $repo "config space/`n" "config space/`n"
        $relative = "config space\測試.local"
        Write-FixtureFile (Join-Path $repo $relative) "unicode`n"
        $target = Join-Path $testRoot "target space 測試"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Unicode provisioning should succeed."
        Assert-True (Test-Path -LiteralPath (Join-Path $target $relative)) "The Unicode fixture is missing."
    }

    Invoke-Case "report missing source pattern" {
        $repo = New-FixtureRepository "missing"
        Add-Manifest $repo "*.env`n" "missing.env`n"
        $target = Join-Path $testRoot "missing-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "A missing optional file should not fail creation."
        Assert-OutputContains $result "[missing] missing.env" "The missing source pattern was not reported."
    }

    Invoke-Case "preserve existing target file" {
        $repo = New-FixtureRepository "conflict"
        Add-Manifest $repo ".env`n" ".env`n"
        Invoke-FixtureGit $repo @("checkout", "--quiet", "-b", "target-with-file") | Out-Null
        Write-FixtureFile (Join-Path $repo ".env") "tracked-target`n"
        Invoke-FixtureGit $repo @("add", "--force", ".env") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "track target file") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "main") | Out-Null
        Write-FixtureFile (Join-Path $repo ".env") "ignored-source`n"
        $target = Join-Path $testRoot "conflict-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", $target, "target-with-file") -AllowFailure
        Assert-Equal 0 $result.ExitCode "A target conflict should be skipped without failing."
        Assert-OutputContains $result "[conflict] .env" "The conflict was not reported."
        $targetContent = [IO.File]::ReadAllText((Join-Path $target ".env")).Trim()
        Assert-Equal "tracked-target" $targetContent "The target file was overwritten."
    }

    Invoke-Case "preserve native Git failure" {
        $repo = New-FixtureRepository "git-failure"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach") -AllowFailure
        Assert-True ($result.ExitCode -ne 0) "Invalid native Git arguments should fail."
        Assert-True (-not $result.Output.Contains("[copied]")) "Copying ran after Git failed."
    }

    Invoke-Case "leave worktree after provisioning rejection" {
        $repo = New-FixtureRepository "copy-failure"
        Add-Manifest $repo ".project-continuity/`n" ".project-continuity/`n"
        Write-FixtureFile (Join-Path $repo ".project-continuity\state.md") "fixture state`n"
        $target = Join-Path $testRoot "copy-failure-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 2 $result.ExitCode "A blocked source should fail provisioning."
        Assert-OutputContains $result "[rejected] .project-continuity/state.md" "The blocked file was not reported."
        Assert-True (Test-Path -LiteralPath (Join-Path $target ".git")) "The created worktree was deleted after provisioning failed."
    }

    Invoke-Case "reject traversal pattern" {
        $repo = New-FixtureRepository "traversal"
        Add-Manifest $repo "*.env`n" "../outside.env`n"
        $target = Join-Path $testRoot "traversal-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 2 $result.ExitCode "A traversal manifest should fail provisioning."
        Assert-OutputContains $result "parent-directory traversal" "The traversal reason was not reported."
    }

    Invoke-Case "reject source reparse point" {
        $repo = New-FixtureRepository "source-reparse"
        Add-Manifest $repo "linked`n" "linked`n"
        $external = Join-Path $testRoot "source-reparse-external"
        [IO.Directory]::CreateDirectory($external) | Out-Null
        Write-FixtureFile (Join-Path $external "local.env") "outside`n"
        New-Item -ItemType Junction -Path (Join-Path $repo "linked") -Target $external | Out-Null
        $target = Join-Path $testRoot "source-reparse-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 2 $result.ExitCode "A source reparse point should fail provisioning."
        Assert-OutputContains $result "source path traverses" "The source reparse point was not reported."
    }

    Invoke-Case "repair raw worktree from discovered primary" {
        $repo = New-FixtureRepository "repair-primary"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "repair`n"
        $target = Join-Path $testRoot "repair-primary-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $result = Invoke-FixtureGit $target @("wt-copy") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Automatic repair should succeed. Output: $($result.Output)"
        Assert-OutputContains $result "Source worktree:" "The selected source was not reported."
        Assert-True (Test-Path -LiteralPath (Join-Path $target ".env.local")) "Repair did not copy the file."
    }

    Invoke-Case "repair raw worktree from explicit source" {
        $repo = New-FixtureRepository "repair-explicit"
        Add-Manifest $repo ".env.test`n" ".env.test`n"
        Write-FixtureFile (Join-Path $repo ".env.test") "explicit`n"
        $target = Join-Path $testRoot "repair-explicit-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null
        $result = Invoke-FixtureGit $target @("wt-copy", "--source", $repo) -AllowFailure
        Assert-Equal 0 $result.ExitCode "Explicit repair should succeed. Output: $($result.Output)"
        Assert-True (Test-Path -LiteralPath (Join-Path $target ".env.test")) "Explicit repair did not copy the file."
    }

    Invoke-Case "forward branch and start-point arguments" {
        $repo = New-FixtureRepository "branch-forwarding"
        Invoke-FixtureGit $repo @("checkout", "--quiet", "-b", "develop") | Out-Null
        Write-FixtureFile (Join-Path $repo "develop.txt") "develop`n"
        Invoke-FixtureGit $repo @("add", "develop.txt") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "develop marker") | Out-Null
        Invoke-FixtureGit $repo @("checkout", "--quiet", "main") | Out-Null
        $target = Join-Path $testRoot "branch-forwarding-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--", "-b", "feat/from-develop", $target, "develop") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Native branch arguments should succeed."
        Assert-OutputContains $result "Handoff reminder: continuity and uncommitted changes stay in this worktree." "The handoff reminder was not printed."
        Assert-OutputContains $result "Open this exact path in Claude Code, Codex, or Copilot:" "The exact-path instruction was not printed."
        Assert-OutputContains $result "Then say: Continue from project continuity." "The continuation prompt was not printed."
        Assert-OutputContains $result "Use a separate worktree for another unfinished task." "The task-isolation reminder was not printed."
        $branch = Invoke-FixtureGit $target @("branch", "--show-current")
        Assert-Equal "feat/from-develop" $branch.Output.Trim() "The target branch is wrong."
        Assert-True (Test-Path -LiteralPath (Join-Path $target "develop.txt")) "The worktree did not start from develop."
    }

    Invoke-Case "open completed worktree in VS Code" {
        $repo = New-FixtureRepository "open-code"
        $shimDirectory = Join-Path $testRoot "code-shim"
        [IO.Directory]::CreateDirectory($shimDirectory) | Out-Null
        $logPath = Join-Path $testRoot "code-invocation.txt"
        $codeShim = '@echo off' + "`r`n" +
            '> "%WORKTREE_PROVISION_TEST_CODE_LOG%" echo %*' + "`r`n" +
            'exit /b 0' + "`r`n"
        Write-FixtureFile (Join-Path $shimDirectory "code.cmd") $codeShim
        $target = Join-Path $testRoot "open-code-target"
        $previousPath = $env:PATH
        $previousLog = $env:WORKTREE_PROVISION_TEST_CODE_LOG
        try {
            $env:PATH = "$shimDirectory;$previousPath"
            $env:WORKTREE_PROVISION_TEST_CODE_LOG = $logPath
            $result = Invoke-FixtureGit $repo @("wt-add", "--open-code", "--", "--detach", $target, "HEAD") -AllowFailure
        } finally {
            $env:PATH = $previousPath
            $env:WORKTREE_PROVISION_TEST_CODE_LOG = $previousLog
        }
        Assert-Equal 0 $result.ExitCode "Opening VS Code should succeed through the shim. Output: $($result.Output)"
        Assert-True (Test-Path -LiteralPath $logPath) "The VS Code shim was not invoked."
        Assert-True ([IO.File]::ReadAllText($logPath).Contains("--new-window")) "The VS Code invocation omitted --new-window."
    }

    Invoke-Case "approve an exact ignored-file mapping without overwriting" {
        $repo = New-FixtureRepository "mapping-approval"
        $destination = "config/local/.env.local"
        Write-FixtureFile (Join-Path $repo ".gitignore") ".env.local`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ignore rule") | Out-Null
        Write-FixtureFile (Join-Path $repo ".env.local") "first-value`n"
        $target = Join-Path $testRoot "mapping-approval-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null

        $dryRun = Invoke-FixtureGit $target @("wt-provision", "--dry-run", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination) -AllowFailure
        Assert-Equal 0 $dryRun.ExitCode "A valid mapping dry run should succeed. Output: $($dryRun.Output)"
        Assert-OutputContains $dryRun "[approval-required] $destination" "The dry run did not require approval."
        Assert-OutputContains $dryRun "Source branch: main" "The source branch was not reported."
        Assert-OutputContains $dryRun "Target branch: (detached)" "The target branch was not reported."
        Assert-OutputContains $dryRun "Target HEAD: " "The target HEAD was not reported."
        Assert-OutputContains $dryRun "Runtime state: runtime-unverified" "The runtime state was not reported."
        $approvalMatch = [regex]::Match($dryRun.Output, "(?m)^Approval id: ([0-9a-f]+)$")
        Assert-True $approvalMatch.Success "The dry run did not return an approval id."
        $approval = $approvalMatch.Groups[1].Value
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target $destination))) "The dry run wrote the target."

        Write-FixtureFile (Join-Path $target "approval-scope-marker.txt") "target-head-changed`n"
        Invoke-FixtureGit $target @("add", "approval-scope-marker.txt") | Out-Null
        Invoke-FixtureGit $target @("commit", "--quiet", "-m", "advance target head") | Out-Null
        $targetHeadStale = Invoke-FixtureGit $target @("wt-provision", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination, "--approve", $approval) -AllowFailure
        Assert-Equal 3 $targetHeadStale.ExitCode "A changed target HEAD must invalidate the previous approval."
        Assert-OutputContains $targetHeadStale "[approval-rejected] $destination" "The changed target HEAD was not rejected."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target $destination))) "A target-HEAD-stale approval wrote the target."

        Write-FixtureFile (Join-Path $repo ".env.local") "changed-value`n"
        $stale = Invoke-FixtureGit $target @("wt-provision", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination, "--approve", $approval) -AllowFailure
        Assert-Equal 3 $stale.ExitCode "A changed source must invalidate the previous approval."
        Assert-OutputContains $stale "[approval-rejected] $destination" "The changed source was not rejected."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target $destination))) "A stale approval wrote the target."

        $freshDryRun = Invoke-FixtureGit $target @("wt-provision", "--dry-run", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination) -AllowFailure
        $freshMatch = [regex]::Match($freshDryRun.Output, "(?m)^Approval id: ([0-9a-f]+)$")
        Assert-True $freshMatch.Success "The changed source did not produce a new approval id."
        $copy = Invoke-FixtureGit $target @("wt-provision", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination, "--approve", $freshMatch.Groups[1].Value) -AllowFailure
        Assert-Equal 0 $copy.ExitCode "An approved exact mapping should copy once. Output: $($copy.Output)"
        Assert-Equal "changed-value`n" ([IO.File]::ReadAllText((Join-Path $target $destination))) "The approved ignored file was not copied exactly."

        $conflict = Invoke-FixtureGit $target @("wt-provision", "--operation", "copy-ignored-file", "--source-file", (Join-Path $repo ".env.local"), "--target", $target, "--destination", $destination, "--approve", $freshMatch.Groups[1].Value) -AllowFailure
        Assert-Equal 2 $conflict.ExitCode "An existing target must block a second copy."
        Assert-OutputContains $conflict "[conflict] $destination" "The existing target conflict was not reported."
    }

    Invoke-Case "reject tracked and section-mapping operations" {
        $repo = New-FixtureRepository "mapping-rejections"
        Write-FixtureFile (Join-Path $repo "Web.config") "connectionString=DO-NOT-PRINT`n"
        Invoke-FixtureGit $repo @("add", "Web.config") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add tracked config") | Out-Null
        Write-FixtureFile (Join-Path $repo ".gitignore") "Web.config`nlocal.config`n"
        Invoke-FixtureGit $repo @("add", ".gitignore") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add config ignore rules") | Out-Null
        $target = Join-Path $testRoot "mapping-rejections-target"
        Invoke-FixtureGit $repo @("worktree", "add", "--quiet", "--detach", $target, "HEAD") | Out-Null

        $tracked = Invoke-FixtureGit $target @("wt-provision", "--dry-run", "--operation", "copy-external-file", "--source-file", (Join-Path $repo "Web.config"), "--target", $target, "--destination", "local.config") -AllowFailure
        Assert-Equal 2 $tracked.ExitCode "A tracked application configuration source must be rejected."
        Assert-OutputContains $tracked "tracked files, including application configuration, cannot be copied" "The tracked source rejection was not reported."
        Assert-True (-not $tracked.Output.Contains("DO-NOT-PRINT")) "The tracked configuration value leaked."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target "local.config"))) "The tracked source was copied."

        foreach ($operation in @("merge-named-section", "replace-file")) {
            $rejected = Invoke-FixtureGit $target @("wt-provision", "--dry-run", "--operation", $operation, "--source-file", (Join-Path $repo "Web.config"), "--target", $target, "--destination", "local.config") -AllowFailure
            Assert-Equal 2 $rejected.ExitCode "The $operation operation must be report-only."
            Assert-OutputContains $rejected "does not perform section merges or whole-file replacement" "The $operation refusal was not reported."
        }
    }

    Invoke-Case "report framework evidence without claiming runtime readiness" {
        $repo = New-FixtureRepository "ecosystem-evidence"
        Write-FixtureFile (Join-Path $repo "package.json") "{`"scripts`": {`"dev`": `"vite`"}, `"private`": true}`n"
        Write-FixtureFile (Join-Path $repo "vite.config.js") "export default {}`n"
        Write-FixtureFile (Join-Path $repo "next.config.js") "module.exports = {}`n"
        Write-FixtureFile (Join-Path $repo ".env.example") "API_TOKEN=DO-NOT-PRINT`n"
        Invoke-FixtureGit $repo @("add", "package.json", "vite.config.js", "next.config.js", ".env.example") | Out-Null
        Invoke-FixtureGit $repo @("commit", "--quiet", "-m", "add ecosystem markers") | Out-Null
        $result = Invoke-FixtureGit $repo @("wt-readiness") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Framework evidence should be advisory."
        Assert-OutputContains $result "[ecosystem] package.json: Node.js script-evidence" "Node evidence was not reported."
        Assert-OutputContains $result "[ecosystem] vite.config.js: React/Vite framework-marker" "Vite evidence was not reported."
        Assert-OutputContains $result "[ecosystem] next.config.js: Next.js framework-marker" "Next.js evidence was not reported."
        Assert-OutputContains $result "Runtime state: runtime-unverified" "The runtime-unverified state was not reported."
        Assert-True (-not $result.Output.Contains("DO-NOT-PRINT")) "Framework evidence leaked an environment value."
    }

    Invoke-Case "dry run creates nothing" {
        $repo = New-FixtureRepository "dry-run"
        Add-Manifest $repo ".env.local`n" ".env.local`n"
        Write-FixtureFile (Join-Path $repo ".env.local") "dry`n"
        $target = Join-Path $testRoot "dry-run-target"
        $result = Invoke-FixtureGit $repo @("wt-add", "--dry-run", "--", "--detach", $target, "HEAD") -AllowFailure
        Assert-Equal 0 $result.ExitCode "Dry run should succeed."
        Assert-OutputContains $result "[matched] .env.local" "Dry run did not report the manifest match."
        Assert-True (-not (Test-Path -LiteralPath $target)) "Dry run created a worktree."
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $safePrefix = $temporaryParent + [IO.Path]::DirectorySeparatorChar + "git-worktree-provision-tests-"
    if ($resolvedTestRoot.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

Write-Host "Worktree tool tests: passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
