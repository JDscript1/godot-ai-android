set -eu
umask 077
if ! command -v python >/dev/null 2>&1; then
    if [ '__GODOT_INSTALL_PYTHON__' = 'true' ]; then
        pkg install -y python
    else
        printf '%s\n' 'Python lipsește. Folosește configurarea Blender din Godot.' >&2
        exit 42
    fi
fi
task_root="$HOME/.local/share/godot-ai/blender"
mkdir -p "$task_root"
printf '%s' '__GODOT_WORKER_BASE64__' | base64 -d > "$task_root/worker.py.tmp"
mv "$task_root/worker.py.tmp" "$task_root/worker.py"
printf '%s\n' 'Godot · Blender: pornesc conexiunea locală. Revino în editor; păstrează această sesiune Termux deschisă.'
exec python "$task_root/worker.py" --root "$task_root" --port __GODOT_PORT__ <<'GODOT_BLENDER_TOKEN'
__GODOT_TOKEN__
GODOT_BLENDER_TOKEN
