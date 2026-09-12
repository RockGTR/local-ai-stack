[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentFile,

    [ValidateRange(1, 10000)]
    [Int32]$ExpectedMemorySpeedMTs = 3600,

    [ValidateRange(0, 1000)]
    [Int32]$MemorySpeedToleranceMTs = 50,

    [ValidateRange(1, [Int64]::MaxValue)]
    [Int64]$ExpectedTotalMemoryBytes = 34359738368,

    [ValidateRange(1, 128)]
    [Int32]$ExpectedMemoryModuleCount = 2,

    [DateTime]$WheaObservationStartUtc,

    [switch]$AllowWheaEvents,

    [switch]$SkipDockerEngine,

    [string]$ReportPath,

    [switch]$CreateReportDirectory,

    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

function Invoke-NativeCheck {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $captured = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($captured | ForEach-Object { [string]$_ })
    }
}

$configuration = Get-LocalAiConfiguration -Path $EnvironmentFile
$violations = [Collections.Generic.List[string]]::new()

$processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
$virtualizationFirmwareEnabled = (
    $processors.Count -gt 0 -and
    @($processors | Where-Object { $_.VirtualizationFirmwareEnabled -ne $true }).Count -eq 0
)
$vmMonitorExtensions = (
    $processors.Count -gt 0 -and
    @($processors | Where-Object { $_.VMMonitorModeExtensions -ne $true }).Count -eq 0
)
$computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
$hypervisorPresent = ($computerSystem.HypervisorPresent -eq $true)
$vmMonitorCapabilitySatisfied = ($vmMonitorExtensions -or $hypervisorPresent)
if (-not $virtualizationFirmwareEnabled) { $violations.Add('FIRMWARE_VIRTUALIZATION_DISABLED') }
if (-not $vmMonitorCapabilitySatisfied) { $violations.Add('VM_MONITOR_MODE_EXTENSIONS_UNAVAILABLE') }
if (-not $hypervisorPresent) { $violations.Add('WINDOWS_HYPERVISOR_NOT_PRESENT') }

$memoryModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
$configuredMemorySpeeds = @(
    $memoryModules |
        ForEach-Object { [Int32]$_.ConfiguredClockSpeed } |
        Where-Object { $_ -gt 0 }
)
$installedMemoryBytes = [Int64](
    $memoryModules |
        Measure-Object -Property Capacity -Sum |
        Select-Object -ExpandProperty Sum
)
$memoryModuleCountMatched = ($memoryModules.Count -eq $ExpectedMemoryModuleCount)
$memoryCapacityMatched = ($installedMemoryBytes -eq $ExpectedTotalMemoryBytes)
$memorySpeedMatched = (
    $configuredMemorySpeeds.Count -eq $memoryModules.Count -and
    $memoryModules.Count -gt 0 -and
    @(
        $configuredMemorySpeeds |
            Where-Object { [Math]::Abs($_ - $ExpectedMemorySpeedMTs) -gt $MemorySpeedToleranceMTs }
    ).Count -eq 0
)
if (-not $memorySpeedMatched) { $violations.Add('MEMORY_PROFILE_SPEED_MISMATCH') }
if (-not $memoryModuleCountMatched) { $violations.Add('MEMORY_MODULE_COUNT_MISMATCH') }
if (-not $memoryCapacityMatched) { $violations.Add('MEMORY_TOTAL_CAPACITY_MISMATCH') }

$featureResults = [ordered]@{}
$featureInspectionAvailable = ($null -ne (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue))
if ($featureInspectionAvailable) {
    foreach ($featureName in @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux')) {
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
            $featureResults[$featureName] = ($feature.State -eq 'Enabled')
        }
        catch {
            $featureInspectionAvailable = $false
            $featureResults[$featureName] = $false
        }
    }
}
if (-not $featureInspectionAvailable) {
    $violations.Add('WINDOWS_FEATURE_INSPECTION_UNAVAILABLE')
}
else {
    foreach ($featureName in $featureResults.Keys) {
        if (-not $featureResults[$featureName]) {
            $violations.Add("WINDOWS_FEATURE_DISABLED_$featureName")
        }
    }
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$wslInstalled = ($null -ne $wslCommand)
$wslVersionCheckPassed = $false
$wslStatusCheckPassed = $false
if ($wslInstalled) {
    $wslVersion = Invoke-NativeCheck -FilePath $wslCommand.Source -Arguments @('--version')
    $wslStatus = Invoke-NativeCheck -FilePath $wslCommand.Source -Arguments @('--status')
    $wslVersionCheckPassed = ($wslVersion.ExitCode -eq 0)
    $wslStatusCheckPassed = ($wslStatus.ExitCode -eq 0)
}
if (-not $wslInstalled) { $violations.Add('WSL_COMMAND_MISSING') }
if ($wslInstalled -and -not $wslVersionCheckPassed) { $violations.Add('WSL_VERSION_CHECK_FAILED') }
if ($wslInstalled -and -not $wslStatusCheckPassed) { $violations.Add('WSL_STATUS_CHECK_FAILED') }

$operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
$lastBootUtc = $operatingSystem.LastBootUpTime.ToUniversalTime()
$wheaStartUtc = if ($PSBoundParameters.ContainsKey('WheaObservationStartUtc')) {
    $WheaObservationStartUtc.ToUniversalTime()
}
else {
    $lastBootUtc
}
if ($wheaStartUtc -lt $lastBootUtc) {
    $wheaStartUtc = $lastBootUtc
}

$wheaErrors = @()
$wheaQueryErrors = @()
$wheaEvents = @(
    Get-WinEvent -FilterHashtable @{
        ProviderName = 'Microsoft-Windows-WHEA-Logger'
        StartTime = $wheaStartUtc
    } -ErrorAction SilentlyContinue -ErrorVariable +wheaQueryErrors
)
foreach ($queryError in $wheaQueryErrors) {
    if ([string]$queryError.FullyQualifiedErrorId -notmatch '^NoMatchingEventsFound') {
        $wheaErrors += $queryError
    }
}
$wheaInspectionAvailable = ($wheaErrors.Count -eq 0)
$wheaEventIds = @(
    $wheaEvents |
        ForEach-Object { [Int32]$_.Id } |
        Sort-Object -Unique
)
if (-not $wheaInspectionAvailable) { $violations.Add('WHEA_EVENT_INSPECTION_UNAVAILABLE') }
if ($wheaInspectionAvailable -and $wheaEvents.Count -gt 0 -and -not $AllowWheaEvents) {
    $violations.Add('WHEA_EVENTS_DETECTED_DURING_OBSERVATION')
}

$nvidiaCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
$nvidiaAvailable = ($null -ne $nvidiaCommand)
$nvidiaCheckPassed = $false
$gpuCount = 0
if ($nvidiaAvailable) {
    $nvidiaResult = Invoke-NativeCheck `
        -FilePath $nvidiaCommand.Source `
        -Arguments @('--query-gpu=driver_version,memory.total', '--format=csv,noheader,nounits')
    $nvidiaCheckPassed = ($nvidiaResult.ExitCode -eq 0 -and $nvidiaResult.Output.Count -gt 0)
    if ($nvidiaCheckPassed) { $gpuCount = $nvidiaResult.Output.Count }
}
if (-not $nvidiaAvailable) { $violations.Add('NVIDIA_SMI_MISSING') }
if ($nvidiaAvailable -and -not $nvidiaCheckPassed) { $violations.Add('NVIDIA_DRIVER_CHECK_FAILED') }

$dockerDataRootExists = Test-Path -LiteralPath $configuration.DockerDataRoot -PathType Container
if (-not $dockerDataRootExists) { $violations.Add('DOCKER_DATA_ROOT_MISSING') }

$dockerExecutable = $configuration.DockerCli
$dockerCliAvailable = Test-Path -LiteralPath $dockerExecutable -PathType Leaf
$dockerDesktopExecutableExists = Test-Path -LiteralPath $configuration.DockerDesktopExecutable -PathType Leaf
$dockerDesktopVersionPinned = -not [string]::IsNullOrWhiteSpace($configuration.DockerDesktopExpectedVersion)
$dockerDesktopVersion = ''
$dockerDesktopVersionMatched = $false
if ($dockerDesktopExecutableExists) {
    $desktopFile = Get-Item -LiteralPath $configuration.DockerDesktopExecutable -Force -ErrorAction Stop
    $dockerDesktopVersion = ([string]$desktopFile.VersionInfo.FileVersion).Trim()
    if ($dockerDesktopVersionPinned) {
        $dockerDesktopVersionMatched = $dockerDesktopVersion.Equals(
            $configuration.DockerDesktopExpectedVersion,
            [StringComparison]::OrdinalIgnoreCase
        )
    }
}
if (-not $dockerCliAvailable) { $violations.Add('MANAGED_DOCKER_CLI_MISSING') }
if (-not $dockerDesktopExecutableExists) { $violations.Add('MANAGED_DOCKER_DESKTOP_EXECUTABLE_MISSING') }
if (-not $dockerDesktopVersionPinned) { $violations.Add('DOCKER_DESKTOP_EXPECTED_VERSION_NOT_PINNED') }
if ($dockerDesktopExecutableExists -and $dockerDesktopVersionPinned -and -not $dockerDesktopVersionMatched) {
    $violations.Add('DOCKER_DESKTOP_VERSION_MISMATCH')
}

$installSettingsPresent = $false
$installSettingsReadable = $false
$wslDefaultDataRootMatched = $false
$programDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
$installSettingsPath = Join-Path $programDataRoot 'DockerDesktop\install-settings.json'
if (Test-Path -LiteralPath $installSettingsPath -PathType Leaf) {
    $installSettingsPresent = $true
    try {
        $installSettings = Get-Content -LiteralPath $installSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $installSettingsReadable = $true
        if ($installSettings.PSObject.Properties.Name -contains 'wslDefaultDataRoot' -and
            -not [string]::IsNullOrWhiteSpace([string]$installSettings.wslDefaultDataRoot)) {
            $configuredDockerDataRoot = [IO.Path]::GetFullPath($configuration.DockerDataRoot).TrimEnd([char[]]@('\', '/'))
            $installedDockerDataRoot = [IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables([string]$installSettings.wslDefaultDataRoot)
            ).TrimEnd([char[]]@('\', '/'))
            $wslDefaultDataRootMatched = $configuredDockerDataRoot.Equals(
                $installedDockerDataRoot,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    }
    catch {
        $installSettingsReadable = $false
    }
}
if (-not $installSettingsPresent) { $violations.Add('DOCKER_INSTALL_SETTINGS_MISSING') }
if ($installSettingsPresent -and -not $installSettingsReadable) { $violations.Add('DOCKER_INSTALL_SETTINGS_UNREADABLE') }
if ($installSettingsReadable -and -not $wslDefaultDataRootMatched) {
    $violations.Add('DOCKER_WSL_DATA_ROOT_MISMATCH')
}

$legacyDockerVhdInspectionAvailable = $true
$legacyDockerVhdCount = 0
$legacyDockerRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Docker'
if (Test-Path -LiteralPath $legacyDockerRoot -PathType Container) {
    try {
        $legacyDockerVhds = @(
            Get-ChildItem -LiteralPath $legacyDockerRoot -Recurse -File -Force -ErrorAction Stop |
                Where-Object { $_.Extension -in @('.vhd', '.vhdx') }
        )
        $legacyDockerVhdCount = $legacyDockerVhds.Count
    }
    catch {
        $legacyDockerVhdInspectionAvailable = $false
    }
}
if (-not $legacyDockerVhdInspectionAvailable) { $violations.Add('LEGACY_DOCKER_VHD_INSPECTION_UNAVAILABLE') }
if ($legacyDockerVhdInspectionAvailable -and $legacyDockerVhdCount -gt 0) {
    $violations.Add('LEGACY_DOCKER_VHD_PRESENT_UNDER_LOCALAPPDATA')
}

$dockerEngineReachable = $false
$dockerLinuxEngine = $false
$dockerServerVersion = ''
if ($dockerCliAvailable -and -not $SkipDockerEngine) {
    $previousDockerTimeout = [Environment]::GetEnvironmentVariable('DOCKER_CLIENT_TIMEOUT', [EnvironmentVariableTarget]::Process)
    try {
        [Environment]::SetEnvironmentVariable('DOCKER_CLIENT_TIMEOUT', '10', [EnvironmentVariableTarget]::Process)
        $dockerResult = Invoke-NativeCheck `
            -FilePath $dockerExecutable `
            -Arguments @('version', '--format', '{{.Server.Os}}|{{.Server.Version}}')
    }
    finally {
        [Environment]::SetEnvironmentVariable('DOCKER_CLIENT_TIMEOUT', $previousDockerTimeout, [EnvironmentVariableTarget]::Process)
    }
    $dockerServerLine = @($dockerResult.Output | Where-Object { $_ -match '^[^|]+\|[^|]+$' } | Select-Object -First 1)
    if ($dockerResult.ExitCode -eq 0 -and $dockerServerLine.Count -eq 1) {
        $dockerParts = $dockerServerLine[0].Trim() -split '\|', 2
        if ($dockerParts.Count -eq 2) {
            $dockerEngineReachable = $true
            $dockerLinuxEngine = $dockerParts[0].Equals('linux', [StringComparison]::OrdinalIgnoreCase)
            $dockerServerVersion = $dockerParts[1]
        }
    }
}
if (-not $SkipDockerEngine -and $dockerCliAvailable -and -not $dockerEngineReachable) {
    $violations.Add('DOCKER_ENGINE_UNREACHABLE')
}
if (-not $SkipDockerEngine -and $dockerEngineReachable -and -not $dockerLinuxEngine) {
    $violations.Add('DOCKER_ENGINE_NOT_LINUX')
}

$managedDockerVhdInspectionAvailable = $dockerDataRootExists
$managedDockerVhdCount = 0
if ($dockerDataRootExists) {
    try {
        $managedDockerVhds = @(
            Get-ChildItem -LiteralPath $configuration.DockerDataRoot -Recurse -File -Force -ErrorAction Stop |
                Where-Object { $_.Extension -eq '.vhdx' -and $_.Length -gt 0 }
        )
        $managedDockerVhdCount = $managedDockerVhds.Count
    }
    catch {
        $managedDockerVhdInspectionAvailable = $false
    }
}
if (-not $SkipDockerEngine -and -not $managedDockerVhdInspectionAvailable) {
    $violations.Add('MANAGED_DOCKER_VHD_INSPECTION_UNAVAILABLE')
}
if (-not $SkipDockerEngine -and $managedDockerVhdInspectionAvailable -and $managedDockerVhdCount -eq 0) {
    $violations.Add('MANAGED_DOCKER_VHD_MISSING_AFTER_ENGINE_START')
}

$storagePreflightPath = Join-Path $PSScriptRoot '..\storage\Test-StoragePreflight.ps1'
$storageReport = & $storagePreflightPath `
    -FastStorageRoot $configuration.FastStorageRoot `
    -RegularStorageRoot $configuration.RegularStorageRoot `
    -ReportOnly
if (-not $storageReport.Passed) {
    foreach ($storageViolation in $storageReport.Violations) {
        $violations.Add("STORAGE_$storageViolation")
    }
}

$rebootPending = (
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
)
if ($rebootPending) { $violations.Add('ANOTHER_WINDOWS_REBOOT_IS_PENDING') }

$report = [pscustomobject]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    State = if ($violations.Count -eq 0) { 'POST_REBOOT_VERIFIED' } else { 'POST_REBOOT_BLOCKED' }
    Passed = ($violations.Count -eq 0)
    NoRebootActionTaken = $true
    Firmware = [pscustomobject]@{
        VirtualizationEnabled = $virtualizationFirmwareEnabled
        VmMonitorExtensionsReported = $vmMonitorExtensions
        VmMonitorCapabilitySatisfied = $vmMonitorCapabilitySatisfied
        HypervisorPresent = $hypervisorPresent
    }
    Memory = [pscustomobject]@{
        ModuleCount = $memoryModules.Count
        ExpectedModuleCount = $ExpectedMemoryModuleCount
        ModuleCountMatched = $memoryModuleCountMatched
        InstalledCapacityBytes = $installedMemoryBytes
        ExpectedCapacityBytes = $ExpectedTotalMemoryBytes
        CapacityMatched = $memoryCapacityMatched
        ExpectedSpeedMTs = $ExpectedMemorySpeedMTs
        ToleranceMTs = $MemorySpeedToleranceMTs
        MinimumConfiguredSpeedMTs = if ($configuredMemorySpeeds.Count -gt 0) { ($configuredMemorySpeeds | Measure-Object -Minimum).Minimum } else { 0 }
        MaximumConfiguredSpeedMTs = if ($configuredMemorySpeeds.Count -gt 0) { ($configuredMemorySpeeds | Measure-Object -Maximum).Maximum } else { 0 }
        SpeedMatched = $memorySpeedMatched
    }
    WindowsFeatures = [pscustomobject]@{
        InspectionAvailable = $featureInspectionAvailable
        VirtualMachinePlatformEnabled = [bool]$featureResults['VirtualMachinePlatform']
        WslFeatureEnabled = [bool]$featureResults['Microsoft-Windows-Subsystem-Linux']
    }
    Wsl = [pscustomobject]@{
        CommandAvailable = $wslInstalled
        VersionCheckPassed = $wslVersionCheckPassed
        StatusCheckPassed = $wslStatusCheckPassed
    }
    Whea = [pscustomobject]@{
        InspectionAvailable = $wheaInspectionAvailable
        ObservationStartedAtUtc = $wheaStartUtc.ToString('o')
        EventCount = $wheaEvents.Count
        EventIds = $wheaEventIds
    }
    Nvidia = [pscustomobject]@{
        CommandAvailable = $nvidiaAvailable
        DriverCheckPassed = $nvidiaCheckPassed
        GpuCount = $gpuCount
    }
    Docker = [pscustomobject]@{
        DataRootExists = $dockerDataRootExists
        CliAvailable = $dockerCliAvailable
        DesktopExecutableExists = $dockerDesktopExecutableExists
        DesktopVersionPinned = $dockerDesktopVersionPinned
        DesktopVersion = $dockerDesktopVersion
        DesktopVersionMatched = $dockerDesktopVersionMatched
        InstallSettingsPresent = $installSettingsPresent
        InstallSettingsReadable = $installSettingsReadable
        WslDefaultDataRootMatched = $wslDefaultDataRootMatched
        ManagedVhdInspectionAvailable = $managedDockerVhdInspectionAvailable
        ManagedVhdCount = $managedDockerVhdCount
        LegacyVhdInspectionAvailable = $legacyDockerVhdInspectionAvailable
        LegacyVhdCount = $legacyDockerVhdCount
        EngineCheckSkipped = [bool]$SkipDockerEngine
        EngineReachable = $dockerEngineReachable
        LinuxEngine = $dockerLinuxEngine
        ServerVersion = $dockerServerVersion
    }
    Storage = [pscustomobject]@{
        Passed = [bool]$storageReport.Passed
        FastCapBytes = [Int64]$storageReport.Policy.FastCapBytes
        RegularCapBytes = [Int64]$storageReport.Policy.RegularCapBytes
        PhysicalDiskMappingVerified = [bool]$storageReport.PhysicalDiskSeparation.MappingVerified
        SeparatePhysicalDisks = [bool]$storageReport.PhysicalDiskSeparation.SeparatePhysicalDisks
    }
    AnotherRebootPending = $rebootPending
    Violations = @($violations | Sort-Object -Unique)
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
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding utf8
    }
}

Write-Output $report

if (-not $report.Passed -and -not $ReportOnly) {
    throw "Post-reboot verification failed: $($report.Violations -join ', ')."
}
