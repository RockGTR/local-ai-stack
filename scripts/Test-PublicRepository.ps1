[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
Push-Location -LiteralPath $resolvedRoot

try {
    $trackedFiles = @(git ls-files --cached)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tracked files.'
    }
    $untrackedFiles = @(git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate untracked files.'
    }
    $candidateFiles = @($trackedFiles + $untrackedFiles | Sort-Object -Unique)
    $trackedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($trackedFile in $trackedFiles) {
        [void]$trackedSet.Add($trackedFile)
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $blockedExtensions = @(
        '.gguf', '.safetensors', '.onnx', '.pt', '.pth',
        '.vhd', '.vhdx', '.sqlite', '.sqlite3', '.db',
        '.pem', '.key', '.pfx', '.p12', '.exe', '.msi', '.dll',
        '.so', '.dylib', '.bin', '.zip', '.7z', '.rar', '.tar',
        '.gz', '.xz'
    )

    foreach ($relativePath in $candidateFiles) {
        $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if ($blockedExtensions -contains $extension) {
            $errors.Add("Prohibited tracked artifact: $relativePath")
        }

        if ($relativePath -match '(?i)(^|/)(?:[^/]*\.env|\.env(?:\..+)?|.*\.private(?:\..+)?)$' -and
            $relativePath -notmatch '(?i)\.env\.example$') {
            $errors.Add("Potential private configuration is tracked: $relativePath")
        }
    }

    $contentRules = @(
        [pscustomobject]@{
            Name = 'drive-qualified absolute path'
            Pattern = '(?i)(?<![A-Z0-9_])[A-Z]:[\\/]'
        },
        [pscustomobject]@{
            Name = 'private IPv4 address'
            Pattern = '(?<!\d)(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.(?:\d{1,3}\.)\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.)\d{1,3}|100\.(?:6[4-9]|[78]\d|9\d|1[01]\d|12[0-7])\.(?:\d{1,3}\.)\d{1,3})(?!\d)'
        },
        [pscustomobject]@{
            Name = 'concrete tailnet URL'
            Pattern = '(?i)https?://[^\s<>]+\.ts\.net(?::\d+)?(?:/[^\s<>]*)?'
        },
        [pscustomobject]@{
            Name = 'secret-like assignment'
            Pattern = '(?i)\b(?:[A-Z0-9]+[_-])*(?:token|secret|password|api[_-]?key|private[_-]?key)\b\s*[:=]\s*["'']?(?!<|REDACTED|CHANGEME)[^\s"''#]+'
        }
    )

    foreach ($relativePath in $candidateFiles) {
        $contentLines = @()
        if ($trackedSet.Contains($relativePath)) {
            $indexLines = @(git show ":$relativePath")
            if ($LASTEXITCODE -ne 0) {
                $errors.Add("Unable to inspect staged content: $relativePath")
                continue
            }
            $contentLines += $indexLines
        }

        $fullPath = Join-Path $resolvedRoot $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            # Scan working-tree content as well as the staged/index blob. This
            # catches both a staged secret removed only from the worktree and
            # an unstaged secret that is about to be staged.
            $contentLines += @(Get-Content -LiteralPath $fullPath -ErrorAction Stop)
        }
        $lineNumber = 0

        foreach ($line in $contentLines) {
            $lineNumber++
            foreach ($rule in $contentRules) {
                if ($line -match $rule.Pattern) {
                    $errors.Add("$($rule.Name): ${relativePath}:$lineNumber")
                }
            }
        }
    }

    if ($errors.Count -gt 0) {
        $errors | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
        exit 1
    }

    Write-Output "Public repository check passed for $($candidateFiles.Count) candidate files."
}
finally {
    Pop-Location
}
