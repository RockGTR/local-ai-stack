[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$AllowMissingManagedRoots,

    [switch]$RequireOpenWebUiSecret,

    [switch]$ValidateOnly,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

$configuration = Get-LocalAiConfiguration `
    -Path $Path `
    -AllowMissingManagedRoots:$AllowMissingManagedRoots `
    -RequireOpenWebUiSecret:$RequireOpenWebUiSecret

$environment = [ordered]@{}
foreach ($key in $configuration.Values.Keys) {
    $environment[[string]$key] = [string]$configuration.Values[$key]
}

# Canonical derived values prevent a private file from redirecting mutable data
# outside its validated managed root.
$environment.FAST_STORAGE_ROOT = $configuration.FastStorageRoot
$environment.REGULAR_STORAGE_ROOT = $configuration.RegularStorageRoot
$environment.DOCKER_DATA_ROOT = $configuration.DockerDataRoot
$environment.DOCKER_CLI = $configuration.DockerCli
$environment.DOCKER_DESKTOP_EXE = $configuration.DockerDesktopExecutable
$environment.DOCKER_DESKTOP_EXPECTED_VERSION = $configuration.DockerDesktopExpectedVersion
$environment.OLLAMA_EXE = $configuration.OllamaExecutable
$environment.OLLAMA_MODELS = $configuration.OllamaModels
$environment.OLLAMA_SCRATCH = $configuration.OllamaScratch
$environment.OLLAMA_LOG_ROOT = $configuration.OllamaLogRoot
$environment.OLLAMA_BIND = $configuration.OllamaBind
$environment.OLLAMA_KEEP_ALIVE = $configuration.OllamaKeepAlive
$environment.OLLAMA_FLASH_ATTENTION = $configuration.OllamaFlashAttention.ToString().ToLowerInvariant()
$environment.OLLAMA_KV_CACHE_TYPE = $configuration.OllamaKvCacheType
$environment.OPEN_WEBUI_BIND = $configuration.OpenWebUiBind
$environment.OPEN_WEBUI_DATA = $configuration.OpenWebUiData
$environment.OPEN_WEBUI_ENABLE_SIGNUP = $configuration.OpenWebUiEnableSignup.ToString().ToLowerInvariant()
$environment.TAILSCALE_FUNNEL_ENABLED = 'false'

$ollamaRuntimeEnvironment = New-LocalAiOllamaEnvironment `
    -FastStorageRoot $configuration.FastStorageRoot `
    -ModelPath $configuration.OllamaModels `
    -ScratchPath $configuration.OllamaScratch `
    -KeepAlive $configuration.OllamaKeepAlive `
    -FlashAttentionSupported:$configuration.OllamaFlashAttention `
    -KvCacheType $configuration.OllamaKvCacheType
foreach ($optionalKey in @('OLLAMA_FLASH_ATTENTION', 'OLLAMA_KV_CACHE_TYPE')) {
    if ($environment.Contains($optionalKey)) {
        $environment.Remove($optionalKey)
    }
}
foreach ($entry in $ollamaRuntimeEnvironment.GetEnumerator()) {
    if ($entry.Key -notin @('TEMP', 'TMP')) {
        $environment[[string]$entry.Key] = [string]$entry.Value
    }
}

$clearedKeys = [Collections.Generic.List[string]]::new()
if (-not $ValidateOnly -and $PSCmdlet.ShouldProcess('the current PowerShell process', 'Load validated local-AI environment')) {
    $knownManagedKeys = @(
        (Get-LocalAiEnvironmentAllowList)
        'OLLAMA_HOST'
        'OLLAMA_MAX_LOADED_MODELS'
        'OLLAMA_NUM_PARALLEL'
        'OLLAMA_NO_CLOUD'
        'OLLAMA_CONTEXT_LENGTH'
    ) | Sort-Object -Unique
    foreach ($knownKey in $knownManagedKeys) {
        if (-not $environment.Contains($knownKey)) {
            [Environment]::SetEnvironmentVariable($knownKey, $null, [EnvironmentVariableTarget]::Process)
            $clearedKeys.Add($knownKey)
        }
    }
    foreach ($entry in $environment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable(
            [string]$entry.Key,
            [string]$entry.Value,
            [EnvironmentVariableTarget]::Process
        )
    }
}

if ($PassThru) {
    [pscustomobject]@{
        ConfigurationValid = $true
        ValidateOnly = [bool]$ValidateOnly
        ManagedRootsExist = (
            (Test-Path -LiteralPath $configuration.FastStorageRoot -PathType Container) -and
            (Test-Path -LiteralPath $configuration.RegularStorageRoot -PathType Container)
        )
        LoadedKeyNames = @($environment.Keys | Sort-Object)
        ClearedKeyNames = @($clearedKeys | Sort-Object)
        GenericTempVariablesChanged = $false
        SecretValuesEmitted = $false
    }
}
