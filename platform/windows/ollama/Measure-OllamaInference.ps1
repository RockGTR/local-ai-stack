[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Model,

    [Parameter(Mandatory)]
    [ValidateSet('chat', 'generate', 'fim')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Prompt,

    [string]$Suffix = '',

    [ValidateRange(512, 1048576)]
    [Int32]$ContextLength = 8192,

    [ValidateRange(1, 4096)]
    [Int32]$PredictTokens = 64,

    [ValidateRange(0.0, 2.0)]
    [double]$Temperature = 0.0,

    [ValidateRange(0, [Int32]::MaxValue)]
    [Int32]$Seed = 42,

    [ValidateRange(-1, 512)]
    [Int32]$NumGpuLayers = -1,

    [ValidatePattern('^(?:-1|0|[1-9][0-9]*(?:ms|s|m|h))$')]
    [string]$KeepAlive = '5m',

    [string]$ImagePath,

    [switch]$ColdStart,

    [switch]$DisableThinking,

    [switch]$RequireFullGpu,

    [ValidateRange(1000000000, [Int64]::MaxValue)]
    [Int64]$MinimumAvailableRamBytes = 8000000000,

    [ValidateRange(100, 5000)]
    [Int32]$SampleIntervalMilliseconds = 250,

    [ValidateRange(10, 3600)]
    [Int32]$TimeoutSeconds = 900,

    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUri = [Uri]'http://127.0.0.1:11434/'
$nvidiaSmi = Get-Command 'nvidia-smi.exe' -ErrorAction Stop

function Convert-NanosecondsToMilliseconds {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    return [Math]::Round(([double]$Value / 1000000.0), 3)
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha256.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-SystemSample {
    $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
    $gpuFields = @(& $nvidiaSmi.Source `
        '--query-gpu=memory.used,memory.total,utilization.gpu,power.draw,temperature.gpu' `
        '--format=csv,noheader,nounits' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $gpuFields.Count -ne 1) {
        throw 'Unable to read a single NVIDIA GPU telemetry row.'
    }
    $gpu = @($gpuFields[0].Split(',') | ForEach-Object { $_.Trim() })
    if ($gpu.Count -ne 5) {
        throw 'Unexpected NVIDIA telemetry shape.'
    }

    [pscustomobject]@{
        CapturedAtUtc       = [DateTime]::UtcNow.ToString('o')
        AvailableRamBytes   = [Int64]$operatingSystem.FreePhysicalMemory * 1024
        GpuMemoryUsedMiB    = [Int32]$gpu[0]
        GpuMemoryTotalMiB   = [Int32]$gpu[1]
        GpuUtilizationPct   = [Int32]$gpu[2]
        GpuPowerWatts       = [double]$gpu[3]
        GpuTemperatureC     = [Int32]$gpu[4]
        PageFileCurrentMiB  = [Int64](($pageFiles | Measure-Object CurrentUsage -Sum).Sum)
        PageFilePeakMiB     = [Int64](($pageFiles | Measure-Object PeakUsage -Sum).Sum)
    }
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory)]
        [Net.Http.HttpClient]$Client,

        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [Parameter(Mandatory)]
        [hashtable]$Body,

        [switch]$Monitor
    )

    $json = $Body | ConvertTo-Json -Depth 12 -Compress
    $content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
    $samples = [Collections.Generic.List[object]]::new()
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $requestTask = $Client.PostAsync($RelativeUri, $content)
        while (-not $requestTask.IsCompleted) {
            if ($Monitor) {
                $sample = Get-SystemSample
                $samples.Add($sample)
                if ($sample.AvailableRamBytes -lt $MinimumAvailableRamBytes) {
                    throw "Available RAM fell below the configured safety floor of $MinimumAvailableRamBytes bytes."
                }
            }
            Start-Sleep -Milliseconds $SampleIntervalMilliseconds
        }
        $response = $requestTask.GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "Ollama returned HTTP $([Int32]$response.StatusCode): $responseText"
        }
        $stopwatch.Stop()
        return [pscustomobject]@{
            Body        = $responseText | ConvertFrom-Json -ErrorAction Stop
            WallSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
            Samples     = @($samples)
        }
    }
    finally {
        $stopwatch.Stop()
        $content.Dispose()
    }
}

Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$handler = [Net.Http.HttpClientHandler]::new()
$handler.UseProxy = $false
$client = [Net.Http.HttpClient]::new($handler)
$client.BaseAddress = $baseUri
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

try {
    if ($ColdStart) {
        [void](Invoke-JsonRequest -Client $client -RelativeUri 'api/generate' -Body @{
            model      = $Model
            prompt     = ''
            stream     = $false
            keep_alive = 0
        })
    }

    $imageBytes = $null
    if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
        if ($Mode -ne 'chat') {
            throw 'Image input is supported only in chat mode by this benchmark.'
        }
        $resolvedImage = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ImagePath))
        if (-not (Test-Path -LiteralPath $resolvedImage -PathType Leaf)) {
            throw 'The requested image does not exist.'
        }
        $imageBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolvedImage))
    }

    $options = @{
        num_ctx     = $ContextLength
        num_predict = $PredictTokens
        temperature = $Temperature
        seed        = $Seed
    }
    if ($NumGpuLayers -ge 0) {
        $options.num_gpu = $NumGpuLayers
    }
    if ($Mode -eq 'chat') {
        $message = @{
            role    = 'user'
            content = $Prompt
        }
        if ($null -ne $imageBytes) {
            $message.images = @($imageBytes)
        }
        $requestBody = @{
            model      = $Model
            messages   = @($message)
            stream     = $false
            keep_alive = $KeepAlive
            options    = $options
        }
        if ($DisableThinking) {
            $requestBody.think = $false
        }
        $relativeUri = 'api/chat'
    }
    else {
        $requestBody = @{
            model      = $Model
            prompt     = $Prompt
            stream     = $false
            keep_alive = $KeepAlive
            options    = $options
        }
        if ($Mode -eq 'fim') {
            if ([string]::IsNullOrWhiteSpace($Suffix)) {
                throw 'FIM mode requires a non-empty suffix.'
            }
            $requestBody.suffix = $Suffix
        }
        $relativeUri = 'api/generate'
    }

    $before = Get-SystemSample
    $run = Invoke-JsonRequest -Client $client -RelativeUri $relativeUri -Body $requestBody -Monitor
    $after = Get-SystemSample
    $samples = @($before) + @($run.Samples) + @($after)

    $psResponse = $client.GetStringAsync('api/ps').GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop
    $loaded = @($psResponse.models | Where-Object { $_.name -eq $Model } | Select-Object -First 1)
    $runtime = if ($loaded.Count -eq 1) { $loaded[0] } else { $null }
    $fullyGpuResident = ($null -ne $runtime -and [Int64]$runtime.size_vram -ge [Int64]$runtime.size)

    if ($RequireFullGpu -and -not $fullyGpuResident) {
        throw 'The measured model was not fully GPU-resident after inference.'
    }

    $body = $run.Body
    $promptDurationSeconds = [double]$body.prompt_eval_duration / 1000000000.0
    $evalDurationSeconds = [double]$body.eval_duration / 1000000000.0
    $outputText = if ($Mode -eq 'chat') { [string]$body.message.content } else { [string]$body.response }
    $result = [pscustomobject]@{
        SchemaVersion                = 1
        CheckedAtUtc                 = [DateTime]::UtcNow.ToString('o')
        Model                        = $Model
        Mode                         = $Mode
        ColdStartRequested           = [bool]$ColdStart
        ContextLength                = $ContextLength
        PredictTokensRequested       = $PredictTokens
        NumGpuLayersRequested        = if ($NumGpuLayers -ge 0) { $NumGpuLayers } else { $null }
        ImageInput                   = ($null -ne $imageBytes)
        ThinkingDisabled             = [bool]$DisableThinking
        Completed                    = [bool]$body.done
        DoneReason                   = [string]$body.done_reason
        OutputCharacters             = $outputText.Length
        OutputSha256                 = Get-TextSha256 -Text $outputText
        WallSeconds                  = $run.WallSeconds
        TotalDurationMs              = Convert-NanosecondsToMilliseconds $body.total_duration
        LoadDurationMs               = Convert-NanosecondsToMilliseconds $body.load_duration
        PromptEvalCount              = [Int64]$body.prompt_eval_count
        PromptEvalTokensPerSecond    = if ($promptDurationSeconds -gt 0) { [Math]::Round(([double]$body.prompt_eval_count / $promptDurationSeconds), 3) } else { $null }
        EvalCount                    = [Int64]$body.eval_count
        EvalTokensPerSecond          = if ($evalDurationSeconds -gt 0) { [Math]::Round(([double]$body.eval_count / $evalDurationSeconds), 3) } else { $null }
        RuntimeContextLength         = if ($null -ne $runtime) { [Int64]$runtime.context_length } else { $null }
        RuntimeSizeBytes             = if ($null -ne $runtime) { [Int64]$runtime.size } else { $null }
        RuntimeVramBytes             = if ($null -ne $runtime) { [Int64]$runtime.size_vram } else { $null }
        FullyGpuResident             = $fullyGpuResident
        PeakGpuMemoryUsedMiB         = [Int32](($samples | Measure-Object GpuMemoryUsedMiB -Maximum).Maximum)
        PeakGpuUtilizationPct        = [Int32](($samples | Measure-Object GpuUtilizationPct -Maximum).Maximum)
        PeakGpuPowerWatts            = [Math]::Round([double](($samples | Measure-Object GpuPowerWatts -Maximum).Maximum), 2)
        PeakGpuTemperatureC          = [Int32](($samples | Measure-Object GpuTemperatureC -Maximum).Maximum)
        MinimumAvailableRamBytes     = [Int64](($samples | Measure-Object AvailableRamBytes -Minimum).Minimum)
        PageFileCurrentMiBBefore     = $before.PageFileCurrentMiB
        PageFileCurrentMiBAfter      = $after.PageFileCurrentMiB
        PageFilePeakMiBBefore        = $before.PageFilePeakMiB
        PageFilePeakMiBAfter         = $after.PageFilePeakMiB
        SampleCount                  = $samples.Count
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $reportFullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ReportPath))
        $reportDirectory = Split-Path -Parent $reportFullPath
        if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
            throw 'The report directory does not exist.'
        }
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFullPath -Encoding utf8
    }

    Write-Output $result
}
finally {
    $client.Dispose()
    $handler.Dispose()
}
