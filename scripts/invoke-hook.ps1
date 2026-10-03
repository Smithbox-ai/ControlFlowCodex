param([Parameter(Mandatory)][ValidateSet('Stop','SessionStart','Interrupt')][string]$Event)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot/ControlFlow.Hooks.psm1" -Force

function Publish($Value) { $Value | ConvertTo-Json -Depth 20 -Compress | Write-Output }
try {
    # Identity is provided by the native callback, never inferred from a transcript or v2 plan.
    $payload=[Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable -Depth 40
    if (-not $payload.ContainsKey('session_id') -or [string]::IsNullOrWhiteSpace($payload.session_id) -or
        -not $payload.ContainsKey('cwd') -or [string]::IsNullOrWhiteSpace($payload.cwd)) {
        throw 'NATIVE_IDENTITY_MISSING'
    }
    $repoRoot=$payload.cwd
    if ($Event -eq 'Interrupt') {
        # A bounded notification remains durable while capture holds the evidence writer lock.
        $notification=Request-ControlFlowInterrupt -RepoRoot $repoRoot -SessionId $payload.session_id -TurnId $payload.turn_id
        if($null -eq $notification){Publish @{};exit 0}
        Publish @{systemMessage='ControlFlow INTERRUPTED. Explicit user resumption is required.'}
        exit 0
    }
    $active=Get-ControlFlowActiveRun -RepoRoot $repoRoot -SessionId $payload.session_id
    if ($null -eq $active) { Publish @{}; exit 0 }
    $repoRoot=$active.state.binding.worktree_realpath
    $runPath=$active.run_path
    $run=Read-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -SessionId $payload.session_id
    if ($Event -eq 'SessionStart') {
        $context="ControlFlow v3 task $($run.state.task_id), run $($run.state.run_id), state $($run.state.status). Reload $runPath/state.json and its contract before acting."
        if ($run.state.status -in @('INTERRUPTED','CANCELLED','PERMISSION_DENIED','CLARIFICATION','BLOCKED','PLAN_MODE')) {
            $context+=' The preceding turn stopped lawfully; this is not DONE. Resume only after an explicit user decision, recorded through update-run.'
        }
        Publish @{hookSpecificOutput=@{hookEventName='SessionStart';additionalContext=$context}}
        exit 0
    }
    if($payload.ContainsKey('permission_mode') -and $payload.permission_mode -eq 'plan') {
        $null=Update-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -ExpectedRevision $run.state.revision `
            -Event @{type='stop';reason='PLAN_MODE';evidence='Native Stop callback permission_mode=plan'}
        Publish @{systemMessage='ControlFlow PLAN_MODE: lawful turn end; task is incomplete.'}
        exit 0
    }
    $gate=Test-ControlFlowGate -RepoRoot $repoRoot -RunPath $runPath -Kind Completion
    $decision=Get-ControlFlowStopPolicy -State $run.state -Gate $gate
    switch($decision.action) {
        'COMPLETE' {
            $null=Update-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -ExpectedRevision $run.state.revision -Event @{type='complete'}
            Publish @{}
        }
        'LAWFUL_STOP' {
            Publish @{systemMessage="ControlFlow $($decision.reason): lawful turn end; task is incomplete."}
        }
        'CONTINUE' {
            $null=Update-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -ExpectedRevision $run.state.revision `
                -Event @{type='continuation';signature=$decision.signature}
            Publish @{decision='block';reason="ControlFlow completion gate failed: $($decision.reason). Repair only the recorded gaps, capture fresh checks and review, then run completion-gate. For missing user input or permission, record a structured lawful stop and end this turn without claiming DONE."}
        }
        'BLOCKED' {
            $blockedEvent=if($run.state.status -eq 'COMPLETED') {
                @{type='stop';reason='BLOCKED';evidence="Previously completed evidence stale: $(@($gate.reasons) -join ',')"}
            }else{@{type='continuation';signature=$decision.signature}}
            $null=Update-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -ExpectedRevision $run.state.revision -Event $blockedEvent
            $message=if($run.state.status -eq 'COMPLETED'){'ControlFlow BLOCKED: previously completed evidence is stale. Task is incomplete; explicit resumption is required.'}else{'ControlFlow BLOCKED: continuation budget exhausted. Task is incomplete; report remaining gaps.'}
            Publish @{continue=$false;stopReason="ControlFlow $($decision.reason)";systemMessage=$message}
        }
        default {
            $null=Update-ControlFlowRun -RepoRoot $repoRoot -RunPath $runPath -ExpectedRevision $run.state.revision `
                -Event @{type='stop';reason='BLOCKED';evidence="UNVERIFIABLE gate: $(@($gate.reasons) -join ',')"}
            Publish @{continue=$false;stopReason='ControlFlow UNVERIFIABLE';systemMessage='ControlFlow BLOCKED/UNVERIFIABLE. Task is incomplete; inspect gate errors before explicit resumption.'}
        }
    }
} catch {
    # A corrupt state cannot safely receive a counter update. End as a visible fault, never DONE.
    $message="ControlFlow BLOCKED/UNVERIFIABLE: $($_.Exception.Message)"
    if($Event -eq 'Interrupt') { Publish @{systemMessage=$message} }
    else { Publish @{continue=$false;stopReason='ControlFlow state unverifiable';systemMessage=$message} }
}
exit 0
