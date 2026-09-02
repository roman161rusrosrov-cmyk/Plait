$ErrorActionPreference = 'Stop'

$GoodHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$BadHash  = 'CEB6432F6FBDF44D886014BCD47241932BF8B67439FEEF9BBDD0961436662650'
$DllName  = 'nvngx_dlssnr.dll'

function Write-Title($Text) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-NvidiaSignature([string]$Path) {
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path
        $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' }
        return ($sig.Status -eq 'Valid' -and $subject -match 'NVIDIA')
    } catch {
        return $false
    }
}

function Find-CyberpunkX64 {
    $candidates = New-Object System.Collections.Generic.List[string]

    $steamRoots = @(
        "$env:ProgramFiles(x86)\Steam",
        "$env:ProgramFiles\Steam",
        'D:\SteamLibrary',
        'E:\SteamLibrary',
        'F:\SteamLibrary',
        'G:\SteamLibrary'
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $steamRoots) {
        $direct = Join-Path $root 'steamapps\common\Cyberpunk 2077\bin\x64'
        if (Test-Path (Join-Path $direct 'Cyberpunk2077.exe')) { $candidates.Add($direct) }

        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $txt = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
            foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\','\'
                $p = Join-Path $lib 'steamapps\common\Cyberpunk 2077\bin\x64'
                if (Test-Path (Join-Path $p 'Cyberpunk2077.exe')) { $candidates.Add($p) }
            }
        }
    }

    $gogCandidates = @(
        'C:\GOG Games\Cyberpunk 2077\bin\x64',
        'D:\GOG Games\Cyberpunk 2077\bin\x64',
        'E:\GOG Games\Cyberpunk 2077\bin\x64'
    )
    foreach ($p in $gogCandidates) {
        if (Test-Path (Join-Path $p 'Cyberpunk2077.exe')) { $candidates.Add($p) }
    }

    $unique = $candidates | Select-Object -Unique
    if ($unique.Count -eq 1) { return $unique[0] }
    if ($unique.Count -gt 1) {
        Write-Host 'Найдено несколько установок Cyberpunk:' -ForegroundColor Yellow
        for ($i=0; $i -lt $unique.Count; $i++) { Write-Host "[$($i+1)] $($unique[$i])" }
        $choice = Read-Host 'Введи номер'
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $unique.Count) {
            return $unique[[int]$choice-1]
        }
    }

    Write-Host 'Автоматически папку Cyberpunk найти не получилось.' -ForegroundColor Yellow
    $manual = Read-Host 'Вставь путь к Cyberpunk 2077\bin\x64'
    if (Test-Path (Join-Path $manual 'Cyberpunk2077.exe')) { return $manual }
    throw 'Не найдена корректная папка bin\x64.'
}

function Find-ValidDll([string]$GameDir) {
    Write-Host 'Ищу рабочий nvngx_dlssnr.dll на ПК...' -ForegroundColor Cyan

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(
        "$env:ProgramFiles\NVIDIA Corporation",
        "$env:ProgramFiles\NVIDIA GPU Computing Toolkit",
        "$env:SystemRoot\System32\DriverStore\FileRepository",
        "$env:ProgramFiles(x86)\Steam\steamapps\common",
        "$env:ProgramFiles\Steam\steamapps\common",
        'D:\SteamLibrary\steamapps\common',
        'E:\SteamLibrary\steamapps\common',
        'F:\SteamLibrary\steamapps\common',
        'G:\SteamLibrary\steamapps\common'
    )) {
        if ($r -and (Test-Path $r)) { $roots.Add($r) }
    }

    foreach ($root in ($roots | Select-Object -Unique)) {
        Write-Host "  -> $root" -ForegroundColor DarkGray
        try {
            $files = Get-ChildItem -LiteralPath $root -Filter $DllName -File -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                if ($f.FullName.StartsWith($GameDir, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                try {
                    $hash = Get-Sha256 $f.FullName
                    if ($hash -eq $GoodHash -and (Test-NvidiaSignature $f.FullName)) {
                        Write-Host "Найден рабочий файл: $($f.FullName)" -ForegroundColor Green
                        return $f.FullName
                    }
                } catch {}
            }
        } catch {}
    }

    return $null
}

function Pick-DllWithDialog {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Выбери рабочий nvngx_dlssnr.dll'
        $dlg.Filter = 'NVIDIA DLSS Neural Rendering DLL (nvngx_dlssnr.dll)|nvngx_dlssnr.dll|DLL files (*.dll)|*.dll|All files (*.*)|*.*'
        $dlg.FileName = $DllName
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dlg.FileName
        }
    } catch {}
    return $null
}

Write-Title 'DLSSNR FIXER — Cyberpunk 2077'
Write-Host 'Закрой Cyberpunk перед продолжением.' -ForegroundColor Yellow

$gameDir = Find-CyberpunkX64
Write-Host "Cyberpunk: $gameDir" -ForegroundColor Green
$target = Join-Path $gameDir $DllName

if (Test-Path $target) {
    $currentHash = Get-Sha256 $target
    Write-Host "Текущий SHA-256: $currentHash"
    if ($currentHash -eq $GoodHash -and (Test-NvidiaSignature $target)) {
        Write-Host 'У тебя уже установлен проверенный рабочий DLL. Ничего менять не нужно.' -ForegroundColor Green
        Read-Host 'Enter для выхода'
        exit 0
    }
    if ($currentHash -eq $BadHash) {
        Write-Host 'Обнаружен известный проблемный файл CEB6432F... Будет заменён после проверки нового.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'Текущего nvngx_dlssnr.dll в папке игры нет.' -ForegroundColor Yellow
}

$source = Find-ValidDll $gameDir
if (-not $source) {
    Write-Host "`nАвтопоиск не нашёл файл с нужным SHA-256 и валидной подписью NVIDIA." -ForegroundColor Yellow
    Write-Host 'Сейчас можно вручную выбрать nvngx_dlssnr.dll, который у тебя уже есть из легитимного источника.' -ForegroundColor Yellow
    $source = Pick-DllWithDialog
}

if (-not $source -or -not (Test-Path $source)) {
    throw 'Рабочий DLL не выбран. Замена не выполнялась.'
}

$sourceHash = Get-Sha256 $source
$sourceSigOk = Test-NvidiaSignature $source
Write-Host "`nНовый файл: $source"
Write-Host "SHA-256: $sourceHash"
Write-Host "Подпись NVIDIA: $sourceSigOk"

if ($sourceHash -ne $GoodHash) {
    throw "Хэш нового файла НЕ совпадает с проверенным. Ожидался: $GoodHash. Ничего не заменено."
}
if (-not $sourceSigOk) {
    throw 'У нового файла нет валидной подписи NVIDIA. Ничего не заменено.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $gameDir "$DllName.bak-$timestamp"

try {
    if (Test-Path $target) {
        Copy-Item -LiteralPath $target -Destination $backup -Force
        Write-Host "Backup: $backup" -ForegroundColor Cyan
    }

    Copy-Item -LiteralPath $source -Destination $target -Force

    $afterHash = Get-Sha256 $target
    $afterSigOk = Test-NvidiaSignature $target
    if ($afterHash -ne $GoodHash -or -not $afterSigOk) {
        throw 'Финальная проверка после копирования не пройдена.'
    }

    Write-Title 'ГОТОВО'
    Write-Host 'nvngx_dlssnr.dll успешно заменён.' -ForegroundColor Green
    Write-Host "SHA-256: $afterHash" -ForegroundColor Green
    Write-Host 'Подпись NVIDIA: OK' -ForegroundColor Green
    Write-Host "`nТеперь запусти Cyberpunk -> Home -> Дополнения -> DLSS 5 Neural Rendering" -ForegroundColor White
    Write-Host 'и нажми: Reset NR feature and clear failure latch.' -ForegroundColor White
}
catch {
    Write-Host "`nОшибка: $($_.Exception.Message)" -ForegroundColor Red
    if ((Test-Path $backup) -and -not (Test-Path $target)) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Write-Host 'Старый файл восстановлен из backup.' -ForegroundColor Yellow
    }
    throw
}
finally {
    Read-Host "`nEnter для выхода"
}
