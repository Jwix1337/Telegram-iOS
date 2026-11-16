# Winter Sync — iOS-интеграция, 2026-11-16

Ветка codex/winter-validation, один агент. Master, VPS/VPN, сертификаты и порты не изменялись; IPA не собиралась. Этап реализации интеграции завершён, переход к развёртыванию не выполнять.

## Реализовано

- URLSession HTTPS + WSS по фактическому API: bearer только в заголовке HTTP/первом WS frame, системный TLS, запрет redirects/cookies/cache, лимиты ответов и foreground reconnect/backoff.
- В меню зимних действий личного чата добавлен Winter Sync setup: импорт только выданных device ID/key (не admin key), проверка GET /v1/device, код/claim/подтверждение пары обеими сторонами, явная локальная привязка UUID к выбранному peer ID, отзыв пары и удаление локального ключа. Один credential не переиспользуется для разных локальных аккаунтов.
- Ключи в Keychain WhenUnlockedThisDeviceOnly. Telegram ID остаются только локально, HTTP/WS их не содержат.
- Подключение к WinterEventTransport: серверные маршруты эксклюзивны. При сбоях/отзыве/удалении ключа отсутствует автоматический fallback в технические сообщения Telegram. Старые неподключённые чаты сохраняют прежний добровольный транспорт.
- Долговечная очередь неизменяемых серверных запросов, cursor replay, отдельная дедупликация снежков/TTL120с, атомарное локальное применение батча. Ответ POST не продвигает replay cursor. Пары перечитываются каждые30с для обнаружения удалённого отзыва. Фон отменяет задачи, foreground восстанавливает состояние; SnowEffect от сети не зависит.
- Авторитетные версии серверного снеговика проецируются в существующий UI отдельно от Telegram CRDT. Конфликт409 обновляет снимок и блокирует старое действие до явного повтора с новым ID; скрытого перезаписывания нет.

## Исправленные первопричины несовместимости API

Исходный сервер не выдавал собственный device_id и автора/время приглашения в снимке, поэтому безопасная идентификация invitee была невозможна. Добавлены фактические GET /v1/device и поля creator_id/created_at/cursor; документация обновлена. SQLite-v1 мигрирует без потери состояния, исторические ответы обогащаются метаданными при replay/idempotent retry. Глобальный watermark учитывает шапки, опубликованные через другую согласованную пару. Нужна именно эта обновлённая версия сервера; старый сервер не поддерживается молчаливыми предположениями.

## Реальные проверки

10 серверных unittest прошли: прежние ACL/pairing/rate/idempotency/конкуренция + новый контракт identity/snapshot, миграция старой SQLite и исторических событий, глобальный watermark. Синтаксический tree-sitter разбор 8 затронутых Swift-файлов без ошибок, git diff --check чистый. Это НЕ Swift type checking.

Добавлены 5 XCTest URLSession/DTO (HTTPS, bearer/no URL token, wire без Telegram ID/Lamport clock,409, обязательные поля снимка) и регрессионный тест запрета fallback. Они НЕ запускались: Swift/Xcode/iOS SDK отсутствуют в текущем Linux. Существующий Foundation test runner расширен для client tests на macOS12+; GitHub Actions ранее отключены, не запускались.

## Изменённые файлы

SnowEffect/Sources: WinterSyncClient.swift, WinterSyncService.swift, WinterSyncSetupViewController.swift (новые), WinterEventTransport.swift.
SnowEffect/Tests: WinterSyncClientTests.swift (новый), WinterEventTests.swift.
TelegramUI/Sources/WinterChatInteractions.swift; SettingsUI/Sources/Themes/SnowHatPublishing.swift.
build-system/SnowEffect/test_winter_models.py; winter-sync/app.py, test_service.py, API.md; CODEX_PROGRESS.md.

## Блокеры и следующая проверка (только отдельным заданием)

Нет real HTTPS/WSS endpoint/device credentials и проверки на двух iPhone. Нужны Apple SDK typecheck/XCTest, реальная проверка Keychain/привязки/фона/reconnect/отзыва/конкуренции. Не заявлять, что сеть или сборка iOS проверена. Не развёртывать VPS и не собирать IPA автоматически.

Команды:
```
cd /workspace/TelegramSnow
python3 -m unittest discover -s winter-sync -q
git diff --check
# только на macOS со Swift:
python3 build-system/SnowEffect/test_winter_models.py
# iOS XCTest target: //submodules/SnowEffect:SnowEffectTests
```

---

# Winter Sync Service — серверный этап, 2026-11-16

Ветка codex/winter-validation. Работа одним агентом. Предыдущий прогресс сохранён ниже.

Реализовано только в winter-sync/: FastAPI + SQLite, version1, строгая схема, одноразовый код с подтверждением обоими устройствами, хеши случайных ключей/отзыв, ACL, идемпотентный журнал, курсоры HTTP/WebSocket, шапки, снежки, атомарные версии общего снеговика. Swift-код не изменён. Telegram identity не подтверждается: используются отдельные псевдонимные устройства.

Проверено: 8 целевых unittest прошли: авторизация/посторонние, pairing/expiry/согласие, replay/конфликт, лимиты/схема/размер, restart/cursor, конкурентные версии, полный снеговик, хеши/0600, отключение шапки, HTTP/WS/отзыв. git diff --check проходит. TestClient предупреждает о будущей замене httpx, тесты проходят на текущих зависимостях.

Изменены app.py, test_service.py, requirements.txt, requirements-test.txt, API.md в winter-sync/ и CODEX_PROGRESS.md. Тестовая SQLite временная. На VPS ничего не развёрнуто; VPN/Xray/3x-ui/порты/TLS/firewall/службы не менялись. IPA не собиралась.

Осталось для отдельных будущих этапов: production/TLS/нагрузочные проверки, Swift-клиент и два iPhone, архивирование/ротация ключей. При заполнении квоты журнала возвращается507 вместо потери событий. Подробная спецификация и эксплуатационные ограничения: winter-sync/API.md. GitHub Actions ранее отключены.

Целевая команда: python3 -m unittest discover -s winter-sync -q

Серверный этап завершён. Остановиться: не переходить автоматически к iOS или VPS.

---
# Telegram Snow — состояние на 2026-11-16

Ветка локально master, база e5326ede940f12b5629c9d9e2eea48171731f0da. Git-метаданные и sparse checkout восстановлены; все прежние изменения сохранены. Проверочная удалённая ветка codex/winter-validation; origin/master НЕ изменена. Работа одним агентом. Резервная копия до восстановления: /workspace/scratch/before-resume.

## Реализовано в коде

Снег/накопление/очистка, десять шапок и редактор, единый WinterEventTransport, подтверждённая исходящая очередь, авторизация по Telegram-автору, дедупликация/TTL, снежки, совместный снеговик с детерминированным слиянием, экспорт изображения и настройки. Транспорт использует видимые сообщения с подтверждением, поэтому отдельный HTTPS backend не требуется. VPN, Xray, 3x-ui и VPS не изменялись.

## Завершённые этапы этой сессии

1. Аудит и восстановление настоящей Git-ветки без потери выборочной копии.
2. Исправлен дефект одновременных приглашений: открытый редактор и callbacks теперь переключаются на каноническую сессию, вместо отправки деталей в старую.
3. Добавлены проверки канонической сессии, UUID-дедупликации и восстановления журнала шапок. Подготовлен runner существующих Foundation XCTest без Telegram, macOS workflow и безопасный models_only режим прежнего build workflow.
4. Проверка упаковки: 14 тестов — 12 прошли, 2 macOS-only пропущены. git diff --check проходит. Swift тесты/проверка синтаксиса НЕ запускались успешно.

## Блокирующая ошибка

Запрос запуска существующего workflow с models_only=true отклонён GitHub: HTTP 422, Actions has been disabled for this repository. Чтение административной настройки Actions через интеграцию недоступно: HTTP 403 Resource not accessible by integration. Нужно включить GitHub Actions вручную в репозитории (Actions → Enable workflows / Settings → Actions), сохранив существующую политику разрешённых actions. Не считать CI запущенным или сборку успешной.

Локально Swift не установлен. Попытка использовать официальный Docker Swift 6.1.3 не дошла до компиляции из-за VFS/нехватки диска; только созданный образ удалён, свободно около 6,9 GB. Не повторять такой Docker запуск без изменения способа хранения.

## Изменено сейчас

- submodules/TelegramUI/Sources/WinterChatInteractions.swift
- submodules/SnowEffect/Sources/WinterSnowmanViewController.swift
- submodules/SnowEffect/Tests/WinterEventTests.swift
- build-system/SnowEffect/test_winter_models.py
- .github/workflows/winter-model-tests.yml
- .github/workflows/build-telegram-snow.yml (добавлен models_only; прежняя device сборка по умолчанию сохранена)
- CODEX_PROGRESS.md

Коммит a2aaf91 сохраняет прежние этапы и интеграцию; a48c3c9 добавляет models_only. Последующие коммиты могут содержать обновление этого прогресса. git diff origin/master показывает общий накопленный патч.

## Следующее конкретное действие

После включения Actions выполнить только модели; исправить реальные ошибки компиляции/тестов, повторить целевые проверки. Затем запускать одну device сборку закреплённым workflow. Два iPhone, UI/клавиатура/звонки, анимации по кадрам, доставка/повторный запуск/конкурентные действия пока НЕ проверены.

Команды из /workspace/TelegramSnow:
```
git status --short
git log -3 --oneline
git diff origin/master --stat
python3 -m unittest discover -s build-system/SnowEffect/tests -q
gh workflow run build-telegram-snow.yml --ref codex/winter-validation -f models_only=true
gh run list --branch codex/winter-validation --limit 3
```

Локальный runner при наличии native Swift: python3 build-system/SnowEffect/test_winter_models.py.

После зелёных моделей и проверки UI-сборки:
```
gh workflow run build-telegram-snow.yml --ref codex/winter-validation -f models_only=false -f api_mode=own -f include_extensions=false -f runner=xcode-27
```

IPA сохраняет org.snoweffect.TelegramSnow, использует macOS 27/Xcode 27.1/Bazel 9.2.0 и существующие Secrets (их значения не читать). После успеха скачать artifact TelegramSnow-iPhone-SideStore-own-api-<run>, извлечь IPA и импортировать в SideStore с прежним Apple ID и bundle ID. Полная инструкция в SNOW_EFFECT.md. Старая IPA этапа до этих изменений не является новой сборкой.
