[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('native','v3')][string]$Variant='native',
    [switch]$ValidateOnly,[switch]$Execute,
    [string]$OutDir,[string]$Model,[ValidateSet('none','minimal','low','medium','high','xhigh','max')][string]$Effort,[string]$HostLabel,
    [string]$CliPath,[string]$ExpectedCliVersion,[string]$SessionRoot,
    [int]$MaxWallSeconds,[int]$MaxTotalWallSeconds,[long]$MaxTokens,[long]$MaxTotalTokens,[int]$MaxToolCalls,[int]$MaxRuns,
    [int]$Trials=1,[int]$MaxResumes=2,
    [ValidateSet('on-request','never')][string]$ApprovalPolicy='never',
    [ValidateSet('user','auto_review')][string]$ApprovalReviewer='user',
    [ValidateSet('workspace-write','read-only')][string]$Sandbox='workspace-write',
    [ValidateSet('elevated','unelevated')][string]$WindowsSandbox,
    [string]$SettingsPath,[string[]]$CaseIds,[string]$PluginRoot,
    [switch]$DiscoverOnly
)
$ErrorActionPreference='Stop'
# Use the identical pinned native policy, explicit opt-in/budgets, isolation,
# process ownership and root/child telemetry adapter as implementation trials.
& (Join-Path $PSScriptRoot 'run-e2e.ps1') @PSBoundParameters -Suite Diagnostics
