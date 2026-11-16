import Foundation
import XCTest
@testable import SnowEffect

final class SnowAccumulationTests: XCTestCase {
    func testGrowthIsGradualBoundedAndPreservedAcrossHeightChanges() {
        var model = SnowAccumulationModel(profile: [0.0, 0.4, 1.0, 0.7, 0.0])
        let settings = SnowEffectSettings()
        XCTAssertEqual(model.heights(maximum: 16.0), [0.0, 0.0, 0.0, 0.0, 0.0])
        model.advance(seconds: 1.0, settings: settings, energyFactor: 1.0)
        XCTAssertGreaterThan(model.coverage, 0.0)
        XCTAssertLessThan(model.coverage, 0.1)
        let coverage = model.coverage
        let small = model.heights(maximum: 6.0)
        let large = model.heights(maximum: 16.0)
        XCTAssertEqual(model.coverage, coverage)
        XCTAssertEqual(small[2] / 6.0, large[2] / 16.0, accuracy: 0.000001)
        model.advance(seconds: 10000.0, settings: settings, energyFactor: 1.0)
        XCTAssertTrue(model.isFull)
        XCTAssertEqual(model.heights(maximum: 16.0).max(), 16.0)
    }

    func testIntensityAccumulationSpeedAndEnergyChangeDeposition() {
        func coverage(intensity: SnowEffectSettings.Intensity, speed: SnowEffectSettings.AccumulationSpeed, energy: Double = 1.0) -> Double {
            var model = SnowAccumulationModel()
            var settings = SnowEffectSettings()
            settings.intensity = intensity
            settings.accumulationSpeed = speed
            model.advance(seconds: 5.0, settings: settings, energyFactor: energy)
            return model.coverage
        }
        XCTAssertLessThan(coverage(intensity: .light, speed: .normal), coverage(intensity: .heavy, speed: .normal))
        XCTAssertLessThan(coverage(intensity: .medium, speed: .slow), coverage(intensity: .medium, speed: .fast))
        XCTAssertLessThan(coverage(intensity: .medium, speed: .normal, energy: 0.45), coverage(intensity: .medium, speed: .normal))
    }

    func testInvalidElapsedTimeDoesNotGrowAndClearingRestartsFromEmpty() {
        var model = SnowAccumulationModel()
        let settings = SnowEffectSettings()
        for seconds in [-1.0, Double.nan, Double.infinity, 0.0] {
            model.advance(seconds: seconds, settings: settings, energyFactor: 1.0)
        }
        XCTAssertEqual(model.coverage, 0.0)
        model.advance(seconds: 10.0, settings: settings, energyFactor: 1.0)
        XCTAssertGreaterThan(model.coverage, 0.0)
        model.clear()
        XCTAssertEqual(model.coverage, 0.0)
        XCTAssertFalse(model.isFull)
        model.advance(seconds: 1.0, settings: settings, energyFactor: 1.0)
        XCTAssertGreaterThan(model.coverage, 0.0)
        XCTAssertLessThan(model.coverage, 0.1)
    }

    func testGeneratedBankHasSoftTaperAndUnevenHeight() {
        var model = SnowAccumulationModel()
        model.advance(seconds: 10000.0, settings: SnowEffectSettings(), energyFactor: 1.0)
        let heights = model.heights(maximum: 16.0)
        XCTAssertEqual(heights.count, 41)
        XCTAssertEqual(heights.first, 0.0)
        XCTAssertEqual(heights.last, 0.0)
        XCTAssertTrue(heights.allSatisfy { $0 >= 0.0 && $0 <= 16.0 })
        XCTAssertGreaterThan(Set(heights.dropFirst().dropLast()).count, 1)
    }
}
