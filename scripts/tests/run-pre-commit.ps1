# Run the repository pre-commit hook through Git for Windows Bash.
# Do not resolve `bash` from PATH: Windows may expose a WSL or WindowsApps shim there.
[CmdletBinding()]
param()

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

$hookPath = Join-Path $repositoryRoot "scripts\git-hooks\pre-commit"
if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
    throw "The repository pre-commit hook was not found: $hookPath"
}

$bashRoot = ($repositoryRoot -replace "\\", "/")
$command = "cd $(ConvertTo-BashSingleQuoted $bashRoot) && bash scripts/git-hooks/pre-commit"
$gitUsrBin = Join-Path (Split-Path (Split-Path $gitBash -Parent) -Parent) "usr\bin"
$previousPath = $env:Path

Write-Host "Using Windows Git Bash: $gitBash"
Write-Host "Running scripts/git-hooks/pre-commit from $repositoryRoot"

try {
    $env:Path = "$gitUsrBin;$previousPath"
    & $gitBash -lc $command
    $exitCode = $LASTEXITCODE
} finally {
    $env:Path = $previousPath
}

exit $exitCode
