import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location("runtime_build", Path(__file__).with_name("build.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class DownloadTests(unittest.TestCase):
    def test_official_mirror_is_used_after_outage_with_same_required_hash(self):
        data = b"verified source archive"
        spec = {"url": "https://source.example/archive", "mirrors": ["https://mirror.example/archive"],
                "sha256": hashlib.sha256(data).hexdigest()}
        with tempfile.TemporaryDirectory() as root, patch.object(builder.time, "sleep"), patch.object(
            builder.urllib.request, "urlopen", side_effect=[urllib.error.URLError("unavailable"), io.BytesIO(data)]
        ) as request:
            path = Path(root) / "source.zip"
            builder.download(path, spec)
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(request.call_args_list[1].args[0].full_url, spec["mirrors"][0])
            self.assertFalse(path.with_suffix(".zip.part").exists())

    def test_modified_source_is_refused_before_publishing_cache_file(self):
        spec = {"url": "https://source.example/archive", "sha256": hashlib.sha256(b"expected").hexdigest()}
        with tempfile.TemporaryDirectory() as root, patch.object(builder.urllib.request, "urlopen", return_value=io.BytesIO(b"modified")):
            path = Path(root) / "source.zip"
            with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                builder.download(path, spec)
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix(".zip.part").exists())


if __name__ == "__main__":
    unittest.main()
