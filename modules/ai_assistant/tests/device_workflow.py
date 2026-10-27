"""Opt-in workflow probe inside the installed Android editor; no API keys are read."""
import argparse
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['prepare', 'open', 'send', 'status', 'stop', 'capture', 'collect'])
    parser.add_argument('--root', required=True, type=Path, help='New test directory in Android shared storage')
    parser.add_argument('--serial', help='Authorized adb device; required for open and collect')
    parser.add_argument('--server-port', type=int, default=5037)
    parser.add_argument('--prompt-file', type=Path)
    parser.add_argument('--effort', default='medium')
    parser.add_argument('--work-mode', choices=['auto', 'default', 'plan'], default='auto')
    parser.add_argument('--continue-conversation', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if not str(root).startswith('/storage/emulated/0/'):
        parser.error('Use a test directory under /storage/emulated/0/')
    project, control = root / 'project', root / 'control'
    package = 'com.jdscript.godotai.debug'
    adb = ['adb', '-P', str(args.server_port)] + (['-s', args.serial] if args.serial else [])

    if args.operation == 'prepare':
        if root.exists(): parser.error('Existing directories are preserved; choose a new test directory')
        addon = project / 'addons/device_workflow_probe'
        addon.mkdir(parents=True)
        control.mkdir()
        shutil.copyfile(Path(__file__).with_suffix('.gd'), control / 'driver.gd')
        (addon / 'plugin.cfg').write_text('[plugin]\nname="Installed agent workflow probe"\ndescription="Opt-in isolated device test"\nauthor="JDscript1"\nversion="1.0"\nscript="bootstrap.gd"\n')
        source = json.dumps(str(control / 'driver.gd'))
        (addon / 'bootstrap.gd').write_text('@tool\nextends EditorPlugin\nvar driver: EditorPlugin\nfunc _enter_tree():\n var script = GDScript.new()\n script.source_code = FileAccess.get_file_as_string(' + source + ')\n if script.reload() != OK: return\n driver = script.new()\n add_child(driver)\nfunc _exit_tree():\n if is_instance_valid(driver): driver.queue_free()\n')
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Isolated device workflow test"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/device_workflow_probe/plugin.cfg")\n[ai_workflow_test]\ncontrol_directory=' + json.dumps(str(control)) + '\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n')
        (project / 'KEEP_ORIGINAL.txt').write_text('Isolated device workflow test. Preserve this marker.\n')
        (control / 'command.json').write_text(json.dumps({'id': 'initial-status', 'operation': 'status'}))
        print(project)
        return
    if not (project / 'addons/device_workflow_probe/plugin.cfg').is_file():
        parser.error('Not a prepared workflow test project')
    if args.operation == 'open':
        if not args.serial: parser.error('Pass the authorized device with --serial')
        command = ['am', 'start', '-a', 'android.intent.action.VIEW', '-d', (project / 'project.godot').as_uri(), '-n', package + '/org.godotengine.editor.ProjectManager']
        subprocess.run(adb + ['shell', shlex.join(command)], check=True)
    elif args.operation in ['send', 'stop', 'capture']:
        command = {'id': args.operation + '-' + str(time.time_ns()), 'operation': args.operation}
        if args.operation == 'send':
            if not args.prompt_file: parser.error('Pass --prompt-file; prompts are not shell commands')
            status = json.loads((control / 'status.json').read_text())
            if status.get('busy'): parser.error('The native agent is already busy')
            command.update(prompt=args.prompt_file.read_text(), effort=args.effort,
                           work_mode=args.work_mode, fresh=not args.continue_conversation)
        temporary = control / 'command.json.tmp'
        temporary.write_text(json.dumps(command, ensure_ascii=True))
        temporary.replace(control / 'command.json')
        print(json.dumps({'queued': command['id']}))
    elif args.operation == 'status':
        status = json.loads((control / 'status.json').read_text())
        print(json.dumps({k: status.get(k) for k in ['request', 'busy', 'requests', 'duration_ms', 'status', 'outcome', 'permission_yolo', 'approval_pending', 'generation_jobs']}, ensure_ascii=False))
    elif args.operation == 'collect':
        if not args.serial or not args.output: parser.error('Pass --serial and a fresh --output directory')
        if args.output.exists(): parser.error('Previous evidence is preserved; choose a new output directory')
        args.output.mkdir(parents=True)
        for name in ['identity.json', 'status.json', 'events.jsonl', 'editor.png']:
            if (control / name).exists(): shutil.copyfile(control / name, args.output / name)
        status = json.loads((control / 'status.json').read_text())
        journal = status.get('journal_path', '')
        pattern = r'/data/(?:data|user/0)/com\.jdscript\.godotai\.debug/files/config/godot/ai_assistant/projects/[a-f0-9]{24}/journal\.json'
        if not re.fullmatch(pattern, journal): parser.error('Journal is outside the app test-project storage')
        result = subprocess.run(adb + ['exec-out', shlex.join(['run-as', package, 'cat', journal])], capture_output=True, check=True)
        json.loads(result.stdout)
        (args.output / 'journal.json').write_bytes(result.stdout)
        base = journal.rsplit('/', 1)[0]
        logs = subprocess.run(adb + ['exec-out', shlex.join(['run-as', package, 'ls', '-1', base + '/logs'])], capture_output=True, timeout=20)
        log_names = []
        if logs.returncode == 0:
            for name in logs.stdout.decode().splitlines():
                if not re.fullmatch(r'activity-[a-f0-9-]{36}-[0-9]{4,}\.jsonl', name):
                    continue
                content = subprocess.run(adb + ['exec-out', shlex.join(['run-as', package, 'cat', base + '/logs/' + name])], capture_output=True, check=True, timeout=30).stdout
                for line in content.splitlines():
                    if line.strip(): json.loads(line)
                (args.output / name).write_bytes(content)
                log_names.append(name)
        for field, directory in [('turn_id', 'runs'), ('conversation_id', 'conversations')]:
            identifier = status.get(field, '')
            if not re.fullmatch(r'[a-f0-9-]{36}', identifier):
                continue
            content = subprocess.run(adb + ['exec-out', shlex.join(['run-as', package, 'cat', base + '/' + directory + '/' + identifier + '.json'])], capture_output=True, timeout=20)
            if content.returncode == 0:
                json.loads(content.stdout)
                (args.output / (directory + '.json')).write_bytes(content.stdout)
        for item in args.output.iterdir():
            if item.is_file(): item.chmod(0o600)
        print(json.dumps({'evidence': str(args.output), 'journal_collected': True, 'complete_activity_logs': log_names}))


if __name__ == '__main__':
    main()
