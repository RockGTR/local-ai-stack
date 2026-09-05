[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentFile,

    [string]$ComposeFile,

    [switch]$AllowSignupBootstrap,

    [switch]$ValidateWithDockerCompose,

    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $PSScriptRoot 'compose.open-webui.yaml'
}

$configuration = Get-LocalAiConfiguration -Path $EnvironmentFile -RequireOpenWebUiSecret
$violations = [Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw 'The Open WebUI Compose template does not exist.'
}
if (-not (Test-Path -LiteralPath $configuration.OpenWebUiData -PathType Container)) {
    $violations.Add('OPEN_WEBUI_DATA_DIRECTORY_MISSING')
}
if ($configuration.OpenWebUiEnableSignup -and -not $AllowSignupBootstrap) {
    $violations.Add('OPEN_WEBUI_SIGNUP_STILL_ENABLED')
}

$composeText = Get-Content -LiteralPath $ComposeFile -Raw -ErrorAction Stop
$expectedImage = 'ghcr.io/open-webui/open-webui:v0.11.3@sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175'
$expectedImageIsImmutable = Test-LocalAiImmutableImageReference -Reference $expectedImage
if (-not $expectedImageIsImmutable) {
    throw 'The expected Open WebUI reference is not immutable.'
}
$imagePinMatches = $composeText -match [regex]::Escape("image: $expectedImage")
if (-not $imagePinMatches) {
    $violations.Add('OPEN_WEBUI_IMAGE_PIN_MISMATCH')
}
if ($composeText -match '(?im)^\s*image:\s*[^\r\n]*:latest(?:\s|$)') {
    $violations.Add('MUTABLE_LATEST_IMAGE_REFERENCE')
}
if ($composeText -notmatch '(?m)^\s*host_ip:\s*127\.0\.0\.1\s*$') {
    $violations.Add('OPEN_WEBUI_LOOPBACK_PUBLISH_MISSING')
}
if ($composeText -match '(?m)^\s*host_ip:\s*(?:0\.0\.0\.0|::)\s*$') {
    $violations.Add('OPEN_WEBUI_BROAD_PUBLISH_DETECTED')
}
if ($composeText -notmatch '\$\{OPEN_WEBUI_DATA:\?') {
    $violations.Add('OPEN_WEBUI_MANAGED_DATA_BIND_MISSING')
}
if ($composeText -notmatch '\$\{OPEN_WEBUI_OLLAMA_BASE_URL:\?') {
    $violations.Add('OPEN_WEBUI_OLLAMA_BRIDGE_REQUIREMENT_MISSING')
}
if ($composeText -notmatch '\$\{OPEN_WEBUI_SECRET_KEY:\?') {
    $violations.Add('OPEN_WEBUI_SECRET_REQUIREMENT_MISSING')
}
if ($composeText -match '(?i)docker\.sock') {
    $violations.Add('DOCKER_SOCKET_MOUNT_DETECTED')
}

$dockerComposeValidated = $false
if ($ValidateWithDockerCompose) {
    $dockerExecutable = $configuration.DockerCli
    if (-not (Test-Path -LiteralPath $dockerExecutable -PathType Leaf)) {
        $violations.Add('MANAGED_DOCKER_CLI_MISSING')
    }
    else {
        $composeOutput = @(
            & $dockerExecutable compose `
                --env-file $EnvironmentFile `
                -f $ComposeFile `
                config --quiet 2>&1
        )
        $dockerComposeValidated = ($LASTEXITCODE -eq 0)
        if (-not $dockerComposeValidated) {
            $violations.Add('DOCKER_COMPOSE_CONFIG_INVALID')
        }
    }
}

$report = [pscustomobject]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    Passed = ($violations.Count -eq 0)
    ImmutableImage = ($expectedImageIsImmutable -and $imagePinMatches)
    LoopbackPublish = ($violations -notcontains 'OPEN_WEBUI_LOOPBACK_PUBLISH_MISSING' -and $violations -notcontains 'OPEN_WEBUI_BROAD_PUBLISH_DETECTED')
    ManagedDataDirectoryExists = (Test-Path -LiteralPath $configuration.OpenWebUiData -PathType Container)
    SignupEnabled = [bool]$configuration.OpenWebUiEnableSignup
    DockerComposeValidationRequested = [bool]$ValidateWithDockerCompose
    DockerComposeValidated = $dockerComposeValidated
    RuntimeBridgeVerified = $false
    RuntimeBridgeVerificationDeferred = $true
    DeploymentReady = $false
    NoContainerStarted = $true
    Violations = @($violations)
}

Write-Output $report

if (-not $report.Passed -and -not $ReportOnly) {
    throw "Open WebUI Compose verification failed: $($report.Violations -join ', ')."
}
