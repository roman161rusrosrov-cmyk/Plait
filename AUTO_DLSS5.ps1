#Requires -Version 5.1
param([switch]$NoLaunch)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$DllName = 'nvngx_dlssnr.dll'
$GoodDllHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$PackageHash = '388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC'
$PackageUrl = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip'
$CacheRoot = Join-Path $env:LOCALAPPDATA 'Plait-DLSS5-Auto'

function Step([string]$s) { Write-Host ''; Write-Host ('== ' + $s + ' ==') -ForegroundColor Cyan }
function Ok([string]$s) { Write-Host ('[OK] ' + $s) -ForegroundColor Green }
function Warn([string]$s) { Write-Host ('[!] ' + $s) -ForegroundColor Yellow }
function Fail([string]$s) { throw $s }
function Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function NvidiaSig([string]$p) {
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $p
        return ($sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'NVIDIA')
    } catch { return $false }
}

function Find-GameDir {
    $c = New-Object System.Collections.Generic.List[string]
    $c.Add('D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64')

    $steam = $null
    try {
        $k = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if ($k) { $steam = $k.SteamPath; if (-not $steam) { $steam = $k.InstallPath } }
    } catch {}

    if ($steam) {
        $steam = ($steam -replace '/', '\').TrimEnd('\')
        $c.Add((Join-Path $steam 'steamapps\common\Cyberpunk 2077\bin\x64'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in [System.IO.File]::ReadAllLines($vdf)) {
                if ($line -match '^\s*"path"\s+"(.+?)"\s*$') {
                    $root = $Matches[1] -replace '\\\\','\'
                    $c.Add((Join-Path $root 'steamapps\common\Cyberpunk 2077\bin\x64'))
                }
            }
        }
    }

    foreach ($d in @('C','D','E','F','G')) {
        $c.Add($d + ':\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64')
        $c.Add($d + ':\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\bin\x64')
        $c.Add($d + ':\GOG Games\Cyberpunk 2077\bin\x64')
    }

    foreach ($p in ($c | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $p 'Cyberpunk2077.exe') -PathType Leaf) { return $p }
    }
    return $null
}

function Ensure-DlssNrDll([string]$GameDir) {
    Step 'DLSSNR DLL validation'
    $target = Join-Path $GameDir $DllName
    if (Test-Path $target -PathType Leaf) {
        $h = Hash $target
        if ($h -eq $GoodDllHash -and (NvidiaSig $target)) {
            Ok ('Verified DLL already installed: ' + $h)
            return
        }
        Warn ('Current DLL is not the verified build: ' + $h)
    } else {
        Warn 'nvngx_dlssnr.dll is missing. It will be restored automatically.'
    }

    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    $zip = Join-Path $CacheRoot 'nvngx_dlssnr_310.8.0.zip'
    $stage = Join-Path $CacheRoot 'stage'

    $needDownload = $true
    if (Test-Path $zip -PathType Leaf) {
        try { if ((Hash $zip) -eq $PackageHash) { $needDownload = $false } } catch {}
    }

    if ($needDownload) {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Write-Host 'Downloading verified DLSS NR package...'
        Invoke-WebRequest -Uri $PackageUrl -OutFile $zip -UseBasicParsing -TimeoutSec 900
    }

    $zh = Hash $zip
    if ($zh -ne $PackageHash) { Fail ('Downloaded ZIP hash mismatch. Got: ' + $zh) }
    Ok 'Upstream ZIP SHA256 verified.'

    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    $src = Get-ChildItem -LiteralPath $stage -Filter $DllName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $src) { Fail 'nvngx_dlssnr.dll was not found inside the verified package.' }

    $dh = Hash $src.FullName
    if ($dh -ne $GoodDllHash) { Fail ('DLL SHA256 mismatch. Got: ' + $dh) }
    if (-not (NvidiaSig $src.FullName)) { Fail 'DLL NVIDIA Authenticode signature is not valid.' }
    Ok 'Replacement DLL hash and NVIDIA signature verified.'

    if (Test-Path $target -PathType Leaf) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bak = Join-Path $GameDir ($DllName + '.bak-' + $stamp)
        Copy-Item -LiteralPath $target -Destination $bak -Force
        Ok ('Backup: ' + $bak)
    }

    Copy-Item -LiteralPath $src.FullName -Destination $target -Force
    if ((Hash $target) -ne $GoodDllHash -or -not (NvidiaSig $target)) { Fail 'Final DLL validation failed after copying.' }
    Ok 'Verified DLSSNR DLL installed.'
}

function Update-LoadFromDllMain([string]$IniPath, [string]$AddonFile) {
    $lines = [System.IO.File]::ReadAllLines($IniPath)
    $keyPrefix = 'LoadFromDllMain='
    $keyIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith($keyPrefix)) { $keyIdx = $i; break }
    }

    if ($keyIdx -ge 0) {
        $value = $lines[$keyIdx].Substring($keyPrefix.Length)
        $entries = @(); $cur = ''
        foreach ($ch in $value.ToCharArray()) {
            if ([int]$ch -eq 0) { if ($cur) { $entries += $cur }; $cur = '' } else { $cur += $ch }
        }
        if ($cur) { $entries += $cur }
        $entries = @($entries | Where-Object { $_ })
        if ($entries -notcontains $AddonFile) { $entries += $AddonFile }
        $newLine = $keyPrefix + ($entries -join [string][char]0)
        if ($newLine -ne $lines[$keyIdx]) {
            $lines[$keyIdx] = $newLine
            [System.IO.File]::WriteAllLines($IniPath, $lines)
            return $true
        }
        return $false
    }

    $hasAddon = $false
    foreach ($l in $lines) { if ($l.Trim() -eq '[ADDON]') { $hasAddon = $true; break } }
    if (-not $hasAddon) { $lines += ''; $lines += '[ADDON]' }
    $out = @(); $inserted = $false
    foreach ($l in $lines) {
        $out += $l
        if (-not $inserted -and $l.Trim() -eq '[ADDON]') {
            $out += ($keyPrefix + $AddonFile)
            $inserted = $true
        }
    }
    [System.IO.File]::WriteAllLines($IniPath, $out)
    return $true
}

function Ensure-EarlyLoad([string]$GameDir) {
    Step 'ReShade early-load configuration'
    $ini = Join-Path $GameDir 'ReShade.ini'
    if (-not (Test-Path $ini -PathType Leaf)) { Fail 'ReShade.ini was not found beside Cyberpunk2077.exe.' }

    $addons = @(Get-ChildItem -LiteralPath $GameDir -Filter 'renodx-dlss5*.addon64' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($addons.Count -eq 0) { Fail 'No renodx-dlss5*.addon64 file was found beside Cyberpunk2077.exe.' }
    $addon = $addons[0].Name
    Ok ('Detected DLSS5 addon: ' + $addon)

    $bak = $ini + '.plait-auto.bak'
    if (-not (Test-Path $bak -PathType Leaf)) {
        Copy-Item -LiteralPath $ini -Destination $bak -Force
        Ok 'Original ReShade.ini backup created.'
    }

    $changed = Update-LoadFromDllMain $ini $addon
    if ($changed) { Ok ('Early load enabled: LoadFromDllMain=' + $addon) }
    else { Ok 'Early load was already configured.' }

    $raw = [System.IO.File]::ReadAllText($ini)
    if ($raw -notmatch [regex]::Escape('LoadFromDllMain=') -or $raw -notmatch [regex]::Escape($addon)) {
        Fail 'ReShade early-load verification failed.'
    }
}

try {
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' PLAIT DLSS5 AUTO - Cyberpunk 2077' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    if (Get-Process -Name 'Cyberpunk2077' -ErrorAction SilentlyContinue) {
        Fail 'Cyberpunk 2077 is running. Close the game, run START_DLSS5.cmd, then let it launch the game.'
    }

    $game = Find-GameDir
    if (-not $game) { Fail 'Cyberpunk 2077 bin\x64 folder was not found.' }
    Ok ('Game: ' + $game)

    Ensure-DlssNrDll $game
    Ensure-EarlyLoad $game

    Step 'Final checks'
    $dll = Join-Path $game $DllName
    if ((Hash $dll) -ne $GoodDllHash) { Fail 'Final DLL hash check failed.' }
    if (-not (NvidiaSig $dll)) { Fail 'Final NVIDIA signature check failed.' }
    Ok 'DLSSNR DLL: verified.'
    Ok 'ReShade early loading: configured.'

    if (-not $NoLaunch) {
        Step 'Launching Cyberpunk 2077'
        $exe = Join-Path $game 'Cyberpunk2077.exe'
        Start-Process -FilePath $exe -WorkingDirectory $game
        Ok 'Game launched.'
        Write-Host ''
        Write-Host 'IMPORTANT: On the epilepsy warning / splash screen DLSSNR may show STANDBY/FAILED.' -ForegroundColor Yellow
        Write-Host 'Load a save and enter the 3D game world before judging the status.' -ForegroundColor Yellow
        Write-Host 'Then open Home -> Add-ons -> DLSS 5 Neural Rendering.' -ForegroundColor Yellow
        Write-Host 'Expected: ACTIVE and Successful NR frames increasing.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'AUTO PREP COMPLETE.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No unverified NVIDIA DLL was installed.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
