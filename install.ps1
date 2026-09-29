<#
Lookback installer and updater for Windows. Idempotent: re-run it to update.

    irm https://raw.githubusercontent.com/LLM-Lineage/lookback/main/install.ps1 | iex

The Windows counterpart of install.sh, and deliberately the same script twice
rather than one clever script: the two have different tools for every step —
Get-FileHash against shasum, Expand-Archive against tar, a user Path variable
against a line in a profile — and pretending otherwise would hide the parts that
actually differ.

What does not differ is the guarantee. Every way of *not knowing* a hash is a
failure here too, because that is the bug install.sh shipped: a chain of guards
where an empty hash short-circuited to success, so the only case that ever failed
was the one where both hashes were present and disagreed. Confirm-Hash below
refuses instead, and refuses for each separate reason.

Everything is user-level. No administrator rights, nothing in Program Files,
nothing an IT policy objects to. Re-running installs the newest release over the
old one and leaves the collected store alone.

Layout matches every other platform, so `lookback --store` means the same thing
everywhere:

    %USERPROFILE%\.lookback\bin\lookback.exe
    %USERPROFILE%\.lookback\store.sqlite
#>

[CmdletBinding()]
param(
    [switch] $Uninstall,
    [switch] $Purge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 is still the default shell on Windows 10 and 11, and it
# negotiates TLS 1.0 unless told otherwise — against which GitHub simply closes
# the connection.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # PowerShell 7+ manages this itself and the type may not be settable.
}

$Repo             = 'LLM-Lineage/lookback'
$Market           = 'LLM-Lineage/lookback'
# `lineage-llm` is already bavarde's marketplace, and Claude Code keys
# marketplaces by name: reusing it made `marketplace add` fail on the collision
# and the fallback silently update *bavarde's* marketplace instead.
$MarketplaceName  = 'lookback'
$Plugin           = 'lookback@lookback'
$Product          = 'lookback'
$StateDir         = Join-Path $env:USERPROFILE '.lookback'
$BinDir           = Join-Path $StateDir 'bin'
$BinPath          = Join-Path $BinDir 'lookback.exe'

function Say  { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Green }
function Warn { param([string] $Message) Write-Host " warning: $Message" -ForegroundColor Yellow }
function Die  { param([string] $Message) Write-Host " error: $Message" -ForegroundColor Red; exit 1 }

# --- 0. uninstall ------------------------------------------------------------
if ($Uninstall) {
    Say 'removing the binary and the Path entry'
    if (Test-Path $BinPath) { Remove-Item -Force $BinPath }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) {
        $kept = $userPath.Split(';') | Where-Object { $_ -and $_ -ne $BinDir }
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        & claude plugin uninstall $Plugin 2>$null
        & claude plugin marketplace remove $MarketplaceName 2>$null
    }

    if ($Purge) {
        # The store is derived from %USERPROFILE%\.claude and can always be
        # rebuilt, but it is the user's own history and is not removed unasked.
        Warn "purging $StateDir - the collected store"
        if (Test-Path $StateDir) { Remove-Item -Recurse -Force $StateDir }
    } else {
        Say "the store at $StateDir is kept; pass -Uninstall -Purge to remove it too"
    }
    Say 'done'
    exit 0
}

# --- 1. platform -------------------------------------------------------------
$architecture = $env:PROCESSOR_ARCHITECTURE
if (-not $architecture) { $architecture = 'AMD64' }

switch ($architecture) {
    'AMD64' { $target = 'x86_64-pc-windows-msvc' }
    'ARM64' {
        # Windows on ARM runs x64 binaries under emulation, so this is a working
        # install rather than a refusal — but it says so, because a native build
        # is a release-targets decision and not something to pretend about.
        Warn 'Windows on ARM: installing the x64 build, which runs under emulation'
        $target = 'x86_64-pc-windows-msvc'
    }
    default { Die "no build for $architecture" }
}

# --- 2. resolve the latest release -------------------------------------------
Say 'finding the latest release'

# The distribution repository is public, so no token is needed and none is asked
# for. GH_TOKEN is still honoured if it happens to be set - for a private fork or
# a rate-limited network - but the documented path uses neither.
$headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'lookback-installer' }
if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $($env:GH_TOKEN)" }

try {
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/latest"
} catch {
    Die "cannot reach $Repo releases - check the network; the repository is public and needs no token"
}

$version = $release.tag_name
if (-not $version) { Die 'no release found' }
Say "installing $version for $target"

$archiveName = "$Product-$($version.TrimStart('v'))-$target.zip"

function Asset-Url {
    param([string] $Name)
    $asset = $release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($asset) { $asset.url } else { $null }
}

$archiveUrl = Asset-Url $archiveName
$sumsUrl    = Asset-Url 'checksums.json'

if (-not $archiveUrl) { Die "no $archiveName in $version" }
# A release with no manifest cannot be verified, and an unverifiable release is
# not one to install.
if (-not $sumsUrl) { Die "no checksums.json in $version; refusing to install unverified" }

# --- 3. download and verify both hashes --------------------------------------
$scratch = Join-Path ([IO.Path]::GetTempPath()) "lookback-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    Say 'downloading'
    $archivePath = Join-Path $scratch $archiveName
    $sumsPath    = Join-Path $scratch 'checksums.json'

    $binaryHeaders = @{ 'Accept' = 'application/octet-stream'; 'User-Agent' = 'lookback-installer' }
    if ($env:GH_TOKEN) { $binaryHeaders['Authorization'] = "Bearer $($env:GH_TOKEN)" }

    Invoke-WebRequest -Headers $binaryHeaders -Uri $archiveUrl -OutFile $archivePath
    try {
        Invoke-WebRequest -Headers $binaryHeaders -Uri $sumsUrl -OutFile $sumsPath
    } catch {
        Die 'could not download checksums.json; refusing to install unverified'
    }

    $manifest = Get-Content -Raw $sumsPath | ConvertFrom-Json

    # The manifest keys are target triples, which are not valid property names to
    # reach for directly.
    $entry = $manifest.binaries.PSObject.Properties |
             Where-Object { $_.Name -eq $target } |
             Select-Object -First 1
    if (-not $entry) { Die "checksums.json has no entry for $target; refusing to install" }

    function Confirm-Hash {
        param(
            [string] $File,
            [string] $Field,
            [string] $Label,
            [object] $Entry
        )
        $property = $Entry.Value.PSObject.Properties |
                    Where-Object { $_.Name -eq $Field } |
                    Select-Object -First 1
        $want = if ($property) { $property.Value } else { $null }
        if (-not $want) { Die "checksums.json has no $Field for $target; refusing to install" }

        if (-not (Test-Path $File)) { Die "$File is missing; refusing to install unverified" }
        $got = (Get-FileHash -Algorithm SHA256 -Path $File).Hash
        if (-not $got) { Die "could not hash $File; refusing to install unverified" }

        if ($want.ToLowerInvariant() -ne $got.ToLowerInvariant()) {
            Die "$Label checksum mismatch (expected $want, got $got)"
        }
        Say "$Label verified"
    }

    Confirm-Hash -File $archivePath -Field 'archive_sha256' -Label 'archive' -Entry $entry

    Say 'unpacking'
    $unpacked = Join-Path $scratch 'unpacked'
    Expand-Archive -Path $archivePath -DestinationPath $unpacked -Force
    $extracted = Get-ChildItem -Path $unpacked -Filter 'lookback.exe' -Recurse |
                 Select-Object -First 1
    if (-not $extracted) { Die 'no lookback.exe in the archive' }

    # The authoritative check: it covers the file that actually executes, rather
    # than trusting the unpack step.
    Confirm-Hash -File $extracted.FullName -Field 'binary_sha256' -Label 'binary' -Entry $entry

    # --- 4. place the binary -------------------------------------------------
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    # A running process holds a lock on its own image, so overwriting the binary
    # while `lookback` is open fails with a sharing violation rather than a
    # useful message.
    if (Test-Path $BinPath) {
        try {
            Remove-Item -Force $BinPath
        } catch {
            Die "cannot replace $BinPath - close any running lookback and re-run"
        }
    }
    Copy-Item -Path $extracted.FullName -Destination $BinPath -Force
    Say "installed $BinPath"
} finally {
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
}

# --- 5. Path -----------------------------------------------------------------
# The user Path, not the machine one: no administrator rights, and nothing that
# affects anybody else who signs in.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$already = $userPath.Split(';') | Where-Object { $_ -eq $BinDir }
if (-not $already) {
    $updated = if ($userPath.TrimEnd(';')) { "$($userPath.TrimEnd(';'));$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    Warn "added $BinDir to your Path; open a new terminal to pick it up"
}
# This session, so the collection below and anything the user tries next work now
# rather than after a restart.
if (-not ($env:Path.Split(';') | Where-Object { $_ -eq $BinDir })) {
    $env:Path = "$($env:Path);$BinDir"
}

# --- 6. plugin ---------------------------------------------------------------
$pluginChanged = $false

function Installed-Version {
    # `claude plugin update` says "Checking for updates..." either way, which is
    # how somebody ends up with a new binary, old commands, and nothing saying so.
    $listing = & claude plugin list 2>$null
    if (-not $listing) { return $null }
    $found = $false
    foreach ($line in $listing) {
        if ($line -match [regex]::Escape($Plugin)) { $found = $true; continue }
        if ($found -and $line -match 'Version:\s*(\S+)') { return $Matches[1] }
    }
    $null
}

function Marketplace-Repo {
    # What Claude Code cached as this marketplace's source, read from its own file
    # rather than scraped out of `marketplace list`, whose output is for people.
    $home = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    $file = Join-Path $home 'plugins\known_marketplaces.json'
    if (-not (Test-Path $file)) { return $null }
    try {
        $document = Get-Content -Raw $file | ConvertFrom-Json
    } catch {
        return $null
    }
    $entry = $document.PSObject.Properties |
             Where-Object { $_.Name -eq $MarketplaceName } |
             Select-Object -First 1
    if (-not $entry) { return $null }
    try { $entry.Value.source.repo } catch { $null }
}

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Say 'installing the plugin'

    # An install made before the distribution repository was renamed still has
    # the old name cached, and keeps working only because GitHub redirects it.
    # Removing a marketplace uninstalls its plugins, so this runs before the
    # install below, which then puts the plugin back.
    $stored = Marketplace-Repo
    if ($stored -and $stored -ne $Market) {
        Warn "the marketplace points at $stored; re-pointing it at $Market"
        & claude plugin marketplace remove $MarketplaceName 2>$null
    }

    & claude plugin marketplace add $Market 2>$null
    if ($LASTEXITCODE -ne 0) { & claude plugin marketplace update $MarketplaceName 2>$null }

    $listing = & claude plugin list 2>$null
    $present = $listing -and ($listing -match "(^|[^-\w])$([regex]::Escape($Plugin))([^-\w]|$)")
    if ($present) {
        $before = Installed-Version
        & claude plugin update $Plugin 2>$null
        if ((Installed-Version) -ne $before) { $pluginChanged = $true }
    } else {
        & claude plugin install $Plugin 2>$null
        if ($LASTEXITCODE -eq 0) { $pluginChanged = $true }
        else { Warn "run: claude plugin install $Plugin" }
    }
} else {
    Warn "claude not found; then: claude plugin marketplace add $Market && claude plugin install $Plugin"
}

# --- 7. first collection -----------------------------------------------------
# Lookback says nothing until it has read the transcripts, and reading them is
# the slowest thing it does. Doing it now means the first question a user asks is
# answered immediately rather than after a minute of silence.
Say 'reading what Claude Code has already written'
& $BinPath collect
if ($LASTEXITCODE -ne 0) { Warn 'run `lookback collect` yourself; nothing else is needed' }

# Claude Code registers a plugin's skills when a session starts, so updating the
# plugin under an open session leaves it with the previous version's commands and
# nothing to say so.
if ($pluginChanged) {
    Say 'done. The binary is ready now; `lookback review` works in this terminal.'
    Warn 'the plugin changed - restart Claude Code to pick up its commands'
} else {
    Say 'done. Try `lookback review`, or /lookback:review inside Claude Code.'
}
