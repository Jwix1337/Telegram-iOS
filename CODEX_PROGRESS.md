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
