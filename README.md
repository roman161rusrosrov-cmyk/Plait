# DLSSNR Fixer / Auto Launcher for Cyberpunk 2077

Автоматический фикс и запуск Cyberpunk 2077 с RenoDX DLSS 5 Neural Rendering.

## Что делает v1.2.0

Главный файл теперь — `START_DLSS5.cmd`.

Он автоматически:

1. проверяет, что Cyberpunk 2077 закрыт;
2. находит `Cyberpunk 2077\bin\x64`;
3. проверяет `nvngx_dlssnr.dll`;
4. если DLL отсутствует или неправильная — скачивает проверенный пакет `DLSS NR 310.8.0` из `RankFTW/rhi-repo`;
5. проверяет SHA-256 ZIP;
6. проверяет SHA-256 самой DLL;
7. проверяет цифровую подпись NVIDIA;
8. делает backup старой DLL перед заменой;
9. находит установленный `renodx-dlss5*.addon64`;
10. создаёт backup `ReShade.ini`;
11. автоматически добавляет DLSS5 add-on в `[ADDON] LoadFromDllMain` для ранней загрузки;
12. перепроверяет конфигурацию;
13. запускает `Cyberpunk2077.exe`.

## Почему добавлена ранняя загрузка

Для DLSS5/RenoDX add-on ранняя загрузка через:

```ini
[ADDON]
LoadFromDllMain=renodx-dlss5-....addon64
```

помогает избежать ситуации, когда Neural Rendering создаётся слишком поздно и остаётся в `STANDBY/FAILED` / `NotInitialized`.

Скрипт не затирает другие add-ons из `LoadFromDllMain`: он сохраняет существующие записи и добавляет текущий DLSS5 add-on.

## Проверки DLL

Ожидаемый SHA-256 `nvngx_dlssnr.dll`:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

Ожидаемый SHA-256 upstream ZIP:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

Источник:

`RankFTW/rhi-repo` → release `dlssnr-310.8.0` → `nvngx_dlssnr_310.8.0.zip`

## Как пользоваться

1. Полностью закрой Cyberpunk 2077.
2. Скачай последний ZIP из **Releases**.
3. Распакуй его.
4. Двойной клик по `START_DLSS5.cmd`.
5. Больше ничего вручную запускать не нужно — скрипт подготовит файлы и сам запустит игру.
6. На экране предупреждения Cyberpunk DLSSNR ещё может показывать `STANDBY/FAILED` — это не показатель.
7. Загрузи сохранение и выйди непосредственно в 3D-мир.
8. Затем `Home` → `Дополнения / Add-ons` → `DLSS 5 Neural Rendering`.
9. Нормальный результат: `ACTIVE`, а `Successful NR frames` постоянно растёт.

Если после загрузки сохранения всё ещё `FAILED`, один раз нажми `Reset NR feature and clear failure latch`. Этот конкретный UI-клик ReShade внешний скрипт надёжно выполнить не может.

## Старый режим

`START_FIX.cmd` оставлен в релизе. Он только чинит/проверяет DLL и не настраивает автоматический запуск.

## Backup

Перед изменениями сохраняются резервные копии:

- `nvngx_dlssnr.dll.bak-YYYYMMDD-HHMMSS`
- `ReShade.ini.plait-auto.bak`

## Важно

DLL NVIDIA не хранится в этом репозитории и не включается в ZIP-релиз. Она скачивается во время запуска из указанного upstream-релиза и устанавливается только после проверки хэшей и цифровой подписи NVIDIA.

Проект не связан с NVIDIA, CD Projekt RED, RenoDX, ReShade или RHI.
