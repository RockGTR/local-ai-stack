[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentFile,

    [ValidateRange(1, 60)]
    [Int32]$TimeoutSeconds = 5,

    [switch]$AllowUnpinnedVersion,

    [string]$ReportPath,

    [switch]$CreateReportDirectory,

    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

$configuration = Get-LocalAiConfiguration -Path $EnvironmentFile
$listener = Get-LocalAiListenerSnapshot -Port 11434
$violations = [Collections.Generic.List[string]]::new()

if (-not $listener.InspectionAvailable) {
    $violations.Add('LISTENER_INSPECTION_UNAVAILABLE')
}
elseif (-not $listener.ListenerPresent) {
    $violations.Add('OLLAMA_LISTENER_MISSING')
}
elseif (-not $listener.LoopbackOnly) {
    $violations.Add('OLLAMA_NON_LOOPBACK_LISTENER_DETECTED')
}

$apiReachable = $false
$reportedVersion = ''
try {
    $versionResponse = Invoke-LocalAiLoopbackJsonRequest `
        -Uri ([Uri]'http://127.0.0.1:11434/api/version') `
        -TimeoutSeconds $TimeoutSeconds
    if ($versionResponse.PSObject.Properties.Name -contains 'version' -and
        -not [string]::IsNullOrWhiteSpace([string]$versionResponse.version)) {
        $reportedVersion = ([string]$versionResponse.version).Trim()
        $apiReachable = $true
    }
    else {
        $violations.Add('OLLAMA_VERSION_RESPONSE_INVALID')
    }
}
catch {
    $violations.Add('OLLAMA_API_UNREACHABLE')
}

$versionPinned = -not [string]::IsNullOrWhiteSpace($configuration.OllamaExpectedVersion)
$versionMatches = $false
if ($versionPinned -and $apiReachable) {
    $expectedNormalized = $configuration.OllamaExpectedVersion.TrimStart('v')
    $reportedNormalized = $reportedVersion.TrimStart('v')
    $versionMatches = $expectedNormalized.Equals($reportedNormalized, [StringComparison]::OrdinalIgnoreCase)
    if (-not $versionMatches) {
        $violations.Add('OLLAMA_VERSION_MISMATCH')
    }
}
elseif (-not $versionPinned -and -not $AllowUnpinnedVersion) {
    $violations.Add('OLLAMA_EXPECTED_VERSION_NOT_PINNED')
}

$processInspectionAvailable = $false
$expectedExecutableMatched = $false
if ($listener.InspectionAvailable -and $listener.ListenerPresent -and $listener.OwningProcessIds.Count -eq 1) {
    try {
        $processId = [UInt32]$listener.OwningProcessIds[0]
        $processRecord = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop
        $processInspectionAvailable = ($null -ne $processRecord -and -not [string]::IsNullOrWhiteSpace([string]$processRecord.ExecutablePath))
        if ($processInspectionAvailable) {
            $actualExecutable = [IO.Path]::GetFullPath([string]$processRecord.ExecutablePath)
            $expectedExecutable = [IO.Path]::GetFullPath($configuration.OllamaExecutable)
            $expectedExecutableMatched = $actualExecutable.Equals($expectedExecutable, [StringComparison]::OrdinalIgnoreCase)
        }
    }
    catch {
        $processInspectionAvailable = $false
    }
}

if (-not $processInspectionAvailable) {
    $violations.Add('OLLAMA_PROCESS_INSPECTION_UNAVAILABLE')
}
elseif (-not $expectedExecutableMatched) {
    $violations.Add('OLLAMA_EXECUTABLE_OUTSIDE_MANAGED_INSTALL')
}

$report = [pscustomobject]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    State = if ($violations.Count -eq 0) { 'HEALTHY' } else { 'ERROR' }
    Passed = ($violations.Count -eq 0)
    Ready = $false
    ReadyReason = 'No inference test was performed by this runtime-only check.'
    ApiReachable = $apiReachable
    ListenerInspectionAvailable = [bool]$listener.InspectionAvailable
    ListenerPresent = [bool]$listener.ListenerPresent
    LoopbackOnly = [bool]$listener.LoopbackOnly
    ProcessInspectionAvailable = $processInspectionAvailable
    ExpectedExecutableMatched = $expectedExecutableMatched
    VersionPinned = $versionPinned
    VersionMatched = $versionMatches
    ReportedVersion = $reportedVersion
    Violations = @($violations)
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportFullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ReportPath))
    if (-not (Test-LocalAiPathContained -ParentPath $configuration.RegularStorageRoot -CandidatePath $reportFullPath)) {
        throw 'The private report must be written below the regular-storage root.'
    }
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    if (Test-LocalAiPathContained -ParentPath $repositoryRoot -CandidatePath $reportFullPath) {
        throw 'Private reports must be written outside the public repository.'
    }
    $reportDirectory = Split-Path -Parent $reportFullPath
    if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
        if (-not $CreateReportDirectory) {
            throw 'The report directory does not exist. Use -CreateReportDirectory to create it explicitly.'
        }
        if ($PSCmdlet.ShouldProcess('the requested private report directory', 'Create directory')) {
            [void](New-Item -ItemType Directory -Path $reportDirectory -Force)
        }
    }
    if ($PSCmdlet.ShouldProcess('the requested private report file', 'Write sanitized JSON report')) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFullPath -Encoding utf8
    }
}

Write-Output $report

if (-not $report.Passed -and -not $ReportOnly) {
    throw "Ollama runtime verification failed: $($report.Violations -join ', ')."
}
