# TV-Kit: clean up an Android TV / Google TV and put the tv-home launcher on it, in one go.
#   1. finds the TV on the network and connects over ADB
#   2. backs everything up (every app's on/off state, all settings, the home screen app)
#   3. turns off ads, tracking, junk and the features you said you don't use; never uninstalls anything
#   4. installs the tv-home launcher with your dock and the nature screensaver, and makes it the home screen
#      (Google TV's home screen is put straight back if the new one doesn't open from the Home button)
#   5. takes screenshots from the TV after each step
# RESTORE.bat puts everything back.

. (Join-Path $PSScriptRoot 'common.ps1')
Start-Log 'tvkit'

# ---- David's answers (Nov 2026). Set one to $true to keep that feature on.
$KeepCasting       = $false   # Chromecast built-in and screen mirroring
$KeepGoogleHome    = $false   # Google TV's own home screen (profiles, Live tab, Home panel); off = tv-home replaces it
$KeepAmbient       = $false   # Ambient mode, Google's screensaver
$TurnOffUnused     = $true    # streaming apps that came with the TV and haven't been opened in 30 days
$NatureScreensaver = $true    # the launcher's nature photos as the screensaver
$FasterAnimations  = $true    # animations at half length, which makes the TV feel quicker
# Google Assistant and voice search, the remote, Play Store and Settings are never turned off.

$Repo          = 'Jitterzz/tv-home'
$LauncherPkg   = 'com.mihir.tvhome'
$LauncherHome  = 'com.mihir.tvhome/.MainActivity'
$LauncherDream = 'com.mihir.tvhome/.NatureDream'

# Ads, tracking and junk: turned off wherever they're on this TV.
$Junk = [ordered]@{
    'com.google.android.feedback'                         = 'Google feedback and bug reports'
    'android.autoinstalls.config.google.gtvpai'           = 'Google TV auto-installer (quietly installs promoted apps)'
    'com.google.android.tvrecommendations'                = 'Recommendation feeds for the old home screen'
    'com.google.android.leanbacklauncher.recommendations' = 'Recommendation feeds for the old home screen'
    'com.google.android.play.games'                       = 'Google Play Games'
    'com.google.android.videos'                           = 'Google TV store and promos (Play Movies)'
    'com.tcl.ttvs'                                        = 'TCL analytics service'
    'com.tcl.usercenter'                                  = 'TCL account and phone binding'
    'com.tcl.messagebox'                                  = 'TCL promo pop-ups'
    'com.tcl.esticker'                                    = 'TCL on-screen promo stickers'
    'com.tcl.partnercustomizer'                           = 'TCL partner promos'
    'com.tcl.channelplus'                                 = 'TCL Channel'
    'com.tcl.waterfall.overseas'                          = 'TCL content tab'
    'com.tcl.tv.tclhome_passive'                          = 'TCL home extras'
    'com.tcl.guard'                                       = 'TCL TV Guard cleaner'
    'com.tcl.notereminder'                                = 'TCL reminders'
    'com.tcl.hotelmenu'                                   = 'TCL hotel mode'
}
$Casting = [ordered]@{
    'com.google.android.apps.mediashell' = 'Chromecast built-in (casting from a phone)'
    'com.tcl.miracast'                   = 'TCL screen mirroring'
    'com.tcl.MultiScreenInteraction_TV'  = 'TCL T-Cast'
}
$Ambient = [ordered]@{
    'com.google.android.apps.tv.dreamx' = 'Ambient mode (Google screensaver with recommendations)'
}
# Google's home screens, setup app first: on Google TV it brings the home screen back if it's left on.
$StockHomes = [ordered]@{
    'com.google.android.tungsten.setupwraith' = 'Google TV setup app (takes over the Home button)'
    'com.google.android.apps.tv.launcherx'    = 'Google TV home screen (where the ads are)'
    'com.google.android.tvlauncher'           = 'Android TV home screen'
    'com.google.android.leanbacklauncher'     = 'Android TV home screen (older)'
}
# Streaming apps that often come with a TV. Only turned off if they came with it AND haven't been opened in 30 days.
$Streaming = [ordered]@{
    'com.google.android.youtube.tv'           = 'YouTube'
    'com.google.android.youtube.tvmusic'      = 'YouTube Music'
    'com.google.android.youtube.tvkids'       = 'YouTube Kids'
    'com.netflix.ninja'                       = 'Netflix'
    'com.amazon.amazonvideo.livingroom'       = 'Prime Video'
    'com.disney.disneyplus'                   = 'Disney+'
    'com.hulu.livingroomplus'                 = 'Hulu'
    'com.wbd.stream'                          = 'Max'
    'com.hbo.hbonow'                          = 'HBO Max'
    'com.peacocktv.peacockandroid'            = 'Peacock'
    'com.cbs.ott'                             = 'Paramount+'
    'com.spotify.tv.android'                  = 'Spotify'
    'com.apple.atve.androidtv.appletv'        = 'Apple TV'
    'tv.pluto.android'                        = 'Pluto TV'
    'com.tubitv'                              = 'Tubi'
    'com.sling'                               = 'Sling TV'
    'com.philo.philo.google'                  = 'Philo'
    'com.vudu.air'                            = 'Fandango at Home'
    'tv.twitch.android.app'                   = 'Twitch'
    'com.crunchyroll.crunchyroid'             = 'Crunchyroll'
    'com.plexapp.android'                     = 'Plex'
    'com.hungama.movies.tv'                   = 'Hungama'
    'tv.airtel.xstream.tvapp'                 = 'Airtel Xstream'
    'in.startv.hotstar'                       = 'Hotstar'
    'com.internet.tvbrowser'                  = 'TV Browser'
    'com.mxtech.videoplayer.television'       = 'MX Player'
}
# Never touched, whatever the lists above say.
$Never = @(
    'com.google.android.katniss', 'com.google.android.tv.remote.service', 'com.google.android.gms',
    'com.google.android.gsf', 'com.android.vending', 'com.android.tv.settings', 'com.android.systemui',
    'com.android.packageinstaller', 'com.google.android.packageinstaller', 'com.android.providers.settings',
    'com.google.android.tts', 'com.google.android.inputmethod.latin', 'com.google.android.leanback.ime', $LauncherPkg
)
# Well-known apps to fill the dock with when there isn't enough use to go on.
$Popular = @('com.google.android.youtube.tv', 'com.netflix.ninja', 'com.amazon.amazonvideo.livingroom',
             'com.disney.disneyplus', 'com.wbd.stream', 'com.hulu.livingroomplus', 'com.plexapp.android',
             'com.spotify.tv.android')

function NameOf {
    param([string]$Pkg)
    foreach ($table in @($Streaming, $Junk, $Casting, $Ambient, $StockHomes)) {
        if ($table.Contains($Pkg)) { return [string]$table[$Pkg] }
    }
    return $Pkg
}

function Get-LauncherApk {
    # tvhome.apk dropped next to TV-KIT.bat wins; otherwise the newest one GitHub built in David's fork.
    $local = Join-Path $script:Kit 'tvhome.apk'
    if (Test-Path -LiteralPath $local) { Ok 'using tvhome.apk from the TV-Kit folder'; return $local }
    $url = 'https://github.com/' + $Repo + '/releases/latest/download/tvhome.apk'
    $sizeText = ''
    try {
        $h = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 20
        $len = [string]$h.Headers['Content-Length']
        if ($len) { $sizeText = ' ({0:N1} MB)' -f ([double]$len / 1MB) }
    } catch { }
    Say ('   the launcher: tvhome.apk' + $sizeText + ', built by GitHub from your fork of tv-home')
    Say ('   from: ' + $url)
    if (-not (Confirm-Go 'Download it?')) { return $null }
    $dir = Join-Path $script:Kit 'downloads'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $out = Join-Path $dir 'tvhome.apk'
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 300
    } catch {
        Bad ('Download failed: ' + $_)
        return $null
    }
    return $out
}

function Select-Dock {
    # Up to 5 TV apps for the dock: the ones used most, then well-known ones. Enter keeps them; numbers pick others.
    param($Usage)
    $skip = @($LauncherPkg, 'com.android.tv.settings') + @($StockHomes.Keys)
    $apps = @(Get-TvApps | Where-Object { $skip -notcontains $_ })
    $ranked = @($apps | Where-Object { $Usage.Total.ContainsKey($_) -and $Usage.Total[$_] -gt 60 } |
                Sort-Object -Property @{ Expression = { $Usage.Total[$_] }; Descending = $true })
    $dock = @($ranked | Select-Object -First 5)
    foreach ($p in $Popular) { if ($dock.Count -lt 5 -and $apps -contains $p -and $dock -notcontains $p) { $dock += $p } }
    foreach ($p in $apps) { if ($dock.Count -lt 5 -and $dock -notcontains $p) { $dock += $p } }
    Say '   Dock, most used first:'
    foreach ($p in $dock) { Say ('      ' + (NameOf $p) + '   (' + $p + ')') }
    $pick = ([string](Read-Host '   Press Enter to keep this dock, or type C to choose the apps yourself')).Trim().ToUpper()
    if ($pick -ne 'C') { return $dock }
    for ($i = 0; $i -lt $apps.Count; $i++) { Say ('      [{0}] {1}   ({2})' -f ($i + 1), (NameOf $apps[$i]), $apps[$i]) }
    $nums = ([string](Read-Host '   Type up to 6 numbers in the order you want them, like 3 1 7')).Trim()
    $chosen = @()
    foreach ($n in ($nums -split '[ ,]+')) {
        $k = 0
        if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $apps.Count -and $chosen.Count -lt 6) {
            if ($chosen -notcontains $apps[$k - 1]) { $chosen += $apps[$k - 1] }
        }
    }
    if ($chosen.Count -eq 0) { return $dock }
    return $chosen
}

function Set-LauncherHome {
    # Makes the launcher the home screen. Turns Google's home screen (setup app first) off, presses Home, and checks it
    # opens the launcher, from Home and from inside an app. If not, everything it turned off goes straight back on.
    param([string[]]$TurnOff, [string]$StockHome)
    $said = (@(Invoke-TvShell ('cmd package set-home-activity --user 0 ' + $LauncherHome)) -join ' ')
    if ($said -notmatch 'Success') { [void](Invoke-TvShell ('cmd package set-home-activity ' + $LauncherHome)) }
    $touched = @()
    foreach ($p in $TurnOff) {
        if (Disable-TvPackage $p) { Ok ('off: ' + (NameOf $p)); $touched += $p } else { Warn ('could not turn off ' + $p) }
    }
    [void](Invoke-TvShell ('cmd package set-home-activity --user 0 ' + $LauncherHome))
    [void](Invoke-TvShell 'am force-stop com.android.tv.settings')
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    Start-Sleep -Seconds 4
    $front = Get-TvFront
    Get-TvShot 'tvkit-03-new-home'
    # The real test: Home from inside an app.
    [void](Invoke-TvShell 'am start -a android.settings.SETTINGS')
    Start-Sleep -Seconds 4
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    Start-Sleep -Seconds 4
    $front2 = Get-TvFront
    Get-TvShot 'tvkit-04-home-from-an-app'
    if (($front -like ($LauncherPkg + '/*')) -and ($front2 -like ($LauncherPkg + '/*'))) {
        Ok 'The Home button opens the new home screen, from Home and from inside an app.'
        return $true
    }
    Warn ('The Home button opened ' + $front2 + ' instead of the new home screen.')
    foreach ($p in $touched) { if (Enable-TvPackage $p) { Ok ('back on: ' + (NameOf $p)) } }
    if ($StockHome) {
        [void](Invoke-TvShell ('cmd package set-home-activity --user 0 ' + $StockHome))
        Ok ('home screen is ' + $StockHome + ' again')
    }
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    return $false
}

Write-Host ''
Write-Host 'TV-Kit: clean up the TV and give it the tv-home launcher' -ForegroundColor White
Write-Host 'Nothing gets uninstalled. Everything is backed up first, and RESTORE.bat puts it all back.' -ForegroundColor DarkGray

$turnedOff = @()
$failed = @()
$homeResult = 'not changed'
try {
    Step 'adb'
    if (-not (Initialize-Adb)) { exit 1 }

    Step 'Find and connect to the TV'
    $script:Serial = Connect-Tv
    if (-not $script:Serial) { Bad 'No TV connected. Nothing was changed.'; exit 1 }
    $info = Get-TvInfo
    Ok ('{0} {1}, Android {2} (API {3})' -f $info.Maker, $info.Model, $info.Release, $info.Sdk)
    $sdk = 0
    [void][int]::TryParse([string]$info.Sdk, [ref]$sdk)

    Step 'Back up everything first'
    $label = 'original'
    if (Test-Path -LiteralPath (Join-Path $script:StateDir 'original-backup.txt')) { $label = 'before-tvkit' }
    $bk = Backup-Tv $info $label
    $bkInfo = Read-KeyValues (Join-Path $bk 'backup-info.txt')
    Ok ('backup saved in ' + $bk)
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    Start-Sleep -Seconds 4
    Get-TvShot 'tvkit-01-before'

    Step 'Work out what to turn off'
    $enabled = @{}
    foreach ($p in @(Read-PackageFile (Join-Path $bk 'packages-enabled.txt'))) { $enabled[$p] = $true }
    $system = @{}
    foreach ($p in @(Read-PackageFile (Join-Path $bk 'packages-system.txt'))) { $system[$p] = $true }
    $plan = New-Object System.Collections.Generic.List[object]
    $planned = @{}
    $add = {
        param($pkg, $why, $group)
        if ($enabled.ContainsKey($pkg) -and ($Never -notcontains $pkg) -and -not $planned.ContainsKey($pkg)) {
            $planned[$pkg] = $true
            $plan.Add([pscustomobject]@{ Pkg = $pkg; Why = $why; Group = $group })
        }
    }
    foreach ($k in $Junk.Keys) { & $add $k $Junk[$k] 'Ads, tracking and junk' }
    if (-not $KeepCasting) { foreach ($k in $Casting.Keys) { & $add $k $Casting[$k] 'Features you said you don''t use' } }
    if (-not $KeepAmbient) { foreach ($k in $Ambient.Keys) { & $add $k $Ambient[$k] 'Features you said you don''t use' } }
    $usage = Get-TvUsage
    if ($TurnOffUnused) {
        $cut = [datetime]::MinValue
        if ($usage.Known) { $cut = $usage.Now.AddDays(-30) }
        foreach ($k in $Streaming.Keys) {
            if (-not $enabled.ContainsKey($k) -or -not $system.ContainsKey($k)) { continue }
            if ($usage.Known) {
                $used = $usage.Last.ContainsKey($k) -and ($usage.Last[$k] -gt $cut)
                if (-not $used) { & $add $k ($Streaming[$k] + ' (came with the TV, not opened in 30 days)') 'Unused apps that came with the TV' }
            } elseif (Confirm-Yes ('   Turn off ' + $Streaming[$k] + ', which came with the TV?')) {
                & $add $k ($Streaming[$k] + ' (came with the TV)') 'Unused apps that came with the TV'
            }
        }
    }
    $homesOff = @()
    if (-not $KeepGoogleHome) { foreach ($k in $StockHomes.Keys) { if ($enabled.ContainsKey($k)) { $homesOff += $k } } }

    Say ''
    Say 'TV-Kit will turn these off (never uninstall them):' 'White'
    foreach ($g in @($plan | ForEach-Object { $_.Group } | Select-Object -Unique)) {
        Say ('   ' + $g + ':')
        foreach ($item in @($plan | Where-Object { $_.Group -eq $g })) { Say ('      - ' + $item.Why) }
    }
    if ($plan.Count -eq 0) { Say '   (nothing from the lists is on this TV)' }
    if ($homesOff.Count -gt 0) {
        Say '   Once the new home screen is installed and working:'
        foreach ($k in $homesOff) { Say ('      - ' + (NameOf $k)) }
        Say '     (they go straight back on if the Home button doesn''t open the new home screen)'
    }
    Say 'Stays on: Google Assistant and voice search, the remote, Play Store, Settings and every other app.'
    if ($FasterAnimations) { Say 'Speed: animations at half length.' }
    if ($NatureScreensaver) { Say 'Screensaver: the launcher''s nature photos.' }
    if (-not (Confirm-Go 'Go ahead?')) { Bad 'Stopped. Nothing on the TV was changed.'; exit 0 }

    Step 'Turn off ads, tracking and junk'
    foreach ($item in $plan) {
        if (Disable-TvPackage $item.Pkg) { Ok ('off: ' + $item.Why); $turnedOff += $item.Pkg } else { Warn ('could not turn off ' + $item.Pkg); $failed += $item.Pkg }
    }
    if ($FasterAnimations) {
        foreach ($k in @('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale')) { [void](Set-TvSetting 'global' $k '0.5') }
        Ok 'animations at half length'
    }
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    Start-Sleep -Seconds 3
    Get-TvShot 'tvkit-02-after-cleanup'

    Step 'Install the tv-home launcher'
    $launcherOk = $false
    if ($sdk -gt 0 -and $sdk -lt 30) {
        Warn 'The launcher needs Android 11 or newer and this TV is older, so it was skipped. The clean-up still applies.'
    } else {
        $apk = Get-LauncherApk
        if ($apk) {
            $o = (@(Invoke-Tv -ArgList @('install', '-r', $apk)) -join ' ')
            if ($o -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
                Warn 'An older copy of the launcher, signed differently, is already on the TV.'
                if (Confirm-Go 'Replace it with the new one? (only the launcher; its dock is set again below)') {
                    [void](Invoke-Tv -ArgList @('uninstall', $LauncherPkg))
                    $o = (@(Invoke-Tv -ArgList @('install', '-r', $apk)) -join ' ')
                }
            }
            if ($o -match 'Success') {
                Ok 'launcher installed'
                Write-Utf8Text (Join-Path $script:StateDir 'launcher-package.txt') $LauncherPkg
                $launcherOk = $true
            } else {
                Bad ('Installing the launcher didn''t work: ' + $o)
            }
        }
    }

    if ($launcherOk) {
        # Its Wi-Fi pill shows the network's name, which Android only reveals to apps with location access.
        [void](Invoke-TvShell ('pm grant ' + $LauncherPkg + ' android.permission.ACCESS_FINE_LOCATION'))
        Step 'Your dock'
        $usage = Get-TvUsage
        $dock = @(Select-Dock $usage)
        [void](Invoke-TvShell ('am start -n ' + $LauncherHome + ' --es tvkit.dock ' + (ConvertTo-ShellQuoted ($dock -join ','))))
        Ok ('dock: ' + (($dock | ForEach-Object { NameOf $_ }) -join ', '))
        if ($NatureScreensaver) {
            [void](Set-TvSetting 'secure' 'screensaver_components' $LauncherDream)
            [void](Set-TvSetting 'secure' 'screensaver_enabled' '1')
            Ok 'screensaver: nature photos'
        }
        Step 'Make it the home screen'
        if (Set-LauncherHome $homesOff ([string]$bkInfo['home'])) {
            $homeResult = 'tv-home launcher'
            foreach ($k in $homesOff) { $turnedOff += $k }
            [void](Invoke-TvShell 'input keyevent KEYCODE_DPAD_DOWN')
            Start-Sleep -Milliseconds 700
            [void](Invoke-TvShell 'input keyevent KEYCODE_DPAD_DOWN')
            Start-Sleep -Seconds 2
            Get-TvShot 'tvkit-05-all-apps'
            [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
        } else {
            $homeResult = 'Google TV home kept (the launcher is in the apps list)'
        }
    }

    Step 'Check'
    $nowOff = @(Read-PackageLines @(Invoke-TvShell 'pm list packages -d'))
    $notOff = @($turnedOff | Where-Object { $nowOff -notcontains $_ })
    if ($notOff.Count -eq 0) { Ok ('all ' + $turnedOff.Count + ' turned off as planned') } else { Warn ('still on: ' + ($notOff -join ', ')) }
    Write-Utf8Lines (Join-Path $script:ResultsDir 'tvkit.txt') @(
        'TV-Kit result',
        ('finished=' + (Get-Date -Format s)),
        ('tv=' + $info.Maker + ' ' + $info.Model + ', Android ' + $info.Release + ' (API ' + $info.Sdk + ')'),
        ('backup=' + $bk),
        ('home=' + $homeResult),
        ('turned_off=' + ($turnedOff -join ',')),
        ('could_not=' + ($failed -join ',')),
        ('still_on=' + ($notOff -join ','))
    )
    Write-Utf8Lines (Join-Path $script:ResultsDir 'disabled-now.txt') $nowOff

    Step 'Pack the results for Claude'
    $send = Join-Path $script:Kit 'SEND-TO-CLAUDE.zip'
    $files = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $script:ShotsDir -Filter 'tvkit-*.jpg' -ErrorAction SilentlyContinue)) { $files += $f.FullName }
    foreach ($f in @('tvkit.txt', 'disabled-now.txt')) { $files += (Join-Path $script:ResultsDir $f) }
    foreach ($f in @('packages-all-names.txt', 'packages-system.txt', 'packages-disabled.txt', 'apps-tv.txt', 'home-candidates.txt', 'memory.txt')) {
        $p = Join-Path $bk $f
        if (Test-Path -LiteralPath $p) { $files += $p }
    }
    if (Test-Path -LiteralPath $send) { Remove-Item -LiteralPath $send -Force }
    Compress-Archive -LiteralPath $files -DestinationPath $send -CompressionLevel Optimal
    Ok ('made ' + $send + ' (screenshots and app lists; no settings, serial numbers or passwords)')

    Step 'Done'
    Say ('Turned off ' + $turnedOff.Count + ' apps and services. Home screen: ' + $homeResult + '.') 'Green'
    Say 'RESTORE.bat puts the TV back exactly as it was in the first backup.' 'Green'
    Say 'Attach SEND-TO-CLAUDE.zip in the Claude chat so the screenshots can be checked.' 'Green'
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $send + '"') } catch { }
} catch {
    Bad ('Something went wrong: ' + $_)
    Say ('Every command is in the log: ' + $script:LogFile)
    Say 'Anything already changed is written down, so RESTORE.bat can put it back.'
    exit 1
}
