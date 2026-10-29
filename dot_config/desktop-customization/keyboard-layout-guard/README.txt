Автоматическая очистка раскладок после Apex

Помощник запускается при входе текущего пользователя в Windows и работает без окна.
Раз в 2 секунды он проверяет список загруженных раскладок. Пока процесс r5apex
или r5apex_dx12 запущен, лишние раскладки не выгружаются. После выхода из игры
обычные US (04090409) и Russian (04190419) автоматически выгружаются.
Если Windows удерживает раскладку, попытки повторяются каждые 2 секунды.

Это автоматическая очистка после игры, а не запрет загрузки внутри Apex.
Во время игры стандартные раскладки могут присутствовать.

Очистка выполняется только при наличии ОБЕИХ одобренных кастомных раскладок:
English - Technical AltGr: a0010409 / ENTECH.dll / HKL F0010409
Russian - Technical AltGr: a0020419 / RUTECH.dll / HKL F0020419
При изменении или отсутствии кастомных раскладок помощник ничего не выгружает.
Другие раскладки не затрагиваются. Настройки языков, системные DLL и игра
не изменяются. Нет перехвата клавиш, внедрения в игру или сетевых запросов.

Общий автозапуск (рекомендуется с 29 октября 2026):
После установки обеих кастомных раскладок развернуть Windows desktop targets,
затем выполнить provision/windows/desktop.ps1 -Action Install -IncludeLayoutGuard
с -Root, указывающим на развёрнутый desktop-customization. Это собирает помощник
и ставит startLayoutGuard: true в desktop.json. Start-Session.ps1 запускает его
независимо от AHK, панели и менеджера окон. Start.ps1 можно вызвать вручную:
повторный запуск сохраняет существующий процесс, чужая копия не останавливается.
Сборка с -Action Build сама по себе не включает очистку при входе.
Перед повторной сборкой работающего помощника вызвать его exe с --stop.
После повторного применения desktop.json через chezmoi опцию нужно включить снова:
по умолчанию она false, так как кастомные раскладки устанавливаются отдельно.
Uninstall.ps1 отключает опцию и останавливает помощник; раскладки сохраняются.

Старый самостоятельный автозапуск через Install.ps1 (legacy):
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
Значение: TechnicalAltGrLayoutGuard
Программа: TechnicalAltGrLayoutGuard.exe в этой папке.
Не перемещайте папку, пока помощник установлен.

Проверка работы: status.txt и events.log в этой папке.
Исходные настройки для справки: backup\keyboard-layout.reg,
backup\language-profile.reg и backup\startup-before.json.

Отключение: запустить Uninstall.ps1 через PowerShell от своего пользователя.
Скрипт убирает только свой автозапуск и останавливает помощник.
Кастомные раскладки сохраняются. Импорт резервных .reg для отключения не нужен.

Сборка (в папке помощника):
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /platform:x64 /optimize+ /out:TechnicalAltGrLayoutGuard.exe LayoutGuard.cs

Документация Windows:
https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unloadkeyboardlayout
https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys
