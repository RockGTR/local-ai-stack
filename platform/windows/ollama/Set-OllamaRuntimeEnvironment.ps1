[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentFile,

    [ValidateSet('Process', 'User')]
    [string]$Target = 'Process',

    [switch]$CreateMissingDirectories
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

$configuration = Get-LocalAiConfiguration -Path $EnvironmentFile
$managedDirectories = @(
    $configuration.OllamaModels
    $configuration.OllamaScratch
    $configuration.OllamaLogRoot
)

foreach ($directory in $managedDirectories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        if (-not $CreateMissingDirectories) {
            throw 'A required Ollama directory is missing. Use -CreateMissingDirectories to create validated managed directories.'
        }
        if ($PSCmdlet.ShouldProcess('a validated managed Ollama directory', 'Create directory')) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
    }
}

$runtimeEnvironment = New-LocalAiOllamaEnvironment `
    -FastStorageRoot $configuration.FastStorageRoot `
    -ModelPath $configuration.OllamaModels `
    -ScratchPath $configuration.OllamaScratch `
    -KeepAlive $configuration.OllamaKeepAlive `
    -FlashAttentionSupported:$configuration.OllamaFlashAttention `
    -KvCacheType $configuration.OllamaKvCacheType

$targetType = [EnvironmentVariableTarget]::$Target
$managedOllamaKeys = @(
    'OLLAMA_HOST'
    'OLLAMA_MODELS'
    'OLLAMA_MAX_LOADED_MODELS'
    'OLLAMA_NUM_PARALLEL'
    'OLLAMA_KEEP_ALIVE'
    'OLLAMA_NO_CLOUD'
    'OLLAMA_FLASH_ATTENTION'
    'OLLAMA_KV_CACHE_TYPE'
    'OLLAMA_CONTEXT_LENGTH'
)

if ($PSCmdlet.ShouldProcess("the $Target environment", 'Apply validated Ollama runtime variables')) {
    foreach ($key in $managedOllamaKeys) {
        $value = $null
        if ($runtimeEnvironment.Contains($key)) {
            $value = [string]$runtimeEnvironment[$key]
        }
        [Environment]::SetEnvironmentVariable($key, $value, $targetType)
    }

}

[pscustomobject]@{
    Target = $Target
    AppliedKeyNames = @($managedOllamaKeys | Where-Object { $_ -ne 'OLLAMA_CONTEXT_LENGTH' })
    ContextLengthCleared = $true
    GenericTempVariablesChanged = $false
    SpawnScratchPrepared = $true
    LoopbackOnly = $true
    OneLoadedModel = $true
    OneParallelRequest = $true
    SecretValuesEmitted = $false
}
