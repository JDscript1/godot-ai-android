@tool
extends EditorPlugin
## The evaluator and its assertions stay outside res://, inaccessible to file tools.
var evaluation: RefCounted

func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "API evaluation"
func _make_visible(value: bool) -> void:
	if evaluation != null and is_instance_valid(evaluation.panel): evaluation.panel.visible = value

func _enter_tree() -> void:
	if OS.get_environment("GODOT_AI_EVALUATION").is_empty(): return
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GODOT_AI_EVALUATION")))
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(str(request.source).path_join("tests/evaluation/plugin.gd"))
	if script.reload() != OK:
		get_tree().quit(2)
		return
	evaluation = script.new(self)
	evaluation.run.call_deferred()

func _process(_delta: float) -> void:
	if evaluation != null: evaluation.poll()
