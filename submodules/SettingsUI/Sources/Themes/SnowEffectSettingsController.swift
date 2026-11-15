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
    let info: String

    init(languageCode: String) {
        if languageCode.lowercased().hasPrefix("ru") {
            self.title = "Снегопад"
            self.labels = ["Включить снег", "Только в декабре и январе", "Интенсивность", "Скорость", "Размер снежинок"]
            self.intensities = ["Слабая", "Средняя", "Сильная"]
            self.speeds = ["Медленная", "Обычная", "Быстрая"]
            self.sizes = ["Маленькие", "Обычные", "Крупные"]
            self.info = "Снег отображается в списке чатов и переписках. Отключите сезонный режим для снега круглый год. При включённом «Уменьшении движения» анимация отключается. Режим энергосбережения снижает интенсивность. Настройки действуют для всех аккаунтов на этом устройстве."
        } else {
            self.title = "Snow Effect"
            self.labels = ["Enable Snow", "Only in December and January", "Intensity", "Fall Speed", "Snowflake Size"]
            self.intensities = ["Light", "Medium", "Heavy"]
            self.speeds = ["Slow", "Normal", "Fast"]
            self.sizes = ["Small", "Normal", "Large"]
            self.info = "Snow appears in the chat list and conversations. Turn off seasonal mode for year-round snow. Reduce Motion disables the animation. Low Power Mode reduces intensity. Settings apply to all accounts on this device."
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
    }

    let stableId: Int32
    let theme: PresentationTheme
    let title: String
    let value: Value

    var section: ItemListSectionId {
        return self.stableId < 2 ? 0 : (self.stableId < 5 ? 1 : 2)
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
        }
    }
}

func snowEffectSettingsController(context: AccountContext) -> ViewController {
    let preferences = SnowEffectPreferences.shared
    var presentImpl: ((ViewController) -> Void)?
    let arguments = SnowEffectSettingsArguments(toggle: { id, value in
        preferences.update { settings in
            if id == 0 {
                settings.enabled = value
            } else {
                settings.seasonal = value
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
        default:
            labels = strings.sizes
            selected = SnowEffectSettings.Size.allCases.firstIndex(of: settings.size) ?? 1
        }
        let sheet = ActionSheetController(presentationData: presentationData)
        let items: [ActionSheetItem] = labels.enumerated().map { index, label in
            return ActionSheetButtonItem(title: (index == selected ? "✓ " : "") + label, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                preferences.update { settings in
                    switch id {
                    case 2: settings.intensity = SnowEffectSettings.Intensity.allCases[index]
                    case 3: settings.speed = SnowEffectSettings.Speed.allCases[index]
                    default: settings.size = SnowEffectSettings.Size.allCases[index]
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
            .choice(strings.sizes[SnowEffectSettings.Size.allCases.firstIndex(of: settings.size) ?? 1])
        ]
        var entries = values.enumerated().map { index, value in
            SnowEffectSettingsEntry(stableId: Int32(index), theme: presentationData.theme, title: strings.labels[index], value: value)
        }
        entries.append(SnowEffectSettingsEntry(stableId: 5, theme: presentationData.theme, title: strings.info, value: .info))
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
