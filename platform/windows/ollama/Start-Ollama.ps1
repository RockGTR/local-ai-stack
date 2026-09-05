[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentFile,

    [ValidateRange(1, 60)]
    [Int32]$StartupTimeoutSeconds = 30,

    [switch]$CreateMissingDirectories,

    [switch]$AllowUnpinnedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

$configuration = Get-LocalAiConfiguration -Path $EnvironmentFile
if (-not (Test-Path -LiteralPath $configuration.OllamaExecutable -PathType Leaf)) {
    throw 'The configured Ollama executable is missing from the managed regular-storage install path.'
}
if ([string]::IsNullOrWhiteSpace($configuration.OllamaExpectedVersion) -and -not $AllowUnpinnedVersion) {
    throw 'OLLAMA_EXPECTED_VERSION must be pinned in private configuration before starting Ollama.'
}

$storagePreflightPath = Join-Path $PSScriptRoot '..\storage\Test-StoragePreflight.ps1'
$storageReport = & $storagePreflightPath `
    -FastStorageRoot $configuration.FastStorageRoot `
    -RegularStorageRoot $configuration.RegularStorageRoot `
    -ReportOnly
if (-not $storageReport.Passed) {
    throw "Storage preflight failed: $($storageReport.Violations -join ', ')."
}

$requiredDirectories = @(
    $configuration.OllamaModels
    $configuration.OllamaScratch
    $configuration.OllamaLogRoot
)
foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        if (-not $CreateMissingDirectories) {
            throw 'A required Ollama directory is missing. Use -CreateMissingDirectories to create validated managed directories.'
        }
        if ($PSCmdlet.ShouldProcess('a validated managed Ollama directory', 'Create directory')) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
    }
}

$testScript = Join-Path $PSScriptRoot 'Test-OllamaRuntime.ps1'
$existing = & $testScript `
    -EnvironmentFile $EnvironmentFile `
    -TimeoutSeconds ([Math]::Min(5, $StartupTimeoutSeconds)) `
    -AllowUnpinnedVersion:$AllowUnpinnedVersion `
    -ReportOnly
if ($existing.Passed) {
    $existing | Add-Member -NotePropertyName StartedThisRun -NotePropertyValue $false -Force
    Write-Output $existing
    return
}
if ($existing.ListenerPresent -or $existing.ApiReachable) {
    throw "An existing service on the Ollama endpoint failed verification: $($existing.Violations -join ', ')."
}

if (-not $PSCmdlet.ShouldProcess('the managed Ollama runtime', 'Start loopback server and verify health')) {
    [pscustomobject]@{
        State = 'PLANNED'
        StartedThisRun = $false
        LoopbackOnly = $true
        Ready = $false
        ReadyReason = 'WhatIf prevented process start; no inference was performed.'
    }
    return
}

foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw 'A required managed directory was not created; refusing to start Ollama.'
    }
}

$runtimeEnvironment = New-LocalAiOllamaEnvironment `
    -FastStorageRoot $configuration.FastStorageRoot `
    -ModelPath $configuration.OllamaModels `
    -ScratchPath $configuration.OllamaScratch `
    -KeepAlive $configuration.OllamaKeepAlive `
    -FlashAttentionSupported:$configuration.OllamaFlashAttention `
    -KvCacheType $configuration.OllamaKvCacheType

$managedKeys = @(
    'OLLAMA_HOST'
    'OLLAMA_MODELS'
    'OLLAMA_MAX_LOADED_MODELS'
    'OLLAMA_NUM_PARALLEL'
    'OLLAMA_KEEP_ALIVE'
    'OLLAMA_NO_CLOUD'
    'OLLAMA_FLASH_ATTENTION'
    'OLLAMA_KV_CACHE_TYPE'
    'OLLAMA_CONTEXT_LENGTH'
    'TEMP'
    'TMP'
)
$previousEnvironment = [ordered]@{}
foreach ($key in $managedKeys) {
    $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, [EnvironmentVariableTarget]::Process)
}

# Windows PowerShell 5.1 cannot pass a per-child environment to Start-Process.
# The launcher therefore changes only its own process environment long enough
# for Ollama to inherit it, then restores every value in a finally block. User
# and machine TEMP/TMP are never changed.

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$standardOutputLog = Join-Path $configuration.OllamaLogRoot "ollama-$timestamp.stdout.log"
$standardErrorLog = Join-Path $configuration.OllamaLogRoot "ollama-$timestamp.stderr.log"
$process = $null
try {
    foreach ($key in $managedKeys) {
        $value = $null
        if ($runtimeEnvironment.Contains($key)) {
            $value = [string]$runtimeEnvironment[$key]
        }
        [Environment]::SetEnvironmentVariable($key, $value, [EnvironmentVariableTarget]::Process)
    }

    $process = Start-Process `
        -FilePath $configuration.OllamaExecutable `
        -ArgumentList 'serve' `
        -WorkingDirectory (Split-Path -Parent $configuration.OllamaExecutable) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $standardOutputLog `
        -RedirectStandardError $standardErrorLog `
        -PassThru
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable(
            [string]$entry.Key,
            $entry.Value,
            [EnvironmentVariableTarget]::Process
        )
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
$verification = $null
do {
    if ($process.HasExited) {
        break
    }
    Start-Sleep -Milliseconds 500
    $verification = & $testScript `
        -EnvironmentFile $EnvironmentFile `
        -TimeoutSeconds ([Math]::Min(5, $StartupTimeoutSeconds)) `
        -AllowUnpinnedVersion:$AllowUnpinnedVersion `
        -ReportOnly
    if ($verification.Passed) {
        $verification | Add-Member -NotePropertyName StartedThisRun -NotePropertyValue $true -Force
        Write-Output $verification
        return
    }
} while ([DateTime]::UtcNow -lt $deadline)

if ($null -ne $process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
}

$lastViolations = if ($null -eq $verification) { 'PROCESS_EXITED_BEFORE_VERIFICATION' } else { $verification.Violations -join ', ' }
throw "Ollama did not pass runtime verification and the newly started process was stopped. Violations: $lastViolations."
