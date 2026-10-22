#!/usr/bin/env python3
"""Verify a CI APK, deliver it atomically, and remove superseded fork downloads."""
import argparse
from datetime import datetime
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

REPO = 'JDscript1/godot-ai-android'
PACKAGE = 'com.jdscript.godotai.debug'
CERTIFICATE = '2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5'
NAME = 'Godot-AI-Android-arm64-debug.apk'
OLD_NAME = re.compile(r'Godot-AI-(?:Android-)?(?:[0-9.]+-)?arm64-(?:[a-f0-9]{7,40}-)?debug\.apk')


def command(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity(path):
    metadata = command('aapt', 'dump', 'badging', str(path)).decode()
    signature = command('apksigner', 'verify', '--verbose', '--print-certs', str(path)).decode()
    assert f"package: name='{PACKAGE}'" in metadata, 'Unexpected Android package'
    assert f'certificate SHA-256 digest: {CERTIFICATE}' in signature, 'Unexpected signing certificate'
    return metadata


def atomic_copy(source, target, expected):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.' + target.name + '-', suffix='.tmp', dir=target.parent, delete=False) as outgoing:
            temporary = Path(outgoing.name)
            with source.open('rb') as incoming:
                shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
            outgoing.flush()
            os.fsync(outgoing.fileno())
        assert sha256(temporary) == expected, 'Copied installer checksum differs'
        os.replace(temporary, target)
        # Android shared-storage FUSE can retain the replaced entry's old mtime.
        os.utime(target, None)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--run', required=True, type=int)
    parser.add_argument('--download', type=Path, default=Path('/storage/emulated/0/Download'))
    parser.add_argument('--deliver', action='store_true', help='Replace the current installer after verification')
    args = parser.parse_args()
    assert re.fullmatch('[a-f0-9]{40}', args.commit), 'Use the exact source commit'
    run = json.loads(command('gh', 'api', f'repos/{REPO}/actions/runs/{args.run}'))
    assert run['head_sha'] == args.commit and run['status'] == 'completed' and run['conclusion'] == 'success', 'Source build has not passed'
    expected = Path(str(args.source) + '.sha256').read_text().split()[0]
    assert sha256(args.source) == expected, 'Artifact checksum differs'
    metadata = identity(args.source)
    assert "native-code: 'arm64-v8a'" in metadata
    builder = ast.parse(command('git', 'show', f'{args.commit}:modules/ai_assistant/runtime_builder.py'))
    bindings = next(ast.literal_eval(node.value) for node in builder.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'SCRIPT_BINDINGS' for target in node.targets))
    with zipfile.ZipFile(args.source) as archive:
        assert {name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')} == {'arm64-v8a'}
        library = archive.read('lib/arm64-v8a/libgodot_android.so')
        for name in bindings:
            source = command('git', 'show', f'{args.commit}:modules/ai_assistant/runtime/{name}.gd')
            assert source + b'\x00' in library, f'Embedded source differs: {name}'
    report = {'commit': args.commit, 'run': args.run, 'build_url': run['html_url'], 'sha256': expected,
              'certificate_sha256': CERTIFICATE, 'package': PACKAGE, 'abi': 'arm64-v8a',
              'embedded_scripts_verified': len(bindings), 'delivered': False, 'removed': [],
              'physical_android_tested': False, 'live_providers_tested': False}
    output = args.source
    if args.deliver:
        assert args.download.is_dir(), 'Android Download directory is unavailable'
        output = args.download / NAME
        if output.exists():
            identity(output)
        superseded = []
        for old in sorted(args.download.iterdir()):
            if old == output or not old.is_file() or not OLD_NAME.fullmatch(old.name):
                continue
            try:
                identity(old)
            except (AssertionError, subprocess.CalledProcessError):
                continue  # A similarly named download from another app stays untouched.
            superseded.append((old, sha256(old)))
        atomic_copy(args.source, output, expected)
        assert sha256(output) == expected
        checksum = output.with_name(output.name + '.sha256')
        with tempfile.NamedTemporaryFile(mode='w', dir=args.download, prefix='.godot-ai-checksum-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(expected + '  ' + NAME + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, checksum)
        os.utime(checksum, None)
        for old, previous_hash in superseded:
            assert sha256(old) == previous_hash, 'Old download changed during delivery'
            old.unlink()
            Path(str(old) + '.sha256').unlink(missing_ok=True)
            report['removed'].append(str(old))
        report['delivered'] = True
    report.update(path=str(output), bytes=output.stat().st_size, modified_at=datetime.fromtimestamp(output.stat().st_mtime).astimezone().isoformat())
    evidence = Path('.ai-qa') / f'delivery-{args.commit[:7]}.json'
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
