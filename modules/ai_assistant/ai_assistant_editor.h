#pragma once

#include "editor/plugins/editor_plugin.h"
#include "ai_runtime_bridge.h"
#include "editor/inspector/editor_inspector.h"
#include "modules/gdscript/gdscript.h"

class AIAssistantSecretStore : public RefCounted {
	GDCLASS(AIAssistantSecretStore, RefCounted);
	String directory;
	Vector<uint8_t> master_key;
	bool ensure_directory();
protected:
	static void _bind_methods();
public:
	bool store(const String &p_name, const String &p_value);
	String read(const String &p_name);
	bool erase(const String &p_name);
};

class AIAssistantEditorPlugin;

class AIAssistantSettingsInspector : public EditorInspectorPlugin {
	GDCLASS(AIAssistantSettingsInspector, EditorInspectorPlugin);
	AIAssistantEditorPlugin *plugin = nullptr;
public:
	void set_plugin(AIAssistantEditorPlugin *p_plugin) { plugin = p_plugin; }
	bool can_handle(Object *p_object) override;
	bool parse_property(Object *p_object, const Variant::Type p_type, const String &p_path, const PropertyHint p_hint, const String &p_hint_text, const BitField<PropertyUsageFlags> p_usage, const bool p_wide = false) override;
};

class AIAssistantEditorPlugin : public EditorPlugin {
	GDCLASS(AIAssistantEditorPlugin, EditorPlugin);
	Control *panel = nullptr;
	Ref<AIAssistantSettingsInspector> settings_inspector;
	Ref<AIAssistantSecretStore> secrets;
	Ref<AIAssistantDebugger> runtime_debugger;
	Vector<Ref<GDScript>> scripts;
protected:
	static void _bind_methods();
public:
	bool has_main_screen() const override { return true; }
	String get_plugin_name() const override { return "AI Assistant"; }
	void make_visible(bool p_visible) override;
	int64_t runtime_request(const String &p_command, const Dictionary &p_arguments);
	Dictionary runtime_poll(int64_t p_id);
	Dictionary speech_request(const String &p_action, const Dictionary &p_args);
	void open_settings(const String &p_section = String());
	AIAssistantEditorPlugin();
	~AIAssistantEditorPlugin();
};
