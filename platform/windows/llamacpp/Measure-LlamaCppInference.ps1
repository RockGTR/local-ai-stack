[CmdletBinding()]
param(
    [string]$Model = 'unsloth-Qwen-3.8',
    [ValidatePattern('^http://127\.0\.0\.1:[0-9]{1,5}/?$')]
    [string]$BaseUri = 'http://127.0.0.1:11500/',
    [Parameter(Mandatory)]
    [string]$Prompt,
    [int]$PredictTokens = 64,
    [double]$Temperature = 0.0,
    [int]$TimeoutSeconds = 600,
    [switch]$DisableThinking
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cleanUri = $BaseUri.TrimEnd('/')
$endpoint = "$cleanUri/v1/chat/completions"

$nvidiaSmi = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
function Get-GpuSample {
    if ($null -eq $nvidiaSmi) { return $null }
    $gpuFields = @(& $nvidiaSmi.Source `
        '--query-gpu=memory.used,memory.total,utilization.gpu,power.draw,temperature.gpu' `
        '--format=csv,noheader,nounits' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $gpuFields.Count -eq 0) { return $null }
    $gpu = [string]($gpuFields[0]) -split ',\s*'
    if ($gpu.Count -lt 5) { return $null }
    [pscustomobject]@{
        MemoryUsedMiB  = [Int32]$gpu[0]
        MemoryTotalMiB = [Int32]$gpu[1]
        UtilizationPct = [Int32]$gpu[2]
        PowerWatts     = [double]$gpu[3]
        TemperatureC   = [Int32]$gpu[4]
    }
}

$sampleBefore = Get-GpuSample

$requestBody = @{
    model       = $Model
    messages    = @(@{ role = 'user'; content = $Prompt })
    max_tokens  = $PredictTokens
    temperature = $Temperature
    stream      = $false
}
if ($DisableThinking) {
    $requestBody['chat_template_kwargs'] = @{ reasoning_effort = 'none' }
}

$jsonPayload = $requestBody | ConvertTo-Json -Depth 5

$sw = [Diagnostics.Stopwatch]::StartNew()
$response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $jsonPayload -ContentType 'application/json' -TimeoutSec $TimeoutSeconds
$sw.Stop()

$sampleAfter = Get-GpuSample

$timings = $response.timings
$draftTotal = if ($timings.PSObject.Properties['draft_n']) { [int]$timings.draft_n } else { 0 }
$draftAccepted = if ($timings.PSObject.Properties['draft_n_accepted']) { [int]$timings.draft_n_accepted } else { 0 }
$acceptanceRate = if ($draftTotal -gt 0) { [Math]::Round(($draftAccepted / $draftTotal) * 100.0, 2) } else { 0.0 }

[pscustomobject]@{
    SchemaVersion          = 1
    CheckedAtUtc           = [DateTime]::UtcNow.ToString('o')
    Model                  = $Model
    Endpoint               = $cleanUri
    WallClockSeconds       = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
    PromptTokens           = if ($timings.PSObject.Properties['prompt_n']) { [int]$timings.prompt_n } else { [int]$response.usage.prompt_tokens }
    PromptDurationMs       = if ($timings.PSObject.Properties['prompt_ms']) { [double]$timings.prompt_ms } else { $null }
    PromptTokensPerSecond  = if ($timings.PSObject.Properties['prompt_per_second']) { [Math]::Round([double]$timings.prompt_per_second, 1) } else { $null }
    PredictTokens          = if ($timings.PSObject.Properties['predicted_n']) { [int]$timings.predicted_n } else { [int]$response.usage.completion_tokens }
    PredictDurationMs      = if ($timings.PSObject.Properties['predicted_ms']) { [double]$timings.predicted_ms } else { $null }
    DecodeTokensPerSecond  = if ($timings.PSObject.Properties['predicted_per_second']) { [Math]::Round([double]$timings.predicted_per_second, 1) } else { $null }
    DraftTokensTotal       = $draftTotal
    DraftTokensAccepted    = $draftAccepted
    DraftAcceptanceRatePct = $acceptanceRate
    GpuMemoryUsedMiBBefore = if ($sampleBefore) { $sampleBefore.MemoryUsedMiB } else { $null }
    GpuMemoryUsedMiBAfter  = if ($sampleAfter) { $sampleAfter.MemoryUsedMiB } else { $null }
    GpuTemperatureCAfter   = if ($sampleAfter) { $sampleAfter.TemperatureC } else { $null }
    Completed              = $true
}
