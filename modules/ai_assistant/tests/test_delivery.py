"""Protect existing downloads if an incoming installer fails verification."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('delivery', Path(__file__).resolve().parents[3] / 'misc/scripts/deliver_ai_android.py')
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class DeliveryTests(unittest.TestCase):
    def test_failed_copy_preserves_installer(self):
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder) / 'incoming', Path(folder) / 'current.apk'
            source.write_bytes(b'incomplete')
            target.write_bytes(b'known-good')
            with self.assertRaises(AssertionError):
                delivery.atomic_copy(source, target, '0' * 64)
            self.assertEqual(target.read_bytes(), b'known-good')
            self.assertEqual(sorted(p.name for p in Path(folder).iterdir()), ['current.apk', 'incoming'])

    def test_verified_copy_replaces_installer(self):
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder) / 'incoming', Path(folder) / delivery.NAME
            source.write_bytes(b'verified-new')
            target.write_bytes(b'previous')
            delivery.atomic_copy(source, target, hashlib.sha256(b'verified-new').hexdigest())
            self.assertEqual(target.read_bytes(), b'verified-new')
            self.assertEqual(len(list(Path(folder).iterdir())), 2)

    def test_cleanup_names_are_scoped_to_the_fork(self):
        self.assertTrue(delivery.OLD_NAME.fullmatch('Godot-AI-4.7.2-arm64-588bef1-debug.apk'))
        self.assertTrue(delivery.OLD_NAME.fullmatch(delivery.NAME))
        for name in ['Godot_v4.7.2.apk', 'Gallery.apk', 'Godot-AI-notes.txt', 'Godot-AI-arm64-debug.apk.sha256']:
            self.assertIsNone(delivery.OLD_NAME.fullmatch(name))

    def test_distribution_cleanup_never_crosses_packages(self):
        package, name, pattern = delivery.DISTRIBUTIONS['ziva-preview']
        self.assertEqual(package, 'com.jdscript.godotai.ziva.debug')
        self.assertTrue(pattern.fullmatch(name))
        self.assertIsNone(pattern.fullmatch(delivery.NAME))
        self.assertIsNone(delivery.OLD_NAME.fullmatch(name))

    def test_ziva_delivery_preserves_the_standard_installer_and_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            standard = root / delivery.NAME
            checksum = root / (delivery.NAME + '.sha256')
            standard.write_bytes(b'existing-standard')
            checksum.write_text('existing-checksum')
            source = root / 'incoming.apk'
            source.write_bytes(b'new-ziva')
            target = root / delivery.DISTRIBUTIONS['ziva-preview'][1]
            delivery.atomic_copy(source, target, hashlib.sha256(b'new-ziva').hexdigest())
            self.assertEqual(standard.read_bytes(), b'existing-standard')
            self.assertEqual(checksum.read_text(), 'existing-checksum')
            self.assertEqual(target.read_bytes(), b'new-ziva')


if __name__ == '__main__':
    unittest.main()
