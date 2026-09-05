[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$FastStorageRoot,

    [Parameter(Mandatory)]
    [string]$RegularStorageRoot,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$FastExpectedDownloadBytes = 0,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$FastExpectedInstallBytes = 0,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$FastExpectedTempBytes = 0,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$RegularExpectedDownloadBytes = 0,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$RegularExpectedInstallBytes = 0,

    [ValidateRange(0, [Int64]::MaxValue)]
    [Int64]$RegularExpectedTempBytes = 0,

    [string]$ReportPath,

    [switch]$CreateMissingRoots,

    [switch]$CreateReportDirectory,

    [switch]$IncludeResolvedPaths,

    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\lib\LocalAi.Windows.psm1') -Force

[Int64]$fastCapBytes = 200000000000
[Int64]$regularCapBytes = 500000000000
[Int64]$minimumOsReserveBytes = 50000000000

function Add-CheckedBytes {
    param([Int64[]]$Values)

    [decimal]$sum = 0
    foreach ($value in $Values) {
        $sum += [decimal]$value
    }
    if ($sum -gt [Int64]::MaxValue) {
        throw 'The requested byte total exceeds the supported integer range.'
    }
    return [Int64]$sum
}

$fast = Resolve-LocalAiManagedPath -Path $FastStorageRoot -AllowMissing
$regular = Resolve-LocalAiManagedPath -Path $RegularStorageRoot -AllowMissing

if ($fast.FullPath.Equals($regular.FullPath, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-LocalAiPathContained -ParentPath $fast.FullPath -CandidatePath $regular.FullPath -AllowEqual) -or
    (Test-LocalAiPathContained -ParentPath $regular.FullPath -CandidatePath $fast.FullPath -AllowEqual)) {
    throw 'Fast and regular managed roots must be distinct and must not contain one another.'
}

if ($CreateMissingRoots) {
    foreach ($root in @($fast, $regular)) {
        if (-not $root.Exists -and $PSCmdlet.ShouldProcess('a missing managed storage root', 'Create directory')) {
            [void](New-Item -ItemType Directory -Path $root.FullPath -Force)
        }
    }
    $fast = Resolve-LocalAiManagedPath -Path $fast.FullPath -AllowMissing
    $regular = Resolve-LocalAiManagedPath -Path $regular.FullPath -AllowMissing
}

$fastScan = Get-LocalAiDirectoryLogicalSize -Path $fast.FullPath
$regularScan = Get-LocalAiDirectoryLogicalSize -Path $regular.FullPath
$fastVolume = Get-LocalAiVolumeSnapshot -DriveRoot $fast.DriveRoot
$regularVolume = Get-LocalAiVolumeSnapshot -DriveRoot $regular.DriveRoot

$osDriveText = $env:SystemDrive
if ([string]::IsNullOrWhiteSpace($osDriveText)) {
    $osDriveText = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).SystemDrive
}
$osDriveRoot = [IO.Path]::GetPathRoot($osDriveText + [IO.Path]::DirectorySeparatorChar)

$fastExpected = Add-CheckedBytes @($FastExpectedDownloadBytes, $FastExpectedInstallBytes, $FastExpectedTempBytes)
$regularExpected = Add-CheckedBytes @($RegularExpectedDownloadBytes, $RegularExpectedInstallBytes, $RegularExpectedTempBytes)
$fastProjected = Add-CheckedBytes @($fastScan.LogicalBytes, $fastExpected)
$regularProjected = Add-CheckedBytes @($regularScan.LogicalBytes, $regularExpected)

$rootRows = @(
    [pscustomobject]@{
        Name                  = 'fast'
        FullPath              = $fast.FullPath
        DriveRoot             = $fast.DriveRoot
        Exists                = $fast.Exists
        Scan                  = $fastScan
        CapBytes              = $fastCapBytes
        ExpectedDownloadBytes = $FastExpectedDownloadBytes
        ExpectedInstallBytes  = $FastExpectedInstallBytes
        ExpectedTempBytes     = $FastExpectedTempBytes
        ExpectedTotalBytes    = $fastExpected
        ProjectedBytes        = $fastProjected
    },
    [pscustomobject]@{
        Name                  = 'regular'
        FullPath              = $regular.FullPath
        DriveRoot             = $regular.DriveRoot
        Exists                = $regular.Exists
        Scan                  = $regularScan
        CapBytes              = $regularCapBytes
        ExpectedDownloadBytes = $RegularExpectedDownloadBytes
        ExpectedInstallBytes  = $RegularExpectedInstallBytes
        ExpectedTempBytes     = $RegularExpectedTempBytes
        ExpectedTotalBytes    = $regularExpected
        ProjectedBytes        = $regularProjected
    }
)

$volumeRows = @()
foreach ($driveGroup in ($rootRows | Group-Object DriveRoot)) {
    $snapshot = if ($driveGroup.Name.Equals($fastVolume.DriveRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $fastVolume
    }
    else {
        $regularVolume
    }

    [Int64]$reserveBytes = 0
    $isOsVolume = $driveGroup.Name.Equals($osDriveRoot, [StringComparison]::OrdinalIgnoreCase)
    if ($isOsVolume) {
        $percentageReserve = [Int64][Math]::Ceiling(([decimal]$snapshot.TotalBytes) * [decimal]0.15)
        $reserveBytes = [Math]::Max($minimumOsReserveBytes, $percentageReserve)
    }

    $groupExpected = Add-CheckedBytes @($driveGroup.Group.ExpectedTotalBytes)
    [Int64]$safeFreeBefore = [Math]::Max([Int64]0, ($snapshot.AvailableFreeBytes - $reserveBytes))
    [Int64]$projectedFree = $snapshot.AvailableFreeBytes - $groupExpected
    $volumeRows += [pscustomobject]@{
        RootNames                    = @($driveGroup.Group.Name | Sort-Object)
        IsOperatingSystemVolume      = $isOsVolume
        TotalBytes                   = $snapshot.TotalBytes
        AvailableFreeBytesBefore     = $snapshot.AvailableFreeBytes
        RequiredReserveBytes         = $reserveBytes
        SafeAdditionalBytesBefore    = $safeFreeBefore
        ExpectedAdditionalBytes      = $groupExpected
        ProjectedFreeBytes           = $projectedFree
        PreservesRequiredReserve     = ($projectedFree -ge $reserveBytes)
    }
}

$rootResults = foreach ($row in $rootRows) {
    $capRemaining = [Math]::Max([Int64]0, ($row.CapBytes - $row.Scan.LogicalBytes))
    $volumeResult = $volumeRows | Where-Object { $_.RootNames -contains $row.Name } | Select-Object -First 1
    $resultProperties = [ordered]@{
        Name                       = $row.Name
        Exists                     = $row.Exists
        CapBytes                   = $row.CapBytes
        CurrentLogicalBytes        = $row.Scan.LogicalBytes
        CapRemainingBytesBefore    = $capRemaining
        ExpectedDownloadBytes      = $row.ExpectedDownloadBytes
        ExpectedInstallBytes       = $row.ExpectedInstallBytes
        ExpectedTempBytes          = $row.ExpectedTempBytes
        ExpectedAdditionalBytes    = $row.ExpectedTotalBytes
        ProjectedLogicalBytes      = $row.ProjectedBytes
        FileCount                  = $row.Scan.FileCount
        DirectoryCount             = $row.Scan.DirectoryCount
        SkippedReparsePointCount   = $row.Scan.SkippedReparseCount
        ScanErrorCount             = $row.Scan.ErrorCount
        ScanComplete               = $row.Scan.Complete
        ReparsePointFree           = ($row.Scan.SkippedReparseCount -eq 0)
        WithinCap                  = ($row.ProjectedBytes -le $row.CapBytes)
        VolumeReservePreserved     = [bool]$volumeResult.PreservesRequiredReserve
        MaximumPermittedAdditionalBytes = [Math]::Min($capRemaining, [Int64]$volumeResult.SafeAdditionalBytesBefore)
    }
    if ($IncludeResolvedPaths) {
        $resultProperties.ResolvedPath = $row.FullPath
    }
    [pscustomobject]$resultProperties
}

$fastDiskNumber = Get-LocalAiPhysicalDiskNumber -DriveRoot $fast.DriveRoot
$regularDiskNumber = Get-LocalAiPhysicalDiskNumber -DriveRoot $regular.DriveRoot
$diskMappingVerified = ($null -ne $fastDiskNumber -and $null -ne $regularDiskNumber)
$separatePhysicalDisks = ($diskMappingVerified -and $fastDiskNumber -ne $regularDiskNumber)

$violations = [Collections.Generic.List[string]]::new()
foreach ($rootResult in $rootResults) {
    if (-not $rootResult.Exists) { $violations.Add("$($rootResult.Name.ToUpperInvariant())_ROOT_MISSING") }
    if (-not $rootResult.ScanComplete) { $violations.Add("$($rootResult.Name.ToUpperInvariant())_SCAN_INCOMPLETE") }
    if (-not $rootResult.ReparsePointFree) { $violations.Add("$($rootResult.Name.ToUpperInvariant())_REPARSE_POINT_PRESENT") }
    if (-not $rootResult.WithinCap) { $violations.Add("$($rootResult.Name.ToUpperInvariant())_CAP_EXCEEDED") }
}
if ($volumeRows | Where-Object { -not $_.PreservesRequiredReserve }) {
    $violations.Add('FILESYSTEM_FREE_SPACE_OR_OS_RESERVE_VIOLATION')
}
if (-not $diskMappingVerified) {
    $violations.Add('PHYSICAL_DISK_MAPPING_UNAVAILABLE')
}
elseif (-not $separatePhysicalDisks) {
    $violations.Add('MANAGED_ROOTS_NOT_ON_SEPARATE_PHYSICAL_DISKS')
}

$report = [pscustomobject]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    Units = 'bytes; caps use decimal GB'
    Policy = [pscustomobject]@{
        FastCapBytes = $fastCapBytes
        RegularCapBytes = $regularCapBytes
        MinimumOperatingSystemReserveBytes = $minimumOsReserveBytes
        OperatingSystemReserveFraction = 0.15
        ReparsePointsFollowed = $false
        ReparsePointsBlockPass = $true
    }
    Roots = @($rootResults)
    Volumes = @($volumeRows)
    PhysicalDiskSeparation = [pscustomobject]@{
        MappingVerified = $diskMappingVerified
        SeparatePhysicalDisks = $separatePhysicalDisks
    }
    Passed = ($violations.Count -eq 0)
    Violations = @($violations)
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportFullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ReportPath))
    if (-not (Test-LocalAiPathContained -ParentPath $regular.FullPath -CandidatePath $reportFullPath)) {
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
        if ($PSCmdlet.ShouldProcess('the requested report directory', 'Create directory')) {
            [void](New-Item -ItemType Directory -Path $reportDirectory -Force)
        }
    }
    if ($PSCmdlet.ShouldProcess('the requested private report file', 'Write sanitized JSON report')) {
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding utf8
    }
}

Write-Output $report

if (-not $report.Passed -and -not $ReportOnly) {
    throw "Storage preflight failed: $($report.Violations -join ', ')."
}
