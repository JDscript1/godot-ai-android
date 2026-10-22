#include "ai_assistant_editor.h"

#include "runtime.gen.h"

#include "core/crypto/crypto.h"
#include "core/io/config_file.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "editor/editor_main_screen.h"
#include "editor/editor_node.h"
#include "editor/file_system/editor_paths.h"
#include "editor/settings/editor_settings.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"

#ifdef ANDROID_ENABLED
#include "platform/android/jni_utils.h"
#include "platform/android/thread_jandroid.h"

static String ai_android_vault(const char *p_method, const String &p_name, const String &p_value = String()) {
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AISecretVault");
	ERR_FAIL_NULL_V(cls, String());
	bool writing = String(p_method) == "store";
	jmethodID method = env->GetStaticMethodID(cls, p_method, writing ? "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" : "(Ljava/lang/String;)Ljava/lang/String;");
	if (!method || env->ExceptionCheck()) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return String();
	}
	jstring name = env->NewStringUTF(p_name.utf8().get_data());
	jstring value = nullptr;
	jstring result = nullptr;
	if (writing) {
		value = env->NewStringUTF(p_value.utf8().get_data());
		result = (jstring)env->CallStaticObjectMethod(cls, method, name, value);
	} else {
		result = (jstring)env->CallStaticObjectMethod(cls, method, name);
	}
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	if (value) {
		env->DeleteLocalRef(value);
	}
	env->DeleteLocalRef(name);
	env->DeleteLocalRef(cls);
	return output;
}
#endif

void AIAssistantSecretStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("store", "name", "value"), &AIAssistantSecretStore::store);
	ClassDB::bind_method(D_METHOD("read", "name"), &AIAssistantSecretStore::read);
	ClassDB::bind_method(D_METHOD("erase", "name"), &AIAssistantSecretStore::erase);
}

bool AIAssistantSecretStore::ensure_directory() {
	if (!master_key.is_empty()) {
		return true;
	}
	directory = EditorPaths::get_singleton()->get_config_dir().path_join("ai_assistant_secrets");
	if (DirAccess::make_dir_recursive_absolute(directory) != OK) {
		return false;
	}
	const String key_path = directory.path_join("master.key");
	if (FileAccess::exists(key_path)) {
		master_key = FileAccess::get_file_as_bytes(key_path);
	} else {
		Ref<Crypto> crypto = Crypto::create();
		ERR_FAIL_COND_V(crypto.is_null(), false);
		master_key = crypto->generate_random_bytes(32);
		Ref<FileAccess> file = FileAccess::open(key_path, FileAccess::WRITE);
		ERR_FAIL_COND_V(file.is_null(), false);
		file->store_buffer(master_key);
		file.unref();
		FileAccess::set_unix_permissions(key_path, 0600);
	}
	return master_key.size() == 32;
}

bool AIAssistantSecretStore::store(const String &p_name, const String &p_value) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("store", p_name, p_value) == "ok";
#else
	ERR_FAIL_COND_V(!ensure_directory(), false);
	Ref<ConfigFile> file;
	file.instantiate();
	file->set_value("secret", "value", p_value);
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	Error err = file->save_encrypted(path + ".tmp", master_key);
	if (err != OK) {
		return false;
	}
	FileAccess::set_unix_permissions(path + ".tmp", 0600);
	return DirAccess::rename_absolute(path + ".tmp", path) == OK;
#endif
}

String AIAssistantSecretStore::read(const String &p_name) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("read", p_name);
#else
	ERR_FAIL_COND_V(!ensure_directory(), String());
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	if (!FileAccess::exists(path)) {
		return String();
	}
	Ref<ConfigFile> file;
	file.instantiate();
	if (file->load_encrypted(path, master_key) != OK) {
		return String();
	}
	return file->get_value("secret", "value", String());
#endif
}

bool AIAssistantSecretStore::erase(const String &p_name) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("erase", p_name) == "ok";
#else
	ERR_FAIL_COND_V(!ensure_directory(), false);
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	return !FileAccess::exists(path) || DirAccess::remove_absolute(path) == OK;
#endif
}

bool AIAssistantSettingsInspector::can_handle(Object *p_object) {
	return Object::cast_to<EditorSettings>(p_object) != nullptr;
}

bool AIAssistantSettingsInspector::parse_property(Object *p_object, const Variant::Type p_type, const String &p_path, const PropertyHint p_hint, const String &p_hint_text, const BitField<PropertyUsageFlags> p_usage, const bool p_wide) {
	if (!p_path.begins_with("ai_assistant/") || !p_path.ends_with("/configure")) {
		return false;
	}
	Button *button = memnew(Button);
	button->set_text(TTR("Configure AI Assistant…"));
	button->connect(SceneStringName(pressed), callable_mp(plugin, &AIAssistantEditorPlugin::open_settings).bind(p_path.get_slice("/", 1)));
	add_custom_control(button);
	return true;
}

void AIAssistantEditorPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("runtime_request", "command", "arguments"), &AIAssistantEditorPlugin::runtime_request);
	ClassDB::bind_method(D_METHOD("runtime_poll", "id"), &AIAssistantEditorPlugin::runtime_poll);
	ClassDB::bind_method(D_METHOD("speech_request", "action", "arguments"), &AIAssistantEditorPlugin::speech_request);
	ClassDB::bind_method(D_METHOD("script_diagnostics", "source", "path"), &AIAssistantEditorPlugin::script_diagnostics);
	ClassDB::bind_method(D_METHOD("open_settings", "section"), &AIAssistantEditorPlugin::open_settings, DEFVAL(String()));
}

Dictionary AIAssistantEditorPlugin::script_diagnostics(const String &p_source, const String &p_path) {
	Dictionary response;
	if (p_source.utf8().length() > 1024 * 1024 || !p_path.begins_with("res://") || p_path.get_extension() != "gd") {
		response["ok"] = false;
		response["code"] = "invalid_arguments";
		response["error"] = "Expected a project GDScript path and at most 1 MB of source.";
		return response;
	}
	List<ScriptLanguage::ScriptError> errors;
	List<ScriptLanguage::Warning> warnings;
	List<String> functions;
	const bool valid = GDScriptLanguage::get_singleton()->validate(p_source, p_path, &functions, &errors, &warnings);
	Array diagnostics;
	for (const ScriptLanguage::ScriptError &error : errors) {
		if (diagnostics.size() >= 200) {
			break;
		}
		Dictionary entry;
		entry["severity"] = "error";
		entry["path"] = error.path;
		entry["line"] = error.line;
		entry["column"] = error.column;
		entry["message"] = error.message;
		diagnostics.push_back(entry);
	}
	for (const ScriptLanguage::Warning &warning : warnings) {
		if (diagnostics.size() >= 200) {
			break;
		}
		Dictionary entry;
		entry["severity"] = "warning";
		entry["path"] = p_path;
		entry["line"] = warning.start_line;
		entry["end_line"] = warning.end_line;
		entry["code"] = warning.string_code;
		entry["message"] = warning.message;
		diagnostics.push_back(entry);
	}
	Array found_functions;
	for (const String &function : functions) {
		if (found_functions.size() >= 200) {
			break;
		}
		found_functions.push_back(function);
	}
	Dictionary result;
	result["path"] = p_path;
	result["valid"] = valid;
	result["diagnostics"] = diagnostics;
	result["functions"] = found_functions;
	result["truncated"] = errors.size() + warnings.size() > diagnostics.size() || functions.size() > found_functions.size();
	response["ok"] = true;
	response["result"] = result;
	return response;
}

int64_t AIAssistantEditorPlugin::runtime_request(const String &p_command, const Dictionary &p_arguments) {
	return runtime_debugger.is_valid() ? runtime_debugger->request(p_command, p_arguments) : -1;
}
Dictionary AIAssistantEditorPlugin::runtime_poll(int64_t p_id) {
	return runtime_debugger->poll(p_id);
}
Dictionary AIAssistantEditorPlugin::speech_request(const String &p_action, const Dictionary &p_args) {
#ifdef ANDROID_ENABLED
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AIVoice");
	if (!cls) {
		return Dictionary();
	}
	jmethodID method = env->GetStaticMethodID(cls, "command", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	if (!method) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return Dictionary();
	}
	jstring action = env->NewStringUTF(p_action.utf8().get_data());
	jstring args = env->NewStringUTF(JSON::stringify(p_args).utf8().get_data());
	jstring result = (jstring)env->CallStaticObjectMethod(cls, method, action, args);
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else if (result) {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	env->DeleteLocalRef(action);
	env->DeleteLocalRef(args);
	env->DeleteLocalRef(cls);
	Variant parsed = JSON::parse_string(output);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
#else
	Dictionary result;
	result["error"] = "Dictarea Android nu este disponibilă pe această platformă.";
	return result;
#endif
}

void AIAssistantEditorPlugin::make_visible(bool p_visible) {
	if (panel) {
		panel->set_visible(p_visible);
	}
}

void AIAssistantEditorPlugin::open_settings(const String &p_section) {
	if (!panel) {
		return;
	}
	EditorMainScreen *main_screen = EditorNode::get_singleton()->get_editor_main_screen();
	if (main_screen) {
		main_screen->select_by_name(get_plugin_name());
	}
	panel->call("open_settings", p_section);
}

AIAssistantEditorPlugin::AIAssistantEditorPlugin() {
	EDITOR_DEF("ai_assistant/general/enabled", true);
	EDITOR_DEF("ai_assistant/general/configure", String());
	EDITOR_DEF("ai_assistant/providers/configure", String());
	EDITOR_DEF("ai_assistant/accounts/configure", String());
	EDITOR_DEF("ai_assistant/generation/configure", String());
	EDITOR_DEF("ai_assistant/mcp/configure", String());
	EDITOR_DEF("ai_assistant/automations/configure", String());
	EDITOR_DEF("ai_assistant/general/default_mode", 0);
	EditorSettings::get_singleton()->add_property_hint(PropertyInfo(Variant::INT, "ai_assistant/general/default_mode", PROPERTY_HINT_ENUM, "Analysis,Confirm changes,Autonomous,Plan"));
	EDITOR_DEF("ai_assistant/general/max_agent_steps", 30);
	EditorSettings::get_singleton()->add_property_hint(PropertyInfo(Variant::INT, "ai_assistant/general/max_agent_steps", PROPERTY_HINT_RANGE, "1,100,1"));
	EDITOR_DEF("ai_assistant/general/history_messages", 24);
	EDITOR_DEF("ai_assistant/companion/url", "http://127.0.0.1:7341");
	EDITOR_DEF("ai_assistant/generation/import_directory", "res://ai_assets");
	EDITOR_DEF("ai_assistant/connection/request_timeout_seconds", 180);
	secrets.instantiate();
	runtime_debugger.instantiate();
	add_debugger_plugin(runtime_debugger);

	for (const AIScriptSource &source : ai_script_sources) {
		Ref<GDScript> script;
		script.instantiate();
		script->set_path(String("local://godot_ai/") + source.name + ".gd");
		script->set_source_code(String::utf8((const char *)source.data));
		if (script->reload() != OK) {
			ERR_PRINT(String("AI Assistant could not load embedded script: ") + source.name);
			return;
		}
		for (int i = 0; i < scripts.size(); i++) {
			script->set(ai_script_sources[i].binding, scripts[i]);
		}
		script->set_edited(false);
		scripts.push_back(script);
	}
	panel = memnew(VBoxContainer);
	panel->set_name("AIAssistantPanel");
	panel->set_script(scripts[scripts.size() - 1]);
	panel->call("configure", this, secrets);
	panel->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	panel->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	EditorNode::get_singleton()->get_editor_main_screen()->get_control()->add_child(panel);
	panel->hide();
	settings_inspector.instantiate();
	settings_inspector->set_plugin(this);
	add_inspector_plugin(settings_inspector);
}

AIAssistantEditorPlugin::~AIAssistantEditorPlugin() {
	if (runtime_debugger.is_valid()) {
		remove_debugger_plugin(runtime_debugger);
	}
	if (settings_inspector.is_valid()) {
		remove_inspector_plugin(settings_inspector);
	}
	if (panel) {
		if (panel->get_parent()) {
			panel->get_parent()->remove_child(panel);
		}
		memdelete(panel);
	}
}
