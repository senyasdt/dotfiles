# AGENTS.md

Этот репозиторий содержит персональные `dotfiles`, управляемые через `chezmoi`.

Документ предназначен для людей и агентных инструментов, которые вносят изменения в репозиторий. Цель: не ломать профильную логику, не путать source и live-файлы, не коммитить generated-state.

## 1. Главный принцип

Единственный источник истины — содержимое этого репозитория, а не live-файлы в домашней директории или в Windows-профиле.

Для управляемых файлов:

- редактировать предпочтительно source-файлы внутри репозитория;
- если правка была сделана в live-файле, её нужно синхронизировать обратно через `chezmoi add <path>` или осознанным копированием в source;
- после правок проверять `chezmoi diff` и только потом применять изменения.

Не считать runtime-состояние, логи, кэши и временные бэкапы частью конфигурации, если это явно не подтверждено структурой репозитория.

## 2. Что это за репозиторий

Репозиторий кроссплатформенный:

- Unix / Linux / macOS: `zsh`, `nvim`, CLI-инструменты, bootstrap;
- Windows desktop: `PowerShell`, `komorebi`, `whkd`, `AutoHotkey`, `yasb`, `vial`;
- часть путей включается или исключается профилями и OS-логикой через `.chezmoiignore.tmpl`.

Ключевые профили:

- `lite` — headless / SSH / low-resource;
- `full` — основной CLI-набор;
- `desktop` — GUI-слой поверх `full`.

Перед изменением файлов, зависящих от платформы или GUI, нужно учитывать active profile и правила в `.chezmoiignore.tmpl`.

## 3. Где что лежит

Основные зоны:

- `dot_config/**` — source для `~/.config/**`;
- `AppData/**` — Windows-специфичные source-файлы;
- `Documents/**` — Windows PowerShell-пути;
- `nvim-full/**`, `nvim-lite/**` — отдельные редакторские профили;
- `dot_config/chezmoi/chezmoi.toml` — настройки самого `chezmoi`;
- `.chezmoiignore.tmpl` — логика исключений по OS, профилям и generated-файлам.

Desktop / Windows-узлы, к которым надо относиться особенно аккуратно:

- `AppData/Roaming/Microsoft/Start Menu/Programs/Startup/*.cmd`
- `dot_config/yasb/**`
- `dot_config/vial/**`
- `dot_config/autohotkey/**`
- `komorebi.json`
- `applications.json`
- `dot_config/whkdrc`

## 4. Правила изменения конфигурации

При любом изменении:

1. Понять, source это файл или live-копия.
2. Если правка делается в live-файле, синхронизировать её в source.
3. Не коммитить generated/runtime-файлы по инерции.
4. Если добавляется новый реально используемый конфиг или скрипт, убедиться, что он:
   - не отсекается `.chezmoiignore.tmpl`;
   - лежит в правильной source-папке;
   - попадает в apply для нужной платформы и профиля.

Для точечных изменений предпочтительно использовать:

```sh
chezmoi diff
chezmoi apply -- <path1> <path2>
```

Глобальный `chezmoi apply` запускать только если нет конфликтов в unrelated-файлах.

## 5. Live-файлы и source-файлы

Для Windows и desktop-конфига часто существует пара:

- source в репозитории;
- live-файл в `/mnt/c/Users/druzh/...` или в Windows `%USERPROFILE%`.

Если агент исследует проблему через live-файл и находит там отличие, нужно проверить:

- есть ли такой файл в source;
- не устарел ли source относительно live;
- не является ли live-файл generated-state.

Пример правильного поведения:

- `yasb/config.yaml`, `yasb/styles.css`, `yasb/scripts/*.py|*.ps1` — это конфигурация/логика, их нужно хранить в source;
- `yasb.log`, `yasb.log.*`, `vial_layer.json`, `vial_layout.json` — это runtime-state, их хранить не нужно;
- startup-скрипты в `AppData/.../Startup/*.cmd` — это source, если они реально используются;
- временные копии вида `*.bak`, `*.backup`, `*_backup.py`, `config_old.yaml` — обычно не source, если только они не нужны как осознанный migration-asset.

## 6. Что не надо коммитить

Не добавлять в репозиторий без отдельного обоснования:

- `*.log`, `*.log.*`
- `*.bak`, `*.backup`
- `__pycache__`
- generated JSON/state-файлы
- временные копии конфигов
- локальные runtime-артефакты GUI-приложений

Актуальный список исключений задаётся в `.gitignore` и `.chezmoiignore.tmpl`. Если в рабочем процессе регулярно появляются новые мусорные файлы, сначала обновить ignore-правила, потом коммитить остальное.

## 7. Правила для `yasb`, `AHK`, `vial`, desktop automation

Для этой подсистемы действуют дополнительные практические правила:

- меню, кнопки и логика `yasb` должны храниться в `dot_config/yasb/**`;
- если `yasb` вызывает внешние `.cmd`/`.ps1`, эти скрипты тоже должны быть заведены в source;
- startup-скрипты Windows должны оставаться согласованными с текущей логикой `yasb`, `komorebi`, `vial-helper`, `AutoHotkey`;
- если меняется live-логика `AutoHotkey`, нужно проверить и source в `dot_config/autohotkey/**`, и startup-файл `autohotkey.cmd`;
- если используется безопасный wrapper для `vial`, он должен жить рядом с остальными `vial`-скриптами в `dot_config/vial/scripts/`.

## 8. Шифрование и приватные данные

В репозитории используется `chezmoi` с `age`.

См.:

- `dot_config/chezmoi/chezmoi.toml`

Нельзя:

- коммитить приватные ключи;
- коммитить расшифрованные чувствительные данные, если файл должен быть encrypted;
- изменять encryption-flow без явной необходимости.

Если файл выглядит приватным, сначала проверить, не должен ли он быть `private_*`, шаблоном или encrypted-asset.

## 9. Проверка перед коммитом

Минимальный чеклист:

1. `git status`
2. `chezmoi diff`
3. проверить, что в staged только осознанные source-файлы
4. убедиться, что runtime/log/backup не попали в индекс
5. по возможности применить точечно через `chezmoi apply -- ...`

Если менялись Windows desktop-файлы:

- проверить `yasb`;
- проверить startup-скрипты;
- проверить, не расходятся ли source и live-копии.

## 10. Предпочтительный стиль коммитов

Коммиты должны быть узкими и тематическими.

Хорошо:

- один коммит на `yasb`/menu/daemon controls;
- отдельный коммит на ignore-cleanup;
- отдельный коммит на синхронизацию missing source-файлов.

Плохо:

- смешивать `zsh`, `nvim`, `yasb`, `PowerShell`, generated-state и ignore-cleanup в одном коммите.

## 11. Куда класть локальные AGENTS

Этот файл — общий для всего репозитория и должен лежать в корне:

- `AGENTS.md`

Если появится необходимость в специальных инструкциях, можно добавлять локальные файлы:

- `dot_config/yasb/AGENTS.md` — для `yasb`, popup-меню, desktop widgets;
- `dot_config/vial/AGENTS.md` — для `vial`, `vial-helper`, безопасного запуска;
- `dot_config/autohotkey/AGENTS.md` — для структуры AHK-скриптов и startup-логики.

Но общий источник правил должен оставаться в корне репозитория.
