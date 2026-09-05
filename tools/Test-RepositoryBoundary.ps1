[CmdletBinding()]
param([switch]$AllowLocalBuildOutputs)

. (Join-Path $PSScriptRoot "Release.Common.ps1")

$root = Get-Fm2RepositoryRoot
$policy = Get-Fm2ReleasePolicy
$allowlistPath = Join-Path $root $policy.source_allowlist
$allowlist = @(Get-Content -LiteralPath $allowlistPath | ForEach-Object { $_.Trim().Replace("\", "/") } | Where-Object { $_ -and -not $_.StartsWith("#") })

$duplicates = @($allowlist | Group-Object | Where-Object Count -gt 1)
if ($duplicates) {
    throw "Duplicate source allowlist entries: $($duplicates.Name -join ', ')"
}

foreach ($relativePath in $allowlist) {
    if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath.Split("/") -contains "..") {
        throw "Unsafe source allowlist path: $relativePath"
    }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
    if (-not $fullPath.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Source allowlist path escapes the repository: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Source allowlist file is missing: $relativePath"
    }
    if ((Get-Item -LiteralPath $fullPath).Length -gt [int64]$policy.maximum_source_file_bytes) {
        throw "Source file exceeds the policy size limit: $relativePath"
    }
}

$allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($relativePath in $allowlist) { [void]$allowed.Add($relativePath) }
$gitMetadata = Join-Path $root ".git"
if (Test-Path -LiteralPath $gitMetadata) {
    $candidatePaths = @(& git -C $root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed"
    }
    $inspectedPaths = @($candidatePaths | Where-Object {
        Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf
    } | Sort-Object -Unique)
    $inspectionLabel = "present tracked and untracked files"
}
else {
    [void]$allowed.Add("SOURCE-PROVENANCE.json")
    # A user can build an extracted archive more than once. Packaging uses the
    # strict default; only the builder can exclude its exact .local directory.
    $entries = @(Get-ChildItem -LiteralPath $root -Force | Where-Object {
        -not ($AllowLocalBuildOutputs -and $_.PSIsContainer -and $_.Name -eq ".local")
    })
    $inspectedPaths = @($entries | ForEach-Object {
        if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force }
        else { $_ }
    } | ForEach-Object {
        [IO.Path]::GetRelativePath($root, $_.FullName).Replace("\", "/")
    })
    $inspectionLabel = "source-package files"
}

$forbiddenExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($extension in $policy.forbidden_extensions) { [void]$forbiddenExtensions.Add($extension) }

foreach ($pathRaw in $inspectedPaths) {
    $relativePath = $pathRaw.Replace("\", "/")
    if (-not $allowed.Contains($relativePath)) {
        throw "Repository file is absent from the source allowlist: $relativePath"
    }
    foreach ($directory in $policy.forbidden_directories) {
        $prefix = $directory.TrimEnd("/") + "/"
        if ($relativePath.Equals($directory, [StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Repository file crosses a forbidden directory boundary: $relativePath"
        }
    }
    if ($forbiddenExtensions.Contains([IO.Path]::GetExtension($relativePath))) {
        throw "Repository file has a forbidden extension: $relativePath"
    }

    $fullPath = Join-Path $root $relativePath
    if ((Get-Item -LiteralPath $fullPath).Length -ge 4) {
        $stream = [IO.File]::OpenRead($fullPath)
        try {
            $bytes = [byte[]]::new(4)
            [void]$stream.Read($bytes, 0, 4)
            $hex = [Convert]::ToHexString($bytes)
            $ascii = [Text.Encoding]::ASCII.GetString($bytes)
            if ($hex.StartsWith("4D5A") -or $ascii -in @("XEX2", "CON ", "LIVE", "PIRS")) {
                throw "Repository file has forbidden binary magic: $relativePath"
            }
        }
        finally {
            $stream.Dispose()
        }
    }
}

Write-Host "Repository boundary passed: $($inspectedPaths.Count) $inspectionLabel, $($allowlist.Count) allowlisted release files."
