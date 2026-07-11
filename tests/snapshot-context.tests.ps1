$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$snapshotScript = Join-Path $repoRoot "scripts/snapshot-context.ps1"

if (-not (Test-Path -LiteralPath $snapshotScript -PathType Leaf)) {
    throw "Missing snapshot script: $snapshotScript"
}

function Invoke-Snapshot([string]$Root, [string]$PlanPath) {
    $global:LASTEXITCODE = 0
    $output = @(& $snapshotScript -RepoRoot $Root -PlanPath $PlanPath 2>&1)
    $exitCode = $global:LASTEXITCODE
    if ($output.Count -ne 1) {
        throw "snapshot-context must emit one JSON object for '$PlanPath', got $($output.Count) output records"
    }
    try {
        $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw "snapshot-context output is not valid JSON for '$PlanPath': $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Json = $json
    }
}

$positive = Invoke-Snapshot $repoRoot "plans/score-plan-plan.md"
if ($positive.ExitCode -ne 0) {
    throw "Expected snapshot to succeed for plans/score-plan-plan.md, got exit code $($positive.ExitCode)"
}

if ($positive.Json.schema_version -ne "1.0.0") {
    throw "Expected schema_version '1.0.0', got '$($positive.Json.schema_version)'"
}
if ($positive.Json.plan_path -ne "plans/score-plan-plan.md") {
    throw "Expected plan_path 'plans/score-plan-plan.md', got '$($positive.Json.plan_path)'"
}
if ($positive.Json.task_slug -ne "score-plan") {
    throw "Expected task_slug 'score-plan', got '$($positive.Json.task_slug)'"
}
if ([string]::IsNullOrWhiteSpace($positive.Json.captured_at)) {
    throw "captured_at must be a non-empty ISO 8601 string"
}

$git = $positive.Json.git
if ($git.available -ne $true) {
    throw "Expected git.available to be true in this repository"
}
if ([string]::IsNullOrWhiteSpace($git.branch)) {
    throw "git.branch must be a non-empty string when git is available"
}
if ($git.head_commit -notmatch '^[0-9a-f]{40}$') {
    throw "git.head_commit must be a 40-character hex SHA-1, got '$($git.head_commit)'"
}
if ($null -eq $git.dirty -or ($git.dirty -isnot [bool])) {
    throw "git.dirty must be a boolean"
}
if ($null -eq $git.tracked_files -or $git.tracked_files.Count -eq 0) {
    throw "git.tracked_files must be a non-empty array"
}
if ($git.tracked_files -notcontains "README.md") {
    throw "git.tracked_files must include README.md"
}
if ($git.tracked_file_count -ne $git.tracked_files.Count) {
    throw "git.tracked_file_count must equal tracked_files.Count"
}
if ($git.file_tree_digest -notmatch '^[0-9a-f]{64}$') {
    throw "git.file_tree_digest must be a 64-character hex SHA-256, got '$($git.file_tree_digest)'"
}

$sortedFiles = @($git.tracked_files | Sort-Object)
for ($i = 0; $i -lt $git.tracked_files.Count; $i++) {
    if ($git.tracked_files[$i] -ne $sortedFiles[$i]) {
        throw "git.tracked_files must be sorted; first mismatch at index $i"
    }
}

$invalidPlanPath = "plans/not-a-plan.txt"
$global:LASTEXITCODE = 0
$errorOutput = @(& $snapshotScript -RepoRoot $repoRoot -PlanPath $invalidPlanPath 2>&1)
$errorExitCode = $global:LASTEXITCODE
if ($errorExitCode -eq 0) {
    throw "snapshot-context must reject a plan path that does not end with '-plan.md'"
}
if ($errorOutput.Count -ne 1) {
    throw "snapshot-context must emit one error JSON object, got $($errorOutput.Count) output records"
}
$errorJson = ($errorOutput -join [Environment]::NewLine) | ConvertFrom-Json
if ($null -eq $errorJson.PSObject.Properties["error"] -or [string]::IsNullOrWhiteSpace($errorJson.error)) {
    throw "Error output must include a non-empty error message"
}
if ($errorJson.task_slug -ne $null) {
    throw "Error output task_slug must be null for an invalid plan path"
}
$global:LASTEXITCODE = 0

Write-Output "VALID context snapshot contract"
