import Foundation
import UIKit
import XCTest
@testable import SnowEffect

final class SnowEffectTests: XCTestCase {
    private func plan(_ settings: SnowEffectSettings, viewport: CGSize = CGSize(width: 390.0, height: 844.0), visible: Bool = true, active: Bool = true, reduceMotion: Bool = false, lowPower: Bool = false, thermalState: ProcessInfo.ThermalState = .nominal) -> SnowEffectRenderPlan? {
        return SnowEffectRenderPlan(settings: settings, viewport: viewport, visible: visible, active: active, reduceMotion: reduceMotion, lowPower: lowPower, thermalState: thermalState)
    }

    func testDefaultIsOffAndEachRuntimeGateStopsRendering() {
        var settings = SnowEffectSettings()
        XCTAssertNil(self.plan(settings))
        settings.enabled = true
        XCTAssertNotNil(self.plan(settings))
        XCTAssertNil(self.plan(settings, visible: false))
        XCTAssertNil(self.plan(settings, active: false))
        XCTAssertNil(self.plan(settings, reduceMotion: true))
        XCTAssertNil(self.plan(settings, thermalState: .critical))
        XCTAssertNil(self.plan(settings, viewport: .zero))
        XCTAssertNil(self.plan(settings, viewport: CGSize(width: .infinity, height: 844.0)))
    }

    func testOnlyDecemberAndJanuaryInSeasonalMode() throws {
        var settings = SnowEffectSettings()
        settings.enabled = true
        settings.seasonal = true
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for month in 1 ... 12 {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: month, day: 15, hour: 12)))
            XCTAssertEqual(settings.isActive(at: date, timeZone: zone), month == 1 || month == 12)
            settings.seasonal = false
            XCTAssertTrue(settings.isActive(at: date, timeZone: zone))
            settings.seasonal = true
        }
        settings.enabled = false
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 15)))
        XCTAssertFalse(settings.isActive(at: january, timeZone: zone))
    }

    func testSeasonBoundaryUsesLocalTimeZone() throws {
        var settings = SnowEffectSettings()
        settings.enabled = true
        settings.seasonal = true
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-31T22:00:00Z"))
        XCTAssertTrue(settings.isActive(at: date, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))))
        XCTAssertFalse(settings.isActive(at: date, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 10800))))
    }

    func testParticleBudgetAndEnergyReduction() throws {
        var settings = SnowEffectSettings()
        settings.enabled = true
        var counts: [Int] = []
        for intensity in SnowEffectSettings.Intensity.allCases {
            settings.intensity = intensity
            counts.append(try XCTUnwrap(self.plan(settings)).particleCount)
            for viewport in [CGSize(width: 320.0, height: 568.0), CGSize(width: 430.0, height: 932.0), CGSize(width: 2000.0, height: 2000.0)] {
                let normal = try XCTUnwrap(self.plan(settings, viewport: viewport))
                let lowPower = try XCTUnwrap(self.plan(settings, viewport: viewport, lowPower: true))
                let hot = try XCTUnwrap(self.plan(settings, viewport: viewport, thermalState: .serious))
                XCTAssertLessThanOrEqual(normal.particleCount, 96)
                XCTAssertLessThan(lowPower.particleCount, normal.particleCount)
                XCTAssertEqual(hot.particleCount, lowPower.particleCount)
            }
        }
        XCTAssertLessThan(counts[0], counts[1])
        XCTAssertLessThan(counts[1], counts[2])
    }

    func testAllSpeedAndSizeOptionsReachRenderPlan() throws {
        var settings = SnowEffectSettings()
        settings.enabled = true
        for speed in SnowEffectSettings.Speed.allCases {
            for size in SnowEffectSettings.Size.allCases {
                settings.speed = speed
                settings.size = size
                let plan = try XCTUnwrap(self.plan(settings))
                XCTAssertEqual(plan.speed, speed.rawValue)
                XCTAssertEqual(plan.size, size.rawValue)
            }
        }
    }

    func testPreferencesSurviveNewStoreAndNotifyOnlyOnChange() throws {
        let suite = "SnowEffectTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SnowEffectPreferences(defaults: defaults)
        let changed = self.expectation(forNotification: SnowEffectPreferences.didChange, object: store)
        changed.expectedFulfillmentCount = 1
        changed.assertForOverFulfill = true
        store.update { settings in
            settings.enabled = true
            settings.seasonal = true
            settings.intensity = .heavy
            settings.speed = .slow
            settings.size = .large
            settings.accumulationEnabled = false
            settings.accumulationSpeed = .fast
            settings.maximumSnowHeight = .large
            settings.shakeToClear = false
            settings.swipeToClear = false
            settings.winterSnowballsEnabled = false
            settings.winterReceiveSnowballs = false
            settings.winterSnowmanEnabled = false
            settings.winterAnimationsEnabled = false
        }
        store.update { _ in }
        self.wait(for: [changed], timeout: 1.0)
        XCTAssertEqual(SnowEffectPreferences(defaults: defaults).settings, store.settings)
        XCTAssertTrue(store.settings.enabled)
        XCTAssertTrue(store.settings.seasonal)
        XCTAssertEqual(store.settings.intensity, .heavy)
        XCTAssertEqual(store.settings.speed, .slow)
        XCTAssertEqual(store.settings.size, .large)
        XCTAssertFalse(store.settings.accumulationEnabled)
        XCTAssertEqual(store.settings.accumulationSpeed, .fast)
        XCTAssertEqual(store.settings.maximumSnowHeight, .large)
        XCTAssertFalse(store.settings.shakeToClear)
        XCTAssertFalse(store.settings.swipeToClear)
        XCTAssertFalse(store.settings.winterSnowballsEnabled)
        XCTAssertFalse(store.settings.winterReceiveSnowballs)
        XCTAssertFalse(store.settings.winterSnowmanEnabled)
        XCTAssertFalse(store.settings.winterAnimationsEnabled)
    }

    func testLegacyPreferencesKeepExistingValuesAndDefaultNewFields() throws {
        let legacy = Data("{\"enabled\":true,\"seasonal\":true,\"intensity\":2,\"speed\":0.65,\"size\":1.35}".utf8)
        let suite = "SnowEffectTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(legacy, forKey: "SnowEffect.settings.v1")
        let settings = SnowEffectPreferences(defaults: defaults).settings
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.seasonal)
        XCTAssertEqual(settings.intensity, .heavy)
        XCTAssertEqual(settings.speed, .slow)
        XCTAssertEqual(settings.size, .large)
        XCTAssertTrue(settings.accumulationEnabled)
        XCTAssertEqual(settings.accumulationSpeed, .normal)
        XCTAssertEqual(settings.maximumSnowHeight, .medium)
        XCTAssertTrue(settings.shakeToClear)
        XCTAssertTrue(settings.swipeToClear)
        XCTAssertTrue(settings.winterSnowballsEnabled)
        XCTAssertTrue(settings.winterReceiveSnowballs)
        XCTAssertTrue(settings.winterSnowmanEnabled)
        XCTAssertTrue(settings.winterAnimationsEnabled)
    }

    func testEveryAccumulationOptionSurvivesEncoding() throws {
        for speed in SnowEffectSettings.AccumulationSpeed.allCases {
            for height in SnowEffectSettings.MaximumSnowHeight.allCases {
                var settings = SnowEffectSettings()
                settings.accumulationSpeed = speed
                settings.maximumSnowHeight = height
                let data = try JSONEncoder().encode(settings)
                XCTAssertEqual(try JSONDecoder().decode(SnowEffectSettings.self, from: data), settings)
            }
        }
    }

    func testMissingFieldsAndCorruptStorageFailSafely() throws {
        let decoded = try JSONDecoder().decode(SnowEffectSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, SnowEffectSettings())
        let suite = "SnowEffectTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for corrupt in ["not JSON", "{\"enabled\":true,\"intensity\":999}", "{\"enabled\":true,\"speed\":-100}"] {
            defaults.set(Data(corrupt.utf8), forKey: "SnowEffect.settings.v1")
            XCTAssertEqual(SnowEffectPreferences(defaults: defaults).settings, SnowEffectSettings())
        }
    }

    func testEveryWinterInteractionSettingSurvivesEncoding() throws {
        for bits in 0 ..< 16 {
            var settings = SnowEffectSettings()
            settings.winterSnowballsEnabled = bits & 1 != 0
            settings.winterReceiveSnowballs = bits & 2 != 0
            settings.winterSnowmanEnabled = bits & 4 != 0
            settings.winterAnimationsEnabled = bits & 8 != 0
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(SnowEffectSettings.self, from: data), settings)
        }
    }
}
