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

if (-not $archiveUrl) {
    # The installer reaches the distribution repository before the Windows binary
    # does. That is deliberate — the build works and the suite has never run on
    # Windows, so the artifact is held back — but "no <file> in <version>" reads
    # like a broken release, and the first thing a Windows user would do is report
    # one. Say which of the two it is.
    $shipped = $release.assets |
               Where-Object { $_.name -like "$Product-*" } |
               ForEach-Object { $_.name }
    if ($shipped) {
        Write-Host ""
        Write-Host " Windows is not published yet." -ForegroundColor Yellow
        Write-Host ""
        Write-Host " $version is a complete release - it just has no Windows binary in it."
        Write-Host " The build works and this installer works; what is missing is a test"
        Write-Host " run on Windows. The differences that matter there are the quiet kind"
        Write-Host " (a report covering the whole machine when you asked about one"
        Write-Host " repository), so it is held back rather than shipped untested."
        Write-Host ""
        Write-Host " Watch https://github.com/$Repo/releases for a"
        Write-Host " $Product-<version>-$target.zip asset, and say so on the repository if"
        Write-Host " you are waiting - knowing somebody is moves it."
        Write-Host ""
        exit 1
    }
    Die "no $archiveName in $version"
}
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
#
# `$env:Path` rather than `$env:PATH` is correct on Windows, where environment
# variables are case-insensitive — and is `$null` on Unix, where PowerShell's
# environment provider is not. That matters only because running this script on a
# Mac is how anybody here checks it at all: without the fallback it stops at this
# line, after the download and both hash checks and before the plugin step, on a
# difference that does not exist on the platform it ships to.
$sessionPath = if ($env:Path) { $env:Path } elseif ($env:PATH) { $env:PATH } else { '' }
if (-not ($sessionPath.Split(';') | Where-Object { $_ -eq $BinDir })) {
    $env:Path = "${sessionPath};${BinDir}"
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
    # Not `$home`: PowerShell's `$HOME` is an automatic variable, ReadOnly and
    # AllScope, on every platform — and variable names are case-insensitive, so
    # assigning to `$home` throws "Cannot overwrite variable HOME because it is
    # read-only or constant". That is a hard failure at the plugin step, on
    # Windows, for every user.
    $claudeHome = if ($env:CLAUDE_CONFIG_DIR) {
        $env:CLAUDE_CONFIG_DIR
    } else {
        Join-Path $env:USERPROFILE '.claude'
    }
    $file = Join-Path $claudeHome 'plugins\known_marketplaces.json'
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

    # Let Claude Code keep the plugin current by itself. `autoUpdate` is a
    # per-marketplace flag in `extraKnownMarketplaces` and `marketplace add` does
    # not set it, so every install so far has been one somebody had to remember to
    # update. This is the host's own mechanism: its setting, its schedule, and
    # removing the line turns it off.
    $claudeHome = if ($env:CLAUDE_CONFIG_DIR) {
        $env:CLAUDE_CONFIG_DIR
    } else {
        Join-Path $env:USERPROFILE '.claude'
    }
    $settingsPath = Join-Path $claudeHome 'settings.json'
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json
            $entry = $settings.extraKnownMarketplaces.PSObject.Properties |
                     Where-Object { $_.Name -eq $MarketplaceName } |
                     Select-Object -First 1
            if ($entry -and -not $entry.Value.autoUpdate) {
                $entry.Value | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $true -Force
                $settings | ConvertTo-Json -Depth 32 | Set-Content -Path $settingsPath
                Say 'Claude Code will keep the plugin up to date by itself'
            }
        } catch {
            # A settings file this cannot parse is not one to rewrite blind.
        }
    }

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

# --- 6b. the OMP plugin ------------------------------------------------------
# This block did not exist on either installer, and that is why OMP drifted: the
# Claude plugin was updated every run and OMP's was left wherever it was first
# put. `install --force` rather than `upgrade`, because `omp plugin upgrade`
# reports everything up to date with an older version installed and the current
# one in its own freshly-refreshed cache.
function Omp-Registry {
    # Where OMP keeps its own marketplace registry. Resolved the way omp 18.3.5
    # was *observed* to resolve it, by planting a marketplace with the real
    # binary under a sandboxed home and finding which `marketplaces.json` it
    # wrote (2026-10-02, re-measured 2026-10-03):
    #
    #   neither                           ->  <home>\.omp
    #   PI_CONFIG_DIR=custom-omp          ->  <home>\custom-omp
    #   PI_PROFILE=work                   ->  <home>\.omp\profiles\work
    #   PI_CONFIG_DIR + PI_PROFILE        ->  <home>\custom-omp\profiles\work
    #   XDG_DATA_HOME with omp\ present   ->  <XDG_DATA_HOME>\omp
    #   the same, plus PI_CONFIG_DIR      ->  <XDG_DATA_HOME>\omp  (PI_CONFIG_DIR
    #                                                               is ignored)
    #   the same, plus PI_PROFILE=work    ->  <home>\.omp\profiles\work  (XDG is
    #                                                                     ignored)
    #
    # Three things that are easy to get wrong, each measured rather than
    # reasoned about, and kept in step with install.sh's omp_registry:
    #
    #  1. The XDG rule is real and is conditional on the directory existing. An
    #     earlier pass recorded the opposite from an experiment that created
    #     XDG_DATA_HOME but not XDG_DATA_HOME\omp, so the condition was false
    #     and the fallback got written down as the rule. `logs\` is the trap: it
    #     stays in the config directory even when the registry moves to the XDG
    #     data directory, so watching the logs measures the wrong thing.
    #  2. The XDG branch applies only when no profile is selected, and when it
    #     applies it beats PI_CONFIG_DIR.
    #  3. OMP_PROFILE wins over PI_PROFILE by being *set*, not by being
    #     non-empty: `OMP_PROFILE=` with `PI_PROFILE=frompi` resolves to the
    #     base directory. Values are trimmed, and the literal `default` means
    #     the base directory rather than profiles\default.
    #
    # PI_CONFIG_DIR is a directory *name* joined under home, not a path.
    #
    # Home is %USERPROFILE%, not $HOME: $HOME is normally unset on Windows, and
    # PowerShell's $HOME is read-only besides — see Marketplace-Repo above.
    #
    # `OMP_CONFIG_DIR`, which this function used to read, is the one name that
    # really is invented: it occurs nowhere in the omp binary and setting it
    # changes nothing. No fallback is kept for it, and release.test.sh greps for
    # exactly that.

    # `Test-Path env:` rather than a truthiness test, because set-and-empty is
    # a different answer from unset here — point (3).
    $profileName = if (Test-Path env:OMP_PROFILE) {
        $env:OMP_PROFILE
    } elseif (Test-Path env:PI_PROFILE) {
        $env:PI_PROFILE
    } else {
        ''
    }
    if ($null -eq $profileName) { $profileName = '' }
    $profileName = $profileName.Trim()
    if ($profileName -eq 'default') { $profileName = '' }

    $configDir = if ($env:PI_CONFIG_DIR) { $env:PI_CONFIG_DIR } else { '.omp' }
    $xdgOmp = if ($env:XDG_DATA_HOME) { Join-Path $env:XDG_DATA_HOME 'omp' } else { $null }

    if (-not $profileName -and $xdgOmp -and (Test-Path -LiteralPath $xdgOmp -PathType Container)) {
        return Join-Path $xdgOmp 'marketplaces.json'
    }

    $base = Join-Path $env:USERPROFILE $configDir
    $dir = if ($profileName) {
        Join-Path (Join-Path $base 'profiles') $profileName
    } else {
        $base
    }
    Join-Path $dir 'marketplaces.json'
}

function Omp-Marketplace-Repo {
    $file = Omp-Registry
    if (-not (Test-Path $file)) { return $null }
    try {
        $document = Get-Content -Raw $file | ConvertFrom-Json
        # Inside the try, because `Set-StrictMode -Version Latest` makes reading a
        # property that is not there a *terminating* error, not `$null`. A registry
        # whose top level has no `marketplaces` — an older schema, a half-written
        # file — would otherwise kill the installer at the omp step rather than
        # falling through to "nothing cached". Verified under pwsh 7.6.6:
        # "The property 'marketplaces' cannot be found on this object."
        $entry = $document.marketplaces |
                 Where-Object { $_.name -eq $MarketplaceName } |
                 Select-Object -First 1
        # `$entry.sourceUri` is inside the try for the same reason the
        # `marketplaces` read above is: under `Set-StrictMode -Version Latest`
        # plus `$ErrorActionPreference = 'Stop'`, reading a property an object
        # does not have is a *terminating* error. A registry entry that exists
        # without a `sourceUri` — a partial write, a schema change — would
        # otherwise kill the installer at the omp step instead of falling
        # through to "nothing cached".
        if ($entry) { return $entry.sourceUri }
        return $null
    } catch {
        return $null
    }
}

function Omp-Installed-Version {
    # The counterpart of install.sh's omp_installed_version, and new on this
    # side: the PowerShell installer reported nothing at all about the OMP
    # plugin, while install.sh had a version reader that never worked (SC2259).
    # Both now answer, so both can report a transition.
    #
    # `omp plugin list --json` prints {npm: [...], marketplace: [{id, entries:
    # [{version}]}]}. `&` hands back one string per line, and Windows
    # PowerShell 5.1's ConvertFrom-Json wants a single document, so join first.
    $listing = (& omp plugin list --json 2>$null) -join "`n"
    if (-not $listing) { return $null }
    try {
        $document = $listing | ConvertFrom-Json
    } catch {
        return $null
    }
    # Wrapped, like Marketplace-Repo's own property read above:
    # `Set-StrictMode -Version Latest` makes a reference to a property an object
    # does not have a terminating error, and a listing from a different omp
    # version is not something to fail an install over. Not knowing the version
    # is answered as $null, which the caller reports as a warning.
    try {
        $plugin = $document.marketplace | Where-Object { $_.id -eq $Plugin } | Select-Object -First 1
        if (-not $plugin) { return $null }
        $entry = $plugin.entries | Select-Object -First 1
        if ($entry) { return $entry.version }
        return $null
    } catch {
        return $null
    }
}

if (Get-Command omp -ErrorAction SilentlyContinue) {
    Say 'installing the OMP plugin'

    # The same rename repair as above. OMP keeps its registry in
    # ~/.omp/marketplaces.json, which the Claude-side fix never touched.
    $ompStored = Omp-Marketplace-Repo
    if ($ompStored -and $ompStored -ne $Market) {
        Warn "OMP's marketplace points at $ompStored; re-pointing it at $Market"
        & omp plugin marketplace remove $MarketplaceName 2>$null
    }

    # Whether the marketplace was actually refreshed, which is what makes a
    # later "already current" a claim about the published release rather than a
    # claim about omp's cache. `add` failing is the ordinary path — the name is
    # already registered — so `update` is the one that has to succeed then.
    & omp plugin marketplace add $Market 2>$null
    if ($LASTEXITCODE -ne 0) { & omp plugin marketplace update $MarketplaceName 2>$null }
    $ompRefreshed = $LASTEXITCODE -eq 0
    if (-not $ompRefreshed) {
        Warn "could not refresh OMP's marketplace; the install below can only use what it has cached"
    }

    # Always report the outcome, as install.sh now does. Silence was the
    # symptom: this side printed nothing whatever happened.
    $ompBefore = Omp-Installed-Version
    & omp plugin install $Plugin --force 2>$null
    if ($LASTEXITCODE -ne 0) {
        Warn "run: omp plugin install $Plugin --force"
    } else {
        $ompAfter = Omp-Installed-Version
        if (-not $ompAfter) {
            Warn "OMP installed $Plugin but reported no version for it"
        } elseif ($ompAfter -ne $ompBefore) {
            $from = if ($ompBefore) { $ompBefore } else { 'none' }
            Say "OMP plugin $from -> $ompAfter"
        } elseif ($ompRefreshed) {
            Say "OMP plugin $ompAfter, already current"
        } else {
            # Equality proves *unchanged*, not *current*. With both marketplace
            # operations failed, a forced install can still succeed from cached
            # files and leave the version where it was — which is how an install
            # reported "already current" while sitting releases behind the
            # marketplace it could not reach.
            Warn "OMP plugin $ompAfter unchanged, and its marketplace could not be refreshed, so whether that is the current release is unknown"
        }
    }
}

# --- 7. first collection -----------------------------------------------------
# Lookback says nothing until it has read the transcripts, and reading them is
# the slowest thing it does. Doing it now means the first question a user asks is
# answered immediately rather than after a minute of silence.
Say 'reading what Claude Code has already written'
# `|| warn` in install.sh; a try/catch here, and it is not decoration.
# `$ErrorActionPreference = 'Stop'` makes a *failure to launch* a terminating
# error, so anything that stops the binary starting — a policy block, an
# antivirus quarantine, a half-written file — kills the installer at its last
# step with a stack trace. The install has already succeeded by this point: the
# binary is placed and verified and the plugin is in. Collection is a head start,
# not part of installing, so failing it must not look like a failed install.
try {
    & $BinPath collect
    if ($LASTEXITCODE -ne 0) {
        Warn 'run `lookback collect` yourself; nothing else is needed'
    }
} catch {
    Warn "could not run ${BinPath}: $($_.Exception.Message)"
    Warn 'the install is complete; run `lookback collect` yourself'
}

# Claude Code registers a plugin's skills when a session starts, so updating the
# plugin under an open session leaves it with the previous version's commands and
# nothing to say so.
if ($pluginChanged) {
    Say 'done. The binary is ready now; `lookback review` works in this terminal.'
    Warn 'the plugin changed - restart Claude Code to pick up its commands'
} else {
    Say 'done. Try `lookback review`, or /lookback:review inside Claude Code.'
}
