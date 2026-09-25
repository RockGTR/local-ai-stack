[CmdletBinding()]
param(
    [string]$FastStorageRoot = '<FAST_STORAGE_ROOT>',
    [string]$RegularStorageRoot = '<REGULAR_STORAGE_ROOT>',
    [string]$ModelRelativePath = 'Models\llama.cpp\unsloth-Qwen-3.8\Qwen3.8-27B-UD-Q4_K_XL.gguf',
    [string]$ProjectorRelativePath = 'Models\llama.cpp\unsloth-Qwen-3.8\mmproj-BF16.gguf',
    [string]$ServerRelativePath = 'Apps\llama.cpp\b10903\llama-server.exe',
    [string]$ModelAlias = 'unsloth-Qwen-3.8',
    [int]$ContextLength = 100000,
    [int]$BatchSize = 2048,
    [int]$MicroBatchSize = 1024,
    [int]$CtxCheckpoints = 32,
    [int]$CacheRamMiB = 8192,
    [int]$Port = 11500,
    [int]$SpecDraftMax = 3,
    [switch]$DisableMtp,
    [switch]$SingleRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FastStorageRoot -match '<[^>]+>' -or $RegularStorageRoot -match '<[^>]+>') {
    throw 'Storage roots still contain unresolved public placeholders. Provide resolved paths or an environment file.'
}

$serverPath = Join-Path $RegularStorageRoot $ServerRelativePath
$modelPath = Join-Path $FastStorageRoot $ModelRelativePath
$projectorPath = Join-Path $FastStorageRoot $ProjectorRelativePath
$logDirectory = Join-Path $RegularStorageRoot 'Logs\llama.cpp\unsloth-100k'
$stdoutPath = Join-Path $logDirectory 'stdout.log'
$stderrPath = Join-Path $logDirectory 'stderr.log'
$supervisorLogPath = Join-Path $logDirectory 'supervisor.log'

if (-not (Test-Path -LiteralPath $serverPath)) {
    throw "llama-server executable not found at: $serverPath"
}
if (-not (Test-Path -LiteralPath $modelPath)) {
    throw "Model GGUF not found at: $modelPath"
}

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$serverArguments = @(
    '-m', $modelPath,
    '--mmproj', $projectorPath,
    '-lm', 'mmap',
    '-c', [string]$ContextLength,
    '-ngl', 'all',
    '-fa', 'on',
    '-ctk', 'q8_0',
    '-ctv', 'q8_0',
    '-b', [string]$BatchSize,
    '-ub', [string]$MicroBatchSize,
    '-np', '1',
    '--ctx-checkpoints', [string]$CtxCheckpoints,
    '--cache-ram', [string]$CacheRamMiB,
    '--cache-idle-slots',
    '--no-cont-batching',
    '--no-host',
    '--host', '127.0.0.1',
    '--port', [string]$Port,
    '--no-webui',
    '--jinja',
    '--reasoning', 'auto',
    '--no-reasoning-preserve',
    '--alias', $ModelAlias,
    '--sleep-idle-seconds', '-1',
    '--cors-origins', 'http://127.0.0.1:3000,http://localhost:3000'
)

if (-not $DisableMtp) {
    $serverArguments += @(
        '--spec-type', 'draft-mtp',
        '--spec-draft-n-max', [string]$SpecDraftMax,
        '--spec-draft-type-k', 'q8_0',
        '--spec-draft-type-v', 'q8_0'
    )
}

do {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        if ($SingleRun) {
            Write-Warning "Port $Port is already active."
            break
        }
        Start-Sleep -Seconds 10
        continue
    }

    try {
        $process = Start-Process `
            -FilePath $serverPath `
            -ArgumentList $serverArguments `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru

        $process.WaitForExit()
        $exitCode = 'UNKNOWN'
        try {
            $process.Refresh()
            $exitCode = [string]$process.ExitCode
        } catch {}

        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        if (Test-Path -LiteralPath $stderrPath) {
            if ($exitCode -ne '0') {
                Copy-Item -LiteralPath $stderrPath -Destination (Join-Path $logDirectory "crash-$timestamp.stderr.log") -Force
            }
        }
        $message = '{0:o} llama-server exited with code {1}; restarting in 10 seconds.' -f (Get-Date), $exitCode
        Add-Content -LiteralPath $supervisorLogPath -Value $message
    }
    catch {
        $message = '{0:o} failed to start llama-server: {1}' -f (Get-Date), $_.Exception.Message
        Add-Content -LiteralPath $supervisorLogPath -Value $message
    }

    if ($SingleRun) { break }
    Start-Sleep -Seconds 10
} while ($true)
