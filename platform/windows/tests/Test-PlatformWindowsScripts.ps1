[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$platformRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$modulePath = Join-Path $platformRoot 'lib\LocalAi.Windows.psm1'
$examplePath = Join-Path $platformRoot 'windows.public.env.example'
$composePath = Join-Path $platformRoot 'docker\compose.open-webui.yaml'
$composeValidatorPath = Join-Path $platformRoot 'docker\Test-OpenWebUiCompose.ps1'
$storagePath = Join-Path $platformRoot 'storage\Test-StoragePreflight.ps1'
$postRebootPath = Join-Path $platformRoot 'verification\Test-PostReboot.ps1'

$failures = [Collections.Generic.List[string]]::new()
[Int32]$script:checkCount = 0
function Assert-LocalAiTest {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Code
    )

    $script:checkCount++
    if (-not $Condition) {
        $failures.Add($Code)
    }
}

$powerShellFiles = @(
    Get-ChildItem -LiteralPath $platformRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }
)
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $failures.Add("POWERSHELL_PARSE_ERROR_$($file.Name)")
    }
}

Import-Module $modulePath -Force

$allowedKeys = Get-LocalAiEnvironmentAllowList
$example = Read-LocalAiEnvironmentFile -Path $examplePath -AllowedKeys $allowedKeys
Assert-LocalAiTest `
    -Condition (@($example.Keys | Where-Object { $allowedKeys -notcontains $_ }).Count -eq 0) `
    -Code 'ENVIRONMENT_EXAMPLE_KEY_NOT_ALLOWED'
Assert-LocalAiTest `
    -Condition ($example.OLLAMA_EXPECTED_VERSION -eq '0.33.3') `
    -Code 'OLLAMA_VERSION_PIN_MISMATCH'
Assert-LocalAiTest `
    -Condition ($example.TAILSCALE_FUNNEL_ENABLED -eq 'false') `
    -Code 'FUNNEL_NOT_DISABLED_IN_EXAMPLE'
Assert-LocalAiTest `
    -Condition ($example.DOCKER_DESKTOP_EXPECTED_VERSION -eq '4.89.0.238018') `
    -Code 'DOCKER_DESKTOP_VERSION_PIN_MISMATCH'
Assert-LocalAiTest `
    -Condition ($example.DOCKER_DATA_ROOT -match '\\Docker\\wsl$') `
    -Code 'DOCKER_WSL_DATA_ROOT_EXAMPLE_MISMATCH'

$expectedImage = 'ghcr.io/open-webui/open-webui:v0.11.3@sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175'
Assert-LocalAiTest `
    -Condition (Test-LocalAiImmutableImageReference -Reference $expectedImage) `
    -Code 'OPEN_WEBUI_PIN_NOT_IMMUTABLE'
Assert-LocalAiTest `
    -Condition (-not (Test-LocalAiImmutableImageReference -Reference 'ghcr.io/open-webui/open-webui:latest')) `
    -Code 'MUTABLE_IMAGE_REFERENCE_ACCEPTED'

$composeText = Get-Content -LiteralPath $composePath -Raw
Assert-LocalAiTest `
    -Condition ($composeText -match [regex]::Escape("image: $expectedImage")) `
    -Code 'COMPOSE_IMAGE_PIN_MISMATCH'
Assert-LocalAiTest `
    -Condition ($composeText -match '(?m)^\s*host_ip:\s*127\.0\.0\.1\s*$') `
    -Code 'COMPOSE_LOOPBACK_BIND_MISSING'
Assert-LocalAiTest `
    -Condition ($composeText -notmatch '(?m)^\s*host_ip:\s*(?:0\.0\.0\.0|::)\s*$') `
    -Code 'COMPOSE_BROAD_BIND_PRESENT'
Assert-LocalAiTest `
    -Condition ($composeText -notmatch '(?i)docker\.sock') `
    -Code 'COMPOSE_DOCKER_SOCKET_PRESENT'

$composeValidatorText = Get-Content -LiteralPath $composeValidatorPath -Raw
Assert-LocalAiTest `
    -Condition ($composeValidatorText -notmatch '(?s)param\s*\(.*?\$ComposeFile\s*=\s*\(Join-Path\s+\$PSScriptRoot') `
    -Code 'PS51_PSSCRIPTROOT_PARAMETER_DEFAULT_PRESENT'
Assert-LocalAiTest `
    -Condition ($composeValidatorText -match '\$ComposeFile\s*=\s*Join-Path\s+\$PSScriptRoot') `
    -Code 'COMPOSE_DEFAULT_NOT_RESOLVED_IN_BODY'
Assert-LocalAiTest `
    -Condition ($composeValidatorText -notmatch 'Get-Command\s+docker') `
    -Code 'COMPOSE_DOCKER_PATH_FALLBACK_PRESENT'

$storageText = Get-Content -LiteralPath $storagePath -Raw
Assert-LocalAiTest `
    -Condition ($storageText -match '\$fastCapBytes\s*=\s*200000000000') `
    -Code 'FAST_CAP_NOT_200_DECIMAL_GB'
Assert-LocalAiTest `
    -Condition ($storageText -match '\$regularCapBytes\s*=\s*500000000000') `
    -Code 'REGULAR_CAP_NOT_500_DECIMAL_GB'

$postRebootText = Get-Content -LiteralPath $postRebootPath -Raw
Assert-LocalAiTest `
    -Condition ($postRebootText -match '\$ExpectedTotalMemoryBytes\s*=\s*34359738368') `
    -Code 'EXPECTED_32_GIB_RAM_DEFAULT_MISSING'
Assert-LocalAiTest `
    -Condition ($postRebootText -match '\$ExpectedMemoryModuleCount\s*=\s*2') `
    -Code 'EXPECTED_TWO_MODULE_DEFAULT_MISSING'
Assert-LocalAiTest `
    -Condition ($postRebootText -notmatch 'Get-Command\s+docker') `
    -Code 'POST_REBOOT_DOCKER_PATH_FALLBACK_PRESENT'
Assert-LocalAiTest `
    -Condition ($postRebootText -notmatch '\$wheaEvents\.Id') `
    -Code 'POST_REBOOT_EMPTY_WHEA_RESULT_UNSAFE'
foreach ($requiredDockerCheck in @(
    'DOCKER_DESKTOP_VERSION_MISMATCH'
    'DOCKER_WSL_DATA_ROOT_MISMATCH'
    'MANAGED_DOCKER_VHD_MISSING_AFTER_ENGINE_START'
    'LEGACY_DOCKER_VHD_PRESENT_UNDER_LOCALAPPDATA'
)) {
    Assert-LocalAiTest `
        -Condition ($postRebootText.Contains($requiredDockerCheck)) `
        -Code "POST_REBOOT_CHECK_MISSING_$requiredDockerCheck"
}

$runtimeEnvironment = New-LocalAiOllamaEnvironment -FastStorageRoot $platformRoot
Assert-LocalAiTest `
    -Condition ($runtimeEnvironment.OLLAMA_HOST -eq '127.0.0.1:11434') `
    -Code 'OLLAMA_NOT_LOOPBACK_ONLY'
Assert-LocalAiTest `
    -Condition ($runtimeEnvironment.OLLAMA_MAX_LOADED_MODELS -eq '1') `
    -Code 'OLLAMA_MODEL_CONCURRENCY_NOT_CONSERVATIVE'
Assert-LocalAiTest `
    -Condition ($runtimeEnvironment.OLLAMA_NUM_PARALLEL -eq '1') `
    -Code 'OLLAMA_REQUEST_CONCURRENCY_NOT_CONSERVATIVE'
Assert-LocalAiTest `
    -Condition ($runtimeEnvironment.OLLAMA_NO_CLOUD -eq '1') `
    -Code 'OLLAMA_CLOUD_NOT_DISABLED'
Assert-LocalAiTest `
    -Condition (-not $runtimeEnvironment.Contains('OLLAMA_CONTEXT_LENGTH')) `
    -Code 'GLOBAL_CONTEXT_LENGTH_PRESENT'

$report = [pscustomobject]@{
    SchemaVersion = 1
    PowerShellFileCount = $powerShellFiles.Count
    CheckCount = $script:checkCount
    Passed = ($failures.Count -eq 0)
    Failures = @($failures)
    NoFilesCreated = $true
    NoServicesStarted = $true
}

Write-Output $report
if (-not $report.Passed) {
    throw "Windows platform self-test failed: $($report.Failures -join ', ')."
}
