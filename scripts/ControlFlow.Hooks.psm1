Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ControlFlowContinuationSignature {
    param([Parameter(Mandatory)]$Gate)
    $contract = if ($Gate.Contains('contract_hash')) { $Gate.contract_hash } else { 'unavailable' }
    $source = if ($Gate.Contains('source_digest')) { $Gate.source_digest } else { 'unavailable' }
    $identity = [ordered]@{contract=$contract;source=$source;reasons=@($Gate.reasons | Sort-Object -Unique)}
    $bytes = [Text.Encoding]::UTF8.GetBytes(($identity | ConvertTo-Json -Compress -Depth 10))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-ControlFlowStopPolicy {
    param([AllowNull()]$State,[AllowNull()]$Gate)
    if ($null -eq $State) { return @{action='UNMANAGED';done=$false} }
    $lawful = @('CLARIFICATION','PERMISSION_DENIED','CANCELLED','PLAN_MODE','BLOCKED','INTERRUPTED')
    if ($State.status -in $lawful) {
        if ($null -eq $State.structured_reason -or [string]::IsNullOrWhiteSpace([string]$State.structured_reason.evidence)) {
            return @{action='UNVERIFIABLE';done=$false;reason='STOP_EVIDENCE_MISSING'}
        }
        return @{action='LAWFUL_STOP';done=$false;reason=$State.status}
    }
    if ($State.status -notin @('ACTIVE','COMPLETED') -or $null -eq $Gate -or $Gate.status -notin @('PASS','FAIL')) {
        return @{action='UNVERIFIABLE';done=$false;reason='GATE_UNVERIFIABLE'}
    }
    if ($Gate.status -eq 'PASS') { return @{action='COMPLETE';done=$true} }
    $signature=Get-ControlFlowContinuationSignature -Gate $Gate
    if($State.status -eq 'COMPLETED') {
        return @{action='BLOCKED';done=$false;signature=$signature;reason='COMPLETED_EVIDENCE_STALE'}
    }
    $same = $State.continuations.signature -eq $signature
    if ([int]$State.continuations.total -ge 5 -or ($same -and [int]$State.continuations.repeated -ge 2)) {
        return @{action='BLOCKED';done=$false;signature=$signature;reason='CONTINUATION_LIMIT'}
    }
    @{action='CONTINUE';done=$false;signature=$signature;reason=(@($Gate.reasons) -join ',')}
}

Export-ModuleMember -Function Get-ControlFlowContinuationSignature,Get-ControlFlowStopPolicy
