#include "register_types.h"
#include "ai_assistant_editor.h"

void initialize_ai_assistant_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		GDREGISTER_INTERNAL_CLASS(AIAssistantSecretStore);
		GDREGISTER_INTERNAL_CLASS(AIAssistantSettingsInspector);
		GDREGISTER_INTERNAL_CLASS(AIAssistantEditorPlugin);
		EditorPlugins::add_by_type<AIAssistantEditorPlugin>();
	}
}

void uninitialize_ai_assistant_module(ModuleInitializationLevel p_level) {
}
