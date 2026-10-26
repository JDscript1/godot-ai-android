"""Exercise the global chat inside the actual upstream project manager (no editor)."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from runtime_builder import SCRIPT_BINDINGS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--proot', action='store_true')
    parser.add_argument('--output', default='.ai-qa/start-agent')
    parser.add_argument('--only', choices=['desktop', 'narrow'])
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    for name, resolution in [('desktop', '1280x900'), ('narrow', '480x900')]:
        if args.only and args.only != name:
            continue
        output = Path(args.output).resolve() / name
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='godot-ai-start-') as directory:
            fixture = Path(directory) / 'fixture'
            shutil.copytree(source / 'tests/fixture', fixture)
            environment = {'XDG_CONFIG_HOME': str(Path(directory) / 'config'),
                           'XDG_DATA_HOME': str(Path(directory) / 'data'),
                           'GODOT_AI_QA_SOURCE': str(source),
                           'GODOT_AI_QA_OUTPUT': str(output),
                           'GODOT_AI_QA_BINDINGS': json.dumps(SCRIPT_BINDINGS)}
            command = ['xvfb-run', '-a', '-s', f'-screen 0 {resolution}x24 -ac',
                       args.godot, '--project-manager', '--script', str(source / 'tests/test_start.gd'),
                       '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy',
                       '--resolution', resolution, '--path', str(fixture)]
            if args.proot:
                command = ['proot-distro', 'login', '--shared-home', 'debian', '--', 'env',
                           *(f'{key}={value}' for key, value in environment.items()), *command]
            with (output / 'start.log').open('w') as stream:
                result = subprocess.run(command, env={**os.environ, **environment},
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=120)
            report = output / 'start-report.json'
            log = (output / 'start.log').read_text()
            if result.returncode or not report.exists() or 'SCRIPT ERROR:' in log:
                print(log[-10000:])
                raise SystemExit(f'{name}: start-screen verification failed')
            data = json.loads(report.read_text())
            print(f"{name}: {data['checks']} checks, {len(data['failures'])} failures")
            if data['failures']:
                print(data['failures'])
                raise SystemExit(1)


if __name__ == '__main__':
    main()
