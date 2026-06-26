$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Read-Skill([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing skill file: $RelativePath"
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains([string]$Content, [string]$Needle, [string]$Label) {
    $normalizedContent = $Content -replace '\s+', ' '
    $normalizedNeedle = $Needle -replace '\s+', ' '
    if ($normalizedContent -notmatch [regex]::Escape($normalizedNeedle)) {
        throw "Missing '$Label': expected to find '$Needle'"
    }
}

$plan = Read-Skill "skills/controlflow-plan/SKILL.md"
$verify = Read-Skill "skills/controlflow-verify/SKILL.md"
$review = Read-Skill "skills/controlflow-review/SKILL.md"

Assert-Contains $plan "No Speculative Abstractions" "plan anti-abstraction rule"
Assert-Contains $plan "Context Language Rule" "plan documentation language rule"
Assert-Contains $plan "XML documentation" "plan XML documentation rule"
Assert-Contains $plan "business-logic comments" "plan business-logic comment rule"

Assert-Contains $verify "XML documentation and business-logic comments" "verify documentation gate"
Assert-Contains $verify "dominant local language" "verify language gate"
Assert-Contains $verify "new abstraction is justified" "verify abstraction gate"

Assert-Contains $review "Documentation and Comment Pass" "review documentation pass"
Assert-Contains $review "speculative abstraction" "review abstraction review wording"
Assert-Contains $review "user explicitly requested a different language" "review language override"

Write-Output "VALID skill behavior contract"
