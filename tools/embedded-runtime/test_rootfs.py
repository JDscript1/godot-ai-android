import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('rootfs_builder', Path(__file__).with_name('rootfs.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class RootfsTests(unittest.TestCase):
    def configuration(self):
        return dict(distribution='Test', release='1', architecture='arm64', source_commit='fixture',
                    source_repository='fixture', sha256='0' * 64, max_entries=50, max_unpacked_bytes=1024)

    def archive(self, path, members):
        with tarfile.open(path, 'w:gz') as archive:
            for name, kind, value in members:
                info = tarfile.TarInfo(name)
                info.mode = 0o755
                if kind == 'link':
                    info.type = tarfile.SYMTYPE
                    info.linkname = value
                    archive.addfile(info)
                else:
                    info.size = len(value)
                    archive.addfile(info, io.BytesIO(value))

    def test_usr_merge_links_are_relative_and_bytes_are_hashed(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / 'root.tar.gz', Path(directory) / 'root.zip'
            self.archive(source, [('usr/bin/sh', 'file', b'ELF fixture'), ('bin', 'link', '/usr/bin')])
            result = builder.package(source, target, self.configuration())
            self.assertEqual(result['entries'][1]['target'], 'usr/bin')
            self.assertEqual(result['entries'][0]['sha256'], hashlib.sha256(b'ELF fixture').hexdigest())
            with zipfile.ZipFile(target) as archive:
                self.assertEqual(archive.read('files/usr/bin/sh'), b'ELF fixture')

    def test_archive_escape_and_writes_through_symlinks_are_refused(self):
        cases = [[('../outside', 'file', b'x')], [('root/link', 'link', '../../outside')],
                 [('bin', 'link', 'usr/bin'), ('bin/injected', 'file', b'x')],
                 [('usr/bin/a', 'file', b'x'), ('usr/bin/a', 'file', b'y')]]
        for members in cases:
            with self.subTest(members=members), tempfile.TemporaryDirectory() as directory:
                source, target = Path(directory) / 'root.tar.gz', Path(directory) / 'root.zip'
                self.archive(source, members)
                with self.assertRaises(ValueError):
                    builder.package(source, target, self.configuration())
                self.assertFalse(target.exists())
                self.assertFalse(target.with_suffix('.zip.part').exists())

    def test_unpacking_budget_is_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / 'root.tar.gz', Path(directory) / 'root.zip'
            self.archive(source, [('large', 'file', b'x' * 1025)])
            with self.assertRaisesRegex(ValueError, 'budget'):
                builder.package(source, target, self.configuration())

    def test_repack_is_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'root.tar.gz'
            self.archive(source, [('etc/release', 'file', b'fixture')])
            first, second = Path(directory) / 'first.zip', Path(directory) / 'second.zip'
            builder.package(source, first, self.configuration())
            builder.package(source, second, self.configuration())
            self.assertEqual(first.read_bytes(), second.read_bytes())


if __name__ == '__main__':
    unittest.main()
