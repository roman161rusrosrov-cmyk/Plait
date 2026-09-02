# DLSSNR Fixer for Cyberpunk 2077

Однокнопочный фикс `nvngx_dlssnr.dll` для Cyberpunk 2077 / RenoDX DLSS 5 Neural Rendering.

## Что делает v1.1.0

Теперь **не нужно искать DLL вручную**.

`START_FIX.cmd` автоматически:

1. проверяет, что Cyberpunk 2077 закрыт;
2. находит `Cyberpunk 2077\bin\x64`;
3. скачивает пакет `DLSS NR 310.8.0` из upstream-репозитория `RankFTW/rhi-repo`;
4. проверяет SHA-256 скачанного ZIP;
5. распаковывает `nvngx_dlssnr.dll` во временную папку;
6. проверяет SHA-256 самой DLL;
7. проверяет валидную цифровую подпись NVIDIA;
8. делает backup текущей DLL;
9. ставит рабочую DLL в Cyberpunk;
10. ещё раз проверяет установленный файл;
11. при ошибке восстанавливает предыдущее состояние.

## Проверки

Ожидаемый SHA-256 DLL:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

Известный проблемный файл:

```text
CEB6432F6FBDF44D886014BCD47241932BF8B67439FEEF9BBDD0961436662650
```

Ожидаемый SHA-256 upstream ZIP `nvngx_dlssnr_310.8.0.zip`:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

Источник загрузки во время запуска:

`RankFTW/rhi-repo` → release `dlssnr-310.8.0` → `nvngx_dlssnr_310.8.0.zip`

## Как пользоваться

1. Полностью закрой Cyberpunk 2077.
2. Скачай последнюю версию из **Releases**.
3. Распакуй ZIP.
4. Запусти `START_FIX.cmd`.
5. Дождись надписи `SUCCESS`.
6. Запусти Cyberpunk.
7. Нажми `Home` → `Дополнения / Add-ons` → `DLSS 5 Neural Rendering`.
8. Нажми `Reset NR feature and clear failure latch`.
9. Если NR сразу не активировался, один раз переключи в игре `DLSS Quality → Balanced → Quality`.

После успешного запуска счётчик `Successful NR frames` должен начать расти.

## Важно

DLL NVIDIA **не хранится в этом репозитории и не включена в релиз**. Скрипт скачивает её напрямую из указанного upstream-релиза во время запуска и устанавливает только после прохождения проверок целостности и цифровой подписи.

Проект не связан с NVIDIA, CD Projekt RED, RenoDX или RHI.
