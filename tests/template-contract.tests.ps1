$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $repoRoot "plans/templates"

$markdownPath = Join-Path $templateRoot "plan.md"
$metadataPath = Join-Path $templateRoot "plan.meta.json"

if (-not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) {
    throw "Missing Markdown template: $markdownPath"
}
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Missing metadata template: $metadataPath"
}

$markdown = Get-Content -LiteralPath $markdownPath -Raw
if ($markdown -notmatch [regex]::Escape("# Plan:")) {
    throw "Template plan.md must start with a '# Plan:' heading"
}
if ($markdown -notmatch [regex]::Escape("plan.meta.json")) {
    throw "Template plan.md must point to the sidecar contract"
}
if ($markdown -notmatch [regex]::Escape("## Goal & Non-Goals")) {
    throw "Template plan.md must include a Goal & Non-Goals section"
}

try {
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
} catch {
    throw "Template plan.meta.json is not valid JSON: $($_.Exception.Message)"
}

foreach ($field in @("schema_version", "goal", "tier", "baseline", "scope", "criteria", "checks")) {
    if ($null -eq $metadata.PSObject.Properties[$field]) {
        throw "Template plan.meta.json is missing '$field'"
    }
}
if ($metadata.schema_version -cne "2.0.0") {
    throw "Template plan.meta.json schema_version must be '2.0.0' (got '$($metadata.schema_version)')"
}
if ($metadata.tier -cnotin @("TRIVIAL", "SMALL", "MEDIUM", "LARGE")) {
    throw "Template plan.meta.json tier must be a valid tier"
}
if ($null -eq $metadata.baseline.PSObject.Properties["commit"] -or $null -eq $metadata.baseline.PSObject.Properties["dirty_paths"]) {
    throw "Template plan.meta.json baseline must have commit and dirty_paths"
}

# Compact vNext ships exactly one template pair.
$shippedTemplates = @(Get-ChildItem -LiteralPath $templateRoot -File | ForEach-Object { $_.Name })
if ($shippedTemplates.Count -ne 2) {
    throw "Expected exactly one template pair (plan.md + plan.meta.json), found: $($shippedTemplates -join ', ')"
}

Write-Output "VALID template contract"
