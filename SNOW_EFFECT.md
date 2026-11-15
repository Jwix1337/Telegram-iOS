# Telegram Snow: GitHub Actions → SideStore → iPhone

GitHub Actions успешно собрал настоящий `TelegramSnow.ipa` с собственными API credentials: [run #4](https://github.com/Jwix1337/Telegram-iOS/actions/runs/43711859547), исходники `b25229b5b0b2e72040297c2039bf048ed564c5d4`, 15 ноября 2026. Выполнены все 9 962 действия Bazel, проверка и упаковка IPA. Локальная iOS-сборка на Windows не запускалась.

## Закреплённая база

- Telegram-iOS `24638bc69bd083981b178dd1e7f921eebbf7fc46`, приложение 13.2; соответствие официальному build 36535 не установлено.
- Из `versions.json`: Xcode 27.1, macOS 27, Bazel 9.2.0 с SHA256 `dd466352a3e4d3581b8898740ee1ff208866ccbe25f8d367c5dcb950219587e6`.
- Из `Telegram/BUILD`: deployment target iOS 15.0; фактическая работа на всех поддерживаемых iOS не проверена.
- GitHub-hosted `xcode-27` на дату проверки содержит нужные macOS и Xcode. Используется `/Applications/Xcode_27.1.app`, версия проверяется перед сборкой. [Состав официального образа](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
- Bazel устанавливает официальный `BazelLocation.py` проекта с проверкой SHA256. Предустановленный на runner Bazel другой версии не используется. Рекурсивные submodules устанавливает checkout.

## Что именно собирается

Режим `api_mode=auto` сначала использует ваши repository secrets. Если оба отсутствуют, разрешена **только разработческая тестовая сборка** с опубликованным API из исходного `build-system/appstore-configuration.json`. SHA256 конфигурации проверяется, новые ключи в код не копируются. Это разрешённый [официальной документацией Telegram](https://core.telegram.org/api/obtaining_api_id) сценарий тестирования; API ограничен сервером, возможен `API_ID_PUBLISHED_FLOOD`. Тестовую сборку нельзя распространять как готовый клиент для пользователей. Её artifact содержит `upstream-test`, файл называется `TelegramSnow-Test.ipa`, приложение — `Telegram Snow Test`. Когда получите собственные ключи, добавьте оба secrets; при `api_mode=own` их наличие обязательно. Неверные или частично заполненные secrets автоматически тестовыми не заменяются.

Штатный `build-system/Make/Make.py build --configuration=release_arm64` компилирует настоящий Telegram вместе со SnowEffect и расширениями. Затем `build-system/SnowEffect/sidestore_build.py` проверяет результат и упаковывает его для переподписи. Пустой или подменённый IPA не создаётся.

Без чужих профилей/сертификатов используются штатные flags закреплённого `rules_apple`: `--//Telegram:disableProvisioningProfiles` и `--features=disable_legacy_signing`. Одного первого флага недостаточно: device build иначе потребует provisioning profile. Это отключение подписи **на стадии сборки**, не обход защиты iOS. После компиляции Apple `codesign --sign -` создаёт локальные hash-подписи для сохранения entitlement metadata. Они **не позволяют установить приложение напрямую**. Сертификат и настоящий provisioning profile создаст SideStore с вашим Apple ID.

В закреплённой ревизии упаковщик отдельно требовал embedded profile даже при отключённой подписи. Узкий `build-system/bazel-patches/rules_apple_unsigned_profiles.patch` устраняет это требование только при `disable_legacy_signing` для iOS application/extension. Конфигуратор применяет patch идемпотентно и отказывает при несовместимой ревизии. Обычный режим подписанной сборки сохраняет требование профилей. Проверки подписи iOS на устройстве не меняются.

Bundle ID по умолчанию: `org.snoweffect.TelegramSnow`, URL scheme `telegram-snow`, display name `Telegram Snow`. Этот ID отличается от официального Telegram; предполагается параллельная установка и отдельный вход в аккаунт. Сессию официального Telegram сборка не читает и не копирует. Сохраняйте ID, Apple ID и Team при обновлениях.

Упаковщик проверяет наличие реального executable, arm64 и платформу iPhoneOS (одного arm64 недостаточно: Simulator тоже arm64), Info.plist, отсутствие DRM, framework binaries и префиксы ID расширений. Embedded frameworks сохраняются и подписываются изнутри наружу. Итог проверяется `codesign --verify --deep --strict` перед публикацией artifact.

App Groups `group.<bundleID>` и keychain metadata сохраняются. Они нужны Telegram для данных и запуска: удалять App Groups без изменения архитектуры нельзя. `UNSIGNED00` — только placeholder в предварительной hash-подписи; SideStore должен заменить его собственными данными подписи. Текущий [SideSign](https://github.com/SideStore/SideSign/blob/main/Sources/Models/Entitlement.swift) включает App Groups в бесплатный набор. Это ещё не доказательство успешной переподписи именно этой IPA.

По умолчанию `include_extensions=false`: в конечную SideStore IPA не включаются Share, Widget, Siri, Notification Content/Service и Broadcast Upload extensions. Это экономит App IDs бесплатного аккаунта; соответствующие системные интеграции отсутствуют. Исходники и полная компиляция этих компонентов сохранены. Если нужны extension bundles и хватает App IDs, включите параметр; поддержка всех их возможностей бесплатной подписью не обещается. Watch app не встраивается.

## Подготовка GitHub с Windows

1. Создайте свой fork [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). Вносить изменения и запускать сборку нужно в своём fork.
2. Примените `telegram-snow.patch` к указанной ревизии. Архив `telegram-snow-sources.zip` содержит только изменённые файлы с относительными путями; это не полный репозиторий. Для patch через PowerShell, заменив USERNAME и путь:

```powershell
git -c core.longpaths=true clone --filter=blob:none https://github.com/USERNAME/Telegram-iOS.git TelegramSnow
cd TelegramSnow
git config core.longpaths true
git checkout -b telegram-snow 24638bc69bd083981b178dd1e7f921eebbf7fc46
git apply --check C:/path/to/telegram-snow.patch
git apply C:/path/to/telegram-snow.patch
git add --all
git commit -m "Add SnowEffect and SideStore device build"
git push -u origin telegram-snow
```

3. Сделайте `telegram-snow` default branch своего fork, чтобы новый `workflow_dispatch` появился в Actions. Включите Actions для fork, если GitHub предлагает это сделать. Рекурсивные зависимости на Windows скачивать для сборки не нужно: это делает macOS runner.
4. Для итогового клиента получите **свои** Telegram `api_id` и `api_hash` на [my.telegram.org/apps](https://my.telegram.org/apps). В fork: Settings → Secrets and variables → Actions → New repository secret. Создайте `TELEGRAM_API_ID` и `TELEGRAM_API_HASH`. Если Telegram пока не выдаёт ключи, в `auto` можно проверить настоящую сборку на штатном тестовом API с указанными выше ограничениями. Apple ID, пароль Apple и сертификаты в GitHub не нужны. Ключи не коммитятся в исходники.
5. Actions → **Build Telegram Snow for SideStore** → Run workflow. Оставьте отдельный bundle ID, выберите `include_extensions` и runner. `xcode-27-xlarge` — опциональный более мощный runner, доступ/оплата зависят от GitHub; автоматически он не выбирается.

Кэшируются только скачанные dependency archives и проверяемый Bazel. Кэш compiled binaries и API-конфигурации не сохраняется. Наличие кэша не заменяет компиляцию. Версии toolchain не обходятся флагами override.

## Где скачать IPA

Готовый [artifact own-api-4](https://github.com/Jwix1337/Telegram-iOS/actions/runs/43711859547/artifacts/14164279465) содержит `TelegramSnow.ipa` (80 939 830 байт). Скачайте ZIP и извлеките IPA; artifact хранится до 22 ноября 2026, 16:57 МСК. SHA256 самой IPA: `1f0acb6b0b5fabe2292b9ce3c3a558fa50e230f86ac1c462a948d2fcdf36b33d`. Версия приложения 13.2 (100004), iOS 15.0+, Bundle ID `org.snoweffect.TelegramSnow`, собственный API, пять embedded frameworks, без extensions.

После **успешного** завершения workflow откройте его страницу → Artifacts → `TelegramSnow-iPhone-SideStore-<тип API>-<номер>`. Скачайте и распакуйте artifact ZIP. Внутри — **TelegramSnow.ipa** для собственных ключей или **TelegramSnow-Test.ipa** для тестового API. Сам artifact ZIP в SideStore не импортируется.

Артефакт появляется только после настоящей компиляции, проверки device binaries и упаковки. Если сборка/упаковка завершилась ошибкой, готовой IPA считать результат нельзя. Другой workflow **Snow Effect — cloud simulator checks** выдаёт Simulator IPA — она для физического iPhone не подходит.

## SideStore: первоначальная установка через Windows

Следуйте актуальным [Prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) и [Install](https://docs.sidestore.io/docs/installation/install):

1. Установите на Windows рекомендованные SideStore драйверы Apple/iTunes и **iloader** из ссылки официальной инструкции.
2. На iPhone установите **LocalDevVPN** из App Store. Для операций SideStore требуются Wi-Fi и включённый LocalDevVPN.
3. Подключите iPhone к Windows по USB, подтвердите доверие, откройте iloader, войдите своим Apple Account, выберите устройство и **Install SideStore (Stable)**. Платная Apple Developer Program для этого сценария не требуется.
4. На iPhone подтвердите доверие Developer App, включите Developer Mode, если он требуется вашей iOS, подключите LocalDevVPN. Откройте SideStore и войдите тем же Apple Account; выполните первое обновление SideStore через счётчик оставшихся дней. Следуйте запросам актуального установщика о pairing — не используйте чужие pairing files.
5. Сохраните `TelegramSnow.ipa` в Files на iPhone. В SideStore откройте My Apps, нажмите **+** и выберите IPA. Сохраните App Groups; не заменяйте ID на официальный Telegram. Дождитесь подписи и установки, затем отдельно войдите в Telegram Snow.
6. Для следующих обновлений скачивайте новую device IPA и импортируйте её в SideStore с тем же ID и Apple Account. Для обычного refresh новой IPA не нужно. Обновляйте SideStore и приложения до истечения семидневной подписи; Wi-Fi/VPN должны соответствовать инструкции SideStore.

[SideStore FAQ](https://docs.sidestore.io/docs/faq): бесплатный аккаунт ограничивает активные приложения (SideStore тоже занимает место) и App IDs. Extensions расходуют дополнительные IDs. Удаление/переустановка приложения может удалить локальные данные; при обновлении через SideStore сохраняйте текущую установку.

## Проверено и не проверено

- SnowEffect не переписывался: Core Animation, сохранение настроек, сезонность, остановка в фоне/Reduce Motion, адаптация Low Power Mode сохранены. Его зависимости присутствуют в ChatListUI/SettingsUI/TelegramUI.
- Ранее проверен синтаксис 8 Swift-файлов. Python-правила упаковки и выбора API прошли **14 unit tests** на Windows. Они проверяют защиту путей, device/Simulator различие, executable, entitlement metadata, приоритет собственных ключей, целостность штатного тестового конфига и идемпотентность unsigned patch; они не имитируют сборку Telegram.
- Статически проверяются YAML workflow, его пути/команды и Python. Patch применяется к закреплённой базе с проверкой совпадения изменённых файлов.
- **Выполнены:** настоящий GitHub device build, 14 unit tests, упаковка и `codesign --verify --deep --strict` на macOS. Скачанный artifact сверён по GitHub SHA256; локально проверены CRC, Info.plist, Mach-O arm64/iPhoneOS, отсутствие DRM, framework executables и отсутствие extensions.
- **Не выполнены:** реальная переподпись SideStore, установка/запуск на iPhone, XCTest, анимационные кадры, Instruments и регрессия функций Telegram.
- Push/APNs, VoIP в фоне, входящие звонки, Siri, iCloud, universal links, покупки Premium и работа всех extensions с бесплатной подписью не гарантируются. App Groups должны реально разрешаться после SideStore: иначе Telegram может не запуститься. Ограничения не устраняются обходом защит iOS.

Если workflow упал, сначала установите класс ошибки: missing secrets → настройка; `Xcode must match` → runner/toolchain; missing module/checksum → dependency/Bazel; Swift diagnostic → исходники; `provisioning_profile` → применён ли unsigned build feature; `No space`/OOM/quota → ресурсы GitHub. Без исправления причины повторную полную сборку не запускайте.

При успешной первой сборке проверьте на iPhone авторизацию, чаты, снег, перезапуск, запись голоса/видео, звонки и обновление поверх приложения. По `AGENTS.md` анимацию нужно записать и оценить по кадрам; FPS/энергопотребление измерить на устройстве. До этого результат не объявляется полностью работоспособным.

Сохраняйте лицензии и соответствующие исходники. При распространении обозначайте неофициальный клиент и соблюдайте требования к названию/логотипу и [Telegram API Terms](https://core.telegram.org/api/terms).
