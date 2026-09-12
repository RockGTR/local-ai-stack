Set-StrictMode -Version Latest

function Resolve-LocalAiManagedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A managed path cannot be empty.'
    }

    if ($Path -match '<[^>]+>') {
        throw 'A managed path still contains an unresolved public placeholder.'
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($expandedPath -notmatch '^[A-Za-z]:[\\/]') {
        throw 'Managed paths must be drive-qualified absolute paths on a local filesystem volume.'
    }

    $fullPath = [IO.Path]::GetFullPath($expandedPath)
    $driveRoot = [IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($driveRoot)) {
        throw 'Unable to determine the filesystem volume for a managed path.'
    }

    $trimCharacters = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $normalizedPath = $fullPath.TrimEnd($trimCharacters)
    $normalizedRoot = $driveRoot.TrimEnd($trimCharacters)
    if ($normalizedPath.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A managed root must be a directory below the filesystem volume root.'
    }

    $exists = Test-Path -LiteralPath $normalizedPath -PathType Container
    if (-not $exists -and -not $AllowMissing) {
        throw 'A required managed directory does not exist.'
    }

    [pscustomobject]@{
        FullPath  = $normalizedPath
        DriveRoot = $driveRoot
        Exists    = $exists
    }
}

function Test-LocalAiPathContained {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentPath,

        [Parameter(Mandatory)]
        [string]$CandidatePath,

        [switch]$AllowEqual
    )

    $parent = (Resolve-LocalAiManagedPath -Path $ParentPath -AllowMissing).FullPath
    if ([string]::IsNullOrWhiteSpace($CandidatePath) -or $CandidatePath -match '<[^>]+>') {
        return $false
    }

    $expandedCandidate = [Environment]::ExpandEnvironmentVariables($CandidatePath.Trim())
    if ($expandedCandidate -notmatch '^[A-Za-z]:[\\/]') {
        return $false
    }

    $candidate = [IO.Path]::GetFullPath($expandedCandidate)
    $separator = [IO.Path]::DirectorySeparatorChar

    if ($candidate.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
        return [bool]$AllowEqual
    }

    return $candidate.StartsWith($parent + $separator, [StringComparison]::OrdinalIgnoreCase)
}

function Get-LocalAiDirectoryLogicalSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            LogicalBytes       = [Int64]0
            FileCount          = [Int64]0
            DirectoryCount     = [Int64]0
            InternalSymlinkCount = [Int64]0
            SkippedReparseCount = [Int64]0
            ErrorCount         = [Int64]0
            Complete           = $false
        }
    }

    try {
        $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject]@{
                LogicalBytes        = [Int64]0
                FileCount           = [Int64]0
                DirectoryCount      = [Int64]0
                InternalSymlinkCount = [Int64]0
                SkippedReparseCount = [Int64]1
                ErrorCount          = [Int64]0
                Complete            = $true
            }
        }
    }
    catch {
        return [pscustomobject]@{
            LogicalBytes        = [Int64]0
            FileCount           = [Int64]0
            DirectoryCount      = [Int64]0
            InternalSymlinkCount = [Int64]0
            SkippedReparseCount = [Int64]0
            ErrorCount          = [Int64]1
            Complete            = $false
        }
    }

    $directories = [Collections.Generic.Queue[string]]::new()
    $directories.Enqueue($Path)
    [Int64]$logicalBytes = 0
    [Int64]$fileCount = 0
    [Int64]$directoryCount = 0
    [Int64]$internalSymlinkCount = 0
    [Int64]$skippedReparseCount = 0
    [Int64]$errorCount = 0
    $rootFullPath = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ))

    while ($directories.Count -gt 0) {
        $currentDirectory = $directories.Dequeue()
        $directoryCount++

        try {
            $children = @(Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop)
        }
        catch {
            $errorCount++
            continue
        }

        foreach ($child in $children) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                # Hugging Face caches use relative file symlinks to deduplicate
                # snapshot files. Accept only links whose final target is an
                # ordinary file below this same root and whose target ancestry
                # contains no other reparse point. The target is counted when
                # its normal directory is scanned, so counting the link again
                # would double-count the same stored bytes.
                $linkTypeProperty = $child.PSObject.Properties['LinkType']
                $targetProperty = $child.PSObject.Properties['Target']
                $linkTargets = @(if ($null -ne $targetProperty) { $targetProperty.Value })
                $safeInternalFileSymlink = (
                    -not $child.PSIsContainer -and
                    $null -ne $linkTypeProperty -and
                    [string]$linkTypeProperty.Value -eq 'SymbolicLink' -and
                    $linkTargets.Count -eq 1 -and
                    -not [string]::IsNullOrWhiteSpace([string]$linkTargets[0]) -and
                    -not [IO.Path]::IsPathRooted([string]$linkTargets[0])
                )

                if ($safeInternalFileSymlink) {
                    try {
                        $targetFullPath = [IO.Path]::GetFullPath((
                            Join-Path $child.DirectoryName ([string]$linkTargets[0])
                        ))
                        if (-not (Test-LocalAiPathContained `
                            -ParentPath $rootFullPath `
                            -CandidatePath $targetFullPath)) {
                            $safeInternalFileSymlink = $false
                        }
                        else {
                            $targetItem = Get-Item -LiteralPath $targetFullPath -Force -ErrorAction Stop
                            if ($targetItem.PSIsContainer -or
                                ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                                $safeInternalFileSymlink = $false
                            }
                            else {
                                $ancestor = $targetItem.Directory
                                while ($null -ne $ancestor -and
                                    -not $ancestor.FullName.Equals($rootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
                                    if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                                        $safeInternalFileSymlink = $false
                                        break
                                    }
                                    $ancestor = $ancestor.Parent
                                }
                                if ($null -eq $ancestor) {
                                    $safeInternalFileSymlink = $false
                                }
                            }
                        }
                    }
                    catch {
                        $safeInternalFileSymlink = $false
                    }
                }

                if ($safeInternalFileSymlink) {
                    $internalSymlinkCount++
                    continue
                }

                $skippedReparseCount++
                continue
            }

            if ($child.PSIsContainer) {
                $directories.Enqueue($child.FullName)
                continue
            }

            try {
                $length = [Int64]$child.Length
                if ($length -gt ([Int64]::MaxValue - $logicalBytes)) {
                    throw 'Directory logical size exceeds the supported integer range.'
                }
                $logicalBytes += $length
                $fileCount++
            }
            catch {
                $errorCount++
            }
        }
    }

    [pscustomobject]@{
        LogicalBytes        = $logicalBytes
        FileCount           = $fileCount
        DirectoryCount      = $directoryCount
        InternalSymlinkCount = $internalSymlinkCount
        SkippedReparseCount = $skippedReparseCount
        ErrorCount          = $errorCount
        Complete            = ($errorCount -eq 0)
    }
}

function Get-LocalAiVolumeSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DriveRoot
    )

    $drive = [IO.DriveInfo]::new($DriveRoot)
    if (-not $drive.IsReady) {
        throw 'The filesystem volume that contains a managed root is not ready.'
    }

    [pscustomobject]@{
        DriveRoot          = $drive.RootDirectory.FullName
        TotalBytes         = [Int64]$drive.TotalSize
        AvailableFreeBytes = [Int64]$drive.AvailableFreeSpace
        Format             = $drive.DriveFormat
    }
}

function Get-LocalAiPhysicalDiskNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DriveRoot
    )

    $driveLetter = $DriveRoot.Substring(0, 1)
    try {
        $partitions = @(Get-Partition -DriveLetter $driveLetter -ErrorAction Stop)
        if ($partitions.Count -ne 1) {
            return $null
        }
        return [Int32]$partitions[0].DiskNumber
    }
    catch {
        return $null
    }
}

function Read-LocalAiEnvironmentFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$AllowedKeys = @(),

        [switch]$AllowAdditionalKeys,

        [switch]$RejectUnresolvedPlaceholders
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'The private environment file does not exist.'
    }

    $result = [ordered]@{}
    $seenKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $allowedKeySet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($allowedKey in $AllowedKeys) {
        [void]$allowedKeySet.Add($allowedKey)
    }
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            throw "Invalid environment entry at line $lineNumber."
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment key at line $lineNumber."
        }
        if (-not $seenKeys.Add($key)) {
            throw "Duplicate environment key at line $lineNumber."
        }
        if ($key.Equals('OLLAMA_CONTEXT_LENGTH', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'OLLAMA_CONTEXT_LENGTH is intentionally prohibited; context is selected per model or request.'
        }
        if (-not $AllowAdditionalKeys -and $AllowedKeys.Count -gt 0 -and -not $allowedKeySet.Contains($key)) {
            throw "Environment key '$key' is not on the public allowlist."
        }

        $value = $line.Substring($separatorIndex + 1).Trim()
        if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
            $value = $value.Substring(1, $value.Length - 2)
        }
        elseif ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
            $inner = $value.Substring(1, $value.Length - 2)
            $builder = [Text.StringBuilder]::new()
            for ($index = 0; $index -lt $inner.Length; $index++) {
                if ($inner[$index] -ne [char]92 -or $index + 1 -ge $inner.Length) {
                    [void]$builder.Append($inner[$index])
                    continue
                }

                $next = $inner[$index + 1]
                switch ($next) {
                    '"' { [void]$builder.Append('"'); $index++; continue }
                    ([char]92) { [void]$builder.Append([char]92); $index++; continue }
                    default {
                        # Preserve ordinary Windows path separators such as \t verbatim.
                        [void]$builder.Append([char]92)
                    }
                }
            }
            $value = $builder.ToString()
        }
        elseif (($value.StartsWith('"') -and -not $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and -not $value.EndsWith("'"))) {
            throw "Unterminated quoted value at line $lineNumber."
        }

        if ($RejectUnresolvedPlaceholders -and $value -match '<[^>]+>') {
            throw "Environment value for '$key' still contains a public placeholder."
        }

        $result[$key] = $value
    }

    return $result
}

function Get-LocalAiEnvironmentAllowList {
    [CmdletBinding()]
    param()

    return @(
        'FAST_STORAGE_ROOT'
        'REGULAR_STORAGE_ROOT'
        'DOCKER_DATA_ROOT'
        'DOCKER_CLI'
        'DOCKER_DESKTOP_EXE'
        'DOCKER_DESKTOP_EXPECTED_VERSION'
        'OLLAMA_EXE'
        'OLLAMA_MODELS'
        'OLLAMA_SCRATCH'
        'OLLAMA_LOG_ROOT'
        'OLLAMA_BIND'
        'OLLAMA_KEEP_ALIVE'
        'OLLAMA_FLASH_ATTENTION'
        'OLLAMA_KV_CACHE_TYPE'
        'OLLAMA_EXPECTED_VERSION'
        'OPEN_WEBUI_BIND'
        'OPEN_WEBUI_DATA'
        'OPEN_WEBUI_OLLAMA_BASE_URL'
        'OPEN_WEBUI_SECRET_KEY'
        'OPEN_WEBUI_ENABLE_SIGNUP'
        'WINDOWS_TAILSCALE_HOST'
        'WINDOWS_CHAT_URL'
        'WINDOWS_OLLAMA_ORIGIN'
        'WINDOWS_OPENAI_BASE_URL'
        'WINDOWS_DASHBOARD_URL'
        'TAILSCALE_FUNNEL_ENABLED'
    )
}

function ConvertFrom-LocalAiBoolean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($Value.Equals('true', [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($Value.Equals('false', [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    throw "Environment value '$Name' must be true or false."
}

function Test-LocalAiLoopbackEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateRange(1, 65535)]
        [Nullable[Int32]]$ExpectedPort
    )

    $match = [regex]::Match($Endpoint.Trim(), '^127\.0\.0\.1:([1-9][0-9]{0,4})$')
    if (-not $match.Success) {
        return $false
    }

    [Int32]$port = $match.Groups[1].Value
    if ($port -gt 65535) {
        return $false
    }

    if ($PSBoundParameters.ContainsKey('ExpectedPort') -and $port -ne [Int32]$ExpectedPort) {
        return $false
    }

    return $true
}

function Get-LocalAiConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$AllowMissingManagedRoots,

        [switch]$RequireOpenWebUiSecret
    )

    $environmentFilePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    if (Test-LocalAiPathContained -ParentPath $repositoryRoot -CandidatePath $environmentFilePath) {
        throw 'Populated environment files must remain outside the public repository.'
    }

    $values = Read-LocalAiEnvironmentFile `
        -Path $environmentFilePath `
        -AllowedKeys (Get-LocalAiEnvironmentAllowList) `
        -RejectUnresolvedPlaceholders

    foreach ($requiredKey in @('FAST_STORAGE_ROOT', 'REGULAR_STORAGE_ROOT')) {
        if (-not $values.Contains($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$values[$requiredKey])) {
            throw "Required environment key '$requiredKey' is missing or empty."
        }
    }

    $fast = Resolve-LocalAiManagedPath -Path $values.FAST_STORAGE_ROOT -AllowMissing:$AllowMissingManagedRoots
    $regular = Resolve-LocalAiManagedPath -Path $values.REGULAR_STORAGE_ROOT -AllowMissing:$AllowMissingManagedRoots
    if ($fast.FullPath.Equals($regular.FullPath, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-LocalAiPathContained -ParentPath $fast.FullPath -CandidatePath $regular.FullPath -AllowEqual) -or
        (Test-LocalAiPathContained -ParentPath $regular.FullPath -CandidatePath $fast.FullPath -AllowEqual)) {
        throw 'Fast and regular managed roots must be distinct and must not contain one another.'
    }

    function Get-ConfiguredPath {
        param(
            [Parameter(Mandatory)]
            [string]$Key,

            [Parameter(Mandatory)]
            [string]$DefaultPath,

            [Parameter(Mandatory)]
            [string]$RequiredParent
        )

        $configuredPath = $DefaultPath
        if ($values.Contains($Key) -and -not [string]::IsNullOrWhiteSpace([string]$values[$Key])) {
            $configuredPath = [string]$values[$Key]
        }
        $expandedPath = [Environment]::ExpandEnvironmentVariables($configuredPath.Trim())
        if ($expandedPath -notmatch '^[A-Za-z]:[\\/]') {
            throw "Environment path '$Key' must be a drive-qualified absolute path."
        }
        $fullPath = [IO.Path]::GetFullPath($expandedPath)
        if (-not (Test-LocalAiPathContained -ParentPath $RequiredParent -CandidatePath $fullPath)) {
            throw "Environment path '$Key' must remain below its managed storage root."
        }
        return $fullPath.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    }

    $ollamaExecutable = Get-ConfiguredPath `
        -Key 'OLLAMA_EXE' `
        -DefaultPath (Join-Path $regular.FullPath 'Apps\Ollama\ollama.exe') `
        -RequiredParent $regular.FullPath
    $ollamaModels = Get-ConfiguredPath `
        -Key 'OLLAMA_MODELS' `
        -DefaultPath (Join-Path $fast.FullPath 'Models\Ollama') `
        -RequiredParent $fast.FullPath
    $ollamaScratch = Get-ConfiguredPath `
        -Key 'OLLAMA_SCRATCH' `
        -DefaultPath (Join-Path $fast.FullPath 'Scratch\Ollama') `
        -RequiredParent $fast.FullPath
    $ollamaLogRoot = Get-ConfiguredPath `
        -Key 'OLLAMA_LOG_ROOT' `
        -DefaultPath (Join-Path $regular.FullPath 'Logs\Ollama') `
        -RequiredParent $regular.FullPath
    $dockerDataRoot = Get-ConfiguredPath `
        -Key 'DOCKER_DATA_ROOT' `
        -DefaultPath (Join-Path $regular.FullPath 'Docker\wsl') `
        -RequiredParent $regular.FullPath
    $dockerCli = Get-ConfiguredPath `
        -Key 'DOCKER_CLI' `
        -DefaultPath (Join-Path $regular.FullPath 'Apps\DockerDesktop\resources\bin\docker.exe') `
        -RequiredParent $regular.FullPath
    $dockerDesktopExecutable = Get-ConfiguredPath `
        -Key 'DOCKER_DESKTOP_EXE' `
        -DefaultPath (Join-Path $regular.FullPath 'Apps\DockerDesktop\Docker Desktop.exe') `
        -RequiredParent $regular.FullPath
    $openWebUiData = Get-ConfiguredPath `
        -Key 'OPEN_WEBUI_DATA' `
        -DefaultPath (Join-Path $regular.FullPath 'OpenWebUI\data') `
        -RequiredParent $regular.FullPath

    $ollamaBind = if ($values.Contains('OLLAMA_BIND')) { [string]$values.OLLAMA_BIND } else { '127.0.0.1:11434' }
    $openWebUiBind = if ($values.Contains('OPEN_WEBUI_BIND')) { [string]$values.OPEN_WEBUI_BIND } else { '127.0.0.1:3000' }
    if (-not (Test-LocalAiLoopbackEndpoint -Endpoint $ollamaBind -ExpectedPort 11434)) {
        throw 'OLLAMA_BIND must be exactly 127.0.0.1:11434 for the published service contract.'
    }
    if (-not (Test-LocalAiLoopbackEndpoint -Endpoint $openWebUiBind -ExpectedPort 3000)) {
        throw 'OPEN_WEBUI_BIND must be exactly 127.0.0.1:3000 for the published service contract.'
    }

    $keepAlive = if ($values.Contains('OLLAMA_KEEP_ALIVE')) { [string]$values.OLLAMA_KEEP_ALIVE } else { '5m' }
    if ($keepAlive -notmatch '^(?:-1|0|[1-9][0-9]*(?:ms|s|m|h))$') {
        throw 'OLLAMA_KEEP_ALIVE is not a supported duration.'
    }

    $flashAttention = $false
    if ($values.Contains('OLLAMA_FLASH_ATTENTION') -and -not [string]::IsNullOrWhiteSpace([string]$values.OLLAMA_FLASH_ATTENTION)) {
        $flashAttention = ConvertFrom-LocalAiBoolean -Value $values.OLLAMA_FLASH_ATTENTION -Name 'OLLAMA_FLASH_ATTENTION'
    }

    $kvCacheType = if ($values.Contains('OLLAMA_KV_CACHE_TYPE')) { ([string]$values.OLLAMA_KV_CACHE_TYPE).Trim() } else { '' }
    if ($kvCacheType -notin @('', 'f16', 'q8_0', 'q4_0')) {
        throw 'OLLAMA_KV_CACHE_TYPE must be empty, f16, q8_0, or q4_0.'
    }
    if ($kvCacheType -in @('q8_0', 'q4_0') -and -not $flashAttention) {
        throw 'Quantized KV cache requires OLLAMA_FLASH_ATTENTION=true.'
    }

    $funnelEnabled = $false
    if ($values.Contains('TAILSCALE_FUNNEL_ENABLED') -and -not [string]::IsNullOrWhiteSpace([string]$values.TAILSCALE_FUNNEL_ENABLED)) {
        $funnelEnabled = ConvertFrom-LocalAiBoolean -Value $values.TAILSCALE_FUNNEL_ENABLED -Name 'TAILSCALE_FUNNEL_ENABLED'
    }
    if ($funnelEnabled) {
        throw 'TAILSCALE_FUNNEL_ENABLED must remain false.'
    }

    $openWebUiSignup = $false
    if ($values.Contains('OPEN_WEBUI_ENABLE_SIGNUP') -and -not [string]::IsNullOrWhiteSpace([string]$values.OPEN_WEBUI_ENABLE_SIGNUP)) {
        $openWebUiSignup = ConvertFrom-LocalAiBoolean -Value $values.OPEN_WEBUI_ENABLE_SIGNUP -Name 'OPEN_WEBUI_ENABLE_SIGNUP'
    }

    $openWebUiSecret = if ($values.Contains('OPEN_WEBUI_SECRET_KEY')) { [string]$values.OPEN_WEBUI_SECRET_KEY } else { '' }
    if ($RequireOpenWebUiSecret -and $openWebUiSecret.Length -lt 32) {
        throw 'OPEN_WEBUI_SECRET_KEY must contain at least 32 characters in private configuration.'
    }

    $expectedOllamaVersion = if ($values.Contains('OLLAMA_EXPECTED_VERSION')) { ([string]$values.OLLAMA_EXPECTED_VERSION).Trim() } else { '' }
    if ($expectedOllamaVersion -ne '' -and $expectedOllamaVersion -notmatch '^v?[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$') {
        throw 'OLLAMA_EXPECTED_VERSION must be an exact semantic version.'
    }

    $expectedDockerDesktopVersion = if ($values.Contains('DOCKER_DESKTOP_EXPECTED_VERSION')) {
        ([string]$values.DOCKER_DESKTOP_EXPECTED_VERSION).Trim()
    }
    else {
        ''
    }
    if ($expectedDockerDesktopVersion -ne '' -and $expectedDockerDesktopVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') {
        throw 'DOCKER_DESKTOP_EXPECTED_VERSION must be an exact four-part file version.'
    }

    return [pscustomobject]@{
        Values                  = $values
        FastStorageRoot         = $fast.FullPath
        RegularStorageRoot      = $regular.FullPath
        OllamaExecutable        = $ollamaExecutable
        OllamaModels            = $ollamaModels
        OllamaScratch           = $ollamaScratch
        OllamaLogRoot           = $ollamaLogRoot
        DockerDataRoot          = $dockerDataRoot
        DockerCli               = $dockerCli
        DockerDesktopExecutable = $dockerDesktopExecutable
        DockerDesktopExpectedVersion = $expectedDockerDesktopVersion
        OpenWebUiData           = $openWebUiData
        OllamaBind              = $ollamaBind
        OpenWebUiBind           = $openWebUiBind
        OllamaKeepAlive         = $keepAlive
        OllamaFlashAttention    = $flashAttention
        OllamaKvCacheType       = $kvCacheType
        OllamaExpectedVersion   = $expectedOllamaVersion
        OpenWebUiSecretKey      = $openWebUiSecret
        OpenWebUiEnableSignup   = $openWebUiSignup
        TailscaleFunnelEnabled  = $funnelEnabled
    }
}

function Test-LocalAiImmutableImageReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Reference
    )

    return $Reference -match '^[a-z0-9][a-z0-9._/-]*(?::[A-Za-z0-9][A-Za-z0-9._-]*)?@sha256:[0-9a-f]{64}$'
}

function Get-LocalAiListenerSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [Int32]$Port
    )

    if ($null -eq (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            InspectionAvailable = $false
            ListenerPresent = $false
            LoopbackOnly = $false
            LocalAddresses = @()
            OwningProcessIds = @()
        }
    }

    try {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{
            InspectionAvailable = $false
            ListenerPresent = $false
            LoopbackOnly = $false
            LocalAddresses = @()
            OwningProcessIds = @()
        }
    }

    $addresses = @($listeners.LocalAddress | Sort-Object -Unique)
    $nonLoopback = @($addresses | Where-Object { $_ -notin @('127.0.0.1', '::1') })
    return [pscustomobject]@{
        InspectionAvailable = $true
        ListenerPresent = ($listeners.Count -gt 0)
        LoopbackOnly = ($listeners.Count -gt 0 -and $nonLoopback.Count -eq 0)
        LocalAddresses = $addresses
        OwningProcessIds = @($listeners.OwningProcess | Sort-Object -Unique)
    }
}

function Invoke-LocalAiLoopbackJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Uri]$Uri,

        [ValidateRange(1, 60)]
        [Int32]$TimeoutSeconds = 5
    )

    if ($Uri.Scheme -ne 'http' -or -not $Uri.IsLoopback) {
        throw 'Runtime verification requests are restricted to loopback HTTP endpoints.'
    }

    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    try {
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "Loopback endpoint returned HTTP $([Int32]$response.StatusCode)."
        }
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ($content.Length -gt 1048576) {
            throw 'Loopback endpoint returned an unexpectedly large response.'
        }
        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function New-LocalAiOllamaEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FastStorageRoot,

        [ValidateRange(1, 65535)]
        [Int32]$Port = 11434,

        [ValidatePattern('^(?:-1|0|[1-9][0-9]*(?:ms|s|m|h))$')]
        [string]$KeepAlive = '5m',

        [string]$ModelPath,

        [string]$ScratchPath,

        [switch]$FlashAttentionSupported,

        [ValidateSet('', 'f16', 'q8_0', 'q4_0')]
        [string]$KvCacheType = ''
    )

    if ($KvCacheType -in @('q8_0', 'q4_0') -and -not $FlashAttentionSupported) {
        throw 'Quantized KV cache may be enabled only when flash-attention support has also been verified.'
    }

    $fastRoot = (Resolve-LocalAiManagedPath -Path $FastStorageRoot -AllowMissing).FullPath
    if ([string]::IsNullOrWhiteSpace($ModelPath)) {
        $ModelPath = Join-Path $fastRoot 'Models\Ollama'
    }
    if ([string]::IsNullOrWhiteSpace($ScratchPath)) {
        $ScratchPath = Join-Path $fastRoot 'Scratch\Ollama'
    }
    if (-not (Test-LocalAiPathContained -ParentPath $fastRoot -CandidatePath $ModelPath) -or
        -not (Test-LocalAiPathContained -ParentPath $fastRoot -CandidatePath $ScratchPath)) {
        throw 'Ollama models and scratch paths must remain below the fast-storage root.'
    }

    $modelPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ModelPath))
    $scratchPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ScratchPath))

    $environment = [ordered]@{
        OLLAMA_HOST              = "127.0.0.1:$Port"
        OLLAMA_MODELS            = $modelPath
        OLLAMA_MAX_LOADED_MODELS = '1'
        OLLAMA_NUM_PARALLEL      = '1'
        OLLAMA_KEEP_ALIVE        = $KeepAlive
        OLLAMA_NO_CLOUD          = '1'
        TEMP                     = $scratchPath
        TMP                      = $scratchPath
    }

    if ($FlashAttentionSupported) {
        $environment.OLLAMA_FLASH_ATTENTION = '1'
    }
    if (-not [string]::IsNullOrWhiteSpace($KvCacheType)) {
        $environment.OLLAMA_KV_CACHE_TYPE = $KvCacheType
    }

    return $environment
}

Export-ModuleMember -Function @(
    'Resolve-LocalAiManagedPath',
    'Test-LocalAiPathContained',
    'Get-LocalAiDirectoryLogicalSize',
    'Get-LocalAiVolumeSnapshot',
    'Get-LocalAiPhysicalDiskNumber',
    'Read-LocalAiEnvironmentFile',
    'Get-LocalAiEnvironmentAllowList',
    'ConvertFrom-LocalAiBoolean',
    'Test-LocalAiLoopbackEndpoint',
    'Get-LocalAiConfiguration',
    'Test-LocalAiImmutableImageReference',
    'Get-LocalAiListenerSnapshot',
    'Invoke-LocalAiLoopbackJsonRequest',
    'New-LocalAiOllamaEnvironment'
)
