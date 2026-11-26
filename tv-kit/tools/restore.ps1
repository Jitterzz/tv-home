# TV-Kit RESTORE: puts the TV back the way it was in a backup (the first one, unless you pick another).
#   - turns back on every app that is off now but was on in the backup
#   - puts back every setting TV-Kit changed (from state\changed-settings.txt)
#   - makes the original home screen the default again
#   - turns off the launcher TV-Kit installed (or removes it with -RemoveLauncher)
# Usage: RESTORE.bat                       (back to the original backup)
#        RESTORE.bat -Backup "backups\<folder>"
#        RESTORE.bat -RemoveLauncher       (also delete the launcher)

param(
    [string]$Backup = '',
    [switch]$RemoveLauncher
)

. (Join-Path $PSScriptRoot 'common.ps1')
Start-Log 'restore'

Write-Host ''
Write-Host 'TV-Kit  RESTORE: put the TV back the way it was' -ForegroundColor White
Write-Host 'Turns apps back on, puts settings back and brings back the original home screen.' -ForegroundColor DarkGray

try {
    if (-not $Backup) {
        $origFile = Join-Path $script:StateDir 'original-backup.txt'
        if (Test-Path -LiteralPath $origFile) { $Backup = ([IO.File]::ReadAllText($origFile)).Trim() }
    }
    if ($Backup -and -not [IO.Path]::IsPathRooted($Backup)) { $Backup = Join-Path $script:Kit $Backup }
    if (-not $Backup -or -not (Test-Path -LiteralPath (Join-Path $Backup 'packages-all-names.txt'))) {
        Bad 'No backup found to restore from, so there is nothing to put back. (TV-KIT.bat makes one before changing anything.)'
        exit 1
    }
    Say ('Backup: ' + $Backup)
    $bk = Read-KeyValues (Join-Path $Backup 'backup-info.txt')

    Step 'adb'
    if (-not (Initialize-Adb)) { exit 1 }

    Step 'Connect to the TV'
    $script:Serial = Connect-Tv
    if (-not $script:Serial) { Bad 'No TV connected. Nothing was changed.'; exit 1 }
    $info = Get-TvInfo
    Ok ($info.Maker + ' ' + $info.Model)
    if ($bk['serialno'] -and $info.SerialNo -and ($bk['serialno'] -ne $info.SerialNo)) {
        Warn ('This backup was made on a different TV (' + $bk['model'] + ').')
        if (-not (Confirm-Yes 'Restore it to this TV anyway?')) { exit 1 }
    }

    Step 'Turn apps back on'
    $knownSet = @{}
    foreach ($p in @(Read-PackageFile (Join-Path $Backup 'packages-all-names.txt'))) { $knownSet[$p] = $true }
    $wasOffSet = @{}
    foreach ($p in @(Read-PackageFile (Join-Path $Backup 'packages-disabled.txt'))) { $wasOffSet[$p] = $true }
    $nowOff = @(Read-PackageLines @(Invoke-TvShell 'pm list packages -d'))
    $turnedOn = 0
    $problems = 0
    foreach ($p in $nowOff) {
        if (-not $knownSet.ContainsKey($p)) { continue }
        if ($wasOffSet.ContainsKey($p)) { continue }
        $o = (@(Invoke-TvShell ('pm enable --user 0 ' + $p)) -join ' ')
        if ($o -match 'new state: enabled') { Ok ('on again: ' + $p); $turnedOn++ } else { Warn ($p + ': ' + $o); $problems++ }
    }
    if ($turnedOn -eq 0 -and $problems -eq 0) { Ok 'Every app is already on/off the way it was.' }

    Step 'Put changed settings back'
    $changedFile = Join-Path $script:StateDir 'changed-settings.txt'
    $restoredSettings = 0
    if (Test-Path -LiteralPath $changedFile) {
        $done = @{}
        foreach ($line in [IO.File]::ReadAllLines($changedFile)) {
            $parts = $line.Split("`t")
            if ($parts.Count -lt 2) { continue }
            $ns = $parts[0].Trim()
            $key = $parts[1].Trim()
            if ($ns -notmatch '^(global|secure|system)$' -or $key -notmatch '^[A-Za-z0-9_\.\-]+$') { continue }
            if ($done.ContainsKey($ns + '/' + $key)) { continue }
            $done[$ns + '/' + $key] = $true
            $old = Get-BackupSetting $Backup $ns $key
            if ($null -eq $old) {
                [void](Invoke-TvShell ('settings delete ' + $ns + ' ' + $key))
                Ok ($ns + '/' + $key + ' cleared (it was not set before)')
            } else {
                [void](Invoke-TvShell ('settings put ' + $ns + ' ' + $key + ' ' + (ConvertTo-ShellQuoted $old)))
                Ok ($ns + '/' + $key + ' = ' + $old)
            }
            $restoredSettings++
        }
    }
    if ($restoredSettings -eq 0) { Ok 'No settings needed putting back.' }

    Step 'Original home screen'
    $homeApp = [string]$bk['home']
    if ($homeApp -and ($homeApp -match '^[A-Za-z0-9_\.]+/[A-Za-z0-9_\.\$]+$') -and ($homeApp -notlike 'android/*')) {
        $homePkg = $homeApp.Split('/')[0]
        [void](Invoke-TvShell ('cmd package set-home-activity ' + $homeApp))
        [void](Invoke-TvShell ('cmd role add-role-holder android.app.role.HOME ' + $homePkg))
        Ok ('default home screen: ' + $homeApp)
    } else {
        Ok 'The backup has no single default home app, so that is left as it is.'
    }
    $launcherPkg = ''
    $lf = Join-Path $script:StateDir 'launcher-package.txt'
    if (Test-Path -LiteralPath $lf) { $launcherPkg = ([IO.File]::ReadAllText($lf)).Trim() }
    if ($launcherPkg -and ($launcherPkg -match '^[A-Za-z0-9_\.]+$')) {
        $present = @(Read-PackageLines @(Invoke-TvShell ('pm list packages ' + $launcherPkg))) -contains $launcherPkg
        if ($present) {
            if ($RemoveLauncher) {
                $o = (@(Invoke-Tv -ArgList @('uninstall', $launcherPkg)) -join ' ')
                Ok ('removed the launcher: ' + $o)
            } else {
                [void](Invoke-TvShell ('pm disable-user --user 0 ' + $launcherPkg))
                Ok ('turned off the launcher (' + $launcherPkg + '). RESTORE.bat -RemoveLauncher deletes it.')
            }
        }
    }

    Step 'Check on the TV'
    [void](Invoke-TvShell 'input keyevent KEYCODE_HOME')
    Start-Sleep -Seconds 4
    $shot = 'restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Get-TvShot $shot

    Write-Utf8Lines (Join-Path $script:ResultsDir 'restore.txt') @(
        'TV-Kit restore result',
        ('finished=' + (Get-Date -Format s)),
        ('backup=' + $Backup),
        ('apps_turned_back_on=' + $turnedOn),
        ('problems=' + $problems),
        ('settings_put_back=' + $restoredSettings),
        ('home=' + $homeApp),
        ('screenshot=shots\' + $shot + '.png')
    )
    Step 'Done'
    Say ('Restore finished: {0} app(s) turned back on, {1} setting(s) put back.' -f $turnedOn, $restoredSettings) 'Green'
    if ($problems -gt 0) { Say ('{0} app(s) could not be turned back on; see the lines marked !! above.' -f $problems) 'Yellow' }
} catch {
    Bad ('Something went wrong: ' + $_)
    Say ('Every command is in the log: ' + $script:LogFile)
    exit 1
}
