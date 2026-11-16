# Этап4 — локальные шапки из профиля, 2026-11-16

Один агент, ветка codex/winter-validation. Исходное дерево чистое; предыдущие этапы сохранены. Сервер/VPS/API/master не менялись, IPA/полная сборка не запускались.

Реализовано: нативный disclosure-пункт «Зимняя шапка» в обычном профиле CloudUser без botInfo. Использован прежний каталог10шапок SnowHatSprite (без изменения PNG и ID). Существующий редактор получил отдельный локальный режим: выбор/геометрия работают с черновиком; «Без шапки» меняет черновик; только «Применить» сохраняет и закрывает, «Отмена»/крестик/back не пишут настройки. Предпросмотр на штатном AvatarNode.ContentNode: реальные фото либо штатные инициалы, без уже сохранённого overlay; подписка на данные peer обновляет фото в открытом редакторе, dispose при закрытии. Тёмная/светлая тема и существующие accessibility labels сохранены.

Хранение: отдельные UserDefaults ключи SnowEffect.hatOverrides.v1.<accountID>.<peerID>; стабильные Telegram IDs, без имени/фотоURL. Disabled override маскирует опубликованную шапку. SnowHatOverlayView читает displayConfiguration (override прежде старой публикации); уведомления фильтруются account+peer. Настоящие фото и Telegram данные не меняются. Выбор локален для аккаунта на устройстве; этот путь не вызывает WinterEventTransport и не активирует серверные соединения.

Семантика прежней синхронизации сохранена: собственный редактор в Settings и owner-only saveLocal/configuration остаются отдельными. Явная публикация собственного украшения использует существующий подтверждённый Winter transport (парный сервер при активной паре, иначе видимое сообщение Telegram). Локальный профильный override не публикуется и не меняет доставленную конфигурацию. Новые сообщения/API/события не добавлены; каталог/состояние шапок снеговика не используются.

Изменены: SnowHatConfiguration.swift, SnowHatOverlayView.swift, SnowHatEditorViewController.swift, SnowHatTests.swift; PeerInfoScreen/BUILD, PeerInfoProfileItems.swift, новый WinterProfileHatController.swift; этот файл.

Реально проверено: grammar parse6Swift-файлов без ошибок (НЕ Swift-компиляция); git diff --check; существующий atlas RGBA1536x1024 с прозрачностью, catalogfilename и10непустых crops внутри границ. Проверка сначала ошибочно требовала alpha maximum255: у исходного PNG maximum254, что допустимо; проверка уточнена, ресурс не менялся. Целевая сверка используемых ContentNode/setPeer/updateSize, subscribe, DisclosureItem и push с исходными API. Добавлен XCTest для draft/cancel без записи, apply, reopening store, account/peer isolation, disabled persistence, masking newer remote updates и сохранения owner-only publication guard. XCTest НЕ выполнен: в Linux нет Swift/Apple SDK/Xcode.

Осталось: macOS typecheck/XCTest; устройство/симулятор — открыть профиль с фото и инициалами,10шапок, применение/отмена/back/снятие, повторное открытие/перезапуск, смена фотографии,2аккаунта/2пользователя; проверить посадку и отсутствие обрезания в свёрнутой/большой аватарке. Запись/оценка кадров по AGENTS.md недоступна без симулятора, визуальное качество на iPhone НЕ подтверждено. Chatlist/title hooks существовали ранее и используют общий overlay, но их интеграция/визуальная проверка в этом этапе не выполнялись (следующий этап). Нет новых подтверждений синхронизации между устройствами.

Следующий конкретный шаг: macOS целевой //submodules/SnowEffect:SnowEffectTests + PeerInfoScreen compile, затем проверка профиля на устройстве и следующий этап отображения chatlist/title. Команды продолжения: git status --short; git log -1 --oneline; git diff; читать только этот раздел и указанные файлы. Обычный push после отдельного коммита, без force и без изменения master.

---

# Этап3 — мини-снеговик и idle-потребление, 2026-11-16

Ветка codex/winter-validation, один агент, исходное дерево чистое. Сервер/VPS/сеть/master не менялись; IPA/тяжёлая сборка не запускались.

Реализовано: миниатюра только completed && isBuilt, на реальном snowAccumulationAnchorView строки ввода. В расчёт inputPanelSize добавляется выделенный ряд56–80pt, история учитывает этот inset; фактическая рамка inputPanelNode сохраняет свою измеренную высоту и сдвигается внутри зарезервированной области. Высота видимой фигуры ориентировочно48–72pt (обычно~60), пропорции сохранены. При недостатке свободной высоты(<220pt), media input/записи/скрытой панели/critical thermal миниатюра скрывается и ряд не резервируется. Клавиатура/поворот/layout/safe side insets используют существующую родительскую геометрию; поведение ещё требует устройства.

PNG mini60pt не выдаётся за видимую высоту60pt: отдельный прозрачный static render существующего Canvas обрезается по alpha-bounds (128px sample + защитный пиксель). Опора — низ обрезанной фигуры, на2pt выше верхней границы реального поля. Для точных завершённых образов Canvas использует master512, для остальных — прежние10шапок/6цветов/векторные слои. Ground/background исключены из картинки. Кеш12элементов/12MB, ключ art-v2 + все визуальные parts/hatStyle/scarfColor + тема, без лишних session IDs/версий. Перекомпозиция только при изменении картинки; никакого display link/idle-таймера/idle-анимации. Нажатие на собственный alpha-cropped rectangle открывает прежний общий редактор, окружающая пустая область не hit-test цель. Доступность: кнопка с label/hint, без motion-анимаций даже в обычном режиме.

Отдельная Codable-настройка showMiniSnowman по умолчаниюtrue, сохраняется независимо от снегопада и строительства. Переключатель добавлен в Winter Interactions. Settings/thermal/power notifications обновляют layout; background/disappear скрывают видимую работу. WinterSync теперь не стартует при отключённых взаимодействиях и отсутствии активной/подтверждённой pending hat-публикации. Активная шапка — тоже зимняя функция и требует прежней синхронизации; полностью выключенное состояние не удерживает WS/таймер. Legacy retry timer снимается при выключении. Это проверка структуры кода, не замер энергии.

Изменены: WinterMiniSnowmanView.swift (новый), WinterMiniSnowmanTests.swift (новый), WinterSnowmanViewController.swift (параметр transparent/shared Canvas), SnowEffectSettings.swift/Settings UI, WinterSyncService.swift, WinterChatInteractions.swift, ChatController.swift/ChatControllerNode.swift, этот файл.

Проверено доступное: check_snowman_assets.py прошёл (32RGBA/16imagesets/2completedpresets/10hat mappings); синтаксический grammar parse изменённых Swift без ошибок, diff whitespace. Добавлены3 XCTest: диапазоны/резерв места, независимая настройка roundtrip/legacy defaults, асимметричный alpha-bbox/bottom anchor. XCTest/Swift typecheck НЕ запускались: нет nativeSwift/Apple SDK. Серверные тесты не повторялись, сервер не менялся.

Осталось для iPhone/macOS: UIKit/actool/Swift компиляция, асимметричный alpha-coordinate test, размещение с обычной/emoji клавиатурой, multiline/вложениями/reply панелью/поворотом и safearea, hit tests жестов/кнопок/истории, первый показ/выключение и переподключение, Instruments memory/CPU/energy на60/120Hz, LowPower/thermal, запись кадров по AGENTS.md. Плавность, отсутствие перекрытия на всех раскладках и батарея НЕ подтверждены статическими проверками.

Целевые команды:
```
python3 build-system/SnowEffect/check_snowman_assets.py
git diff --check
# XCTest target на подходящем macOS/iOS SDK:
# //submodules/SnowEffect:SnowEffectTests
```

Сохранить отдельным коммитом и обычным push codex/winter-validation. Завершить только этот этап, без VPS или IPA.

---

# Этап 2 — лепка и зимняя коробка, 2026-11-16

Ветка codex/winter-validation, один агент. Исходное дерево чистое. VPS/сервер/протокол v1 не менялись, к endpoint не подключались, IPA не собиралась. Текущий HTTPS endpoint добавлен только как начальное значение setup: https://winter.ogirin-media-assets-pack.space:9443; без device key нет автоматических запросов.

Реализовано: long-press0.45с непосредственно на сугробе, затем движение>=12pt. До окончания жеста снег не списывается; отменённый/короткий жест ничего не расходует. Формирование резервирует20% нормализованной ёмкости сугроба (одинаковый снежок). Один UUID резерва, commit/cancel идемпотентны. Отмена меню/подтверждения, неудача постановки события и освобождение ticket возвращают резерв. Пока резерв удерживается, рост учитывает его в максимальной ёмкости. Недостаток снега показывает краткую подсказку. Swipe/Shake очистки сохранены; long-press вне области сугроба не добавлялся, край жеста защищён12pt.

Меню сформированного снежка предлагает бросок или добавление следующего body-part bottom/middle/head через существующий WinterEventTransport/WinterSync. Требуется принятое общее приглашение; иначе резерв возвращается и показана инструкция приглашения. Бесплатные обходы расхода через прежние кнопки броска/добавления body выключены. Списание фиксируется при подтверждённой постановке локального действия в очередь; это НЕ утверждение о серверном ACK. После сетевого409 действуют прежние refresh/explicit retry, не автоматическое повторное списание одного ticket.

После головы показывается бесплатная коробка, доступная обоим: отдельные кнопки украшений,10 шапок и6 цветов; улыбка/пуговицы выводятся автоматически при наличии головы, одинаково у обоих. Детали привязаны к исходным координатам векторного рендера, ветки позади корпуса. В процессе нет целого PNG; готовые PNG только при completed && isBuilt и точном Santa1+цвет0/1. Остальные сочетания послойные; ресурсы bare-head сохранены, но не выдаются за завершённый v1 снеговик.

Ограничение API: действующий сервер требует eyes→nose→arms→scarf→hat, поэтому свободный порядок/произвольные drag-позиции невозможно честно синхронизировать v1. Реализован разрешённый пользователем вариант добавления нажатием, с поэтапно доступными кнопками и пояснением. Цвет/тип выбираются существующими scarfColor/hatStyle. Новые события/поля/PNG transport не вводились; сервер не менялся. Если нужен произвольный порядок/drag-placement, это отдельная согласованная эволюция API, не локальная имитация.

Проверки: новый серверный ASGI-тест трёх шаров, запрета head-before-bottom, повтора ID и stale simultaneous eyes прошёл. Это имитируемые клиенты на временной SQLite, не действующий endpoint и не iPhone. Добавлен Foundation XCTest резерва/недостатка/отмены/повторногоcommit, обновлены проверки незавершённых PNG и runner. Swift/XCTest НЕ запускались: нет Apple SDK/Swift. Grammar parse изменённых Swift и diff whitespace проверены. Ресурсный check подтверждает32RGBA/16imagesets/2completedpresets/10texture mappings.

Изменено: SnowAccumulationModel/View, ChatControllerNode/ChatController/WinterChatInteractions; WinterSnowmanViewController/Appearance; WinterSyncSetupViewController (только endpoint); SnowAccumulationTests/WinterSnowmanAppearanceTests; runner/check_snowman_assets.py; winter-sync/test_integration.py (только тест); этот прогресс.

Нужны два устройства/Apple SDK: реальная компиляция, gesture arbitration с прокруткой/клавиатурой/edge navigation, визуальная посадка/анимация и все сетевые сценарии live. По AGENTS.md запись/оценка кадров не выполнена без macOS. Не заявлять о подтверждённой UI-плавности или реальном обмене.

Целевые команды:
```
PYTHONPATH=winter-sync python3 -m unittest test_integration.IntegrationTests.test_three_balls_then_ordered_decoration_without_protocol_extensions -q
python3 build-system/SnowEffect/check_snowman_assets.py
# macOS/native Swift only:
python3 build-system/SnowEffect/test_winter_models.py
```

Сохранить отдельным коммитом и обычным push в эту ветку; завершить только этап2.

---

# Этап 1: исправленные ресурсы снеговика — 2026-11-16

Ветка codex/winter-validation, один агент. Исходное рабочее дерево чистое. Прочитаны AGENTS.md/CLAUDE.md, предыдущий прогресс и manifest v2/README_RU.md из TelegramSnow_Ready_Snowmen_Fixed.zip. Сервер, аватарки, механика снега и протоколы не менялись.

Аудит: SnowAccumulationView/Model, SnowEffectView и WinterSnowballView существуют с CA-анимацией/ограниченными бюджетами/таймерами и runtime gates; WinterEventTransport/WinterSyncService реализованы в прежних этапах. Это наличие кода, не подтверждение работы на iPhone. WinterSnowmanViewController ранее рисовал только векторные слои и брал текстуры шапок из SnowHatAssets; готовых Snowman PNG в tracked ресурсах не было. Изменений в этих компонентах, кроме рендера снеговика, в этом этапе нет.

Подключены 8 НЕпраздничных образов: 32 исходных PNG без изменения байтов, 16 imagesets (мини60pt 1x/2x/3x + master512). Ресурсы включаются существующим glob TelegramUIAssets и существующей зависимостью приложения; BUILD не менялся. PREVIEW/stages не бандлятся; оригинальные manifest/README сохранены как документация происхождения. Старые ресурсы не удалялись.

SnowmanHatStyle: отдельные замороженные IDs1..10; avatar SnowHatConfiguration и её настройки не менялись. Графические текстуры переиспользуются через явную таблицу, не через состояние аватарки. Все 10 шапок и 6 цветов шарфа сохранены. Простой синий колпак из архива НЕ равен существующему стилю6 с гирляндой, цилиндр НЕ равен10 с неоном: эти PNG включены как невыбираемые сейчас ресурсы, IDs не подменялись.

Точный selector использует только Santa1+красный0/синий1 и без шапки+красный0/синий1 после наличия всех предыдущих7 деталей. Для остальных сочетаний/неполной сборки — прежние независимые CALayer-слои. Готовый PNG заменяет все слои фигуры сразу, второй шарф/шапка не накладываются. Если изображения нет — fallback на слои. Сохранены кеш текстур и reuse слоёв; добавлен ограниченный NSCache готовых PNG. Пропорции fit-square, прозрачные поля не обрезаются, 512 используется для крупного preview/export. Звёзды09/10 не включены: общее состояние не представляет звезду. stages_512 не используются как независимые слои или произвольное состояние.

Проверки: все46 PNG архива (без PREVIEW) RGBA, квадратные заявленных размеров, прозрачный фон и alpha-bbox строго внутри холста. 32 импортированных PNG побайтно совпадают с архивом. В manifest нормализованы только окончания строк CRLF→LF, JSON-значения совпадают с архивом. git diff --cached --check после нормализации чистый. Постоянный check_snowman_assets.py проверил32 PNG/16imagesets/4точныхpreset/10textureMappings, пути и metadata. Swift grammar parse4 файлов прошёл, это НЕ compilation. Добавлены3 XCTest для 60 комбинаций, неполных стадий и исключения неверных/праздничных подстановок; они НЕ запускались — нет Swift/Xcode/iOS SDK. Runner моделей дополнен для macOS. Серверные тесты не повторялись, сервер не затронут.

Ограничения: UIKit/actool/запись анимации по кадрам и производительность на iPhone не проверены; AGENTS.md требует такую проверку перед визуальным подтверждением. Разные готовые PNG немного отличаются пропорциями/деталями; не считать их геометрически совместимыми слоями. Остальные цвета/типы шапок остаются векторными. Текущий этап не добавляет новые типы шапок/звезду/новую механику.

Изменения: WinterSnowmanAppearance.swift, WinterSnowmanResources.swift, WinterSnowmanViewController.swift, WinterSnowmanAppearanceTests.swift; SnowEffect/Resources/SnowmenV2/{manifest.json,README_RU.md}; TelegramUI/Images.xcassets/SnowmanReady_*; build-system/SnowEffect/{check_snowman_assets.py,test_winter_models.py}; CODEX_PROGRESS.md.

Целевые команды:
```
cd /workspace/TelegramSnow
python3 build-system/SnowEffect/check_snowman_assets.py  # developer dependency: Pillow
# Только при наличии native Swift/macOS:
python3 build-system/SnowEffect/test_winter_models.py
```

После локальных проверок сохранить отдельным коммитом и обычным push в эту ветку; master не менять, VPS не подключать, IPA не собирать. Завершить только этап1.

---

# Публикация Winter Sync — 2026-11-16

Ветка codex/winter-validation. Перед публикацией рабочее дерево чистое; удалённая ветка отставала на три локальных коммита: e848e51 (backend), 7bd12bf (iOS transport), 4b3d9a5 (стабилизация/инструкция). Изменения кода не переписывались и история не заменялась.

Актуальная проверка: python3 -m unittest discover -s winter-sync -q — 13 тестов прошли, 2.221с. git diff --check без ошибок. Проверены добавленные строки всех трёх неопубликованных коммитов и имена 17 изменённых файлов на private keys, типовые access-token/JWT паттерны и credential/database files; совпадений нет. Выданные production-секреты не обнаружены; тестовые credentials — явные синтетические fixtures. Проверка не является гарантией полного аудита всей upstream-истории.

Сервер: winter-sync/app.py; зависимости requirements.txt и requirements-test.txt; тесты test_service.py и test_integration.py; API.md; безопасная инструкция winter-sync/DEPLOYMENT.md. __pycache__ не отслеживается Git. Swift/XCTest и реальная сеть двух iPhone по-прежнему не проверены.

Публикация: обычный fast-forward push HEAD:refs/heads/codex/winter-validation; force push запрещён. Origin/master перед публикацией: e5326ede940f12b5629c9d9e2eea48171731f0da. Сборки, развёртывание и изменения master не выполняются. После push сверить удалённый SHA с HEAD.

---

# Стабилизация Winter Sync — 2026-11-16

Ветка codex/winter-validation, один агент. Новые функции не добавлялись, рабочие компоненты не переписывались. Новых подтверждённых дефектов production-кода в доступных проверках не обнаружено.

Проверено 13 уникальных серверных тестов: 10 существующих + 3 интеграционных. Два независимых ASGI HTTP-клиента проходят pairing/взаимное подтверждение, шапки и отключение, снежки/idempotency, общий снеговик, stale-version409 и явный новый запрос, равенство снимков, рестарт SQLite/cursor replay. Дополнительно проверены существующий authenticated WS после отзыва ключа и имитированный отказ SQLite:500 не подтверждает доставку, повтор после восстановления создаёт ровно одно событие. Посторонние/подмена, schema/лимиты/миграция API покрыты существующими тестами. ASGI-клиенты — не Swift и не два iPhone.

Swift: добавлен URLProtocol XCTest ошибки notConnectedToInternet. Он НЕ запускался (нет swiftc/Apple SDK). Изменённый Swift-тест прошёл только grammar parse, git diff --check чистый. Cursor/UI/Keychain/HTTPS/WSS поведения настоящего URLSession пока не подтверждены компиляцией или исполнением. Предыдущая проверка соответствия wire-моделей фактическим API/schema остаётся актуальной; сервер в этой сессии не менялся.

Секреты: 50 доступных tracked текстовых файлов выборочного checkout проверены на private keys, GitHub/AWS credential patterns — совпадений нет, значения не выводились. Дополнительно просмотрены хранение ключей и тестовые credential fixtures. Это ограниченная проверка, НЕ полное сканирование отсутствующих upstream blobs или всей истории Git. Production keys в репозиторий не добавлялись.

Изменены: winter-sync/test_integration.py (3 теста), winter-sync/DEPLOYMENT.md (безопасный staging/rollback/NO-GO при занятом443), submodules/SnowEffect/Tests/WinterSyncClientTests.swift, CODEX_PROGRESS.md. Production код не изменён. VPS, VPN, службы, порты, сертификаты и firewall не трогались; IPA не собиралась.

Готовность: серверная основа готова к отдельной согласованной staging-проверке. Production-развёртывание и заявление о готовности iOS — преждевременны. Перед тестом двух устройств обязательны Apple SDK typecheck/XCTest и безопасный действительный HTTPS/WSS endpoint. Если ingress443 занят VPN и нет отдельно разрешённого варианта, STOP без изменений VPN. GitHub Actions ранее отключены.

Следующий этап только по отдельному разрешению: следовать winter-sync/DEPLOYMENT.md, подготовить staging, выполнить macOS модельные тесты и iOS XCTest/Keychain, затем реальную проверку двух устройств. В текущей сессии остановиться.

Команды из /workspace/TelegramSnow:
```
python3 -m unittest discover -s winter-sync -q
# только новые сценарии:
python3 -m unittest discover -s winter-sync -p test_integration.py -q
# только с native Swift на macOS:
python3 build-system/SnowEffect/test_winter_models.py
```

---

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
