# Run the repository's Bash-based test suites with Git for Windows.
# Do not resolve `bash` from PATH: Windows may expose a WSL or WindowsApps shim there.
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]] $TestScript = @(
        "scripts/tests/test-ai-configuration-profiles.sh",
        "scripts/tests/test-git-worktree-provision.sh",
        "scripts/tests/test-project-continuity-hook.sh",
        "scripts/tests/test-workflow-archive.sh"
    )
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

function ConvertTo-BashSingleQuoted([string] $Value) {
    return "'" + ($Value -replace "'", "'\\''") + "'"
}

function Test-GitBash([string] $Candidate) {
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        return $false
    }

    $uname = (& $Candidate -lc "uname -s" 2>$null | Out-String).Trim()
    return $LASTEXITCODE -eq 0 -and $uname -match "^(MINGW|MSYS|CYGWIN)"
}

$bashCandidates = @(
    (Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
)

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -ne $gitCommand -and $gitCommand.Source) {
    $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
    $bashCandidates += Join-Path $gitRoot "bin\bash.exe"
}

$gitBash = $bashCandidates |
    Where-Object { $_ -and (Test-GitBash $_) } |
    Select-Object -First 1

if (-not $gitBash) {
    throw "Windows Git Bash was not found. Install Git for Windows or run this from Git Bash directly. The PATH bash command is intentionally not used because it may resolve to WSL."
}

Write-Host "Using Windows Git Bash: $gitBash"

foreach ($relativeScript in $TestScript) {
    if ([IO.Path]::IsPathRooted($relativeScript)) {
        $scriptPath = [IO.Path]::GetFullPath($relativeScript)
    } else {
        $scriptPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $relativeScript))
    }

    $repositoryPrefix = $repositoryRoot.TrimEnd("\") + "\"
    if (-not $scriptPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Test script must be an existing .sh file under the repository: $relativeScript"
    }

    $relativeToRoot = $scriptPath.Substring($repositoryPrefix.Length)
    if ([IO.Path]::IsPathRooted($relativeToRoot) -or
        -not $relativeToRoot.EndsWith(".sh") -or
        -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Test script must be an existing .sh file under the repository: $relativeScript"
    }

    $bashRoot = ($repositoryRoot -replace "\\", "/")
    $bashScript = ($relativeToRoot -replace "\\", "/")
    $command = "cd $(ConvertTo-BashSingleQuoted $bashRoot) && bash $(ConvertTo-BashSingleQuoted $bashScript)"

    Write-Host "Running $relativeToRoot"
    & $gitBash -lc $command
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
