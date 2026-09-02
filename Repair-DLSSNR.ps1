$ErrorActionPreference = 'Stop'

$GoodHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$BadHash  = 'CEB6432F6FBDF44D886014BCD47241932BF8B67439FEEF9BBDD0961436662650'
$DllName  = 'nvngx_dlssnr.dll'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host (' ' + $Text) -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-NvidiaSignature([string]$Path) {
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path
        if (-not $sig.SignerCertificate) { return $false }
        return ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'NVIDIA')
    }
    catch {
        return $false
    }
}

function Test-GoodDll([string]$Path) {
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $hash = Get-Sha256 $Path
        if ($hash -ne $GoodHash) { return $false }
        if (-not (Test-NvidiaSignature $Path)) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Find-CyberpunkDir {
    $candidates = @()

    # Exact path seen on the target PC.
    $candidates += 'D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64'

    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles

    if ($pf86) { $candidates += (Join-Path $pf86 'Steam\steamapps\common\Cyberpunk 2077\bin\x64') }
    if ($pf)   { $candidates += (Join-Path $pf   'Steam\steamapps\common\Cyberpunk 2077\bin\x64') }

    foreach ($drive in @('C','D','E','F','G')) {
        $candidates += ($drive + ':\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64')
        $candidates += ($drive + ':\GOG Games\Cyberpunk 2077\bin\x64')
    }

    foreach ($p in ($candidates | Select-Object -Unique)) {
        try {
            if (Test-Path -LiteralPath (Join-Path $p 'Cyberpunk2077.exe') -PathType Leaf) {
                return $p
            }
        }
        catch {}
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select Cyberpunk 2077 bin\x64 folder'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $p = $dlg.SelectedPath
            if (Test-Path -LiteralPath (Join-Path $p 'Cyberpunk2077.exe') -PathType Leaf) {
                return $p
            }
        }
    }
    catch {}

    throw 'Cyberpunk 2077 bin\x64 folder was not found.'
}

function Find-GoodDll([string]$GameDir) {
    Write-Host '[1/4] Looking for a verified DLSSNR DLL...' -ForegroundColor Cyan

    # First: DLL placed next to this fixer.
    $local = Join-Path $ScriptDir $DllName
    if ((-not $local.StartsWith($GameDir, [System.StringComparison]::OrdinalIgnoreCase)) -and (Test-GoodDll $local)) {
        Write-Host ('Found verified DLL: ' + $local) -ForegroundColor Green
        return $local
    }

    $searchRoots = @()
    if ($env:USERPROFILE) {
        $searchRoots += (Join-Path $env:USERPROFILE 'Downloads')
        $searchRoots += (Join-Path $env:USERPROFILE 'Desktop')
    }

    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles
    if ($pf86) { $searchRoots += (Join-Path $pf86 'Steam\steamapps\common') }
    if ($pf)   { $searchRoots += (Join-Path $pf 'Steam\steamapps\common') }

    foreach ($drive in @('D','E','F','G')) {
        $searchRoots += ($drive + ':\SteamLibrary\steamapps\common')
    }

    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Write-Host ('Scanning: ' + $root) -ForegroundColor DarkGray
        try {
            $files = Get-ChildItem -LiteralPath $root -Filter $DllName -File -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                if ($f.FullName.StartsWith($GameDir, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if (Test-GoodDll $f.FullName) {
                    Write-Host ('Found verified DLL: ' + $f.FullName) -ForegroundColor Green
                    return $f.FullName
                }
            }
        }
        catch {}
    }

    return $null
}

function Pick-GoodDll {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Select verified nvngx_dlssnr.dll'
        $dlg.Filter = 'nvngx_dlssnr.dll|nvngx_dlssnr.dll|DLL files (*.dll)|*.dll|All files (*.*)|*.*'
        $dlg.FileName = $DllName
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dlg.FileName
        }
    }
    catch {}
    return $null
}

try {
    Banner 'DLSSNR FIXER - Cyberpunk 2077'
    Write-Host 'Close Cyberpunk 2077 before continuing.' -ForegroundColor Yellow

    $GameDir = Find-CyberpunkDir
    $Target = Join-Path $GameDir $DllName
    Write-Host ('Game folder: ' + $GameDir) -ForegroundColor Green

    Write-Host '[2/4] Checking current game DLL...' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        $CurrentHash = Get-Sha256 $Target
        Write-Host ('Current SHA256: ' + $CurrentHash)

        if ((Test-GoodDll $Target)) {
            Banner 'ALREADY FIXED'
            Write-Host 'The verified NVIDIA DLL is already installed.' -ForegroundColor Green
            Read-Host 'Press Enter to exit'
            exit 0
        }

        if ($CurrentHash -eq $BadHash) {
            Write-Host 'Known broken CEB643... DLL detected.' -ForegroundColor Yellow
        }
    }
    else {
        Write-Host 'Current nvngx_dlssnr.dll is missing. That is OK if you renamed it to .bak.' -ForegroundColor Yellow
    }

    $Source = Find-GoodDll $GameDir
    if (-not $Source) {
        Write-Host ''
        Write-Host 'Automatic search did not find the verified DLL.' -ForegroundColor Yellow
        Write-Host 'A file picker will open. Select your working nvngx_dlssnr.dll.' -ForegroundColor Yellow
        $Source = Pick-GoodDll
    }

    if (-not $Source) {
        throw 'No source DLL was selected. Nothing was changed.'
    }

    Write-Host '[3/4] Validating replacement DLL...' -ForegroundColor Cyan
    $SourceHash = Get-Sha256 $Source
    $Sig = Get-AuthenticodeSignature -LiteralPath $Source
    Write-Host ('Source: ' + $Source)
    Write-Host ('SHA256: ' + $SourceHash)
    Write-Host ('Signature status: ' + $Sig.Status)
    if ($Sig.SignerCertificate) {
        Write-Host ('Signer: ' + $Sig.SignerCertificate.Subject)
    }

    if ($SourceHash -ne $GoodHash) {
        throw ('Wrong SHA256. Expected: ' + $GoodHash)
    }
    if (-not (Test-NvidiaSignature $Source)) {
        throw 'The selected DLL does not have a valid NVIDIA signature.'
    }

    Write-Host '[4/4] Backing up and replacing...' -ForegroundColor Cyan
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Backup = Join-Path $GameDir ($DllName + '.bak-' + $Timestamp)

    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        Copy-Item -LiteralPath $Target -Destination $Backup -Force
        Write-Host ('Backup created: ' + $Backup) -ForegroundColor DarkGray
    }

    Copy-Item -LiteralPath $Source -Destination $Target -Force

    $AfterHash = Get-Sha256 $Target
    if ($AfterHash -ne $GoodHash -or -not (Test-NvidiaSignature $Target)) {
        throw 'Final validation failed after copying.'
    }

    Banner 'SUCCESS'
    Write-Host 'nvngx_dlssnr.dll was replaced successfully.' -ForegroundColor Green
    Write-Host ('SHA256: ' + $AfterHash) -ForegroundColor Green
    Write-Host 'NVIDIA signature: VALID' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Now launch Cyberpunk 2077.' -ForegroundColor White
    Write-Host 'Open ReShade -> Add-ons -> DLSS 5 Neural Rendering.' -ForegroundColor White
    Write-Host 'Click: Reset NR feature and clear failure latch.' -ForegroundColor White
    Write-Host 'Successful NR frames should start increasing.' -ForegroundColor White
}
catch {
    Write-Host ''
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No unverified DLL was installed.' -ForegroundColor Yellow
    exit 1
}
finally {
    Read-Host 'Press Enter to close'
}
