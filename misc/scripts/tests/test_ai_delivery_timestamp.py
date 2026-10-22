"""Cover Android shared-storage metadata retained across atomic replacement."""
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('delivery', Path(__file__).resolve().parents[1] / 'deliver_ai_android.py')
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class AndroidDeliveryTimestampTests(unittest.TestCase):
    def test_replacement_refreshes_retained_android_timestamp(self):
        real_replace = os.replace
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder) / 'incoming.apk', Path(folder) / delivery.NAME
            source.write_bytes(b'verified-new')
            target.write_bytes(b'previous')
            old_timestamp = 1_600_000_000
            os.utime(target, (old_timestamp, old_timestamp))

            def replace_retaining_timestamp(incoming, outgoing):
                real_replace(incoming, outgoing)
                os.utime(outgoing, (old_timestamp, old_timestamp))

            started = time.time()
            with patch.object(delivery.os, 'replace', replace_retaining_timestamp):
                delivery.atomic_copy(source, target, hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertGreaterEqual(target.stat().st_mtime, started - 1)


if __name__ == '__main__':
    unittest.main()
