"""Exercise the real editor MCP endpoint over TCP in a disposable native Godot editor."""
import argparse
import concurrent.futures
import http.client as http_client
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import tempfile
import time


PLUGIN = '''@tool
extends EditorPlugin
class Owner:
    extends Node
    var project_manager_mode = false
    var busy = false
    func _redact(text: String) -> String: return text.replace("mcp-fixture-secret", "[redacted]")
var scripts = {}
var controller: RefCounted
var host_panel: Node
var closing = false
var status_at = 0
func _enter_tree(): boot.call_deferred()
func boot():
    print("MCP_QA boot")
    await get_tree().process_frame
    while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
    var bindings: Dictionary = BINDINGS
    for name in bindings:
        var script = GDScript.new()
        script.take_over_path("local://godot_ai_" + name + ".gd")
        script.source_code = FileAccess.get_file_as_string(OS.get_environment("MCP_SOURCE").path_join("runtime/" + name + ".gd"))
        if script.reload() != OK: get_tree().quit(2); return
        for dependency in scripts: script.set(bindings[dependency], scripts[dependency])
        scripts[name] = script
    host_panel = Owner.new()
    add_child(host_panel)
    controller = scripts.ziva.new(self, ProjectSettings.globalize_path("res://").trim_suffix("/"))
    controller.configure(host_panel, "user://mcp-recovery")
    var result: Dictionary = controller._start_editor()
    if not result.get("ok", false):
        print("MCP_QA start failed ", result)
        get_tree().quit(3)
        return
    var endpoint: Node = controller.editor_mcp
    for name in ["qa_wait", "qa_read_only", "qa_busy"]:
        endpoint.definitions[name] = scripts.common.tool(name, "Test fixture only", {"value": {"type": "boolean"}}, [], "read")
    endpoint.execute_tool = execute
    FileAccess.open(OS.get_environment("MCP_ENDPOINT"), FileAccess.WRITE).store_string(JSON.stringify(result.result))
    set_process(true)
func execute(name: String, args: Dictionary, cancel: Dictionary) -> Dictionary:
    if name == "qa_wait":
        for i in 100:
            await get_tree().create_timer(0.02).timeout
            if cancel.get("cancelled", false): return scripts.common.failure("Cancelled", "cancelled")
        return scripts.common.success("Wait complete")
    if name == "qa_read_only": controller.editor_mcp.read_only = args.get("value", false); return scripts.common.success(true)
    if name == "qa_busy": host_panel.busy = args.get("value", false); return scripts.common.success(true)
    return await controller._execute_editor(name, args, cancel)
func _process(_delta):
    if controller != null and is_instance_valid(controller.editor_mcp) and Time.get_ticks_msec() > status_at:
        status_at = Time.get_ticks_msec() + 250
        FileAccess.open(OS.get_environment("MCP_STATUS"), FileAccess.WRITE).store_string(JSON.stringify(controller.editor_mcp.snapshot()))
    if not closing and FileAccess.file_exists(OS.get_environment("MCP_STOP")):
        closing = true
        controller._stop_editor()
        get_tree().quit()
func _exit_tree():
    if controller != null: controller.close()
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--proot', action='store_true')
    parser.add_argument('--output', default='.ai-qa/editor-mcp')
    parser.add_argument('--ziva-binary', help='Optional upstream binary; probe automatic external MCP discovery without accounts or model calls')
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    spec = importlib.util.spec_from_file_location('runtime_builder', source / 'runtime_builder.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    for filename in ['report.json', 'ziva-probe.json']:
        (output / filename).unlink(missing_ok=True)
    checks = []

    def check(value, label):
        if not value:
            raise AssertionError(label)
        checks.append(label)

    with tempfile.TemporaryDirectory(prefix='godot-editor-mcp-') as directory:
        scratch = Path(directory)
        project = scratch / 'project'
        addon = project / 'addons/mcp_probe'
        addon.mkdir(parents=True)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="MCP Native Test"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mcp_probe/plugin.cfg")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (addon / 'plugin.cfg').write_text('[plugin]\nname="MCP test"\ndescription="Disposable native MCP test"\nauthor="QA"\nversion="1"\nscript="plugin.gd"\n')
        (addon / 'plugin.gd').write_text(PLUGIN.replace('BINDINGS', json.dumps(builder.SCRIPT_BINDINGS)))
        endpoint_path = scratch / 'endpoint.json'
        stop_path = scratch / 'stop'
        environment = {**os.environ, 'MCP_SOURCE': str(source), 'MCP_ENDPOINT': str(endpoint_path), 'MCP_STOP': str(stop_path), 'MCP_STATUS': str(scratch / 'status.json'),
                       'XDG_CONFIG_HOME': str(scratch / 'config'), 'XDG_DATA_HOME': str(scratch / 'data')}
        command = ['xvfb-run', '-a', '-s', '-screen 0 640x800x24 -ac', args.godot, '--editor', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--path', str(project)]
        if args.proot:
            command = ['proot-distro', 'login', '--shared-home', 'debian', '--', 'env',
                       *(f'{key}={environment[key]}' for key in ['MCP_SOURCE', 'MCP_ENDPOINT', 'MCP_STOP', 'MCP_STATUS', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME']), *command]
        with (output / 'editor.log').open('w') as log:
            process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                deadline = time.monotonic() + 90
                while not endpoint_path.exists() and time.monotonic() < deadline and process.poll() is None:
                    time.sleep(.1)
                check(endpoint_path.exists(), 'Native editor MCP starts')
                endpoint = json.loads(endpoint_path.read_text())
                port = int(endpoint['url'].split(':')[2].split('/')[0])
                session = ''
                counter = 0

                def http(body=None, method='POST', extra=None, token=True, use_session=True):
                    connection = http_client.HTTPConnection('127.0.0.1', port, timeout=20)
                    headers = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'}
                    if token: headers['Authorization'] = 'Bearer ' + endpoint['token']
                    if session and use_session: headers['Mcp-Session-Id'] = session
                    headers.update(extra or {})
                    encoded = json.dumps(body) if isinstance(body, (dict, list)) else body
                    try:
                        connection.request(method, '/mcp', encoded, headers)
                        response = connection.getresponse()
                        data = response.read()
                        return response.status, dict(response.getheaders()), json.loads(data) if data else None
                    finally:
                        connection.close()

                def rpc(method, params=None, request_id=None):
                    nonlocal counter
                    counter += 1
                    return http({'jsonrpc': '2.0', 'id': counter if request_id is None else request_id, 'method': method, 'params': params or {}})[2]

                def tool(name, arguments=None, request_id=None):
                    response = rpc('tools/call', {'name': name, 'arguments': arguments or {}}, request_id)
                    if 'error' in response: return response
                    return json.loads(response['result']['content'][0]['text'])

                check(http({}, token=False)[0] == 401, 'Unauthenticated local clients rejected')
                check(http({}, extra={'Origin': 'https://untrusted.example'})[0] == 403, 'Foreign browser origins rejected')
                check(http({}, extra={'Host': 'untrusted.example'})[0] == 403, 'DNS rebinding Host rejected')
                check(http(method='GET')[0] == 405, 'Unsupported SSE GET rejected')
                check(http('{')[2]['error']['code'] == -32700, 'Malformed JSON returns a valid JSON-RPC error')
                status, headers, response = http({'jsonrpc': '2.0', 'id': 'init', 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 'native-qa', 'version': '1'}}})
                session = headers['Mcp-Session-Id']
                check(status == 200 and response['result']['serverInfo']['name'] == 'godot-ai-editor', 'MCP identity and session negotiated')
                check(rpc('tools/list')['error']['code'] == -32000, 'Tool calls require initialized notification')
                check(http({'jsonrpc': '2.0', 'method': 'notifications/initialized'})[0] == 202, 'Notifications acknowledged without JSON body')
                catalog = []
                cursor = None
                while True:
                    listing = rpc('tools/list', {'cursor': cursor} if cursor else {})['result']
                    catalog.extend(listing['tools'])
                    cursor = listing.get('nextCursor')
                    if cursor is None: break
                names = {item['name'] for item in catalog}
                check(len(names) == len(catalog) and {'godot_debugger', 'godot_panels', 'godot_create_node', 'godot_changes_apply'} <= names, 'All native tool pages discoverable without agent discovery gates')
                check(not {'asset_generate', 'agent_spawn'} & names, 'No built-in agent or generation profiles exposed to Ziva')
                check(tool('godot_project')['result']['name'] == 'MCP Native Test', 'Real editor project read through MCP')
                check('error' in tool('nonexistent'), 'Unknown tools rejected')
                check('error' in tool('godot_write_file', {'path': 'res://probe.txt'}), 'Native argument schema enforced before execution')
                check(not tool('godot_read_file', {'path': 'res://../outside.txt'})['ok'], 'Native project path boundary preserved')
                check(tool('godot_write_file', {'path': 'res://probe.txt', 'text': 'FIRST'}, 'write-once')['ok'], 'Native write succeeds independently of our harness')
                check(tool('godot_write_file', {'path': 'res://probe.txt', 'text': 'FIRST'}, 'write-once')['ok'], 'Repeated request returns cached result')
                check(tool('godot_write_file', {'path': 'res://probe.txt', 'text': 'SECOND'}, 'write-once')['error']['code'] == -32600 and (project / 'probe.txt').read_text() == 'FIRST', 'Request ID reuse cannot execute a different write')
                check(tool('godot_restore_file', {'index': 0})['ok'] and not (project / 'probe.txt').exists(), 'Native recovery journal restores the MCP write')
                (project / 'private.txt').write_text('mcp-fixture-secret')
                observed = tool('godot_read_file', {'path': 'res://private.txt'})
                check(observed['result'] == '[redacted]' and (project / 'private.txt').read_text() == 'mcp-fixture-secret', 'Configured secrets redacted in MCP output without modifying original files')
                tool('qa_busy', {'value': True})
                check(tool('godot_write_file', {'path': 'res://busy.txt', 'text': 'NO'})['code'] == 'project_busy' and not (project / 'busy.txt').exists(), 'Concurrent built-in agent mutations blocked')
                check(tool('godot_project')['ok'], 'Read access remains available while built-in agent is busy')
                tool('qa_busy', {'value': False})
                tool('qa_read_only', {'value': True})
                check(tool('godot_write_file', {'path': 'res://readonly.txt', 'text': 'NO'})['code'] == 'read_only', 'MCP read-only gate blocks project mutations')
                tool('qa_read_only', {'value': False})
                staged = tool('godot_changes_prepare', {'changes': [{'path': 'res://batch-a.txt', 'action': 'write', 'expected_sha256': 'missing', 'text': 'A'}, {'path': 'res://batch-b.txt', 'action': 'write', 'expected_sha256': 'missing', 'text': 'B'}]})
                check(staged['ok'] and not (project / 'batch-a.txt').exists(), 'Native change set stages without editing project files')
                batch_id = staged['result']['id']
                check(tool('godot_changes_apply', {'id': batch_id})['ok'] and (project / 'batch-a.txt').read_text() == 'A' and (project / 'batch-b.txt').read_text() == 'B', 'Asynchronous native change-set application completes through MCP')
                check(tool('godot_changes_rollback', {'id': batch_id})['ok'] and not (project / 'batch-a.txt').exists() and not (project / 'batch-b.txt').exists(), 'Native batch recovery works through MCP')
                check(tool('godot_create_scene', {'type': 'Node3D', 'name': 'McpScene'})['ok'], 'Native scene creation succeeds')
                check(tool('godot_create_node', {'type': 'Camera3D', 'name': 'Camera'})['ok'], 'Native scene node creation succeeds')
                check(tool('godot_save_scene', {'path': 'res://mcp_scene.tscn'})['ok'] and 'Camera3D' in (project / 'mcp_scene.tscn').read_text(), 'MCP-created scene saved and verified on disk')
                check('Camera3D' in json.dumps(tool('godot_scene_tree')), 'Real scene tree read back through MCP')
                check(not tool('godot_create_node', {'type': 'NoSuchNativeClass', 'name': 'Invalid'})['ok'], 'Native tool errors remain errors in MCP results')
                with concurrent.futures.ThreadPoolExecutor() as pool:
                    waiting = pool.submit(tool, 'qa_wait', {}, 'cancel-me')
                    time.sleep(.2)
                    check(tool('godot_write_file', {'path': 'res://concurrent.txt', 'text': 'NO'})['code'] == 'editor_busy', 'Tools serialize while an asynchronous operation runs')
                    check(http({'jsonrpc': '2.0', 'method': 'notifications/cancelled', 'params': {'requestId': 'cancel-me'}})[0] == 202, 'Explicit MCP cancellation accepted during operation')
                    check(waiting.result()['code'] == 'cancelled', 'Cancellation reaches the in-flight executor')
                check(http(method='DELETE')[0] == 200, 'Session shutdown accepted')
                check(http({'jsonrpc': '2.0', 'id': 'stale', 'method': 'ping'})[0] == 404, 'Stale sessions cannot call the editor')
                # The March revision permits batches; later revisions reject them.
                check(http([{'jsonrpc': '2.0', 'id': 'batch', 'method': 'ping'}])[2]['error']['code'] == -32600, 'Batches rejected outside the supported legacy session')
                status, headers, response = http({'jsonrpc': '2.0', 'id': 'legacy', 'method': 'initialize', 'params': {'protocolVersion': '2025-03-26'}}, use_session=False)
                session = headers['Mcp-Session-Id']
                http({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
                batch = http([{'jsonrpc': '2.0', 'id': 'p1', 'method': 'ping'}, {'jsonrpc': '2.0', 'id': 'p2', 'method': 'ping'}])[2]
                check(isinstance(batch, list) and {item['id'] for item in batch} == {'p1', 'p2'}, 'Legacy JSON-RPC batches return correlated responses')
                http(method='DELETE')
                ziva_probe = {'attempted': bool(args.ziva_binary), 'automatic_mcp_discovery': False, 'http_server': False, 'model_calls': False}
                if args.ziva_binary:
                    with socket.socket() as probe:
                        probe.bind(('127.0.0.1', 7012))
                    baseline_pages = json.loads((scratch / 'status.json').read_text())['discovered_pages']
                    (project / '.mcp.json').write_text(json.dumps({'mcpServers': {'godot_ai_editor': {'url': endpoint['url'], 'headers': {'Authorization': 'Bearer ${GODOT_AI_EDITOR_MCP_TOKEN}'}}}}))
                    ziva_data = scratch / 'ziva-data'
                    ziva_command = ['env', '-i', 'PATH=/usr/bin:/bin', 'LANG=C.UTF-8', 'DO_NOT_TRACK=1', f'HOME={scratch}', f'XDG_DATA_HOME={scratch / "ziva-xdg"}', f'XDG_CONFIG_HOME={scratch / "ziva-config"}', f'ZIVA_DATA_PATH={ziva_data}',
                                    'GODOT_AI_EDITOR_MCP_TOKEN=' + endpoint['token'], str(Path(args.ziva_binary).resolve())]
                    if args.proot:
                        ziva_command = ['proot-distro', 'login', '--shared-home', '--work-dir', str(project), 'debian', '--', *ziva_command]
                    with (output / 'ziva-startup.log').open('w') as ziva_log:
                        ziva_process = subprocess.Popen(ziva_command, cwd=project, stdout=ziva_log, stderr=subprocess.STDOUT, start_new_session=True)
                        try:
                            deadline = time.monotonic() + 35
                            while time.monotonic() < deadline and ziva_process.poll() is None:
                                try:
                                    observed = json.loads((scratch / 'status.json').read_text())
                                    if observed['clients_initialized'] and observed['discovered_pages'] > baseline_pages:
                                        ziva_probe['automatic_mcp_discovery'] = True
                                        break
                                except (OSError, ValueError):
                                    pass
                                time.sleep(.25)
                            ziva_probe['process_running'] = ziva_process.poll() is None
                            ziva_probe['exit_code_before_stop'] = ziva_process.poll()
                            try:
                                connection = http_client.HTTPConnection('127.0.0.1', 7012, timeout=2)
                                connection.request('GET', '/')
                                response = connection.getresponse()
                                ziva_probe['http_server'] = response.status == 200 and b'html' in response.read(32768).lower()
                                connection.close()
                            except OSError:
                                pass
                        finally:
                            try: os.killpg(ziva_process.pid, signal.SIGTERM)
                            except ProcessLookupError: pass
                            try: ziva_process.wait(timeout=5)
                            except subprocess.TimeoutExpired: os.killpg(ziva_process.pid, signal.SIGKILL); ziva_process.wait()
                    # Retain only normal startup logs, never bundled implementation/error source.
                    startup = (output / 'ziva-startup.log').read_text(errors='replace')
                    for log_file in (ziva_data / 'logs').glob('*.log'):
                        if log_file.is_file() and log_file.stat().st_size <= 1048576:
                            startup += '\n' + log_file.read_text(errors='replace')
                    startup = re.sub(r'\x1b\[[0-9;]*m', '', startup)
                    safe_lines = [line for line in startup.splitlines() if len(line) < 1000 and not endpoint['token'] in line and line.startswith(('[20', 'Server running', 'MCP server', 'error:', 'WARN', 'INFO'))]
                    (output / 'ziva-startup.log').write_text('\n'.join(safe_lines) + '\n')
                    print('Ziva automatic MCP discovery:', ziva_probe['automatic_mcp_discovery'])
                (output / 'report.json').write_text(json.dumps({'checks': len(checks), 'failures': [], 'assertions': checks, 'native_editor': True, 'android_device': False, 'ziva_client': False}, indent=2) + '\n')
                (output / 'ziva-probe.json').write_text(json.dumps(ziva_probe, indent=2) + '\n')
                print(f'Editor MCP: {len(checks)} checks, 0 failures')
            finally:
                stop_path.touch()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait()
        editor_log = (output / 'editor.log').read_text()
        if 'SCRIPT ERROR:' in editor_log or 'ERROR: Cannot save GDScript' in editor_log:
            raise AssertionError('Editor script error; inspect editor.log')


if __name__ == '__main__':
    main()
