Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Fm2RepositoryRoot {
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Get-Fm2ReleasePolicy {
    $root = Get-Fm2RepositoryRoot
    $path = Join-Path $root "release/release-policy.json"
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Invoke-CheckedNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][string]$WorkingDirectory = (Get-Location).Path
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        # PowerShell may leave LASTEXITCODE undefined for Windows GUI programs.
        # Seed it so a clean GUI launch is treated as success while console
        # tools can still replace it with their actual exit code.
        $global:LASTEXITCODE = 0
        & $FilePath @ArgumentList
        $exitCode = $global:LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Command failed with exit code $exitCode`: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Resolve-Fm2Tool {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -in @("clang", "clang++", "clang-cl")) {
        $candidate = Join-Path $env:ProgramFiles "LLVM/bin/$Name.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Required tool not found: $Name"
}

function Assert-Fm2GameInputs {
    param([Parameter(Mandatory)][string]$GameDataRoot)

    $policy = Get-Fm2ReleasePolicy
    $resolvedRoot = [IO.Path]::GetFullPath($GameDataRoot)
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Game data folder not found: $resolvedRoot"
    }

    foreach ($inputFile in $policy.required_game_inputs) {
        $candidate = Join-Path $resolvedRoot $inputFile.path
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Required input not found: $($inputFile.path)"
        }
        $item = Get-Item -LiteralPath $candidate
        if ($item.Length -ne [int64]$inputFile.size) {
            throw "Size mismatch for $($inputFile.path): expected $($inputFile.size), got $($item.Length)"
        }
        $actualHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        if ($actualHash -ne $inputFile.sha256) {
            throw "SHA-256 mismatch for $($inputFile.path): this dump is not the validated input"
        }
    }

    return $resolvedRoot
}

function Get-Fm2FileRecords {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter()][string]$BasePath
    )

    return @($Paths | Sort-Object | ForEach-Object {
        $item = Get-Item -LiteralPath $_
        [ordered]@{
            path = if ($BasePath) { [IO.Path]::GetRelativePath($BasePath, $item.FullName).Replace("\", "/") } else { $item.FullName }
            size = $item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    })
}

function Get-Fm2SourceIdentity {
    param([string]$Root = (Get-Fm2RepositoryRoot))

    $Root = [IO.Path]::GetFullPath($Root)
    $policy = Get-Content -LiteralPath (Join-Path $Root "release/release-policy.json") -Raw | ConvertFrom-Json
    $paths = @(Get-Content -LiteralPath (Join-Path $Root $policy.source_allowlist) |
        ForEach-Object { $_.Trim().Replace("\", "/") } | Where-Object { $_ -and -not $_.StartsWith("#") })
    foreach ($path in $paths) {
        if ([IO.Path]::IsPathRooted($path) -or $path.Split("/") -contains "..") {
            throw "Unsafe source identity path: $path"
        }
    }
    $records = @(Get-Fm2FileRecords -Paths @($paths | ForEach-Object { Join-Path $Root $_ }) -BasePath $Root)

    # Do not search parent repositories: an extracted archive can live in one.
    if (Test-Path -LiteralPath (Join-Path $Root ".git")) {
        $git = Resolve-Fm2Tool -Name "git"
        $commit = & $git -C $Root rev-parse --verify HEAD
        if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
            throw "Cannot read the source commit."
        }
        $status = @(& $git -C $Root status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw "Cannot read the source worktree status." }
        return [ordered]@{
            kind = "git"
            project_commit = $commit.Trim()
            project_worktree_dirty = ($status.Count -ne 0)
            source_provenance_sha256 = $null
            files = $records
        }
    }

    $provenancePath = Join-Path $Root "SOURCE-PROVENANCE.json"
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
        throw "Source identity is missing. Use a Git checkout or an unchanged source release with SOURCE-PROVENANCE.json."
    }
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    if ($provenance.schema_version -ne 1 -or $provenance.project_commit -notmatch '^[0-9a-f]{40}$' -or
        $provenance.project_worktree_dirty -isnot [bool] -or
        $provenance.sdk_repository -ne $policy.sdk.repository -or $provenance.sdk_commit -ne $policy.sdk.commit) {
        throw "Source provenance does not match the release policy."
    }
    $payload = @($provenance.payload)
    if ($payload.Count -ne $records.Count -or @($payload | Group-Object path | Where-Object Count -ne 1).Count) {
        throw "Source provenance does not match the source allowlist."
    }
    foreach ($record in $records) {
        $expected = @($payload | Where-Object path -CEQ $record.path)
        if ($expected.Count -ne 1 -or $expected[0].size -ne $record.size -or $expected[0].sha256 -ne $record.sha256) {
            throw "Source provenance mismatch: $($record.path). Use an unchanged source archive or a Git checkout for edits."
        }
    }
    return [ordered]@{
        kind = "source-archive"
        project_commit = $provenance.project_commit
        project_worktree_dirty = $provenance.project_worktree_dirty
        source_provenance_sha256 = (Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash
        files = $records
    }
}
