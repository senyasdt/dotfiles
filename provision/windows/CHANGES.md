> Исторический этап 27 октября. Текущая схема LeopardWM и изменения выпуска: [28 октября](RELEASE-2026-10-28.md).

# Все изменения стабильного Windows-окружения

Подготовлено 27 октября 2026 года в `windows-desktop-integration` от свежего
`origin/master`. Ветка объединяет опубликованный `yasb-catppuccin` с текущим master.
Работающее окружение HOMEPC этим переносом не переключалось.

## Целевая схема

**YASB 2.0.7+ → DesktopBridge → штатный komorebi/whkd с девятью BSP-пространствами.**
ScriptLauncher остаётся единым владельцем AHK. Vial/ZMK читаются существующими
интеграциями; MyDockFinder и FinderWidgets исключены из установки и автозапуска.
`-Bar none -Theme classic` оставляет минимальный вариант восстановления.

## Панель, док и библиотека приложений

- Верхняя панель Cold Grey: нейтральный полупрозрачный серый, приглушённые голубые
  акценты, компактные интервалы и облегчённый матовый трей.
- Пространства/раскладка komorebi, активное окно, часы, медиа, язык, погода, звук,
  трей, VPN, AHK, Vial/ZMK и меню обслуживания собраны в одной панели.
- Нижний док использует нативный YASB Taskbar: открытые приложения, пользовательские
  закрепления, preview и корректные области нажатия. Подложка только у активного.
  Принудительных закреплений Проводника/Терминала нет.
- Убран пустой Grouper и искусственная минимальная ширина; пустой док и reveal
  у всей нижней границы учитываются существующим DesktopBridge.
- Док скрывается при занятых пространствах и плавно появляется; fullscreen имеет
  приоритет. Нет отдельного нового watchdog или владельца анимации поверх bridge.
- Встроенный Launchpad с поиском импортирует Start Menu/AppsFolder. Alt+F12
  регистрируется YASB без AHK; одиночный Win доступен через управляемый AHK.
  Независимый All Applications открывает `shell:AppsFolder` даже без панели/AHK.

## Надёжность komorebi и YASB

- Единый Start-DesktopWM: ограниченные таймауты CLI, проверка готовности, аккуратный
  restart и проверяемый opt-in ремонт занятого IPC junction. Нет массового Kill.
- Start-Yasb задаёт реальные Known Folder пути и явный CLI/PATH. Проверка IPC
  выполняется до остановки работающей панели; запрещённый контекст не заменяет её
  заведомо неисправным запуском. Выключенный WM допускается для штатных повторов.
- Переподключение после WM restart остаётся штатным в YASB, без reload всей панели.
- Исправлен цикл ActiveLayout 2.0.7: все девять поддерживаемых раскладок, включая
  Scrolling, присутствуют в основном, классическом и резервном YAML.
- Конфиг komorebi по умолчанию остаётся BSP на всех девяти пространствах.

## AHK, игровые блокировки и клавиатуры

- Один ScriptLauncher управляет группами скриптов и списками блокирующих процессов.
  Объединяются все блокировки, исключаются дубликаты, выдерживается задержка
  возобновления 15 секунд, сохраняются ручные выключения и восстановление состояния.
- Apex/Battlefield и их указанные ранние запускатели полностью останавливают AHK.
  Контроллер меню не обходит правила и не запускает интерпретаторы напрямую.
- Старое имя `mydockfinder-hotkeys.ahk` сохранено для правил/ручных состояний;
  код больше не обращается к MyDockFinder. Classic открывает AppsFolder,
  профиль YASB использует его Launchpad. Win+E и другие сочетания сохраняются.
- Vial открывается безопасным wrapper с освобождением HID помощником; overlay
  использует подписи AHK. ZMK и Vial бинарники/прошивки не входят в Git.
- Technical AltGr guard отделён и включается только явно после установки двух
  ожидаемых раскладок. Он не становится обязательной частью нового ПК.

## Обслуживание, погода и VPN

- Меню ↻ запускает/останавливает/перезапускает помощники, управляет AHK и Vial,
  содержит ручное восстановление отрисовки ChatGPT и диагностический запуск без GPU.
  Аппаратное ускорение по умолчанию не отключается, автоматического GPU-reset нет.
- Записывается ограниченный локальный журнал операций служб и ручного восстановления
  графики. Аварийные дампы YASB включаются отдельно штатной административной командой.
- Погода использует бесплатный Open-Meteo. Кеш/координаты локальны; домашнее VPN-
  правило для API и токены не включаются в автоматическое восстановление ПК.
- VPN callbacks добавляют/проверяют домен через существующий клиент. Авторизация
  DPAPI остаётся пользовательской и требует повторной регистрации на новом ПК.

## Оформление приложений и откат

- Общая Cold Grey палитра для VS Code, Windows Terminal, WezTerm и привязки Neovim.
  Менеджер меняет только оформление, сохраняет точные байты с SHA256, поддерживает
  WhatIf/idempotency и отказывается затирать последующие пользовательские изменения.
- Chrome использует обычное выбранное владельцем оформление. Эксперименты с custom
  theme/new-tab/обоями были сняты; расширения и профиль Chrome не устанавливаются.
- YASB хранит отдельный private snapshot и команды возврата к предыдущему виду
  или классической панели. Исторические MyDock имена сохранены только для отката.

После первого CI исправлена совместимость Restore с PowerShell 7: JSON-индекс
может быть Int64, тогда как Windows PowerShell 5.1 возвращает Int32. Оба типа
принимаются после проверки диапазона; строки, дроби, отрицательные и слишком
большие индексы отвергаются. Четыре regression cases добавлены в тесты, полный
Windows-набор запускается в обеих версиях PowerShell, без изменения live-профиля.

## Установка, обновление и совместимость

- Native PowerShell restore планирует действия по умолчанию; Apply задан явно.
  Установка использует целевого Windows-пользователя, один Desktop Session Startup
  и не дублирует старые задачи/ярлыки. Ранее установленные программы не удаляются.
- Поддерживаемый `-Bar` теперь `none|yasb`. FinderWidgets исключён chezmoi ignore,
  не требуется установщику и не собирается/не запускается при восстановлении.
- Профили `lite`, `full`, `full,desktop` разделены. Исправлено преимущество явного
  параметра над старым env; `full,desktop` одинаково принимается массивом и строкой.
- Сохранены изменения свежего master: mise/Java 21/Docker, AeroSpace и macOS WezTerm,
  zsh PATH. Содержимое Ansible, packages manifest, AeroSpace и mise не заменялось
  старыми версиями из тематической ветки.
- update.ps1 разрешён через общий restore: preview без изменений, clean source,
  fast-forward pull и сохранение выбора темы/панели. Прямой безусловный apply убран.
- Windows GUI восстанавливается этими же скриптами; Ansible остаётся Unix-слоем.
  WinRM/контроллер, HID прошивки, VPN секреты и весь AppData не разворачиваются.

## Проверено и что ещё требуется

- Девять комбинаций OS/profile для Linux/macOS/Windows, два выбора панели и темы.
- Три YAML-варианта по схеме YASB 2.0.7 и обязательный полный список раскладок.
- Windows PowerShell 5.1 и PowerShell 7: синтаксис, планы, конфликт env/Profiles, restore preview,
  40 assertions ScriptLauncher, 23 проверки оформления/отката, сборки bridge/guard
  и policy test DesktopBridge. Реальные AHK/HID не запускались.
- Ранее живьём проверены restart/reconnect YASB, исправление нагрузки с одного
  занятого ядра до ~0.1 CPU s за 5 wall s и память около 160 MB.
- Не выполнены чистая Windows VM установка, перезагрузка, новая учётная запись,
  нативный запуск на macOS/Linux и длительный прогон последнего исправления.
  Сначала review/CI и день-два обычной работы; затем финальное слияние в master.

## Остаётся отдельно

- `komorebi-scrolling`: Alt+wheel, независимые колонки, собственная native-сборка,
  патчи и переключатель stock/native. В этой интеграции этих файлов/механизмов нет.
- Незакоммиченные настройки группировки приложений и Nord WezTerm в основном
  checkout не включены. Live-конфиги, pins, runtime, бинарники и private snapshots
  не переносятся в Git.

## Полный список файлов относительно master

База сравнения: `c7243df5b27967edc33a0508a8ff1ec6b807c31c`. Всего 95 записей изменений.

| Статус | Файл / переименование |
| --- | --- |
| M | `.chezmoiignore.tmpl` |
| A | `.gitattributes` |
| M | `.github/workflows/chezmoi-ci.yml` |
| M | `.gitignore` |
| M | `AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` |
| M | `AppData/Roaming/Code/User/settings.json` |
| D | `AppData/Roaming/Microsoft/Start Menu/Programs/Startup/autohotkey.cmd` |
| D | `AppData/Roaming/Microsoft/Start Menu/Programs/Startup/komorebi.cmd` |
| D | `AppData/Roaming/Microsoft/Start Menu/Programs/Startup/yasb.cmd` |
| A | `AppData/Roaming/Microsoft/Start Menu/Programs/Startup/zmk-helperd.cmd` |
| M | `README.md` |
| M | `WORKFLOW.md` |
| M | `dot_config/autohotkey/creative_macropad.ahk` |
| A | `dot_config/autohotkey/mydockfinder-hotkeys.ahk` |
| M | `dot_config/autohotkey/zmk-text-replacements.ahk` |
| A | `dot_config/desktop-customization/Open-AppLibrary.ps1` |
| A | `dot_config/desktop-customization/Start-Session.ps1` |
| A | `dot_config/desktop-customization/appearance/Manage-Appearance.ps1` |
| A | `dot_config/desktop-customization/appearance/README.md` |
| A | `dot_config/desktop-customization/appearance/obsidian/cold-grey.css` |
| A | `dot_config/desktop-customization/appearance/palette.json` |
| A | `dot_config/desktop-customization/appearance/vscode.json` |
| A | `dot_config/desktop-customization/appearance/wezterm.toml` |
| A | `dot_config/desktop-customization/appearance/windows-terminal.json` |
| A | `dot_config/desktop-customization/desktop.json.tmpl` |
| A | `dot_config/desktop-customization/finder-widgets/Actions.ps1` |
| A | `dot_config/desktop-customization/finder-widgets/FinderWidgets.cs` |
| A | `dot_config/desktop-customization/finder-widgets/Manage.ps1` |
| A | `dot_config/desktop-customization/keyboard-layout-guard/Install.ps1` |
| A | `dot_config/desktop-customization/keyboard-layout-guard/LayoutGuard.cs` |
| A | `dot_config/desktop-customization/keyboard-layout-guard/README.txt` |
| A | `dot_config/desktop-customization/keyboard-layout-guard/Uninstall.ps1` |
| A | `dot_config/desktop-customization/komorebi-support/README.txt` |
| A | `dot_config/desktop-customization/komorebi-support/Start-DesktopWM.ps1` |
| A | `dot_config/desktop-customization/komorebi-support/settings.json` |
| A | `dot_config/desktop-customization/script-launcher/LauncherTests.cs` |
| A | `dot_config/desktop-customization/script-launcher/Manage.ps1` |
| A | `dot_config/desktop-customization/script-launcher/README.txt` |
| A | `dot_config/desktop-customization/script-launcher/ScriptLauncher.cs` |
| A | `dot_config/desktop-customization/script-launcher/config.json` |
| A | `dot_config/desktop-customization/yasb-catppuccin/AppIcons.cs` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Apply Catppuccin.cmd` |
| A | `dot_config/desktop-customization/yasb-catppuccin/DesktopBridge.cs` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Ensure-DockIcons.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Import-Apps.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/KomorebiFeed.cs` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Manage.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/README.md` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Repair-ChatGPTRendering.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Restore Before MyDock.cmd` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Restore Previous.cmd` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Services.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Show Windows Taskbar.cmd` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Snapshot.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Start-ChatGPTRenderMode.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Start-Yasb.ps1` |
| A | `dot_config/desktop-customization/yasb-catppuccin/Start.vbs` |
| A | `dot_config/desktop-customization/yasb-catppuccin/config-predock.yaml` |
| A | `dot_config/desktop-customization/yasb-catppuccin/config.yaml` |
| A | `dot_config/desktop-customization/yasb-catppuccin/settings.example.json` |
| A | `dot_config/desktop-customization/yasb-catppuccin/styles-predock.css` |
| A | `dot_config/desktop-customization/yasb-catppuccin/styles.css` |
| A | `dot_config/desktop-customization/yasb-catppuccin/win-launchpad.ahk` |
| A | `dot_config/open-app-library.cmd` |
| M | `dot_config/start-autohotkey.cmd` |
| M | `dot_config/start-daemons.cmd` |
| M | `dot_config/stop-autohotkey.cmd` |
| M | `dot_config/stop-daemons.cmd` |
| M | `dot_config/vial/scripts/open_vial_safely.ps1` |
| M | `dot_config/wezterm/theme` |
| A | `dot_config/wezterm/themes/cold-grey.toml` |
| R082 | `dot_config/yasb/config.yaml` → `dot_config/yasb/config.yaml.tmpl` |
| A | `dot_config/yasb/scripts/Add-VpnDomainGui.ps1` |
| A | `dot_config/yasb/scripts/Open-RouterVpn.ps1` |
| A | `dot_config/yasb/scripts/RouterVpnClient.ps1` |
| A | `dot_config/yasb/scripts/export_ahk_bindings.py` |
| M | `dot_config/yasb/scripts/vial_layout_overlay.py` |
| A | `dot_config/yasb/scripts/vial_layout_overlay_launcher.vbs` |
| A | `dot_config/yasb/scripts/vpn_domain_check_launcher.vbs` |
| A | `dot_config/yasb/scripts/vpn_domain_submit_launcher.vbs` |
| M | `komorebi.json` |
| A | `nvim-full/lua/config/cold_grey_palette.lua` |
| M | `nvim-full/lua/config/theme_sync.lua` |
| M | `provision/README.md` |
| A | `provision/tests/Test-Appearance.ps1` |
| A | `provision/tests/check_catppuccin_profile.py` |
| A | `provision/tests/check_desktop_profiles.py` |
| A | `provision/windows/CHANGES.md` |
| A | `provision/windows/README.md` |
| A | `provision/windows/Test-Desktop.ps1` |
| A | `provision/windows/desktop.ps1` |
| A | `provision/windows/generate_appearance.py` |
| M | `provision/windows/install.ps1` |
| A | `provision/windows/restore.ps1` |
| M | `provision/windows/update.ps1` |
