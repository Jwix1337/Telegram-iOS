import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compiled_cache', Path(__file__).resolve().parents[1] / 'compiled_cache.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class CompiledCacheTests(unittest.TestCase):
    secret = (b'e' * 32, b'a' * 32)  # Deliberately artificial test keys, never production credentials.

    def test_round_trip_keeps_plaintext_out_of_published_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / 'source'; source.mkdir()
            (source / 'cas').mkdir(); (source / 'cas/object').write_bytes(b'private-config-test-marker')
            self.assertEqual(cache.save(source, root / 'bundle', self.secret), 1)
            self.assertEqual({p.name for p in (root / 'bundle').iterdir()}, {'actions.enc', 'actions.mac'})
            self.assertNotIn(b'private-config-test-marker', (root / 'bundle/actions.enc').read_bytes())
            self.assertTrue(cache.restore(root / 'result', root / 'bundle', self.secret))
            self.assertEqual((root / 'result/cas/object').read_bytes(), b'private-config-test-marker')

    def test_tampering_and_other_repository_keys_are_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / 'source'; source.mkdir(); (source / 'one').write_bytes(b'one')
            cache.save(source, root / 'bundle', self.secret)
            with self.assertRaisesRegex(ValueError, 'authentication'):
                cache.restore(root / 'result', root / 'bundle', (b'x' * 32, b'y' * 32))
            path = root / 'bundle/actions.enc'; data = bytearray(path.read_bytes()); data[-1] ^= 1; path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'authentication'):
                cache.restore(root / 'result', root / 'bundle', self.secret)
            self.assertFalse((root / 'result').exists())

    def test_size_budget_and_no_following_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / 'source'; source.mkdir()
            (source / 'small').write_bytes(b'123'); (source / 'large').write_bytes(b'0123456789')
            (source / 'link').symlink_to(root / 'outside')
            self.assertEqual(cache.save(source, root / 'bundle', self.secret, budget=4), 1)
            cache.restore(root / 'result', root / 'bundle', self.secret)
            self.assertEqual([p.name for p in (root / 'result').iterdir()], ['small'])

    def test_absolute_paths_traversal_and_links_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            for name, kind in [('../escape', tarfile.REGTYPE), ('/escape', tarfile.REGTYPE), ('link', tarfile.SYMTYPE)]:
                with self.subTest(name=name):
                    data = io.BytesIO()
                    with tarfile.open(fileobj=data, mode='w') as archive:
                        member = tarfile.TarInfo(name); member.type = kind
                        archive.addfile(member)
                    data.seek(0)
                    with tarfile.open(fileobj=data, mode='r') as archive, self.assertRaises(ValueError):
                        cache.extract(archive, Path(temp))
