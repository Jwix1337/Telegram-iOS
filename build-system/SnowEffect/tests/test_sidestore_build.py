import importlib.util
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SPEC = importlib.util.spec_from_file_location("sidestore_build", Path(__file__).resolve().parents[1] / "sidestore_build.py")
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class SideStoreArtifactTests(unittest.TestCase):
    def test_bundle_id_is_separate_and_cannot_inject_build_configuration(self):
        self.assertEqual(build.bundle_identifier("org.snoweffect.TelegramSnow"), "org.snoweffect.TelegramSnow")
        for value in ("ph.telegra.Telegraph", "org.telegram.Telegram-iOS", "no-dot", "a.b\n", 'a.b"', "a/b.c"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                build.bundle_identifier(value)

    def test_arm64_simulator_is_rejected_even_though_architecture_matches(self):
        for platform in ("IOSSIMULATOR", "7", "MACOS", "1"):
            with self.subTest(platform=platform), patch.object(build, "run", side_effect=["arm64\n", "platform " + platform + "\n"]), self.assertRaisesRegex(ValueError, "Not an iPhoneOS"):
                build.check_device_binary(Path("executable"))

    def test_device_binary_and_legacy_embedded_runtime_are_accepted(self):
        for load_command in ("platform IOS\n", "platform 2\n", "cmd LC_VERSION_MIN_IPHONEOS\n"):
            with self.subTest(command=load_command), patch.object(build, "run", side_effect=["arm64\n", load_command]):
                build.check_device_binary(Path("executable"))

    def test_intel_and_unknown_platform_binaries_are_rejected(self):
        with patch.object(build, "run", return_value="x86_64\n"), self.assertRaises(ValueError):
            build.check_device_binary(Path("executable"))
        with patch.object(build, "run", side_effect=["arm64\n", "unrecognized output\n"]), self.assertRaises(ValueError):
            build.check_device_binary(Path("executable"))

    def test_required_app_group_and_keychain_metadata_survive(self):
        entitlements = build.sidestore_entitlements("org.snoweffect.TelegramSnow.Share", "org.snoweffect.TelegramSnow")
        self.assertEqual(entitlements["com.apple.security.application-groups"], ["group.org.snoweffect.TelegramSnow"])
        self.assertEqual(entitlements["keychain-access-groups"], ["UNSIGNED00.org.snoweffect.TelegramSnow"])
        self.assertEqual(set(entitlements), {"application-identifier", "keychain-access-groups", "com.apple.security.application-groups"})
        self.assertEqual(plistlib.loads(plistlib.dumps(entitlements)), entitlements)

    def test_archive_rejects_traversal_and_escaping_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "fixture.zip"
            for path in ("../outside", "/absolute", "Payload/../../outside", "Payload\\outside"):
                with self.subTest(path=path):
                    with zipfile.ZipFile(archive, "w") as destination:
                        entry = zipfile.ZipInfo("fixture")
                        entry.filename = path
                        destination.writestr(entry, "fixture")
                    with self.assertRaises(ValueError):
                        build.check_archive(archive)
            entry = zipfile.ZipInfo("Payload/link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(archive, "w") as destination:
                destination.writestr(entry, "../../outside")
            with self.assertRaises(ValueError):
                build.check_archive(archive)

    def test_normal_archive_and_relative_framework_link_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "fixture.zip"
            link = zipfile.ZipInfo("Payload/App.app/Frameworks/A.framework/A")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(archive, "w") as destination:
                destination.writestr("Payload/App.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "a.b"}))
                destination.writestr(link, "Versions/Current/A")
            build.check_archive(archive)

    def test_bundle_executable_must_exist_inside_its_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory)
            for executable in ("../escape", "missing", "folder/executable", "folder\\executable"):
                with self.subTest(executable=executable):
                    (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
                    with self.assertRaises(ValueError):
                        build.load_bundle(bundle)


if __name__ == "__main__":
    unittest.main()
