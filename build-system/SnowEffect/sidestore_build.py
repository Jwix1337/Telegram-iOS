#!/usr/bin/env python3
"""Build configuration and validation for a real, re-signable iPhone IPA.

The local ad-hoc signature preserves entitlement metadata for SideStore. It does
not authorize installation: SideStore must sign with the user's own account.
"""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
OFFICIAL_IDS = {"ph.telegra.Telegraph", "org.telegram.Telegram-iOS"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bundle_identifier(value):
    require(bool(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value)), "Invalid bundle identifier")
    require(value not in OFFICIAL_IDS, "Use a separate bundle identifier")
    return value


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True, stderr=subprocess.STDOUT)


def configure():
    require(sys.platform == "darwin" and platform.machine() == "arm64", "Requires an Apple Silicon macOS runner")
    versions = json.loads((ROOT / "versions.json").read_text())
    require(run("xcodebuild", "-version").splitlines()[0] == "Xcode " + versions["xcode"], "Xcode must match versions.json")
    require(platform.mac_ver()[0].split(".")[0] == versions["macos"].split(".")[0], "macOS must match versions.json")
    bundle_id = bundle_identifier(os.environ["SNOW_BUNDLE_ID"])
    api_id = os.environ.get("TELEGRAM_API_ID", "").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
    require(api_id.isascii() and api_id.isdecimal() and 0 < int(api_id) <= 2147483647, "Set the TELEGRAM_API_ID repository secret")
    require(bool(re.fullmatch(r"[0-9a-fA-F]{32}", api_hash)), "Set the TELEGRAM_API_HASH repository secret")

    for module in ("ChatListUI", "SettingsUI", "TelegramUI"):
        require("//submodules/SnowEffect:SnowEffect" in (ROOT / "submodules" / module / "BUILD").read_text(), "SnowEffect dependency missing: " + module)
    require((ROOT / "submodules/SnowEffect/Sources/SnowEffectView.swift").is_file(), "SnowEffect sources missing")
    rules = ROOT / "build-system/bazel-rules/rules_apple/apple/internal/codesigning_support.bzl"
    require('"disable_legacy_signing" in features' in rules.read_text(), "The pinned rules_apple signing feature is missing")

    config = json.loads((ROOT / "build-system/template_minimal_development_configuration.json").read_text())
    config.update(bundle_id=bundle_id, api_id=api_id, api_hash=api_hash,
                  team_id="UNSIGNED00", app_specific_url_scheme="telegram-snow",
                  is_internal_build="false", enable_siri=False, enable_icloud=False)
    # UNSIGNED00 is metadata for the unsigned build, not an Apple identity/profile.
    config_path = Path(os.environ["RUNNER_TEMP"]) / "telegram-snow-configuration.json"
    config_path.write_text(json.dumps(config))
    config_path.chmod(0o600)

    cache = Path.home() / ".cache/telegram-snow-repositories"
    cache.mkdir(parents=True, exist_ok=True)
    flags = (
        "build --//Telegram:disableProvisioningProfiles\n"
        "build --features=disable_legacy_signing\n"
        "build --jobs=2\n"
        f"build --repository_cache={cache}\n"
    )
    with (ROOT / ".bazelrc").open("a") as rc:
        rc.write("\n# Temporary SideStore CI build configuration\n" + flags)

    # Use Telegram's own downloader and its SHA256 pin, not the runner's Bazel.
    sys.path.insert(0, str(ROOT / "build-system/Make"))
    from BazelLocation import locate_bazel
    bazel = locate_bazel(str(ROOT), None, None)
    require(run(bazel, "--version").strip() == "bazel " + versions["bazel"].split(":")[0], "Bazel version mismatch")
    with Path(os.environ["GITHUB_ENV"]).open("a") as env:
        env.write(f"SNOW_BAZEL={bazel}\n")
    print("Configured device build; SnowEffect included; no certificate or provisioning profile imported")


def check_archive(archive):
    """Validate paths before handing the archive to ditto."""
    with zipfile.ZipFile(archive) as source:
        require(source.testzip() is None, "Corrupt IPA archive")
        for entry in source.infolist():
            # ZipInfo normalizes backslashes on Windows; inspect the raw name too.
            original_name = entry.orig_filename
            path = PurePosixPath(original_name)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in original_name, "Unsafe archive path")
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = source.read(entry).decode("utf-8")
                require(not PurePosixPath(target).is_absolute() and "\\" not in target, "Unsafe archive symlink")
                parts = list(path.parent.parts)
                for part in PurePosixPath(target).parts:
                    if part == "..":
                        require(bool(parts), "Archive symlink escapes the archive")
                        parts.pop()
                    elif part != ".":
                        parts.append(part)


def load_bundle(bundle):
    with (bundle / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    executable = info.get("CFBundleExecutable", "")
    require(bool(executable) and Path(executable).name == executable and "\\" not in executable, "Invalid bundle executable")
    require((bundle / executable).is_file(), "Missing executable: " + str(bundle))
    return info, bundle / executable


def check_device_binary(binary):
    arches = run("xcrun", "lipo", "-archs", binary).split()
    require("arm64" in arches and not {"x86_64", "i386"}.intersection(arches), "Expected an arm64 device binary: " + str(binary))
    build = run("xcrun", "vtool", "-show-build", binary)
    platforms = re.findall(r"^\s*platform\s+(\S+)", build, re.MULTILINE)
    # Some embedded runtime libraries still use the legacy minimum-version load command.
    require((platforms and all(value in ("IOS", "2") for value in platforms)) or
            (not platforms and "LC_VERSION_MIN_IPHONEOS" in build), "Not an iPhoneOS binary: " + str(binary))


def sidestore_entitlements(bundle_id, main_id):
    return {
        "application-identifier": "UNSIGNED00." + bundle_id,
        "keychain-access-groups": ["UNSIGNED00." + main_id],
        "com.apple.security.application-groups": ["group." + main_id],
    }


def package(input_path, output_path, bundle_id, include_extensions=False):
    bundle_identifier(bundle_id)
    require(sys.platform == "darwin", "Packaging requires Apple's macOS codesign tools")
    require(input_path.is_file(), "Official build produced no IPA: " + str(input_path))
    require(input_path.resolve() != output_path.resolve(), "Input and output must differ")
    check_archive(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="telegram-snow-") as directory:
        stage = Path(directory)
        run("/usr/bin/ditto", "-x", "-k", input_path.resolve(), stage)
        apps = list((stage / "Payload").glob("*.app"))
        require(len(apps) == 1, "Expected exactly one real application in Payload")
        app = apps[0]
        info, executable = load_bundle(app)
        require(info.get("CFBundleIdentifier") == bundle_id, "Bundle ID differs from the compiled configuration")
        require(info.get("CFBundlePackageType") == "APPL", "Invalid application bundle")
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Simulator IPA cannot run on iPhone")
        require(bool(info.get("MinimumOSVersion")) and bool(info.get("CFBundleVersion")), "Incomplete Info.plist")
        require(not (app / "Watch").exists(), "Unexpected embedded Watch app")
        check_device_binary(executable)
        require(not re.search(r"^\s*cryptid\s+[1-9]\d*", run("xcrun", "otool", "-l", executable), re.MULTILINE), "Encrypted executable cannot be re-signed")

        plugins = app / "PlugIns"
        extensions = sorted(plugins.glob("*.appex")) if plugins.exists() else []
        for extension in extensions:
            extension_info, extension_executable = load_bundle(extension)
            require(extension_info.get("CFBundleIdentifier", "").startswith(bundle_id + "."), "Extension bundle ID mismatch")
            check_device_binary(extension_executable)
        original_extensions = len(extensions)
        if not include_extensions and plugins.exists():
            shutil.rmtree(plugins)
            extensions = []

        # Keep frameworks intact. Sign from the inside out; never use --deep to sign.
        for framework in sorted(app.rglob("*.framework"), key=lambda value: len(value.parts), reverse=True):
            _, framework_binary = load_bundle(framework)
            check_device_binary(framework_binary)
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", framework)
        for dylib in app.rglob("*.dylib"):
            if not dylib.is_symlink():
                check_device_binary(dylib)
                run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", dylib)

        info["CFBundleDisplayName"] = "Telegram Snow"
        with (app / "Info.plist").open("wb") as destination:
            plistlib.dump(info, destination)
        for profile in app.rglob("embedded.mobileprovision"):
            profile.unlink()
        for bundle in extensions + [app]:
            bundle_info, _ = load_bundle(bundle)
            entitlements = sidestore_entitlements(bundle_info["CFBundleIdentifier"], bundle_id)
            entitlement_path = stage / "sidestore.entitlements"
            with entitlement_path.open("wb") as destination:
                plistlib.dump(entitlements, destination)
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der", "--entitlements", entitlement_path, bundle)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        # Only the real compiled Payload is packaged; configuration and keys stay outside.
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", stage / "Payload", output_path.resolve())
    check_archive(output_path)
    print(f"Device IPA prepared: {output_path}; extensions {len(extensions)}/{original_extensions}; re-sign with SideStore before installation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("configure")
    package_parser = commands.add_parser("package")
    package_parser.add_argument("--input", type=Path, required=True)
    package_parser.add_argument("--output", type=Path, required=True)
    package_parser.add_argument("--bundle-id", required=True)
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure()
        else:
            package(args.input, args.output, args.bundle_id, os.environ.get("SNOW_INCLUDE_EXTENSIONS", "false").lower() == "true")
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("Telegram Snow: " + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.output:
            print(error.output[-3000:], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
