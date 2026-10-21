#pragma once
#include "core/input/input_event.h"
#include "editor/debugger/editor_debugger_plugin.h"
#include "scene/main/node.h"

class AIAssistantDebugger : public EditorDebuggerPlugin {
	GDCLASS(AIAssistantDebugger, EditorDebuggerPlugin);
	Dictionary pending;
	Dictionary replies;
	int64_t next_id = 1;

public:
	bool has_capture(const String &p_capture) const override;
	bool capture(const String &p_message, const Array &p_data, int p_session) override;
	int64_t request(const String &p_command, const Dictionary &p_arguments);
	Dictionary poll(int64_t p_id);
};

class AIRuntimeInputGuard : public Node {
	GDCLASS(AIRuntimeInputGuard, Node);
	Array pressed;
	uint64_t expires = 0;

protected:
	void _notification(int p_what);

public:
	void hold(const Ref<InputEvent> &p_event);
	void release();
};
void initialize_ai_runtime_capture();
void uninitialize_ai_runtime_capture();
