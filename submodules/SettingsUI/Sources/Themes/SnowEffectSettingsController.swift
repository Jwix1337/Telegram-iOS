import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ItemListUI
import SnowEffect

struct SnowEffectStrings {
    let title: String
    let labels: [String]
    let intensities: [String]
    let speeds: [String]
    let sizes: [String]
    let snowHeights: [String]
    let info: String
    let winterTitle: String
    let winterLabels: [String]

    init(languageCode: String) {
        if languageCode.lowercased().hasPrefix("ru") {
            self.title = "Снегопад"
            self.labels = ["Включить снег", "Только в декабре и январе", "Интенсивность", "Скорость", "Размер снежинок", "Накопление снега", "Скорость накопления", "Максимальная высота снега", "Встряхнуть для очистки", "Смахнуть для очистки"]
            self.intensities = ["Слабая", "Средняя", "Сильная"]
            self.speeds = ["Медленная", "Обычная", "Быстрая"]
            self.sizes = ["Маленькие", "Обычные", "Крупные"]
            self.snowHeights = ["Малая", "Средняя", "Большая"]
            self.winterTitle = "Зимние взаимодействия"
            self.winterLabels = ["Отправлять снежки", "Принимать снежки", "Совместный снеговик", "Зимние анимации"]
            self.info = "Снег отображается только внутри открытых переписок. Сугроб накапливается над полем ввода; смахните его или встряхните iPhone для очистки. Отключите сезонный режим для снега круглый год. При включённом «Уменьшении движения» анимация отключается. Режим энергосбережения снижает интенсивность. Настройки действуют для всех аккаунтов на этом устройстве."
        } else {
            self.title = "Snow Effect"
            self.labels = ["Enable Snow", "Only in December and January", "Intensity", "Fall Speed", "Snowflake Size", "Enable Accumulation", "Accumulation Speed", "Maximum Snow Height", "Shake to Clear", "Swipe to Clear"]
            self.intensities = ["Light", "Medium", "Heavy"]
            self.speeds = ["Slow", "Normal", "Fast"]
            self.sizes = ["Small", "Normal", "Large"]
            self.snowHeights = ["Small", "Medium", "Large"]
            self.winterTitle = "Winter Interactions"
            self.winterLabels = ["Enable Snowballs", "Receive Snowballs", "Enable Snowman", "Winter Animations"]
            self.info = "Snow appears only inside open conversations. Snow accumulates above the message field; swipe it or shake your iPhone to clear it. Turn off seasonal mode for year-round snow. Reduce Motion disables the animation. Low Power Mode reduces intensity. Settings apply to all accounts on this device."
        }
    }
}

private final class SnowEffectSettingsArguments {
    let toggle: (Int32, Bool) -> Void
    let choose: (Int32) -> Void

    init(toggle: @escaping (Int32, Bool) -> Void, choose: @escaping (Int32) -> Void) {
        self.toggle = toggle
        self.choose = choose
    }
}

private struct SnowEffectSettingsEntry: ItemListNodeEntry {
    enum Value: Equatable {
        case toggle(Bool)
        case choice(String)
        case info
        case header
    }

    let stableId: Int32
    let theme: PresentationTheme
    let title: String
    let value: Value

    var section: ItemListSectionId {
        return self.stableId < 2 ? 0 : (self.stableId < 5 ? 1 : (self.stableId < 10 ? 2 : (self.stableId == 10 ? 3 : 4)))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.theme === rhs.theme && lhs.title == rhs.title && lhs.value == rhs.value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SnowEffectSettingsArguments
        switch self.value {
        case let .toggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(self.stableId, value)
            })
        case let .choice(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.choose(self.stableId)
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        }
    }
}

func snowEffectSettingsController(context: AccountContext) -> ViewController {
    let preferences = SnowEffectPreferences.shared
    var presentImpl: ((ViewController) -> Void)?
    let arguments = SnowEffectSettingsArguments(toggle: { id, value in
        preferences.update { settings in
            switch id {
            case 0: settings.enabled = value
            case 1: settings.seasonal = value
            case 5: settings.accumulationEnabled = value
            case 8: settings.shakeToClear = value
            case 9: settings.swipeToClear = value
            case 12: settings.winterSnowballsEnabled = value
            case 13: settings.winterReceiveSnowballs = value
            case 14: settings.winterSnowmanEnabled = value
            case 15: settings.winterAnimationsEnabled = value
            default: break
            }
        }
    }, choose: { id in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = SnowEffectStrings(languageCode: presentationData.strings.baseLanguageCode)
        let settings = preferences.settings
        let labels: [String]
        let selected: Int
        switch id {
        case 2:
            labels = strings.intensities
            selected = SnowEffectSettings.Intensity.allCases.firstIndex(of: settings.intensity) ?? 1
        case 3:
            labels = strings.speeds
            selected = SnowEffectSettings.Speed.allCases.firstIndex(of: settings.speed) ?? 1
        case 4:
            labels = strings.sizes
            selected = SnowEffectSettings.Size.allCases.firstIndex(of: settings.size) ?? 1
        case 6:
            labels = strings.speeds
            selected = SnowEffectSettings.AccumulationSpeed.allCases.firstIndex(of: settings.accumulationSpeed) ?? 1
        case 7:
            labels = strings.snowHeights
            selected = SnowEffectSettings.MaximumSnowHeight.allCases.firstIndex(of: settings.maximumSnowHeight) ?? 1
        default:
            return
        }
        let sheet = ActionSheetController(presentationData: presentationData)
        let items: [ActionSheetItem] = labels.enumerated().map { index, label in
            return ActionSheetButtonItem(title: (index == selected ? "✓ " : "") + label, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                preferences.update { settings in
                    switch id {
                    case 2: settings.intensity = SnowEffectSettings.Intensity.allCases[index]
                    case 3: settings.speed = SnowEffectSettings.Speed.allCases[index]
                    case 4: settings.size = SnowEffectSettings.Size.allCases[index]
                    case 6: settings.accumulationSpeed = SnowEffectSettings.AccumulationSpeed.allCases[index]
                    case 7: settings.maximumSnowHeight = SnowEffectSettings.MaximumSnowHeight.allCases[index]
                    default: break
                    }
                }
            })
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentImpl?(sheet)
    })

    let settingsSignal = Signal<SnowEffectSettings, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: SnowEffectPreferences.didChange, object: preferences, queue: .main) { _ in
            subscriber.putNext(preferences.settings)
        }
        subscriber.putNext(preferences.settings)
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, settingsSignal)
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = SnowEffectStrings(languageCode: presentationData.strings.baseLanguageCode)
        let values: [SnowEffectSettingsEntry.Value] = [
            .toggle(settings.enabled), .toggle(settings.seasonal),
            .choice(strings.intensities[settings.intensity.rawValue]),
            .choice(strings.speeds[SnowEffectSettings.Speed.allCases.firstIndex(of: settings.speed) ?? 1]),
            .choice(strings.sizes[SnowEffectSettings.Size.allCases.firstIndex(of: settings.size) ?? 1]),
            .toggle(settings.accumulationEnabled),
            .choice(strings.speeds[SnowEffectSettings.AccumulationSpeed.allCases.firstIndex(of: settings.accumulationSpeed) ?? 1]),
            .choice(strings.snowHeights[SnowEffectSettings.MaximumSnowHeight.allCases.firstIndex(of: settings.maximumSnowHeight) ?? 1]),
            .toggle(settings.shakeToClear), .toggle(settings.swipeToClear)
        ]
        var entries = values.enumerated().map { index, value in
            SnowEffectSettingsEntry(stableId: Int32(index), theme: presentationData.theme, title: strings.labels[index], value: value)
        }
        entries.append(SnowEffectSettingsEntry(stableId: 10, theme: presentationData.theme, title: strings.info, value: .info))
        entries.append(SnowEffectSettingsEntry(stableId: 11, theme: presentationData.theme, title: strings.winterTitle, value: .header))
        let winterValues = [settings.winterSnowballsEnabled, settings.winterReceiveSnowballs, settings.winterSnowmanEnabled, settings.winterAnimationsEnabled]
        for (index, value) in winterValues.enumerated() {
            entries.append(SnowEffectSettingsEntry(stableId: Int32(index + 12), theme: presentationData.theme, title: strings.winterLabels[index], value: .toggle(value)))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
