# TV-Kit shared helpers. Works in Windows PowerShell 5.1 and PowerShell 7.
# Open source (MIT). TV-Kit never uninstalls anything that came with the TV:
# apps are only turned off ("disabled"), and every step backs up first.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
$env:ADB_MDNS_OPENSCREEN = '1'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Kit        = Split-Path -Parent $PSScriptRoot
$script:StateDir   = Join-Path $script:Kit 'state'
$script:ShotsDir   = Join-Path $script:Kit 'shots'
$script:LogsDir    = Join-Path $script:Kit 'logs'
$script:BackupsDir = Join-Path $script:Kit 'backups'
$script:ResultsDir = Join-Path $script:Kit 'results'
foreach ($dir in @($script:StateDir, $script:ShotsDir, $script:LogsDir, $script:BackupsDir, $script:ResultsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

$script:Adb     = $null
$script:Serial  = $null
$script:LogFile = $null
$script:AdbExit = 0
$script:Utf8    = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------- files, log, console

function Write-Utf8Lines {
    param([string]$Path, [object[]]$Lines)
    if ($null -eq $Lines) { $Lines = @() }
    [IO.File]::WriteAllLines($Path, [string[]]$Lines, $script:Utf8)
}

function Write-Utf8Text {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
}

function Start-Log {
    param([string]$Name)
    $script:LogFile = Join-Path $script:LogsDir ('{0}-{1}.log' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Utf8Text $script:LogFile ("TV-Kit {0} - {1}`r`n" -f $Name, (Get-Date -Format s))
}

function Write-Log {
    param([string]$Text)
    if ($script:LogFile) { [IO.File]::AppendAllText($script:LogFile, $Text + "`r`n", $script:Utf8) }
}

function Say {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    Write-Log $Text
}
function Step { param([string]$Text) Write-Host ''; Say ('== ' + $Text) 'Cyan' }
function Ok   { param([string]$Text) Say ('   OK  ' + $Text) 'Green' }
function Warn { param([string]$Text) Say ('   !!  ' + $Text) 'Yellow' }
function Bad  { param([string]$Text) Say ('   XX  ' + $Text) 'Red' }

function Confirm-Yes {
    param([string]$Question)
    $answer = [string](Read-Host ($Question + ' (y/N)'))
    Write-Log ('? ' + $Question + ' -> ' + $answer)
    return ($answer -match '^\s*(y|yes)\s*$')
}

function Read-KeyValues {
    param([string]$Path)
    $table = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $table[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
        }
    }
    return $table
}

function Select-FromList {
    param([object[]]$Items, [string]$Prompt)
    for ($i = 0; $i -lt $Items.Count; $i++) { Say ('   [{0}] {1}' -f ($i + 1), $Items[$i].Label) }
    $pick = [string](Read-Host $Prompt)
    $n = 0
    if ([int]::TryParse($pick.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) { return $Items[$n - 1] }
    return $null
}

# ---------------------------------------------------------------- adb

function Invoke-AdbRaw {
    # Runs adb with exactly these arguments. Returns the output lines as strings.
    param([string[]]$ArgList)
    Write-Log ('> adb ' + ($ArgList -join ' '))
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @()
    try {
        $out = @(& $script:Adb @ArgList 2>&1 | ForEach-Object { [string]$_ })
        $script:AdbExit = $LASTEXITCODE
    } catch {
        $out = @([string]$_)
        $script:AdbExit = 1
    } finally {
        $ErrorActionPreference = $old
    }
    if ($out.Count -le 6) { foreach ($l in $out) { Write-Log ('  ' + $l) } } else { Write-Log ('  (' + $out.Count + ' lines)') }
    return $out
}

function Invoke-Tv {
    # adb aimed at the chosen TV.
    param([string[]]$ArgList)
    $list = @()
    if ($script:Serial) { $list += @('-s', $script:Serial) }
    $list += $ArgList
    return (Invoke-AdbRaw -ArgList $list)
}

function Invoke-TvShell {
    param([string]$Command)
    return (Invoke-Tv -ArgList @('shell', $Command))
}

function Find-Adb {
    $candidates = New-Object System.Collections.Generic.List[string]
    $cmd = Get-Command 'adb.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $candidates.Add([string]$cmd.Path) }
    $candidates.Add((Join-Path $script:Kit 'platform-tools\adb.exe'))
    if ($env:ANDROID_HOME)     { $candidates.Add((Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe')) }
    if ($env:ANDROID_SDK_ROOT) { $candidates.Add((Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe')) }
    if ($env:LOCALAPPDATA)     { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')) }
    $candidates.Add('C:\platform-tools\adb.exe')
    $candidates.Add('C:\adb\adb.exe')
    if ($env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'platform-tools\adb.exe'))
        $candidates.Add((Join-Path $env:USERPROFILE 'Downloads\platform-tools\adb.exe'))
        $candidates.Add((Join-Path $env:USERPROFILE 'Desktop\platform-tools\adb.exe'))
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Install-PlatformTools {
    $url = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
    $sizeText = 'about 7 MB'
    try {
        $head = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 20
        $len = [string]$head.Headers['Content-Length']
        if ($len) { $sizeText = '{0:N1} MB' -f ([double]$len / 1MB) }
    } catch { }
    Say ''
    Say 'adb (Google''s Android platform-tools) is not on this PC. TV-Kit can download the official copy:' 'Yellow'
    Say ('   file:   platform-tools-latest-windows.zip (' + $sizeText + ')')
    Say ('   from:   ' + $url)
    Say ('   into:   ' + (Join-Path $script:Kit 'platform-tools') + '   (nothing gets installed on Windows)')
    Say '   terms:  Google''s Android SDK Platform-Tools terms, https://developer.android.com/studio/releases/platform-tools'
    if (-not (Confirm-Yes 'Download it and agree to those terms?')) { return $null }
    $zip = Join-Path $env:TEMP 'tvkit-platform-tools.zip'
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 300
        Expand-Archive -LiteralPath $zip -DestinationPath $script:Kit -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    } catch {
        Bad ('Download failed: ' + $_)
        return $null
    }
    $adb = Join-Path $script:Kit 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adb) { return $adb }
    return $null
}

function Initialize-Adb {
    $script:Adb = Find-Adb
    if (-not $script:Adb) { $script:Adb = Install-PlatformTools }
    if (-not $script:Adb) { Bad 'adb is needed to talk to the TV. Nothing was changed.'; return $false }
    $ver = @(Invoke-AdbRaw -ArgList @('version'))
    $first = ''
    if ($ver.Count -gt 0) { $first = $ver[0] }
    Ok ($script:Adb + '   ' + $first)
    [void](Invoke-AdbRaw -ArgList @('start-server'))
    return $true
}

# ---------------------------------------------------------------- finding the TV

function Get-LocalNet {
    # The PC's own address on the home network (the adapter with a default gateway).
    $best = $null
    $bestScore = -1
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($ni.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        $type = [string]$ni.NetworkInterfaceType
        if ($type -eq 'Loopback' -or $type -eq 'Tunnel') { continue }
        $props = $ni.GetIPProperties()
        $gw = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $_.Address.ToString() -ne '0.0.0.0' })
        if ($gw.Count -eq 0) { continue }
        foreach ($ua in $props.UnicastAddresses) {
            if ($ua.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
            $ip = $ua.Address.ToString()
            if ($ip -like '169.254.*') { continue }
            $prefix = 24
            try {
                $bits = 0
                foreach ($b in $ua.IPv4Mask.GetAddressBytes()) { $bits += ([Convert]::ToString([int]$b, 2) -replace '0', '').Length }
                if ($bits -gt 0) { $prefix = $bits }
            } catch { $prefix = 24 }
            $score = 1
            if ($type -match 'Ethernet|Wireless') { $score = 3 }
            if ($ni.Description -match 'Virtual|Hyper-V|VMware|VirtualBox|VPN|TAP|WireGuard|Tailscale|ZeroTier') { $score = 0 }
            if ($score -gt $bestScore) {
                $bestScore = $score
                $best = [pscustomobject]@{ Ip = $ip; Prefix = $prefix; Name = $ni.Name; Gateway = $gw[0].Address.ToString() }
            }
        }
    }
    return $best
}

function Get-SubnetHosts {
    # Every other address on the PC's network (only the PC's own /24 if the network is bigger than /22).
    param([string]$Ip, [int]$Prefix)
    if ($Prefix -lt 22 -or $Prefix -gt 30) { $Prefix = 24 }
    $b = ([Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    [int64]$n = ([int64]$b[0] * 16777216) + ([int64]$b[1] * 65536) + ([int64]$b[2] * 256) + [int64]$b[3]
    [int64]$size = [int64][Math]::Pow(2, 32 - $Prefix)
    [int64]$net = $n - ($n % $size)
    $hosts = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt ($size - 1); $i++) {
        [int64]$h = $net + $i
        if ($h -eq $n) { continue }
        $hosts.Add(('{0}.{1}.{2}.{3}' -f [int](($h -shr 24) -band 255), [int](($h -shr 16) -band 255), [int](($h -shr 8) -band 255), [int]($h -band 255)))
    }
    return $hosts.ToArray()
}

function Test-TcpPort {
    # Which of these hosts accept a TCP connection on this port (checked 256 at a time, in parallel).
    param([string[]]$Hosts, [int]$Port, [int]$TimeoutMs = 1200)
    $open = New-Object System.Collections.Generic.List[string]
    for ($start = 0; $start -lt $Hosts.Count; $start += 256) {
        $end = [Math]::Min($start + 255, $Hosts.Count - 1)
        $batch = @()
        for ($i = $start; $i -le $end; $i++) {
            $client = New-Object System.Net.Sockets.TcpClient
            $task = $null
            try { $task = $client.ConnectAsync($Hosts[$i], $Port) } catch { }
            $batch += [pscustomobject]@{ Ip = $Hosts[$i]; Client = $client; Task = $task }
        }
        $tasks = @($batch | Where-Object { $null -ne $_.Task } | ForEach-Object { $_.Task })
        if ($tasks.Count -gt 0) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks, $TimeoutMs) } catch { }
        }
        foreach ($item in $batch) {
            try {
                if ($item.Task -and $item.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and $item.Client.Connected) { $open.Add($item.Ip) }
            } catch { }
            try { $item.Client.Close() } catch { }
        }
    }
    return $open.ToArray()
}

function Find-SsdpDevices {
    # Asks the network "who is a TV / cast device?" so the TV can be shown by its name.
    param([string]$LocalIp)
    $found = @{}
    $udp = $null
    try {
        $udp = New-Object System.Net.Sockets.UdpClient((New-Object System.Net.IPEndPoint([Net.IPAddress]::Parse($LocalIp), 0)))
        $group = New-Object System.Net.IPEndPoint([Net.IPAddress]::Parse('239.255.255.250'), 1900)
        foreach ($st in @('urn:dial-multiscreen-org:service:dial:1', 'roku:ecp', 'urn:schemas-upnp-org:device:MediaRenderer:1')) {
            $msg = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: $st`r`n`r`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($msg)
            [void]$udp.Send($bytes, $bytes.Length, $group)
        }
        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline) {
            if ($udp.Available -gt 0) {
                $remote = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any, 0)
                $data = $udp.Receive([ref]$remote)
                $text = [Text.Encoding]::ASCII.GetString($data)
                $m = [regex]::Match($text, '(?im)^LOCATION:\s*(\S+)')
                if ($m.Success) {
                    $ip = $remote.Address.ToString()
                    if (-not $found.ContainsKey($ip)) { $found[$ip] = $m.Groups[1].Value }
                }
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {
        Write-Log ('ssdp: ' + $_)
    } finally {
        if ($udp) { $udp.Close() }
    }
    $list = @()
    foreach ($ip in @($found.Keys)) {
        $name = ''; $model = ''; $maker = ''
        try {
            $resp = Invoke-WebRequest -Uri $found[$ip] -UseBasicParsing -TimeoutSec 3
            $content = $resp.Content
            if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
            [xml]$x = [string]$content
            $dev = $x.root.device
            $name = [string]$dev.friendlyName
            $model = [string]$dev.modelName
            $maker = [string]$dev.manufacturer
        } catch { }
        $list += [pscustomobject]@{ Ip = $ip; Name = $name; Model = $model; Maker = $maker }
    }
    return $list
}

function Get-AdbMdns {
    $rows = @()
    foreach ($line in @(Invoke-AdbRaw -ArgList @('mdns', 'services'))) {
        $m = [regex]::Match([string]$line, '^(\S+)\s+(_adb[\w\-\.]*)\s+(\d{1,3}(?:\.\d{1,3}){3}):(\d+)')
        if ($m.Success) {
            $rows += [pscustomobject]@{ Name = $m.Groups[1].Value; Type = $m.Groups[2].Value.TrimEnd('.'); Ip = $m.Groups[3].Value; Port = [int]$m.Groups[4].Value }
        }
    }
    return $rows
}

function Get-AdbDevices {
    $rows = @()
    foreach ($line in @(Invoke-AdbRaw -ArgList @('devices', '-l'))) {
        $m = [regex]::Match([string]$line, '^(\S+)\s+(device|unauthorized|offline|authorizing|connecting|recovery|sideload|bootloader)\b(.*)$')
        if (-not $m.Success) { continue }
        $model = ''
        $mm = [regex]::Match($m.Groups[3].Value, 'model:(\S+)')
        if ($mm.Success) { $model = $mm.Groups[1].Value -replace '_', ' ' }
        $rows += [pscustomobject]@{ Serial = $m.Groups[1].Value; State = $m.Groups[2].Value; Model = $model }
    }
    return $rows
}

function Connect-Address {
    param([string]$Address)
    $out = (@(Invoke-AdbRaw -ArgList @('connect', $Address)) -join ' ')
    return ($out -match 'connected to|already connected')
}

function Get-DeviceFacts {
    param([string]$Serial)
    $sn    = (@(Invoke-AdbRaw -ArgList @('-s', $Serial, 'shell', 'getprop ro.serialno')) -join '').Trim()
    $model = (@(Invoke-AdbRaw -ArgList @('-s', $Serial, 'shell', 'getprop ro.product.model')) -join '').Trim()
    $chars = (@(Invoke-AdbRaw -ArgList @('-s', $Serial, 'shell', 'getprop ro.build.characteristics')) -join '')
    $lean  = (@(Invoke-AdbRaw -ArgList @('-s', $Serial, 'shell', 'pm has-feature android.software.leanback')) -join '')
    $isTv  = ($lean -match 'true') -or ($chars -match 'tv')
    return [pscustomobject]@{ Serial = $Serial; SerialNo = $sn; Model = $model; IsTv = $isTv; Label = '' }
}

function Wait-Authorized {
    param([string]$Serial)
    Say 'Look at the TV now: tick "Always allow from this computer", then choose Allow.' 'Yellow'
    $deadline = (Get-Date).AddSeconds(120)
    $n = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $n++
        $d = @(Get-AdbDevices | Where-Object { $_.Serial -eq $Serial })
        if ($d.Count -gt 0 -and $d[0].State -eq 'device') { Ok 'The TV allowed this PC.'; return $true }
        if (($n % 10) -eq 0 -and $Serial -match '^\d+\.\d+\.\d+\.\d+:\d+$') {
            [void](Invoke-AdbRaw -ArgList @('disconnect', $Serial))
            [void](Connect-Address $Serial)
        }
    }
    Warn 'The TV did not allow this PC in time.'
    return $false
}

function Resolve-ReadyDevice {
    # Picks the TV among connected devices. Waits for the "Allow" prompt if needed.
    $devs = @(Get-AdbDevices)
    $ready = @($devs | Where-Object { $_.State -eq 'device' })
    $waiting = @($devs | Where-Object { $_.State -eq 'unauthorized' -or $_.State -eq 'authorizing' -or $_.State -eq 'connecting' })
    if ($ready.Count -eq 0 -and $waiting.Count -gt 0) {
        [void](Wait-Authorized $waiting[0].Serial)
        $ready = @(Get-AdbDevices | Where-Object { $_.State -eq 'device' })
    }
    if ($ready.Count -eq 0) { return $null }
    $facts = @()
    $seen = @{}
    foreach ($d in $ready) {
        $f = Get-DeviceFacts $d.Serial
        $key = $f.SerialNo
        if (-not $key) { $key = $d.Serial }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $kind = 'not a TV'
        if ($f.IsTv) { $kind = 'TV' }
        $f.Label = ('{0}   {1}   ({2})' -f $f.Model, $d.Serial, $kind)
        $facts += $f
    }
    $tvs = @($facts | Where-Object { $_.IsTv })
    if ($tvs.Count -eq 1) { return $tvs[0].Serial }
    if ($tvs.Count -eq 0 -and $facts.Count -eq 1) {
        Warn ('The only connected device does not look like a TV: ' + $facts[0].Label)
        if (Confirm-Yes 'Use it anyway?') { return $facts[0].Serial }
        return $null
    }
    $pool = $tvs
    if ($pool.Count -eq 0) { $pool = $facts }
    Say 'More than one device is connected:'
    $pick = Select-FromList $pool 'Number of the TV to use'
    if ($pick) { return $pick.Serial }
    return $null
}

function Save-TvChoice {
    param([string]$Serial)
    $facts = Get-DeviceFacts $Serial
    $ip = ''
    $m = [regex]::Match($Serial, '^(\d{1,3}(?:\.\d{1,3}){3}):\d+$')
    if ($m.Success) { $ip = $m.Groups[1].Value }
    if (-not $ip) {
        $addrs = (@(Invoke-AdbRaw -ArgList @('-s', $Serial, 'shell', 'ip -4 -o addr show')) -join "`n")
        foreach ($x in [regex]::Matches($addrs, 'inet (\d{1,3}(?:\.\d{1,3}){3})/')) {
            if ($x.Groups[1].Value -ne '127.0.0.1') { $ip = $x.Groups[1].Value; break }
        }
    }
    Write-Utf8Lines (Join-Path $script:StateDir 'tv.txt') @(('serial=' + $Serial), ('ip=' + $ip), ('serialno=' + $facts.SerialNo), ('model=' + $facts.Model))
}

function Show-AdbHelp {
    Say ''
    Say 'No TV with ADB turned on has answered yet. On the TV:' 'Yellow'
    Say '  1. Settings > System > About: select "Android TV OS build" 7 times ("You are now a developer").'
    Say '     (Older Android TV: Settings > Device Preferences > About > Build.)'
    Say '  2. Settings > System > Developer options:'
    Say '       TV on Wi-Fi:     turn on "Wireless debugging" and allow it on this network,'
    Say '                        then type P below and pair with the code the TV shows.'
    Say '       TV on Ethernet:  turn on "USB debugging", then type R below.'
    Say '  The TV and this PC have to be on the same network.'
    Say '  If Windows asks whether adb may use the network, choose Allow (Private networks).'
    Say ''
}

function Invoke-Pairing {
    Say 'On the TV: Settings > System > Developer options > Wireless debugging > "Pair device with pairing code".'
    $hp = ([string](Read-Host 'Type the IP address & Port shown in the pairing box (like 192.168.1.50:37123)')).Trim()
    $code = ([string](Read-Host 'Type the 6-digit Wi-Fi pairing code')).Trim()
    if (-not $hp -or -not $code) { return }
    $out = (@(Invoke-AdbRaw -ArgList @('pair', $hp, $code)) -join ' ')
    if ($out -notmatch 'Successfully paired') { Bad ('Pairing did not work: ' + $out); return }
    Ok 'Paired with the TV.'
    $ip = $hp.Split(':')[0]
    for ($i = 0; $i -lt 5; $i++) {
        Start-Sleep -Seconds 2
        if (@(Get-AdbDevices | Where-Object { $_.State -eq 'device' }).Count -gt 0) { return }
        foreach ($m in @(Get-AdbMdns)) {
            if ($m.Type -like '*tls-connect*' -and $m.Ip -eq $ip) {
                if (Connect-Address ('{0}:{1}' -f $m.Ip, $m.Port)) { return }
            }
        }
    }
    $cp = ([string](Read-Host 'Now type the IP address & Port shown at the top of the Wireless debugging screen (not the pairing box)')).Trim()
    if ($cp) { [void](Connect-Address $cp) }
}

function Find-AndConnect {
    param($Saved)
    Say 'Looking for the TV on your network...'
    $net = Get-LocalNet
    $names = @{}
    $adbHosts = @()
    if ($net) {
        Say ('   this PC is {0} on "{1}"' -f $net.Ip, $net.Name)
        foreach ($d in @(Find-SsdpDevices $net.Ip)) {
            $names[$d.Ip] = $d
            $label = (@($d.Name, $d.Model) | Where-Object { $_ }) -join ' / '
            Say ('   seen  {0,-15}  {1}' -f $d.Ip, $label)
        }
        $adbHosts = @(Test-TcpPort -Hosts @(Get-SubnetHosts $net.Ip $net.Prefix) -Port 5555 -TimeoutMs 1200)
    } else {
        Warn 'Could not read this PC''s network settings, so the scan was skipped.'
    }
    $byIp = [ordered]@{}
    foreach ($h in $adbHosts) { if (-not $byIp.Contains($h)) { $byIp[$h] = $h + ':5555' } }
    foreach ($m in @(Get-AdbMdns)) {
        if ($m.Type -like '*tls-connect*') {
            if (-not $byIp.Contains($m.Ip)) { $byIp[$m.Ip] = ('{0}:{1}' -f $m.Ip, $m.Port) }
        } elseif ($m.Type -like '*tls-pairing*') {
            Say ('   {0} is waiting to pair (port {1}): type P below' -f $m.Ip, $m.Port) 'Yellow'
        }
    }
    if ($byIp.Count -eq 0) { return }
    $list = @()
    foreach ($ip in @($byIp.Keys)) {
        $label = $byIp[$ip]
        if ($names.ContainsKey($ip)) { $label = $label + '   ' + ((@($names[$ip].Name, $names[$ip].Model) | Where-Object { $_ }) -join ' / ') }
        $list += [pscustomobject]@{ Address = $byIp[$ip]; Ip = $ip; Label = $label }
    }
    if ($Saved -and $Saved['ip']) {
        $mine = @($list | Where-Object { $_.Ip -eq $Saved['ip'] })
        if ($mine.Count -gt 0) { $list = $mine }
    }
    if ($list.Count -gt 1) {
        Say 'These devices have ADB turned on:'
        $pick = Select-FromList $list 'Number of your TV'
        if (-not $pick) { return }
        $list = @($pick)
    }
    foreach ($item in $list) {
        Say ('   connecting to ' + $item.Label)
        if (Connect-Address $item.Address) { Ok ('connected: ' + $item.Address) } else { Warn ('no answer yet from ' + $item.Address) }
    }
}

function Connect-Tv {
    # Finds the TV, connects, waits for "Allow" on the TV. Returns the adb serial, or $null.
    $saved = Read-KeyValues (Join-Path $script:StateDir 'tv.txt')
    $choice = 'R'
    $round = 0
    while ($true) {
        $round++
        if ($choice -eq 'R') {
            if ($round -eq 1) { Start-Sleep -Seconds 2 }
            if ($saved['serial'] -and ($saved['serial'] -match '^\d+\.\d+\.\d+\.\d+:\d+$')) { [void](Connect-Address $saved['serial']) }
            $already = @(Get-AdbDevices | Where-Object { $_.State -eq 'device' })
            if ($already.Count -eq 0 -or $round -gt 1) { Find-AndConnect $saved }
        }
        $serial = Resolve-ReadyDevice
        if ($serial) {
            Save-TvChoice $serial
            return $serial
        }
        Show-AdbHelp
        $choice = ([string](Read-Host 'Type R to scan again, P to pair with a code, M to type the TV address, Q to quit')).Trim().ToUpper()
        if ($choice -eq 'Q') { return $null }
        elseif ($choice -eq 'P') { Invoke-Pairing }
        elseif ($choice -eq 'M') {
            $addr = ([string](Read-Host 'TV address (IP, or IP:port from the Wireless debugging screen)')).Trim()
            if ($addr) {
                if ($addr -notmatch ':\d+$') { $addr = $addr + ':5555' }
                [void](Connect-Address $addr)
            }
        }
        else { $choice = 'R' }
    }
}

# ---------------------------------------------------------------- reading the TV

function Read-PackageLines {
    param([object[]]$Lines)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($l in $Lines) {
        $m = [regex]::Match([string]$l, '^package:([A-Za-z0-9_\.]+)\s*$')
        if ($m.Success) { $names.Add($m.Groups[1].Value) }
    }
    return $names.ToArray()
}

function Read-PackageFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return (Read-PackageLines ([IO.File]::ReadAllLines($Path)))
}

function Get-TvInfo {
    $p = @{}
    foreach ($line in @(Invoke-TvShell 'getprop')) {
        $m = [regex]::Match([string]$line, '^\[([^\]]+)\]: \[(.*)\]$')
        if ($m.Success) { $p[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
    return [pscustomobject]@{
        Maker       = [string]$p['ro.product.manufacturer']
        Brand       = [string]$p['ro.product.brand']
        Model       = [string]$p['ro.product.model']
        Device      = [string]$p['ro.product.device']
        Release     = [string]$p['ro.build.version.release']
        Sdk         = [string]$p['ro.build.version.sdk']
        Fingerprint = [string]$p['ro.build.fingerprint']
        Patch       = [string]$p['ro.build.version.security_patch']
        SerialNo    = [string]$p['ro.serialno']
    }
}

function Get-TvShot {
    # Screenshot straight from the TV, plus a small .jpg copy.
    param([string]$Name)
    $png = Join-Path $script:ShotsDir ($Name + '.png')
    $remote = '/data/local/tmp/tvkit-shot.png'
    [void](Invoke-TvShell ('screencap -p ' + $remote))
    [void](Invoke-Tv -ArgList @('pull', $remote, $png))
    [void](Invoke-TvShell ('rm -f ' + $remote))
    if (-not (Test-Path -LiteralPath $png)) { Warn ('Could not take a screenshot (' + $Name + ')'); return }
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($png)
        $w = 1280
        $h = [int][Math]::Round($img.Height * $w / $img.Width)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, 0, 0, $w, $h)
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
        $bmp.Save((Join-Path $script:ShotsDir ($Name + '.jpg')), $codec, $ep)
        $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    } catch {
        Write-Log ('jpg copy failed: ' + $_)
    }
    Ok ('TV screenshot: shots\' + $Name + '.png')
}

function Save-TvOutput {
    param([string]$Dir, [string]$File, [string]$Command)
    $lines = @(Invoke-TvShell $Command)
    Write-Utf8Lines (Join-Path $Dir $File) $lines
}

function Get-HomeComponent {
    # The app the Home button opens right now, like com.google.android.apps.tv.launcherx/.home.HomeActivity
    param([object[]]$Lines)
    $comp = ''
    foreach ($l in $Lines) {
        $s = ([string]$l).Trim()
        if ($s -match '^[A-Za-z0-9_\.]+/[A-Za-z0-9_\.\$]+$') { $comp = $s }
    }
    return $comp
}

function Backup-Tv {
    # Saves everything needed to put the TV back: every app's on/off state, settings, home app.
    param($Info, [string]$Label = 'backup')
    $safe = ([string]$Info.Model -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if (-not $safe) { $safe = 'TV' }
    $dir = Join-Path $script:BackupsDir ((Get-Date -Format 'yyyy-MM-dd_HHmmss') + '_' + $safe + '_' + $Label)
    New-Item -ItemType Directory -Path $dir | Out-Null
    $jobs = [ordered]@{
        'getprop.txt'                 = 'getprop'
        'packages-all-names.txt'      = 'pm list packages -u'
        'packages-all-paths.txt'      = 'pm list packages -u -f'
        'packages-enabled.txt'        = 'pm list packages -e'
        'packages-disabled.txt'       = 'pm list packages -d'
        'packages-system.txt'         = 'pm list packages -s'
        'packages-user-installed.txt' = 'pm list packages -3'
        'packages-installers.txt'     = 'pm list packages -i'
        'package-versions.txt'        = "dumpsys package packages | grep -E '^  Package \[|versionName='"
        'users.txt'                   = 'pm list users'
        'home-app.txt'                = 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
        'home-candidates.txt'         = 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
        'home-role.txt'               = 'cmd role get-role-holders android.app.role.HOME'
        'apps-tv.txt'                 = 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER'
        'apps-phone.txt'              = 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER'
        'settings-global.txt'         = 'settings list global'
        'settings-secure.txt'         = 'settings list secure'
        'settings-system.txt'         = 'settings list system'
        'features.txt'                = 'pm list features'
        'memory.txt'                  = 'dumpsys meminfo'
        'cpu-top.txt'                 = 'top -b -n 1 -m 40'
        'storage.txt'                 = 'df -h /data'
        'processes.txt'               = 'ps -A -o PID,RSS,NAME'
    }
    foreach ($k in $jobs.Keys) {
        Say ('   saving ' + $k)
        Save-TvOutput $dir $k $jobs[$k]
    }
    $homeApp = Get-HomeComponent ([IO.File]::ReadAllLines((Join-Path $dir 'home-app.txt')))
    $all = @(Read-PackageFile (Join-Path $dir 'packages-all-names.txt'))
    $off = @(Read-PackageFile (Join-Path $dir 'packages-disabled.txt'))
    $mine = @(Read-PackageFile (Join-Path $dir 'packages-user-installed.txt'))
    Write-Utf8Lines (Join-Path $dir 'backup-info.txt') @(
        ('time=' + (Get-Date -Format s)),
        ('maker=' + $Info.Maker),
        ('brand=' + $Info.Brand),
        ('model=' + $Info.Model),
        ('device=' + $Info.Device),
        ('android=' + $Info.Release),
        ('sdk=' + $Info.Sdk),
        ('build=' + $Info.Fingerprint),
        ('patch=' + $Info.Patch),
        ('serialno=' + $Info.SerialNo),
        ('connection=' + $script:Serial),
        ('home=' + $homeApp),
        ('packages=' + $all.Count),
        ('disabled=' + $off.Count),
        ('user_installed=' + $mine.Count)
    )
    $orig = Join-Path $script:StateDir 'original-backup.txt'
    if (-not (Test-Path -LiteralPath $orig)) { Write-Utf8Text $orig $dir }
    Write-Utf8Text (Join-Path $script:StateDir 'latest-backup.txt') $dir
    return $dir
}

function Get-BackupSetting {
    # Value a setting had in a backup, or $null if it was not set.
    param([string]$Backup, [string]$Namespace, [string]$Key)
    $file = Join-Path $Backup ('settings-' + $Namespace + '.txt')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if ($line.StartsWith($Key + '=')) {
            $v = $line.Substring($Key.Length + 1)
            if ($v -eq 'null') { return $null }
            return $v
        }
    }
    return $null
}

function ConvertTo-ShellQuoted {
    param([string]$Value)
    return ("'" + $Value.Replace("'", "'\''") + "'")
}

# ---------------------------------------------------------------- changing the TV (always written down first)

function Confirm-Go {
    # Like Confirm-Yes, but Enter means yes.
    param([string]$Question)
    $answer = [string](Read-Host ($Question + ' (Y/n)'))
    Write-Log ('? ' + $Question + ' -> ' + $answer)
    return ($answer -notmatch '^\s*(n|no)\s*$')
}

function Add-StateLine {
    param([string]$File, [string]$Line)
    $path = Join-Path $script:StateDir $File
    $existing = @()
    if (Test-Path -LiteralPath $path) { $existing = @([IO.File]::ReadAllLines($path)) }
    if ($existing -notcontains $Line) { [IO.File]::AppendAllText($path, $Line + "`r`n", $script:Utf8) }
}

function Set-TvSetting {
    # Writes the setting down in state\changed-settings.txt first, so RESTORE.bat can put the backup's value back.
    param([string]$Namespace, [string]$Key, [string]$Value)
    Add-StateLine 'changed-settings.txt' ($Namespace + "`t" + $Key)
    [void](Invoke-TvShell ('settings put ' + $Namespace + ' ' + $Key + ' ' + (ConvertTo-ShellQuoted $Value)))
    $now = (@(Invoke-TvShell ('settings get ' + $Namespace + ' ' + $Key)) -join '').Trim()
    return ($now -eq $Value)
}

function Disable-TvPackage {
    # Turns an app off for the main user (pm disable-user). Never uninstalls. Written down in state\disabled-by-tvkit.txt.
    param([string]$Pkg)
    Add-StateLine 'disabled-by-tvkit.txt' $Pkg
    $o = (@(Invoke-TvShell ('pm disable-user --user 0 ' + $Pkg)) -join ' ')
    if ($o -notmatch 'new state') { $o = (@(Invoke-TvShell ('pm disable-user ' + $Pkg)) -join ' ') }
    return ($o -match 'new state: disabled')
}

function Enable-TvPackage {
    param([string]$Pkg)
    $o = (@(Invoke-TvShell ('pm enable --user 0 ' + $Pkg)) -join ' ')
    if ($o -notmatch 'new state') { $o = (@(Invoke-TvShell ('pm enable ' + $Pkg)) -join ' ') }
    return ($o -match 'new state: enabled')
}

function Get-TvFront {
    # The activity in front right now, like com.mihir.tvhome/.MainActivity, or '' if the TV won't say.
    $lines = @(Invoke-TvShell "dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity|ResumedActivity:'")
    foreach ($l in $lines) {
        $m = [regex]::Match([string]$l, '([A-Za-z0-9_\.]+/[A-Za-z0-9_\.\$]+)')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ''
}

function Get-TvApps {
    # Packages with a TV launcher entry (what a TV home screen shows), in the TV's own order.
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($l in @(Invoke-TvShell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER')) {
        $m = [regex]::Match(([string]$l).Trim(), '^([A-Za-z0-9_\.]+)/')
        if ($m.Success -and -not $found.Contains($m.Groups[1].Value)) { $found.Add($m.Groups[1].Value) }
    }
    return $found.ToArray()
}

function Get-TvUsage {
    # When each app was last used, and for how long in total, from Android's usage stats. Known = false if the TV won't say.
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.DateTimeStyles]::None
    $now = [datetime]::MinValue
    $nowText = (@(Invoke-TvShell "date '+%Y-%m-%d %H:%M:%S'") -join '').Trim()
    [void][datetime]::TryParseExact($nowText, 'yyyy-MM-dd HH:mm:ss', $culture, $style, [ref]$now)
    $last = @{}
    $total = @{}
    foreach ($l in @(Invoke-TvShell "dumpsys usagestats | grep -E 'package=.*lastTimeUsed'")) {
        $p = [regex]::Match([string]$l, 'package=(\S+)')
        if (-not $p.Success) { continue }
        $pkg = $p.Groups[1].Value
        $t = [regex]::Match([string]$l, 'lastTimeUsed="(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)"')
        if ($t.Success) {
            $d = [datetime]::MinValue
            if ([datetime]::TryParseExact($t.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', $culture, $style, [ref]$d)) {
                if (-not $last.ContainsKey($pkg) -or $d -gt $last[$pkg]) { $last[$pkg] = $d }
            }
        }
        $u = [regex]::Match([string]$l, 'totalTimeUsed="([\d:]+)"')
        if ($u.Success) {
            $secs = 0
            foreach ($part in $u.Groups[1].Value.Split(':')) { $secs = $secs * 60 + [int]$part }
            if ($total.ContainsKey($pkg)) { $total[$pkg] = $total[$pkg] + $secs } else { $total[$pkg] = $secs }
        }
    }
    return [pscustomobject]@{ Now = $now; Last = $last; Total = $total; Known = (($last.Count -gt 0) -and ($now -ne [datetime]::MinValue)) }
}
