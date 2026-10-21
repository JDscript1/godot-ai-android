#include "ai_runtime_bridge.h"

#include "core/config/engine.h"
#include "core/crypto/crypto_core.h"
#include "core/debugger/engine_debugger.h"
#include "core/error/error_macros.h"
#include "core/input/input.h"
#include "core/input/input_map.h"
#include "core/io/image.h"
#include "core/os/mutex.h"
#include "core/os/os.h"
#include "editor/debugger/editor_debugger_node.h"
#include "editor/debugger/script_editor_debugger.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/texture.h"

bool AIAssistantDebugger::has_capture(const String &p_capture) const {
	return p_capture == "ai_assistant";
}
bool AIAssistantDebugger::capture(const String &p_message, const Array &p_data, int p_session) {
	if (p_message != "ai_assistant:response" || p_data.size() != 2) {
		return false;
	}
	int64_t id = p_data[0];
	if (pending.has(id) && int(Dictionary(pending[id])["session"]) == p_session) {
		replies[id] = p_data[1];
	}
	return true;
}
int64_t AIAssistantDebugger::request(const String &p_command, const Dictionary &p_arguments) {
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	if (!node) {
		return -1;
	}
	ScriptEditorDebugger *current = node->get_current_debugger();
	if (!current || !current->is_session_active()) {
		return -1;
	}
	Array sessions = get_sessions();
	int index = -1;
	for (int i = 0; i < sessions.size(); i++) {
		if (node->get_debugger(i) == current) {
			index = i;
			break;
		}
	}
	if (index < 0) {
		return -1;
	}
	Array keys = pending.keys();
	uint64_t now = OS::get_singleton()->get_ticks_msec();
	for (int i = 0; i < keys.size(); i++) {
		Dictionary state = pending[keys[i]];
		if (now - uint64_t(state["time"]) > 15000) {
			pending.erase(keys[i]);
			replies.erase(keys[i]);
		}
	}
	if (pending.size() >= 64) {
		return -1;
	}
	int64_t id = next_id++;
	Dictionary state;
	state["session"] = index;
	state["time"] = now;
	pending[id] = state;
	Array data;
	data.append(id);
	data.append(p_command);
	data.append(p_arguments);
	current->send_message("ai_assistant:request", data);
	return id;
}
Dictionary AIAssistantDebugger::poll(int64_t p_id) {
	if (!replies.has(p_id)) {
		return Dictionary();
	}
	Dictionary result = replies[p_id];
	replies.erase(p_id);
	pending.erase(p_id);
	return result;
}

void AIRuntimeInputGuard::hold(const Ref<InputEvent> &p_event) {
	pressed.append(p_event);
	expires = OS::get_singleton()->get_ticks_msec() + 2200;
	Input::get_singleton()->parse_input_event(p_event);
}
void AIRuntimeInputGuard::release() {
	for (int i = 0; i < pressed.size(); i++) {
		Ref<InputEvent> event = pressed[i];
		Ref<InputEvent> up = event->duplicate();
		up->set("pressed", false);
		Input::get_singleton()->parse_input_event(up);
	}
	pressed.clear();
}
void AIRuntimeInputGuard::_notification(int p_what) {
	if (p_what == NOTIFICATION_PROCESS && !pressed.is_empty()) {
		if (!EngineDebugger::is_active() || OS::get_singleton()->get_ticks_msec() >= expires) {
			release();
		}
	}
	if (p_what == NOTIFICATION_EXIT_TREE) {
		release();
	}
}
static ObjectID input_guard_id;
static Mutex error_mutex;
static PackedStringArray runtime_errors;
static ErrorHandlerList runtime_error_handler;
static void ai_log_error(void *, const char *, const char *p_file, int p_line, const char *p_error, const char *p_description, bool, ErrorHandlerType p_type) {
	if (!Engine::get_singleton() || Engine::get_singleton()->is_editor_hint() || p_type == ERR_HANDLER_WARNING) {
		return;
	}
	MutexLock lock(error_mutex);
	if (runtime_errors.size() >= 32) {
		runtime_errors.remove_at(0);
	}
	runtime_errors.append((String::utf8(p_file) + ":" + itos(p_line) + " " + String::utf8(p_error) + " " + String::utf8(p_description)).left(1200));
}
static Dictionary ai_error(const String &p_error) {
	Dictionary result;
	result["ok"] = false;
	result["error"] = p_error;
	return result;
}
static Dictionary ai_success(const Variant &p_value) {
	Dictionary result;
	result["ok"] = true;
	result["result"] = p_value;
	return result;
}
static Variant ai_runtime_value(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
			return p_value;
		case Variant::VECTOR2:
		case Variant::VECTOR3:
		case Variant::COLOR:
			return p_value.stringify();
		default:
			return String("[complex value]");
	}
}
static Error ai_capture(void *p_user, const String &p_message, const Array &p_args, bool &r_captured) {
	r_captured = true;
	if (p_message != "request" || p_args.size() != 3 || Engine::get_singleton()->is_editor_hint()) {
		return ERR_INVALID_DATA;
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (!tree || !tree->get_root()) {
		return ERR_UNCONFIGURED;
	}
	Window *viewport = tree->get_root();
	String command = p_args[1];
	Dictionary args = p_args[2];
	Dictionary response;
	AIRuntimeInputGuard *guard = Object::cast_to<AIRuntimeInputGuard>(ObjectDB::get_instance(input_guard_id));
	if (!guard) {
		guard = memnew(AIRuntimeInputGuard);
		guard->set_name("__GodotAIInputGuard");
		guard->set_process_mode(Node::PROCESS_MODE_ALWAYS);
		viewport->add_child(guard);
		guard->set_process(true);
		input_guard_id = guard->get_instance_id();
	}
	if (command == "release") {
		guard->release();
		response = ai_success(true);
	} else if (command == "status") {
		Dictionary state;
		state["scene"] = tree->get_current_scene() ? tree->get_current_scene()->get_scene_file_path() : String();
		Array actions;
		const HashMap<StringName, InputMap::Action> &map = InputMap::get_singleton()->get_action_map();
		for (const KeyValue<StringName, InputMap::Action> &entry : map) {
			actions.append(String(entry.key));
		}
		state["actions"] = actions;
		{
			MutexLock lock(error_mutex);
			state["errors"] = runtime_errors;
		}
		response = ai_success(state);
	} else if (command == "inspect") {
		Node *root = tree->get_current_scene();
		String path = args.get("path", ".");
		Node *target = root ? root->get_node_or_null(NodePath(path)) : nullptr;
		if (!target || (target != root && !root->is_ancestor_of(target))) {
			response = ai_error("Runtime node does not exist in the current scene.");
		} else {
			Dictionary state;
			state["class"] = target->get_class();
			Array children;
			for (int i = 0; i < target->get_child_count() && i < 200; i++) {
				children.append(String(target->get_child(i)->get_name()));
			}
			state["children"] = children;
			Dictionary properties;
			Array requested = args.get("properties", Array());
			for (int i = 0; i < requested.size() && i < 40; i++) {
				String key = requested[i];
				if (key.begins_with("_") || key.contains("password") || key.contains("token") || key.contains("secret")) {
					continue;
				}
				bool valid = false;
				Variant value = target->get(key, &valid);
				if (valid) {
					properties[key] = ai_runtime_value(value);
				}
			}
			state["properties"] = properties;
			response = ai_success(state);
		}
	} else if (command == "screenshot") {
		Ref<ViewportTexture> texture = viewport->get_texture();
		Ref<Image> image = texture.is_valid() ? texture->get_image() : Ref<Image>();
		if (image.is_null() || image->is_empty()) {
			response = ai_error("The running game has no rendered viewport.");
		} else {
			image->convert(Image::FORMAT_RGBA8);
			while (image->get_width() > 1536 || image->get_height() > 1536) {
				image->resize(MAX(1, image->get_width() / 2), MAX(1, image->get_height() / 2));
			}
			Vector<uint8_t> bytes = image->save_png_to_buffer();
			while (bytes.size() > 2 * 1024 * 1024 && image->get_width() > 256) {
				image->resize(MAX(1, image->get_width() / 2), MAX(1, image->get_height() / 2));
				bytes = image->save_png_to_buffer();
			}
			Dictionary frame;
			frame["width"] = image->get_width();
			frame["height"] = image->get_height();
			frame["data"] = CryptoCore::b64_encode_str(bytes.ptr(), bytes.size());
			response = bytes.size() <= 2 * 1024 * 1024 ? ai_success(frame) : ai_error("Frame exceeds the screenshot limit.");
		}
	} else if (command == "input") {
		String kind = args.get("kind", "");
		Ref<InputEvent> event;
		Vector2 position(CLAMP(double(args.get("x", 0.5)), 0.0, 1.0) * viewport->get_visible_rect().size.x, CLAMP(double(args.get("y", 0.5)), 0.0, 1.0) * viewport->get_visible_rect().size.y);
		if (kind == "action") {
			StringName action = args.get("action", "");
			if (InputMap::get_singleton()->has_action(action)) {
				Ref<InputEventAction> press;
				press.instantiate();
				press->set_action(action);
				press->set_pressed(true);
				press->set_strength(1.0);
				event = press;
			}
		} else if (kind == "key") {
			Ref<InputEventKey> press;
			press.instantiate();
			press->set_physical_keycode(Key(int64_t(args.get("key", 0))));
			press->set_pressed(true);
			event = press;
		} else if (kind == "mouse") {
			Ref<InputEventMouseButton> press;
			press.instantiate();
			press->set_position(position);
			press->set_global_position(position);
			press->set_button_index(MouseButton(CLAMP(int(args.get("button", 1)), 1, 9)));
			press->set_pressed(true);
			event = press;
		} else if (kind == "touch") {
			Ref<InputEventScreenTouch> press;
			press.instantiate();
			press->set_index(0);
			press->set_position(position);
			press->set_pressed(true);
			event = press;
		}
		if (event.is_null()) {
			response = ai_error("Unknown input kind or InputMap action.");
		} else {
			guard->hold(event);
			response = ai_success(true);
		}
	} else {
		response = ai_error("Unsupported playtest operation.");
	}
	Array reply;
	reply.append(p_args[0]);
	reply.append(response);
	EngineDebugger::get_singleton()->send_message("ai_assistant:response", reply);
	return OK;
}
void initialize_ai_runtime_capture() {
	runtime_error_handler.errfunc = ai_log_error;
	add_error_handler(&runtime_error_handler);
	if (!EngineDebugger::has_capture("ai_assistant")) {
		EngineDebugger::register_message_capture("ai_assistant", EngineDebugger::Capture(nullptr, ai_capture));
	}
}
void uninitialize_ai_runtime_capture() {
	remove_error_handler(&runtime_error_handler);
	if (EngineDebugger::has_capture("ai_assistant")) {
		EngineDebugger::unregister_message_capture("ai_assistant");
	}
}
