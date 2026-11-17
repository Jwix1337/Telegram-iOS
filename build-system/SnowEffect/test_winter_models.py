#!/usr/bin/env python3
"""Run the existing Foundation model tests without building Telegram or an IPA."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    module = root / "submodules/SnowEffect"
    with tempfile.TemporaryDirectory(prefix="telegram-winter-tests-") as directory:
        package = Path(directory)
        sources = package / "Sources/SnowEffect"
        tests = package / "Tests/SnowEffectTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        for name in ["SnowEffectSettings.swift", "SnowHatConfiguration.swift", "WinterEventTransport.swift", "WinterSyncClient.swift", "WinterSnowmanAppearance.swift", "SnowAccumulationModel.swift", "SnowHatGeometry.swift", "SnowAccumulationSurface.swift", "WinterSnowmanCutout.swift"]:
            shutil.copyfile(module / "Sources" / name, sources / name)
        for name in ["SnowHatTests.swift", "WinterEventTests.swift", "WinterSyncClientTests.swift", "WinterSnowmanAppearanceTests.swift", "SnowAccumulationTests.swift", "WinterSoloAndLinkTests.swift", "SnowHatPlacementTests.swift", "SnowSurfaceTests.swift", "WinterSnowmanCutoutTests.swift"]:
            shutil.copyfile(module / "Tests" / name, tests / name)
        (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WinterModelChecks", platforms: [.macOS(.v12)], targets: [
    .target(name: "SnowEffect"),
    .testTarget(name: "SnowEffectTests", dependencies: ["SnowEffect"])
])
''')
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True, env=dict(os.environ, SNOW_WINTER_ASSET_ROOT=str(root / "submodules/TelegramUI/Images.xcassets")))


if __name__ == "__main__":
    main()
