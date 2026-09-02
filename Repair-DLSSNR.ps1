$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DllName = 'nvngx_dlssnr.dll'
$GoodHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$BadHash = 'CEB6432F6FBDF44D886014BCD47241932BF8B67439FEEF9BBDD0961436662650'

$PackageUrl = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip'
$PackageHash = '388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC'

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host (' ' + $Text) -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-SignatureInfo([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = ''
    if ($sig.SignerCertificate) {
        $subject = $sig.SignerCertificate.Subject
    }

    return [PSCustomObject]@{
        Status = [string]$sig.Status
        Subject = $subject
        IsNvidiaValid = ($sig.Status -eq 'Valid' -and $subject -match 'NVIDIA')
    }
}

function Find-CyberpunkDir {
    $candidates = New-Object System.Collections.Generic.List[string]

    $candidates.Add('D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64')

    $steamRoots = New-Object System.Collections.Generic.List[string]
    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles

    if ($pf86) { $steamRoots.Add((Join-Path $pf86 'Steam')) }
    if ($pf) { $steamRoots.Add((Join-Path $pf 'Steam')) }

    foreach ($drive in @('C','D','E','F','G')) {
        $steamRoots.Add(($drive + ':\SteamLibrary'))
    }

    foreach ($root in ($steamRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $direct = Join-Path $root 'steamapps\common\Cyberpunk 2077\bin\x64'
        $candidates.Add($direct)

        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            try {
                $text = Get-Content -LiteralPath $vdf -Raw
                $matches = [regex]::Matches($text, '"path"\s+"([^"]+)"')
                foreach ($m in $matches) {
                    $lib = $m.Groups[1].Value -replace '\\\\','\'
                    if ($lib) {
                        $candidates.Add((Join-Path $lib 'steamapps\common\Cyberpunk 2077\bin\x64'))
                    }
                }
            }
            catch {}
        }
    }

    foreach ($drive in @('C','D','E','F','G')) {
        $candidates.Add(($drive + ':\GOG Games\Cyberpunk 2077\bin\x64'))
    }

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not $path) { continue }
        try {
            if (Test-Path -LiteralPath (Join-Path $path 'Cyberpunk2077.exe') -PathType Leaf) {
                return $path
            }
        }
        catch {}
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select Cyberpunk 2077 bin\x64 folder'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (Test-Path -LiteralPath (Join-Path $path 'Cyberpunk2077.exe') -PathType Leaf) {
                return $path
            }
        }
    }
    catch {}

    throw 'Cyberpunk 2077 bin\x64 folder was not found.'
}

function Download-VerifiedDll([string]$WorkDir) {
    $zipPath = Join-Path $WorkDir 'nvngx_dlssnr_310.8.0.zip'
    $extractDir = Join-Path $WorkDir 'extract'

    Write-Host '[2/5] Downloading verified DLSSNR package from RankFTW/rhi-repo...' -ForegroundColor Cyan
    Write-Host ('Source: ' + $PackageUrl) -ForegroundColor DarkGray
    Write-Host 'Download size is about 110 MB. Please wait.' -ForegroundColor Yellow

    $headers = @{ 'User-Agent' = 'DLSSNR-Fixer-Cyberpunk/1.1.0' }
    Invoke-WebRequest -Uri $PackageUrl -OutFile $zipPath -UseBasicParsing -Headers $headers

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        throw 'The download did not produce a ZIP file.'
    }

    Write-Host '[3/5] Verifying downloaded package...' -ForegroundColor Cyan
    $zipHash = Get-Sha256 $zipPath
    Write-Host ('ZIP SHA256: ' + $zipHash)

    if ($zipHash -ne $PackageHash) {
        throw ('Downloaded ZIP hash mismatch. Expected: ' + $PackageHash)
    }

    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $candidate = Get-ChildItem -LiteralPath $extractDir -Filter $DllName -File -Recurse -ErrorAction Stop |
        Select-Object -First 1

    if (-not $candidate) {
        throw 'nvngx_dlssnr.dll was not found inside the downloaded package.'
    }

    $dllHash = Get-Sha256 $candidate.FullName
    $sig = Get-SignatureInfo $candidate.FullName
    $version = (Get-Item -LiteralPath $candidate.FullName).VersionInfo.FileVersion

    Write-Host ('DLL version: ' + $version)
    Write-Host ('DLL SHA256: ' + $dllHash)
    Write-Host ('Signature: ' + $sig.Status)
    if ($sig.Subject) {
        Write-Host ('Signer: ' + $sig.Subject)
    }

    if ($dllHash -ne $GoodHash) {
        throw ('Downloaded DLL hash mismatch. Expected: ' + $GoodHash)
    }

    if (-not $sig.IsNvidiaValid) {
        throw 'Downloaded DLL does not have a valid NVIDIA signature.'
    }

    return $candidate.FullName
}

$workDir = $null
$backup = $null
$target = $null

try {
    Banner 'DLSSNR ONE-CLICK FIX - Cyberpunk 2077'

    $running = Get-Process -Name 'Cyberpunk2077' -ErrorAction SilentlyContinue
    if ($running) {
        throw 'Cyberpunk 2077 is running. Close the game and run START_FIX.cmd again.'
    }

    Write-Host '[1/5] Finding Cyberpunk 2077...' -ForegroundColor Cyan
    $gameDir = Find-CyberpunkDir
    $target = Join-Path $gameDir $DllName
    Write-Host ('Game folder: ' + $gameDir) -ForegroundColor Green

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $currentHash = Get-Sha256 $target
        Write-Host ('Current DLL SHA256: ' + $currentHash)

        $currentSig = Get-SignatureInfo $target
        if ($currentHash -eq $GoodHash -and $currentSig.IsNvidiaValid) {
            Banner 'ALREADY FIXED'
            Write-Host 'The verified NVIDIA DLSSNR DLL is already installed.' -ForegroundColor Green
            exit 0
        }

        if ($currentHash -eq $BadHash) {
            Write-Host 'Known broken CEB643... DLL detected.' -ForegroundColor Yellow
        }
    }
    else {
        Write-Host 'Current nvngx_dlssnr.dll is missing. Existing .bak files will be left untouched.' -ForegroundColor Yellow
    }

    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('DLSSNR-Fixer-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $source = Download-VerifiedDll $workDir

    Write-Host '[4/5] Backing up current DLL...' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $gameDir ($DllName + '.bak-' + $stamp)
        Copy-Item -LiteralPath $target -Destination $backup -Force
        Write-Host ('Backup: ' + $backup) -ForegroundColor DarkGray
    }
    else {
        Write-Host 'No active DLL to back up.' -ForegroundColor DarkGray
    }

    Write-Host '[5/5] Installing verified DLL...' -ForegroundColor Cyan
    Copy-Item -LiteralPath $source -Destination $target -Force

    $afterHash = Get-Sha256 $target
    $afterSig = Get-SignatureInfo $target

    if ($afterHash -ne $GoodHash -or -not $afterSig.IsNvidiaValid) {
        if ($backup -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Copy-Item -LiteralPath $backup -Destination $target -Force
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }

        throw 'Final validation failed after installation. The previous state was restored.'
    }

    Banner 'SUCCESS'
    Write-Host 'Working nvngx_dlssnr.dll installed automatically.' -ForegroundColor Green
    Write-Host ('SHA256: ' + $afterHash) -ForegroundColor Green
    Write-Host 'NVIDIA signature: VALID' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Next:' -ForegroundColor White
    Write-Host '1. Launch Cyberpunk 2077.' -ForegroundColor White
    Write-Host '2. Press Home -> Add-ons -> DLSS 5 Neural Rendering.' -ForegroundColor White
    Write-Host '3. Click "Reset NR feature and clear failure latch".' -ForegroundColor White
    Write-Host '4. If needed, switch DLSS Quality -> Balanced -> Quality once.' -ForegroundColor White
    Write-Host '5. Successful NR frames should start increasing.' -ForegroundColor White
}
catch {
    Write-Host ''
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No unverified DLL was installed.' -ForegroundColor Yellow
    exit 1
}
finally {
    if ($workDir -and (Test-Path -LiteralPath $workDir)) {
        try {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }

    Write-Host ''
    Read-Host 'Press Enter to close'
}
