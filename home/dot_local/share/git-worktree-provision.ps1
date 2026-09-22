# Managed by the developer environment repository. Provides the implementation behind the Windows-only
# `git wt-add` and `git wt-copy` aliases.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:GitExecutable = (Get-Command git.exe -ErrorAction Stop).Source
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:PathComparison = [StringComparison]::OrdinalIgnoreCase

function Format-DisplayText {
    param([AllowEmptyString()][string] $Text)

    if ($null -eq $Text) { $Text = "" }
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Text.ToCharArray()) {
        if ([char]::IsControl($character)) {
            [void]$builder.Append("?")
        } else {
            [void]$builder.Append($character)
        }
    }
    $safeText = $builder.ToString()
    $sensitiveAssignment = '(?i)(password|passwd|pwd|connectionstring|connection-string|api[_-]?key|token|secret|client[_-]?secret|access[_-]?token)\s*[:=]\s*'
    $safeText = [regex]::Replace($safeText, $sensitiveAssignment + '"[^"]*"', '$1=[REDACTED]')
    $safeText = [regex]::Replace($safeText, $sensitiveAssignment + "'[^']*'", '$1=[REDACTED]')
    return [regex]::Replace($safeText, $sensitiveAssignment + '[^\s;,]+', '$1=[REDACTED]')
}

function Write-ProvisionRecord {
    param(
        [string] $Category,
        [string] $Path,
        [string] $Detail = ""
    )

    $safePath = Format-DisplayText $Path
    $suffix = if ($Detail) { ": $(Format-DisplayText $Detail)" } else { "" }
    Write-Host "[$Category] $safePath$suffix"
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string] $Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append((([string][char]92) * ($backslashCount * 2)))
            }
            [void]$builder.Append('\"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append((([string][char]92) * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append((([string][char]92) * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-GitCapture {
    param(
        [string] $WorkingDirectory,
        [string[]] $Arguments
    )

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $script:GitExecutable
    $processInfo.WorkingDirectory = $WorkingDirectory
    $processInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join " ")
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.StandardOutputEncoding = $script:Utf8NoBom
    $processInfo.StandardErrorEncoding = $script:Utf8NoBom

    # A shell Git alias exports repository-local variables from the invoking worktree. If they
    # reach a nested `git -C <other-worktree>` call, GIT_DIR wins over -C and makes Git inspect
    # the wrong index. Clear only repository-local variables; user-level Git configuration and
    # authentication remain available normally.
    foreach ($variableName in @(
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_DIR", "GIT_GRAFT_FILE",
        "GIT_IMPLICIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_INTERNAL_SUPER_PREFIX",
        "GIT_NO_REPLACE_OBJECTS", "GIT_OBJECT_DIRECTORY", "GIT_PREFIX",
        "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE", "GIT_WORK_TREE"
    )) {
        [void]$processInfo.EnvironmentVariables.Remove($variableName)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Could not start Git."
    }

    try {
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $standardOutput.Result
            Stderr = $standardError.Result
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-GitChecked {
    param(
        [string] $WorkingDirectory,
        [string[]] $Arguments,
        [string] $FailureMessage
    )

    $result = Invoke-GitCapture $WorkingDirectory $Arguments
    if ($result.ExitCode -ne 0) {
        $detail = $result.Stderr.Trim()
        if (-not $detail) { $detail = $result.Stdout.Trim() }
        if ($detail) {
            throw "$FailureMessage`n$detail"
        }
        throw $FailureMessage
    }
    return $result.Stdout
}

function Get-RepositoryRoot {
    param([string] $Path)

    $root = Invoke-GitChecked $Path @("rev-parse", "--show-toplevel") "Not inside a Git working tree."
    return [IO.Path]::GetFullPath($root.Trim())
}

function Get-CommonGitDirectory {
    param([string] $RepositoryRoot)

    $path = Invoke-GitChecked $RepositoryRoot `
        @("rev-parse", "--path-format=absolute", "--git-common-dir") `
        "Could not resolve the repository's common Git directory."
    return [IO.Path]::GetFullPath($path.Trim())
}

function Test-SamePath {
    param([string] $Left, [string] $Right)
    return [string]::Equals(
        [IO.Path]::GetFullPath($Left).TrimEnd("\", "/"),
        [IO.Path]::GetFullPath($Right).TrimEnd("\", "/"),
        $script:PathComparison
    )
}

function Test-PathInsideRoot {
    param([string] $Root, [string] $Path)

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, $script:PathComparison)
}

function Split-NulOutput {
    param([AllowEmptyString()][string] $Text)
    return @($Text.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries))
}

function Get-WorktreePaths {
    param([string] $RepositoryRoot)

    $output = Invoke-GitChecked $RepositoryRoot `
        @("worktree", "list", "--porcelain", "-z") `
        "Could not list Git worktrees."
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($field in (Split-NulOutput $output)) {
        if ($field.StartsWith("worktree ", [StringComparison]::Ordinal)) {
            $paths.Add([IO.Path]::GetFullPath($field.Substring(9)))
        }
    }
    return $paths.ToArray()
}

function Get-NewWorktreePath {
    param(
        [string[]] $Before,
        [string[]] $After
    )

    $known = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $Before) { [void]$known.Add([IO.Path]::GetFullPath($path)) }
    $added = @($After | Where-Object { -not $known.Contains([IO.Path]::GetFullPath($_)) })
    if ($added.Count -ne 1) {
        throw "Git created the worktree, but the new path could not be identified safely (found $($added.Count) new entries)."
    }
    return $added[0]
}

function Get-ReparsePoint {
    param(
        [string] $Root,
        [string] $Path,
        [bool] $IncludeLeaf
    )

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-PathInsideRoot $fullRoot $fullPath)) {
        return $fullPath
    }

    $relative = $fullPath.Substring($fullRoot.Length).TrimStart("\", "/")
    $segments = @($relative -split '[\\/]')
    if (-not $IncludeLeaf -and $segments.Count -gt 0) {
        $segments = @($segments[0..($segments.Count - 2)])
    }

    $current = $fullRoot
    foreach ($segment in $segments) {
        if (-not $segment) { continue }
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { continue }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }
    return $null
}

function Get-PatternRejectionReason {
    param([string] $Pattern)

    $candidate = $Pattern
    if ($candidate.StartsWith("!", [StringComparison]::Ordinal)) {
        $candidate = $candidate.Substring(1)
    }
    if ($candidate.StartsWith("/", [StringComparison]::Ordinal)) {
        $candidate = $candidate.Substring(1)
    }

    if ($candidate -match '^[A-Za-z]:[\\/]' -or $candidate -match '^[/\\]{2}') {
        return "absolute filesystem paths are not allowed"
    }
    if ($candidate -match '(^|/)\.\.(/|$)') {
        return "parent-directory traversal is not allowed"
    }
    return $null
}

function Get-FileRejectionReason {
    param([string] $RelativePath)

    $path = "/" + $RelativePath.Replace("\", "/").TrimStart("/")
    $lower = $path.ToLowerInvariant()
    $segments = @($lower.Trim("/") -split "/")
    $blockedDirectories = @(
        ".git", ".project-continuity", "node_modules", "packages", "bin", "obj", ".vs",
        ".cache", "__pycache__", "coverage", "dist"
    )
    foreach ($segment in $segments) {
        if ($blockedDirectories -contains $segment) {
            return "blocked directory '$segment'"
        }
    }

    if ($lower -match '^/\.claude/(worktrees|logs|agent-memory-local)(/|$)') {
        return "Claude session state is never copied"
    }
    if ($lower -match '^/\.codex(/|$)') {
        return "Codex local state is never copied"
    }

    $name = [IO.Path]::GetFileName($lower)
    if ($name -in @(".env.production", ".env.production.local")) {
        return "production environment files are never copied"
    }
    if ($name -in @(".npmrc", "nuget.config", "credentials.json", "auth.json", "id_rsa", "id_ed25519")) {
        return "credential or authentication files are never copied"
    }

    $extension = [IO.Path]::GetExtension($name)
    if ($extension -in @(".pem", ".key", ".pfx", ".p12", ".cer", ".crt")) {
        return "private keys and certificates are never copied"
    }
    if ($extension -in @(".bak", ".db", ".sqlite", ".sqlite3", ".pyc", ".pyo")) {
        return "database backups and local data stores are never copied"
    }
    return $null
}

function Get-ExplicitOnlyCategory {
    param([string] $RelativePath)

    $normalized = $RelativePath.Replace("\", "/").TrimStart("/").ToLowerInvariant()
    $name = [IO.Path]::GetFileName($normalized)
    if ($name -in @("claude.local.md", "claude.override.md", "agents.override.md", "agents.local.md", "codex.local.md", "codex.override.md")) {
        return "agent-override"
    }
    if ($name -in @(
            "claude.settings.md", "claude.settings.local.md", "agents.settings.md", "agents.settings.local.md",
            "codex.settings.md", "codex.settings.local.md"
        ) -or $normalized -match "(^|/)\.claude/settings\.local\.json$") {
        return "client-settings"
    }
    return $null
}

function Get-ManifestPatterns {
    param([string] $ManifestPath)

    $patterns = @()
    foreach ($line in [IO.File]::ReadAllLines($ManifestPath, $script:Utf8NoBom)) {
        if (-not $line -or $line.StartsWith("#", [StringComparison]::Ordinal)) { continue }
        $patterns += $line
    }
    return $patterns
}

function Get-IgnoredFileSet {
    param(
        [string] $RepositoryRoot,
        [string[]] $ExcludeArguments
    )

    $arguments = @("ls-files", "--others", "--ignored") + $ExcludeArguments + @("-z", "--")
    $output = Invoke-GitChecked $RepositoryRoot $arguments "Git could not enumerate ignored files."
    $set = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
    foreach ($path in (Split-NulOutput $output)) { [void]$set.Add($path) }
    Write-Output -NoEnumerate $set
}

function Test-RepositoryRelativeContractPath {
    param([AllowEmptyString()][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normalized = $Path.Trim().Replace("\", "/")
    if ($normalized -match '^[A-Za-z]:/' -or $normalized.StartsWith("/", [StringComparison]::Ordinal) -or
        $normalized -match '(^|/)\.\.(?:/|$)' -or $normalized -match '[\r\n]') {
        return $false
    }
    return $true
}

function Get-SetupContract {
    param(
        [string] $SourceRoot,
        [System.Collections.Generic.HashSet[string]] $TrackedPaths
    )

    $relativePath = ".worktree-provision"
    $contractPath = Join-Path $SourceRoot $relativePath
    $contract = [pscustomobject]@{
        Status = "absent"
        Path = $relativePath
        Script = ""
        Documentation = ""
        Reason = ""
    }
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { return $contract }
    if (-not $TrackedPaths.Contains($relativePath)) {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract exists but is not tracked"
        return $contract
    }
    if (Get-ReparsePoint $SourceRoot $contractPath $true) {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract is or traverses a symbolic link or Windows reparse point"
        return $contract
    }

    $values = @{}
    try {
        foreach ($line in [IO.File]::ReadAllLines($contractPath, $script:Utf8NoBom)) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#", [StringComparison]::Ordinal)) { continue }
            $separator = $trimmed.IndexOf("=")
            if ($separator -le 0) {
                $contract.Status = "invalid"
                $contract.Reason = "setup contract contains an invalid entry"
                return $contract
            }
            $key = $trimmed.Substring(0, $separator).Trim()
            $value = $trimmed.Substring($separator + 1).Trim()
            if ($key -notin @("schemaVersion", "script", "documentation") -or $values.ContainsKey($key)) {
                $contract.Status = "invalid"
                $contract.Reason = "setup contract contains an unsupported or duplicate key"
                return $contract
            }
            $values[$key] = $value
        }
    } catch {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract could not be read"
        return $contract
    }

    if ($values["schemaVersion"] -ne "1") {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract schemaVersion must be 1"
        return $contract
    }
    $scriptPath = if ($values.ContainsKey("script")) { $values["script"].Replace("\", "/") } else { "" }
    $scriptFullPath = Join-Path $SourceRoot $scriptPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-RepositoryRelativeContractPath $scriptPath) -or
        -not $TrackedPaths.Contains($scriptPath) -or
        -not (Test-Path -LiteralPath $scriptFullPath -PathType Leaf) -or
        (Get-ReparsePoint $SourceRoot $scriptFullPath $true)) {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract must declare a tracked, repository-relative setup script"
        return $contract
    }
    $documentationPath = if ($values.ContainsKey("documentation")) { $values["documentation"].Replace("\", "/") } else { "" }
    $documentationFullPath = if ($documentationPath) {
        Join-Path $SourceRoot $documentationPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    } else { "" }
    if ($documentationPath -and (-not (Test-RepositoryRelativeContractPath $documentationPath) -or
        -not $TrackedPaths.Contains($documentationPath) -or
        -not (Test-Path -LiteralPath $documentationFullPath -PathType Leaf) -or
        (Get-ReparsePoint $SourceRoot $documentationFullPath $true))) {
        $contract.Status = "invalid"
        $contract.Reason = "setup contract documentation must be a tracked, repository-relative file"
        return $contract
    }

    $contract.Status = "valid"
    $contract.Script = $scriptPath
    $contract.Documentation = $documentationPath
    return $contract
}

function Write-SetupContractRecord {
    param($Contract)

    if ($Contract.Status -eq "absent") {
        Write-ProvisionRecord "setup-contract" $Contract.Path "no tracked setup contract was found"
    } elseif ($Contract.Status -eq "valid") {
        $detail = "tracked setup contract declares $($Contract.Script); not executed"
        if ($Contract.Documentation) { $detail += "; review $($Contract.Documentation)" }
        Write-ProvisionRecord "setup-contract" $Contract.Path $detail
    } else {
        Write-ProvisionRecord "setup-contract-invalid" $Contract.Path $Contract.Reason
    }
}

function Get-TextFingerprint {
    param([AllowEmptyString()][string] $Text)

    $sha = New-Object System.Security.Cryptography.SHA256Managed
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Get-FileFingerprint {
    param([string] $Path)

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}

function Get-ProvisioningState {
    param(
        $Selection,
        [int] $RequiredMissing = 0
    )

    $decision = Get-ProvisionDecision $Selection $RequiredMissing
    switch ($decision) {
        "invalid-manifest" { return "provisioning-blocked" }
        "required-local-config-missing" { return "provisioning-blocked" }
        "eligible-ignored-files-unlisted" { return "provisioning-review-required" }
        default { return "provisioning-ready" }
    }
}

function Write-ReadinessStates {
    param(
        $Selection,
        [int] $RequiredMissing = 0
    )

    Write-Host "Provisioning state: $(Get-ProvisioningState $Selection $RequiredMissing)"
    Write-Host "Runtime state: runtime-unverified"
}

function Get-ConfigurationEvidence {
    param(
        [string] $SourceRoot,
        [System.Collections.Generic.HashSet[string]] $TrackedPaths
    )

    $evidence = New-Object System.Collections.Generic.List[object]
    $normalized = @($TrackedPaths | ForEach-Object { $_.Replace("\", "/") })
    $addEvidence = {
        param([string] $Ecosystem, [string] $Kind, [string] $Path, [string] $Detail)
        [void]$evidence.Add([pscustomobject]@{
            Ecosystem = $Ecosystem
            Kind = $Kind
            Path = $Path
            Detail = $Detail
        })
    }

    foreach ($path in $normalized) {
        $name = [IO.Path]::GetFileName($path).ToLowerInvariant()
        if ($name -in @("web.config", "app.config", "global.json", "packages.config") -or
            $name -like "*.csproj" -or $name -like "*.fsproj" -or
            $name -like "appsettings*.json" -or $name -like "launchsettings.json") {
            & $addEvidence ".NET" "framework-marker" $path "tracked .NET configuration or project marker; runtime consumption is not established"
        }
        if ($name -eq "package.json") {
            & $addEvidence "Node.js" "framework-marker" $path "tracked package manifest; scripts and runtime consumption require project verification"
            try {
                $text = [IO.File]::ReadAllText((Join-Path $SourceRoot $path.Replace('/', [IO.Path]::DirectorySeparatorChar)))
                if ($text -match '(?i)\b(next|vite|react-scripts|webpack|node)\b') {
                    & $addEvidence "Node.js" "script-evidence" $path "package scripts or dependencies mention a JavaScript tool; runtime consumption is not established"
                }
            } catch {
                & $addEvidence "Node.js" "inspection-limited" $path "package manifest could not be inspected; runtime consumption is unknown"
            }
        }
        if ($name -like "vite.config.*" -or $path -match '(^|/)vite\.config\.') {
            & $addEvidence "React/Vite" "framework-marker" $path "tracked Vite configuration marker; environment consumption is not established"
        }
        if ($name -like "next.config.*" -or $path -match '(^|/)next\.config\.') {
            & $addEvidence "Next.js" "framework-marker" $path "tracked Next.js configuration marker; environment consumption is not established"
        }
        if ($name -like ".env.example" -or $name -like ".env.template" -or
            $name -like "docker-compose*.yml" -or $name -like "docker-compose*.yaml" -or
            $name -like "compose*.yml" -or $name -like "compose*.yaml") {
            & $addEvidence "generic" "configuration-marker" $path "tracked configuration documentation or container marker; runtime consumption is not established"
        }
    }

    return $evidence.ToArray()
}

function Write-ConfigurationEvidenceRecords {
    param($ConfigurationReadiness)

    foreach ($evidence in $ConfigurationReadiness.Evidence) {
        Write-ProvisionRecord "ecosystem" $evidence.Path "$($evidence.Ecosystem) $($evidence.Kind): $($evidence.Detail)"
    }
}

function Get-ProvisionSelection {
    param([string] $SourceRoot)

    $manifestPath = Join-Path $SourceRoot ".worktreeinclude"
    $standardIgnored = Get-IgnoredFileSet $SourceRoot @("--exclude-standard")
    $manifestStatus = "absent"
    $manifestTracked = $false
    $files = @()
    $missingPatterns = @()
    $rejectedPatterns = @()
    $trackedManifestFiles = @()
    $trackedPaths = Get-TrackedPathSet $SourceRoot
        $trackedInstructions = @($trackedPaths | Where-Object {
        $name = [IO.Path]::GetFileName($_.Replace("\", "/")).ToLowerInvariant()
        $name -in @("claude.md", "agents.md")
    } | Sort-Object)
    $setupContract = Get-SetupContract $SourceRoot $trackedPaths

    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifestStatus = "tracked"
        $manifestReparse = Get-ReparsePoint $SourceRoot $manifestPath $true
        if ($manifestReparse) {
            throw ".worktreeinclude is or traverses a symbolic link or Windows reparse point."
        }

        $tracked = Invoke-GitCapture $SourceRoot @("ls-files", "--error-unmatch", "--", ".worktreeinclude")
        if ($tracked.ExitCode -ne 0) {
            $manifestStatus = "untracked"
        } else {
            $manifestTracked = $true
            $patterns = Get-ManifestPatterns $manifestPath
            foreach ($pattern in $patterns) {
                $reason = Get-PatternRejectionReason $pattern
                if ($reason) {
                    $rejectedPatterns += [pscustomobject]@{ Pattern = $pattern; Reason = $reason }
                }
            }

            if ($rejectedPatterns.Count -eq 0) {
                $trackedManifestFiles = @(Get-TrackedManifestFiles $SourceRoot $trackedPaths)
            }

            $manifestMatched = Get-IgnoredFileSet $SourceRoot @("--exclude-from=.worktreeinclude")
            $files = @($manifestMatched | Where-Object { $standardIgnored.Contains($_) } | Sort-Object)

            foreach ($pattern in $patterns) {
                if ($pattern.StartsWith("!", [StringComparison]::Ordinal)) { continue }
                if (Get-PatternRejectionReason $pattern) { continue }

                $temporaryPatternFile = [IO.Path]::GetTempFileName()
                try {
                    [IO.File]::WriteAllText($temporaryPatternFile, "$pattern`n", $script:Utf8NoBom)
                    $matchedByPattern = Get-IgnoredFileSet $SourceRoot @("--exclude-from=$temporaryPatternFile")
                    $hasEligibleMatch = $false
                    foreach ($match in $matchedByPattern) {
                        if ($standardIgnored.Contains($match)) {
                            $hasEligibleMatch = $true
                            break
                        }
                    }
                    if (-not $hasEligibleMatch) { $missingPatterns += $pattern }
                } finally {
                    Remove-Item -LiteralPath $temporaryPatternFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $selected = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
    foreach ($path in $files) { [void]$selected.Add($path) }
    $unlistedFiles = @()
    $explicitOnlyFiles = New-Object System.Collections.Generic.List[object]
    foreach ($path in $standardIgnored) {
        if ($selected.Contains($path)) { continue }
        $sourcePath = Join-Path $SourceRoot ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
        if (Get-FileRejectionReason $path) { continue }
        $category = Get-ExplicitOnlyCategory $path
        if ($category) {
            [void]$explicitOnlyFiles.Add([pscustomobject]@{ Path = $path; Category = $category })
            continue
        }
        $unlistedFiles += $path
    }

    return [pscustomobject]@{
        ManifestPresent = ($manifestStatus -ne "absent")
        ManifestTracked = $manifestTracked
        ManifestStatus = $manifestStatus
        Files = @($files)
        TrackedManifestFiles = @($trackedManifestFiles)
        TrackedInstructions = @($trackedInstructions)
        ExplicitOnlyFiles = @($explicitOnlyFiles.ToArray())
        UnlistedFiles = @($unlistedFiles | Sort-Object)
        MissingPatterns = @($missingPatterns)
        RejectedPatterns = @($rejectedPatterns)
        SetupContract = $setupContract
    }
}

function Get-ProvisionDecision {
    param(
        $Selection,
        [int] $RequiredMissing = 0
    )

    if ($Selection.ManifestStatus -eq "untracked") { return "invalid-manifest" }
    if ($Selection.RejectedPatterns.Count -gt 0) { return "invalid-manifest" }
    if ($Selection.TrackedManifestFiles.Count -gt 0) { return "invalid-manifest" }
    if ($RequiredMissing -gt 0) { return "required-local-config-missing" }
    if ($Selection.UnlistedFiles.Count -gt 0) { return "eligible-ignored-files-unlisted" }
    if (-not $Selection.ManifestPresent) { return "no-manifest-needed" }
    if ($Selection.Files.Count -eq 0) { return "manifest-present-no-matches" }
    return "manifest-ready"
}

function Test-RequiredPath {
    param(
        [string] $SourceRoot,
        [AllowNull()][string] $TargetRoot,
        [string[]] $RequiredPaths
    )

    $missing = @()
    foreach ($relativePath in $RequiredPaths) {
        if ([IO.Path]::IsPathRooted($relativePath) -or (Get-PatternRejectionReason $relativePath)) {
            Write-ProvisionRecord "required-rejected" $relativePath "required paths must be repository-relative"
            $missing += $relativePath
            continue
        }

        $platformRelativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $sourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $platformRelativePath))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Write-ProvisionRecord "required-missing" $relativePath "source file is not present"
            $missing += $relativePath
            continue
        }

        if ($TargetRoot) {
            $targetPath = [IO.Path]::GetFullPath((Join-Path $TargetRoot $platformRelativePath))
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                Write-ProvisionRecord "required-missing" $relativePath "target file is not present"
                $missing += $relativePath
                continue
            }
        }
        Write-ProvisionRecord "required-present" $relativePath
    }
    return $missing.Count
}

function Get-WorktreeBranch {
    param(
        [AllowNull()][string] $WorktreeRoot,
        [string] $MissingValue = "(not-created)"
    )

    if (-not $WorktreeRoot -or -not (Test-Path -LiteralPath $WorktreeRoot -PathType Container)) {
        return $MissingValue
    }

    $result = Invoke-GitCapture $WorktreeRoot @("branch", "--show-current")
    if ($result.ExitCode -ne 0) {
        throw "Could not resolve the branch for worktree '$WorktreeRoot'."
    }
    $branch = $result.Stdout.Trim()
    if ($branch) { return $branch }
    return "(detached)"
}

function Get-WorktreeHead {
    param(
        [AllowNull()][string] $WorktreeRoot,
        [string] $MissingValue = "(not-created)"
    )

    if (-not $WorktreeRoot -or -not (Test-Path -LiteralPath $WorktreeRoot -PathType Container)) {
        return $MissingValue
    }

    $result = Invoke-GitCapture $WorktreeRoot @("rev-parse", "HEAD")
    if ($result.ExitCode -ne 0) {
        throw "Could not resolve the current commit for worktree '$WorktreeRoot'."
    }
    $head = $result.Stdout.Trim()
    if ($head) { return $head }
    return "(no-commit)"
}

function Test-TrackedConfigurationCandidate {
    param([string] $RelativePath)

    $normalized = $RelativePath.Replace("\\", "/")
    $name = [IO.Path]::GetFileName($normalized).ToLowerInvariant()
    if ($name -like "*.config") { return $true }
    if ($name -in @(".env", "web.config", "app.config", "appsettings.json", "launchsettings.json", "applicationhost.config")) {
        return $true
    }
    if ($name -like "appsettings.*.json" -or $name -like ".env.*") { return $true }
    return $false
}

function Get-TrackedManifestRejectionReason {
    param([string] $RelativePath)

    if (Test-TrackedConfigurationCandidate $RelativePath) {
        return "tracked application-owned configuration cannot be copied from another worktree; use project-specific manual setup or an explicit repository contract"
    }
    return "tracked files already arrive through Git and cannot be copied from another worktree; remove this path from .worktreeinclude"
}

function Get-ModifiedTrackedConfiguration {
    param([string] $SourceRoot)

    $paths = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
    $diffArguments = @(
        @("diff", "--name-only", "--diff-filter=ACMRTUXB", "-z", "--"),
        @("diff", "--cached", "--name-only", "--diff-filter=ACMRTUXB", "-z", "--")
    )
    foreach ($arguments in $diffArguments) {
        $output = Invoke-GitChecked $SourceRoot $arguments "Git could not enumerate modified tracked configuration."
        foreach ($path in (Split-NulOutput $output)) {
            if (Test-TrackedConfigurationCandidate $path) { [void]$paths.Add($path) }
        }
    }
    return @($paths | Sort-Object)
}

function Get-TrackedPathSet {
    param([string] $SourceRoot)

    $output = Invoke-GitChecked $SourceRoot @("ls-files", "-z", "--") "Git could not enumerate tracked files."
    $set = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
    foreach ($path in (Split-NulOutput $output)) { [void]$set.Add($path) }
    Write-Output -NoEnumerate $set
}

function Get-TrackedManifestFiles {
    param(
        [string] $SourceRoot,
        [System.Collections.Generic.HashSet[string]] $TrackedPaths
    )

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("git-worktree-provision-manifest-" + [guid]::NewGuid().ToString("N"))
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    try {
        [IO.File]::Copy((Join-Path $SourceRoot ".worktreeinclude"), (Join-Path $temporaryRoot ".gitignore"), $true)
        Invoke-GitChecked $temporaryRoot @("init", "--quiet") "Git could not prepare the isolated manifest matcher." | Out-Null

        $matches = @()
        foreach ($path in $TrackedPaths) {
            $result = Invoke-GitCapture $temporaryRoot @("check-ignore", "--no-index", "--", $path)
            if ($result.ExitCode -eq 0) {
                $matches += $path
            } elseif ($result.ExitCode -ne 1) {
                throw "Git could not evaluate tracked paths against .worktreeinclude."
            }
        }
        return @($matches | Sort-Object)
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ConfigurationReferencePath {
    param(
        [string] $SourceRelativePath,
        [string] $RawPath
    )

    $normalized = $RawPath.Trim().Replace("\", "/")
    if (-not $normalized) {
        return [pscustomobject]@{ Valid = $false; Target = "(invalid-reference)"; Reason = "reference path is empty" }
    }
    if ($normalized -match '^[A-Za-z]:/' -or $normalized.StartsWith("/", [StringComparison]::Ordinal) -or
        $normalized -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        return [pscustomobject]@{ Valid = $false; Target = "(invalid-reference)"; Reason = "reference is not a repository-relative path" }
    }

    $sourceDirectory = [IO.Path]::GetDirectoryName($SourceRelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar))
    $combined = if ($sourceDirectory) { "$sourceDirectory/$normalized" } else { $normalized }
    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in ($combined.Replace("\", "/") -split "/")) {
        if (-not $segment -or $segment -eq ".") { continue }
        if ($segment -eq "..") {
            return [pscustomobject]@{ Valid = $false; Target = "(invalid-reference)"; Reason = "reference escapes the repository-relative configuration boundary" }
        }
        $segments.Add($segment)
    }

    $target = ($segments -join "/")
    if (-not $target) {
        return [pscustomobject]@{ Valid = $false; Target = "(invalid-reference)"; Reason = "reference path resolves to the repository root" }
    }
    return [pscustomobject]@{ Valid = $true; Target = $target; Reason = "" }
}

function Get-ConfigurationReadiness {
    param(
        [string] $SourceRoot,
        [AllowNull()][string] $TargetRoot
    )

    $tracked = Get-TrackedPathSet $SourceRoot
    $ignored = Get-IgnoredFileSet $SourceRoot @("--exclude-standard")
    $configurationFiles = @($tracked | Where-Object { Test-TrackedConfigurationCandidate $_ } | Sort-Object)
    $references = New-Object System.Collections.Generic.List[object]
    $referenceKeys = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $configSourcePattern = '(?is)\bconfigSource\s*=\s*(["''])(?<path>[^"'']+)\1'
    $appSettingsPattern = '(?is)<appSettings\b(?<attributes>[^>]*)>'
    $filePattern = '\bfile\s*=\s*(["''])(?<path>[^"'']+)\1'

    foreach ($sourceRelativePath in $configurationFiles) {
        $sourcePath = Join-Path $SourceRoot ($sourceRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        try {
            $text = [IO.File]::ReadAllText($sourcePath)
        } catch {
            $key = "$sourceRelativePath|unreadable"
            if ($referenceKeys.Add($key)) {
                [void]$references.Add([pscustomobject]@{
                    Source = $sourceRelativePath
                    Kind = "configuration file"
                    Raw = ""
                    Target = $sourceRelativePath
                    Valid = $false
                    SourcePresent = $false
                    TargetPresent = $false
                    TargetRootSupplied = [bool]$TargetRoot
                    Mapping = "unmapped"
                    Reason = "could not inspect the file for explicit configuration references"
                })
            }
            continue
        }

        $scanText = [Text.RegularExpressions.Regex]::Replace($text, '(?is)<!--.*?-->', '')
        $rawReferences = New-Object System.Collections.Generic.List[object]
        foreach ($match in [regex]::Matches($scanText, $configSourcePattern)) {
            [void]$rawReferences.Add([pscustomobject]@{ Kind = "configSource"; Raw = $match.Groups["path"].Value.Trim() })
        }
        foreach ($match in [regex]::Matches($scanText, $appSettingsPattern)) {
            foreach ($fileMatch in [regex]::Matches($match.Groups["attributes"].Value, $filePattern)) {
                [void]$rawReferences.Add([pscustomobject]@{ Kind = "appSettings file"; Raw = $fileMatch.Groups["path"].Value.Trim() })
            }
        }

        foreach ($rawReference in $rawReferences) {
            $resolved = Get-ConfigurationReferencePath $sourceRelativePath $rawReference.Raw
            $key = "$sourceRelativePath|$($rawReference.Kind)|$($resolved.Target)"
            if (-not $referenceKeys.Add($key)) { continue }

            $sourcePresent = $false
            $targetPresent = $false
            $mapping = "unmapped"
            if ($resolved.Valid) {
                $sourceTargetPath = Join-Path $SourceRoot ($resolved.Target.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $sourcePresent = Test-Path -LiteralPath $sourceTargetPath -PathType Leaf
                if ($tracked.Contains($resolved.Target)) {
                    $mapping = "tracked"
                } elseif ($ignored.Contains($resolved.Target)) {
                    $mapping = "ignored"
                }
                if ($TargetRoot) {
                    $targetTargetPath = Join-Path $TargetRoot ($resolved.Target.Replace('/', [IO.Path]::DirectorySeparatorChar))
                    $targetPresent = Test-Path -LiteralPath $targetTargetPath -PathType Leaf
                }
            }

            [void]$references.Add([pscustomobject]@{
                Source = $sourceRelativePath
                Kind = $rawReference.Kind
                Raw = $rawReference.Raw
                Target = $resolved.Target
                Valid = $resolved.Valid
                SourcePresent = $sourcePresent
                TargetPresent = $targetPresent
                TargetRootSupplied = [bool]$TargetRoot
                Mapping = $mapping
                Reason = $resolved.Reason
            })
        }
    }

    return [pscustomobject]@{
        References = $references.ToArray()
        ModifiedTrackedConfigurations = @(Get-ModifiedTrackedConfiguration $SourceRoot)
        Evidence = @(Get-ConfigurationEvidence $SourceRoot $tracked)
    }
}

function Write-ConfigurationReferenceRecords {
    param($ConfigurationReadiness)

    $issues = 0
    foreach ($reference in $ConfigurationReadiness.References) {
        $label = if ($reference.Target) { "$($reference.Source) -> $($reference.Target)" } else { $reference.Source }
        Write-ProvisionRecord "expected" $label "explicit $($reference.Kind) reference"
        if (-not $reference.Valid) {
            Write-ProvisionRecord "unmapped" $label $reference.Reason
            $issues++
            continue
        }
        if (-not $reference.SourcePresent) {
            Write-ProvisionRecord "missing" $label "referenced configuration file is missing from the source worktree"
            $issues++
            continue
        }

        Write-ProvisionRecord "present" $label "referenced configuration file is present in the source worktree ($($reference.Mapping))"
        if ($reference.Mapping -eq "unmapped") {
            Write-ProvisionRecord "unmapped" $label "referenced configuration file is present but is neither tracked nor ignored"
            $issues++
        }
        if ($reference.TargetRootSupplied -and -not $reference.TargetPresent) {
            Write-ProvisionRecord "missing" $label "target worktree is missing the referenced configuration file"
            $issues++
        }
    }
    return $issues
}

function Write-WorktreeIdentity {
    param(
        [string] $SourceRoot,
        [AllowNull()][string] $TargetRoot
    )

    Write-Host "Source worktree: $(Format-DisplayText $SourceRoot)"
    Write-Host "Source branch: $(Format-DisplayText (Get-WorktreeBranch $SourceRoot))"
    $targetDisplay = if ($TargetRoot) { [IO.Path]::GetFullPath($TargetRoot) } else { "(not-specified)" }
    $targetBranch = if ($TargetRoot) { Get-WorktreeBranch $TargetRoot } else { "(not-specified)" }
    Write-Host "Target worktree: $(Format-DisplayText $targetDisplay)"
    Write-Host "Target branch: $(Format-DisplayText $targetBranch)"
}

function Write-ReadinessReport {
    param(
        [string] $SourceRoot,
        $Selection,
        [AllowNull()][string] $TargetRoot,
        $ConfigurationReadiness
    )

    Write-Host "Worktree readiness: read-only"
    Write-WorktreeIdentity $SourceRoot $TargetRoot
    Write-Host "Manifest: $(Format-DisplayText $Selection.ManifestStatus)"
    Write-SetupContractRecord $Selection.SetupContract

    foreach ($relativePath in $Selection.Files) {
        Write-ProvisionRecord "authorized" $relativePath "ignored file authorized for provisioning"
    }
    foreach ($relativePath in $Selection.TrackedManifestFiles) {
        Write-ProvisionRecord "rejected" $relativePath (Get-TrackedManifestRejectionReason $relativePath)
    }
    foreach ($relativePath in $Selection.TrackedInstructions) {
        Write-ProvisionRecord "tracked-instructions" $relativePath "tracked instructions arrive through Git; not copied"
    }
    foreach ($entry in $Selection.ExplicitOnlyFiles) {
        $detail = if ($entry.Category -eq "agent-override") {
            "private agent override affects agent behavior; not suggested as ordinary configuration"
        } else {
            "client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration"
        }
        Write-ProvisionRecord $entry.Category $entry.Path $detail
    }
    foreach ($relativePath in $Selection.UnlistedFiles) {
        Write-ProvisionRecord "unlisted" $relativePath "ignored file present but not authorized for provisioning"
    }
    foreach ($relativePath in $ConfigurationReadiness.ModifiedTrackedConfigurations) {
        Write-ProvisionRecord "tracked-config" $relativePath "modified tracked configuration was not copied; review only if this worktree requires the local override."
    }
    Write-ConfigurationEvidenceRecords $ConfigurationReadiness
    $configurationIssues = Write-ConfigurationReferenceRecords $ConfigurationReadiness
    if ($Selection.Files.Count -eq 0 -and $Selection.TrackedManifestFiles.Count -eq 0 -and
        $Selection.TrackedInstructions.Count -eq 0 -and $Selection.ExplicitOnlyFiles.Count -eq 0 -and
        $Selection.UnlistedFiles.Count -eq 0 -and
        $ConfigurationReadiness.ModifiedTrackedConfigurations.Count -eq 0 -and
        $ConfigurationReadiness.Evidence.Count -eq 0 -and $configurationIssues -eq 0) {
        Write-Host "[configuration] no local configuration differences"
    }

    Write-ReadinessStates $Selection
    Write-Host "Readiness limits: fresh build, running application server, authenticated browser session, and application credentials were not checked."
    Write-Host "Writes: none"
}

function Write-ProvisionReport {
    param(
        [string] $SourceRoot,
        $Selection,
        [AllowNull()][string] $TargetRoot,
        [string[]] $RequiredPaths = @(),
        $ConfigurationReadiness = $null
    )

    Write-Host "Provisioning check: read-only"
    Write-Host "Source worktree: $(Format-DisplayText $SourceRoot)"
    Write-Host "Manifest: $(Format-DisplayText $Selection.ManifestStatus)"
    Write-SetupContractRecord $Selection.SetupContract

    foreach ($relativePath in $Selection.Files) {
        Write-ProvisionRecord "matched" $relativePath "Git-ignored and manifest-listed"
    }
    foreach ($relativePath in $Selection.TrackedManifestFiles) {
        Write-ProvisionRecord "rejected" $relativePath (Get-TrackedManifestRejectionReason $relativePath)
    }
    foreach ($relativePath in $Selection.TrackedInstructions) {
        Write-ProvisionRecord "tracked-instructions" $relativePath "tracked instructions arrive through Git; not copied"
    }
    foreach ($entry in $Selection.ExplicitOnlyFiles) {
        $detail = if ($entry.Category -eq "agent-override") {
            "private agent override affects agent behavior; not suggested as ordinary configuration"
        } else {
            "client-local settings can alter permissions or tool behavior; not suggested as ordinary configuration"
        }
        Write-ProvisionRecord $entry.Category $entry.Path $detail
    }
    foreach ($relativePath in $Selection.UnlistedFiles) {
        Write-ProvisionRecord "unlisted" $relativePath "eligible Git-ignored file is not manifest-listed"
    }
    foreach ($pattern in $Selection.MissingPatterns) {
        Write-ProvisionRecord "missing" $pattern "no present Git-ignored source file matched"
    }
    foreach ($entry in $Selection.RejectedPatterns) {
        Write-ProvisionRecord "rejected" $entry.Pattern $entry.Reason
    }
    if ($ConfigurationReadiness) {
        foreach ($relativePath in $ConfigurationReadiness.ModifiedTrackedConfigurations) {
            Write-ProvisionRecord "tracked-config" $relativePath "modified tracked configuration was not copied; review only if this worktree requires the local override."
        }
        Write-ConfigurationEvidenceRecords $ConfigurationReadiness
        [void](Write-ConfigurationReferenceRecords $ConfigurationReadiness)
    }

    foreach ($relativePath in $Selection.Files) {
        $reason = Get-FileRejectionReason $relativePath
        if ($reason) {
            Write-ProvisionRecord "rejected" $relativePath $reason
            continue
        }

        $platformRelativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $sourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $platformRelativePath))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Write-ProvisionRecord "missing" $relativePath "source file no longer exists or is not a regular file"
            continue
        }

        if ($TargetRoot) {
            $targetPath = [IO.Path]::GetFullPath((Join-Path $TargetRoot $platformRelativePath))
            if (Test-Path -LiteralPath $targetPath) {
                Write-ProvisionRecord "conflict" $relativePath "target already exists; not overwritten"
                continue
            }
        }
        Write-ProvisionRecord "would-copy" $relativePath
    }

    $requiredMissing = Test-RequiredPath $SourceRoot $TargetRoot $RequiredPaths
    $decision = Get-ProvisionDecision $Selection $requiredMissing
    if ($RequiredPaths.Count -eq 0) {
        Write-Host "Requirement: unknown (application-specific; verify build or startup)"
    }
    Write-Host "Decision: $(Format-DisplayText $decision)"
    Write-ReadinessStates $Selection $requiredMissing
    Write-Host "Writes: none"
    return [pscustomobject]@{
        Decision = $decision
        RequiredMissing = $requiredMissing
    }
}

function Assert-SameRepository {
    param([string] $SourceRoot, [string] $TargetRoot)

    $sourceCommon = Get-CommonGitDirectory $SourceRoot
    $targetCommon = Get-CommonGitDirectory $TargetRoot
    if (-not (Test-SamePath $sourceCommon $targetCommon)) {
        throw "Source and target are not worktrees of the same Git repository."
    }
}

function Invoke-ProvisionFiles {
    param(
        [string] $SourceRoot,
        [string] $TargetRoot,
        [switch] $DryRun
    )

    Assert-SameRepository $SourceRoot $TargetRoot
    $selection = Get-ProvisionSelection $SourceRoot
    if (-not $selection.ManifestPresent) {
        Write-ProvisionRecord "skipped" ".worktreeinclude" "manifest not found in source worktree"
        foreach ($relativePath in $selection.UnlistedFiles) {
            Write-ProvisionRecord "unlisted" $relativePath "eligible Git-ignored file is not manifest-listed"
        }
        return [pscustomobject]@{ Success = $true; Copied = 0; Conflicts = 0; Rejected = 0; Missing = 0; Unlisted = $selection.UnlistedFiles.Count }
    }
    if (-not $selection.ManifestTracked) {
        Write-ProvisionRecord "rejected" ".worktreeinclude" "manifest exists but is not tracked"
        return [pscustomobject]@{ Success = $false; Copied = 0; Conflicts = 0; Rejected = 1; Missing = 0; Unlisted = $selection.UnlistedFiles.Count }
    }

    foreach ($relativePath in $selection.UnlistedFiles) {
        Write-ProvisionRecord "unlisted" $relativePath "eligible Git-ignored file is not manifest-listed"
    }
    foreach ($pattern in $selection.MissingPatterns) {
        Write-ProvisionRecord "missing" $pattern "no present Git-ignored source file matched"
    }
    foreach ($entry in $selection.RejectedPatterns) {
        Write-ProvisionRecord "rejected" $entry.Pattern $entry.Reason
    }

    $copied = 0
    $conflicts = 0
    $rejected = $selection.RejectedPatterns.Count + $selection.TrackedManifestFiles.Count

    foreach ($relativePath in $selection.TrackedManifestFiles) {
        Write-ProvisionRecord "rejected" $relativePath (Get-TrackedManifestRejectionReason $relativePath)
    }

    foreach ($relativePath in $selection.Files) {
        $reason = Get-FileRejectionReason $relativePath
        if ($reason) {
            Write-ProvisionRecord "rejected" $relativePath $reason
            $rejected++
            continue
        }

        $platformRelativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $sourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $platformRelativePath))
        $targetPath = [IO.Path]::GetFullPath((Join-Path $TargetRoot $platformRelativePath))
        if (-not (Test-PathInsideRoot $SourceRoot $sourcePath) -or -not (Test-PathInsideRoot $TargetRoot $targetPath)) {
            Write-ProvisionRecord "rejected" $relativePath "resolved path escapes a worktree root"
            $rejected++
            continue
        }

        $sourceReparse = Get-ReparsePoint $SourceRoot $sourcePath $true
        if ($sourceReparse) {
            Write-ProvisionRecord "rejected" $relativePath "source path traverses a symbolic link or Windows reparse point"
            $rejected++
            continue
        }

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Write-ProvisionRecord "missing" $relativePath "source file no longer exists or is not a regular file"
            continue
        }

        $targetReparse = Get-ReparsePoint $TargetRoot $targetPath $false
        if ($targetReparse) {
            Write-ProvisionRecord "rejected" $relativePath "target path traverses a symbolic link or Windows reparse point"
            $rejected++
            continue
        }

        if (Test-Path -LiteralPath $targetPath) {
            Write-ProvisionRecord "conflict" $relativePath "target already exists; not overwritten"
            $conflicts++
            continue
        }

        if ($DryRun) {
            Write-ProvisionRecord "would-copy" $relativePath
            $copied++
            continue
        }

        try {
            $targetDirectory = Split-Path -Parent $targetPath
            [IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
            $targetReparse = Get-ReparsePoint $TargetRoot $targetPath $false
            if ($targetReparse) {
                throw "target parent became a symbolic link or Windows reparse point"
            }
            [IO.File]::Copy($sourcePath, $targetPath, $false)
            Write-ProvisionRecord "copied" $relativePath
            $copied++
        } catch {
            Write-ProvisionRecord "rejected" $relativePath $_.Exception.Message
            $rejected++
        }
    }

    Write-Host "Summary: copied=$copied conflicts=$conflicts missing=$($selection.MissingPatterns.Count) rejected=$rejected unlisted=$($selection.UnlistedFiles.Count)"
    return [pscustomobject]@{
        Success = ($rejected -eq 0)
        Copied = $copied
        Conflicts = $conflicts
        Rejected = $rejected
        Missing = $selection.MissingPatterns.Count
        Unlisted = $selection.UnlistedFiles.Count
    }
}

function Open-WorktreeInCode {
    param([string] $WorktreePath)

    $codeCommand = Get-Command code.cmd -ErrorAction SilentlyContinue
    if (-not $codeCommand) { $codeCommand = Get-Command code -ErrorAction SilentlyContinue }
    if (-not $codeCommand) {
        throw "VS Code's 'code' command is not available on PATH."
    }

    & $codeCommand.Source --new-window $WorktreePath
    if ($LASTEXITCODE -ne 0) {
        throw "VS Code could not open the worktree."
    }
}

function Show-HandoffReminder {
    param([string] $WorktreePath)

    Write-Host "Handoff reminder: continuity and uncommitted changes stay in this worktree."
    Write-Host "Open this exact path in Claude Code, Codex, or Copilot:"
    Write-Host "  $(Format-DisplayText $WorktreePath)"
    Write-Host "Then say: Continue from project continuity."
    Write-Host "Use a separate worktree for another unfinished task."
}

function Show-AddUsage {
    Write-Host "Usage: git wt-add [--dry-run] [--skip-copy] [--allow-unprovisioned] [--open-code] -- <git worktree add arguments>"
}

function Show-CopyUsage {
    Write-Host "Usage: git wt-copy [--dry-run] [--source <existing-worktree-path>]"
}

function Show-CheckUsage {
    Write-Host "Usage: git wt-check [--source <worktree>] [--target <path>] [--required <repo-relative-path>]..."
}

function Show-ReadinessUsage {
    Write-Host "Usage: git wt-readiness [--source <worktree>] [--target <path>]"
}

function Show-ProvisionUsage {
    Write-Host "Usage: git wt-provision --operation <copy-ignored-file|copy-external-file|merge-named-section|replace-file> --source-file <path> --target <worktree> --destination <repo-relative-path> [--approve <approval-id>] [--dry-run]"
}

function Get-ProvisionMapping {
    param(
        [string] $Operation,
        [string] $SourceFile,
        [string] $TargetRoot,
        [string] $Destination
    )

    $mapping = [pscustomobject]@{
        Valid = $false
        Operation = $Operation
        SourcePath = ""
        SourceBranch = "(external)"
        SourceClassification = ""
        SourceFingerprint = ""
        TargetRoot = [IO.Path]::GetFullPath($TargetRoot)
        TargetBranch = "(unknown)"
        TargetHead = "(unknown)"
        TargetPath = ""
        Destination = $Destination.Replace("\", "/")
        ApprovalId = ""
        Reason = ""
    }

    if ($Operation -notin @("copy-ignored-file", "copy-external-file", "merge-named-section", "replace-file")) {
        $mapping.Reason = "unsupported mapping operation"
        return $mapping
    }
    if ($Operation -in @("merge-named-section", "replace-file")) {
        $mapping.Reason = "the generic helper does not perform section merges or whole-file replacement"
        return $mapping
    }
    $mapping.SourcePath = [IO.Path]::GetFullPath($SourceFile)
    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        $mapping.Reason = "source file is not present"
        return $mapping
    }
    if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
        $mapping.Reason = "target worktree does not exist"
        return $mapping
    }
    $mapping.TargetBranch = Get-WorktreeBranch $TargetRoot
    $mapping.TargetHead = Get-WorktreeHead $TargetRoot

    $sourceItem = Get-Item -LiteralPath $SourceFile -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $mapping.Reason = "source file is or traverses a symbolic link or Windows reparse point"
        return $mapping
    }
    $mapping.SourcePath = $sourceItem.FullName
    $mapping.SourceFingerprint = Get-FileFingerprint $mapping.SourcePath

    $sourceRoot = $null
    try { $sourceRoot = Get-RepositoryRoot (Split-Path -Parent $mapping.SourcePath) } catch { $sourceRoot = $null }
    $sourceRelative = $null
    $sourceIsIgnored = $false
    $sourceIsTracked = $false
    if ($sourceRoot) {
        $sourceRoot = [IO.Path]::GetFullPath($sourceRoot)
        $mapping.SourceBranch = Get-WorktreeBranch $sourceRoot "(detached)"
        if (Test-PathInsideRoot $sourceRoot $mapping.SourcePath) {
            $sourceRelative = $mapping.SourcePath.Substring($sourceRoot.TrimEnd("\", "/").Length).TrimStart("\", "/").Replace("\", "/")
            $trackedResult = Invoke-GitCapture $sourceRoot @("ls-files", "--error-unmatch", "--", $sourceRelative)
            $sourceIsTracked = ($trackedResult.ExitCode -eq 0)
            $ignoredResult = Invoke-GitCapture $sourceRoot @("check-ignore", "--no-index", "-q", "--", $sourceRelative)
            $sourceIsIgnored = ($ignoredResult.ExitCode -eq 0)
        }
    }
    if ($sourceIsTracked) {
        $mapping.SourceClassification = "tracked"
        $mapping.Reason = "tracked files, including application configuration, cannot be copied by the generic helper"
        return $mapping
    }
    if ($sourceIsIgnored) {
        $mapping.SourceClassification = "ignored"
    } else {
        $mapping.SourceClassification = "external"
    }
    if ($Operation -eq "copy-ignored-file" -and -not $sourceIsIgnored) {
        $mapping.Reason = "copy-ignored-file requires a Git-ignored source file"
        return $mapping
    }
    if ($Operation -eq "copy-external-file" -and $sourceIsIgnored -and $sourceRoot) {
        $mapping.SourceClassification = "ignored-external"
    }

    if (-not (Test-RepositoryRelativeContractPath $Destination)) {
        $mapping.Reason = "destination must be a repository-relative path"
        return $mapping
    }
    $mapping.TargetPath = [IO.Path]::GetFullPath((Join-Path $TargetRoot $mapping.Destination.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not (Test-PathInsideRoot $TargetRoot $mapping.TargetPath)) {
        $mapping.Reason = "destination escapes the target worktree"
        return $mapping
    }
    if (Get-ReparsePoint $TargetRoot $mapping.TargetPath $false) {
        $mapping.Reason = "destination traverses a symbolic link or Windows reparse point"
        return $mapping
    }
    $targetTracked = (Get-TrackedPathSet $TargetRoot).Contains($mapping.Destination)
    if ($targetTracked) {
        $mapping.Reason = "tracked target files cannot be overwritten by a generic mapping"
        return $mapping
    }
    $targetIgnored = Invoke-GitCapture $TargetRoot @("check-ignore", "--no-index", "-q", "--", $mapping.Destination)
    if ($targetIgnored.ExitCode -ne 0) {
        $mapping.Reason = "destination must be Git-ignored in the target worktree"
        return $mapping
    }

    if ($Operation -eq "copy-ignored-file" -and $sourceRoot) {
        $sourceCommon = Get-CommonGitDirectory $sourceRoot
        $targetCommon = Get-CommonGitDirectory $TargetRoot
        if (-not (Test-SamePath $sourceCommon $targetCommon)) {
            $mapping.Reason = "copy-ignored-file accepts only an ignored source from the target repository's worktree set"
            return $mapping
        }
    }
    $mapping.TargetBranch = Get-WorktreeBranch $TargetRoot
    $mapping.TargetHead = Get-WorktreeHead $TargetRoot

    $identity = "schema=2|operation=$Operation|source=$($mapping.SourcePath)|fingerprint=$($mapping.SourceFingerprint)|target=$($mapping.TargetRoot)|target-head=$($mapping.TargetHead)|destination=$($mapping.Destination)"
    $mapping.ApprovalId = Get-TextFingerprint $identity
    $mapping.Valid = $true
    return $mapping
}

function Write-ProvisionMappingReport {
    param(
        $Mapping,
        [AllowNull()][string] $Approval
    )

    Write-Host "Provisioning mapping: read-only"
    Write-Host "Operation: $(Format-DisplayText $Mapping.Operation)"
    Write-Host "Source file: $(Format-DisplayText $Mapping.SourcePath)"
    Write-Host "Source branch: $(Format-DisplayText $Mapping.SourceBranch)"
    Write-Host "Source classification: $(Format-DisplayText $Mapping.SourceClassification)"
    if ($Mapping.SourceFingerprint) { Write-Host "Source fingerprint: sha256:$($Mapping.SourceFingerprint)" }
    Write-Host "Target worktree: $(Format-DisplayText $Mapping.TargetRoot)"
    Write-Host "Target branch: $(Format-DisplayText $Mapping.TargetBranch)"
    Write-Host "Target HEAD: $(Format-DisplayText $Mapping.TargetHead)"
    Write-Host "Destination: $(Format-DisplayText $Mapping.Destination)"
    if (-not $Mapping.Valid) {
        Write-ProvisionRecord "mapping-rejected" $Mapping.Destination $Mapping.Reason
        Write-Host "Provisioning state: provisioning-blocked"
        Write-Host "Runtime state: runtime-unverified"
        Write-Host "Writes: none"
        return
    }
    Write-Host "Approval id: $(Format-DisplayText $Mapping.ApprovalId)"
    $state = "provisioning-ready"
    if (Test-Path -LiteralPath $Mapping.TargetPath) {
        Write-ProvisionRecord "conflict" $Mapping.Destination "target already exists; whole-file replacement is refused"
        $state = "provisioning-blocked"
    } elseif ($Approval -and $Approval -ne $Mapping.ApprovalId) {
        Write-ProvisionRecord "approval-rejected" $Mapping.Destination "approval id does not match the current source, destination, operation, target HEAD, or fingerprint"
        $state = "provisioning-review-required"
    } elseif (-not $Approval) {
        Write-ProvisionRecord "approval-required" $Mapping.Destination "ask the user to approve this exact mapping before copying"
        $state = "provisioning-review-required"
    } else {
        Write-ProvisionRecord "approved" $Mapping.Destination "exact mapping approval matches"
    }
    Write-Host "Provisioning state: $state"
    Write-Host "Runtime state: runtime-unverified"
    Write-Host "Writes: none"
}

function Invoke-ProvisionCommand {
    param([string[]] $CommandArguments)

    if ($null -eq $CommandArguments) { $CommandArguments = @() }
    if ($CommandArguments -contains "--help" -or $CommandArguments -contains "-h") {
        Show-ProvisionUsage
        return 0
    }
    $operation = $null
    $sourceFile = $null
    $targetArgument = $null
    $destination = $null
    $approval = $null
    $dryRun = $false
    for ($index = 0; $index -lt $CommandArguments.Count; $index++) {
        switch ($CommandArguments[$index]) {
            "--operation" { $index++; if ($index -ge $CommandArguments.Count) { throw "--operation requires a value." }; $operation = $CommandArguments[$index] }
            "--source-file" { $index++; if ($index -ge $CommandArguments.Count) { throw "--source-file requires a path." }; $sourceFile = $CommandArguments[$index] }
            "--target" { $index++; if ($index -ge $CommandArguments.Count) { throw "--target requires a worktree path." }; $targetArgument = $CommandArguments[$index] }
            "--destination" { $index++; if ($index -ge $CommandArguments.Count) { throw "--destination requires a repository-relative path." }; $destination = $CommandArguments[$index] }
            "--approve" { $index++; if ($index -ge $CommandArguments.Count) { throw "--approve requires an approval id." }; $approval = $CommandArguments[$index] }
            "--dry-run" { $dryRun = $true }
            default { throw "Unknown wt-provision option: $(Format-DisplayText $CommandArguments[$index])" }
        }
    }
    if (-not $operation -or -not $sourceFile -or -not $destination) {
        throw "--operation, --source-file, and --destination are required."
    }
    $sourcePath = if ([IO.Path]::IsPathRooted($sourceFile)) { [IO.Path]::GetFullPath($sourceFile) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $sourceFile)) }
    $targetPath = if ($targetArgument) {
        if ([IO.Path]::IsPathRooted($targetArgument)) { [IO.Path]::GetFullPath($targetArgument) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $targetArgument)) }
    } else { (Get-Location).Path }
    $targetRoot = Get-RepositoryRoot $targetPath
    $mapping = Get-ProvisionMapping $operation $sourcePath $targetRoot $destination
    Write-ProvisionMappingReport $mapping $approval
    if (-not $mapping.Valid) { return 2 }
    if ($dryRun) { return 0 }
    if (-not $approval) { return 3 }
    if ($approval -ne $mapping.ApprovalId) { return 3 }
    if (Test-Path -LiteralPath $mapping.TargetPath) { return 2 }
    try {
        $targetDirectory = Split-Path -Parent $mapping.TargetPath
        [IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
        if (Get-ReparsePoint $mapping.TargetRoot $mapping.TargetPath $false) {
            throw "target path became a symbolic link or Windows reparse point"
        }
        [IO.File]::Copy($mapping.SourcePath, $mapping.TargetPath, $false)
        Write-ProvisionRecord "copied" $mapping.Destination "approved exact mapping; target was absent"
        Write-Host "Runtime state: runtime-unverified"
        return 0
    } catch {
        Write-ProvisionRecord "mapping-rejected" $mapping.Destination $_.Exception.Message
        return 2
    }
}

function Invoke-CheckCommand {
    param([string[]] $CommandArguments)

    if ($null -eq $CommandArguments) { $CommandArguments = @() }
    if ($CommandArguments -contains "--help" -or $CommandArguments -contains "-h") {
        Show-CheckUsage
        return 0
    }

    $sourceArgument = $null
    $targetArgument = $null
    $requiredPaths = @()
    for ($index = 0; $index -lt $CommandArguments.Count; $index++) {
        switch ($CommandArguments[$index]) {
            "--source" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--source requires a path." }
                $sourceArgument = $CommandArguments[$index]
            }
            "--target" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--target requires a path." }
                $targetArgument = $CommandArguments[$index]
            }
            "--required" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--required requires a repository-relative path." }
                $requiredPaths += $CommandArguments[$index]
            }
            default { throw "Unknown wt-check option: $(Format-DisplayText $CommandArguments[$index])" }
        }
    }

    $sourcePath = if ($sourceArgument) {
        if ([IO.Path]::IsPathRooted($sourceArgument)) { [IO.Path]::GetFullPath($sourceArgument) }
        else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $sourceArgument)) }
    } else { (Get-Location).Path }
    $sourceRoot = Get-RepositoryRoot $sourcePath
    $targetRoot = $null
    if ($targetArgument) {
        $targetRoot = if ([IO.Path]::IsPathRooted($targetArgument)) {
            [IO.Path]::GetFullPath($targetArgument)
        } else {
            [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $targetArgument))
        }
        if (Test-Path -LiteralPath $targetRoot -PathType Container) {
            Assert-SameRepository $sourceRoot (Get-RepositoryRoot $targetRoot)
        }
    }

    $selection = Get-ProvisionSelection $sourceRoot
    $configurationReadiness = Get-ConfigurationReadiness $sourceRoot $targetRoot
    $report = Write-ProvisionReport $sourceRoot $selection $targetRoot $requiredPaths $configurationReadiness
    if ($report.Decision -eq "invalid-manifest" -or $report.Decision -eq "required-local-config-missing") { return 2 }
    if ($report.Decision -eq "eligible-ignored-files-unlisted") { return 3 }
    return 0
}

function Invoke-ReadinessCommand {
    param([string[]] $CommandArguments)

    if ($null -eq $CommandArguments) { $CommandArguments = @() }
    if ($CommandArguments -contains "--help" -or $CommandArguments -contains "-h") {
        Show-ReadinessUsage
        return 0
    }

    $sourceArgument = $null
    $targetArgument = $null
    for ($index = 0; $index -lt $CommandArguments.Count; $index++) {
        switch ($CommandArguments[$index]) {
            "--source" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--source requires a path." }
                $sourceArgument = $CommandArguments[$index]
            }
            "--target" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--target requires a path." }
                $targetArgument = $CommandArguments[$index]
            }
            default { throw "Unknown wt-readiness option: $(Format-DisplayText $CommandArguments[$index])" }
        }
    }

    $sourcePath = if ($sourceArgument) {
        if ([IO.Path]::IsPathRooted($sourceArgument)) { [IO.Path]::GetFullPath($sourceArgument) }
        else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $sourceArgument)) }
    } else { (Get-Location).Path }
    $sourceRoot = Get-RepositoryRoot $sourcePath
    $targetRoot = $null
    if ($targetArgument) {
        $targetRoot = if ([IO.Path]::IsPathRooted($targetArgument)) {
            [IO.Path]::GetFullPath($targetArgument)
        } else {
            [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $targetArgument))
        }
        if (Test-Path -LiteralPath $targetRoot -PathType Container) {
            Assert-SameRepository $sourceRoot (Get-RepositoryRoot $targetRoot)
        }
    }

    $selection = Get-ProvisionSelection $sourceRoot
    $configurationReadiness = Get-ConfigurationReadiness $sourceRoot $targetRoot
    Write-ReadinessReport $sourceRoot $selection $targetRoot $configurationReadiness
    return 0
}

function Invoke-AddCommand {
    param([string[]] $CommandArguments)

    if ($CommandArguments -contains "--help" -or $CommandArguments -contains "-h") {
        Show-AddUsage
        return 0
    }

    $separatorIndex = [Array]::IndexOf($CommandArguments, "--")
    if ($separatorIndex -lt 0) {
        throw "Use -- to separate wrapper options from native 'git worktree add' arguments."
    }

    $wrapperArguments = if ($separatorIndex -eq 0) { @() } else { @($CommandArguments[0..($separatorIndex - 1)]) }
    $gitArguments = if ($separatorIndex -eq $CommandArguments.Count - 1) { @() } else { @($CommandArguments[($separatorIndex + 1)..($CommandArguments.Count - 1)]) }
    if ($gitArguments.Count -eq 0) {
        throw "Native 'git worktree add' arguments are required after --."
    }

    $dryRun = $false
    $skipCopy = $false
    $allowUnprovisioned = $false
    $openCode = $false
    foreach ($argument in $wrapperArguments) {
        switch ($argument) {
            "--dry-run" { $dryRun = $true }
            "--skip-copy" { $skipCopy = $true }
            "--allow-unprovisioned" { $allowUnprovisioned = $true }
            "--open-code" { $openCode = $true }
            default { throw "Unknown wt-add option: $(Format-DisplayText $argument)" }
        }
    }

    $sourceRoot = Get-RepositoryRoot (Get-Location).Path
    if ($skipCopy) { $allowUnprovisioned = $true }
    $selection = Get-ProvisionSelection $sourceRoot
    $configurationReadiness = Get-ConfigurationReadiness $sourceRoot $null
    $preflight = Write-ProvisionReport $sourceRoot $selection $null @() $configurationReadiness
    if ($preflight.Decision -eq "invalid-manifest") { return 2 }
    if ($preflight.Decision -eq "eligible-ignored-files-unlisted" -and -not $allowUnprovisioned) {
        Write-Host "Creation blocked: eligible ignored files are not manifest-listed. Use --allow-unprovisioned only after reviewing the report."
        return 3
    }
    if ($dryRun) {
        Write-Host "[dry-run] git worktree add arguments accepted; Git will not be executed."
        if ($skipCopy) { Write-ProvisionRecord "skipped" ".worktreeinclude" "copying disabled by --skip-copy" }
        if ($openCode) { Write-Host "[dry-run] VS Code will not be opened." }
        return 0
    }

    $before = Get-WorktreePaths $sourceRoot
    $gitResult = Invoke-GitCapture $sourceRoot (@("worktree", "add") + $gitArguments)
    if ($gitResult.Stdout) { [Console]::Out.Write($gitResult.Stdout) }
    if ($gitResult.Stderr) { [Console]::Error.Write($gitResult.Stderr) }
    if ($gitResult.ExitCode -ne 0) { return $gitResult.ExitCode }

    $after = Get-WorktreePaths $sourceRoot
    $targetRoot = Get-NewWorktreePath $before $after
    Write-Host "Worktree: $(Format-DisplayText $targetRoot)"

    if ($skipCopy) {
        Write-ProvisionRecord "skipped" ".worktreeinclude" "copying disabled by --skip-copy"
    } else {
        $result = Invoke-ProvisionFiles $sourceRoot $targetRoot
        if (-not $result.Success) { return 2 }
    }

    if ($openCode) { Open-WorktreeInCode $targetRoot }
    Show-HandoffReminder $targetRoot
    return 0
}

function Get-PrimaryWorktreeRoot {
    param([string] $TargetRoot)

    $commonDirectory = Get-CommonGitDirectory $TargetRoot
    if ($env:GIT_WORKTREE_PROVISION_DEBUG) {
        [Console]::Error.WriteLine("debug common Git directory: $(Format-DisplayText $commonDirectory)")
    }
    foreach ($worktreePath in (Get-WorktreePaths $TargetRoot)) {
        if (-not (Test-Path -LiteralPath $worktreePath -PathType Container)) { continue }
        $gitDirectoryOutput = Invoke-GitCapture $worktreePath @("rev-parse", "--path-format=absolute", "--git-dir")
        if ($gitDirectoryOutput.ExitCode -ne 0) { continue }
        $gitDirectory = [IO.Path]::GetFullPath($gitDirectoryOutput.Stdout.Trim())
        if ($env:GIT_WORKTREE_PROVISION_DEBUG) {
            [Console]::Error.WriteLine("debug worktree Git directory: $(Format-DisplayText $worktreePath) -> $(Format-DisplayText $gitDirectory)")
        }
        if (Test-SamePath $gitDirectory $commonDirectory) { return $worktreePath }
    }
    return $null
}

function Invoke-CopyCommand {
    param([string[]] $CommandArguments)

    if ($null -eq $CommandArguments) { $CommandArguments = @() }

    if ($CommandArguments -contains "--help" -or $CommandArguments -contains "-h") {
        Show-CopyUsage
        return 0
    }

    $dryRun = $false
    $sourceArgument = $null
    for ($index = 0; $index -lt $CommandArguments.Count; $index++) {
        $argument = $CommandArguments[$index]
        switch ($argument) {
            "--dry-run" { $dryRun = $true }
            "--source" {
                $index++
                if ($index -ge $CommandArguments.Count) { throw "--source requires a path." }
                $sourceArgument = $CommandArguments[$index]
            }
            default { throw "Unknown wt-copy option: $(Format-DisplayText $argument)" }
        }
    }

    $targetRoot = Get-RepositoryRoot (Get-Location).Path
    if ($sourceArgument) {
        $sourcePath = if ([IO.Path]::IsPathRooted($sourceArgument)) {
            [IO.Path]::GetFullPath($sourceArgument)
        } else {
            [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $sourceArgument))
        }
        $sourceRoot = Get-RepositoryRoot $sourcePath
    } else {
        $sourceRoot = Get-PrimaryWorktreeRoot $targetRoot
        if (-not $sourceRoot -or (Test-SamePath $sourceRoot $targetRoot)) {
            throw "The source worktree is ambiguous. Supply --source <existing-worktree-path>."
        }
    }

    Assert-SameRepository $sourceRoot $targetRoot
    if (Test-SamePath $sourceRoot $targetRoot) {
        throw "Source and target must be different worktrees."
    }
    Write-Host "Source worktree: $(Format-DisplayText $sourceRoot)"
    Write-Host "Target worktree: $(Format-DisplayText $targetRoot)"

    $result = Invoke-ProvisionFiles $sourceRoot $targetRoot -DryRun:$dryRun
    if (-not $result.Success) { return 2 }
    return 0
}

try {
    if ($args.Count -eq 0) {
        Write-Host "Usage: git-worktree-provision.ps1 <add|copy|check|readiness|provision> [arguments]"
        exit 2
    }

    $command = $args[0]
    $commandArguments = if ($args.Count -eq 1) { @() } else { @($args[1..($args.Count - 1)]) }
    $exitCode = switch ($command) {
        "add" { Invoke-AddCommand $commandArguments; break }
        "copy" { Invoke-CopyCommand $commandArguments; break }
        "check" { Invoke-CheckCommand $commandArguments; break }
        "readiness" { Invoke-ReadinessCommand $commandArguments; break }
        "provision" { Invoke-ProvisionCommand $commandArguments; break }
        default { throw "Unknown command: $(Format-DisplayText $command)" }
    }
    exit $exitCode
} catch {
    [Console]::Error.WriteLine("git-worktree-provision: $(Format-DisplayText $_.Exception.Message)")
    if ($env:GIT_WORKTREE_PROVISION_DEBUG) {
        [Console]::Error.WriteLine((Format-DisplayText $_.ScriptStackTrace))
    }
    exit 2
}
