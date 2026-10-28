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
	Array sustained;

	bool act_active = false;
	int64_t act_id = 0;
	Dictionary act_args;
	Array act_release;
	int act_phase = 0;
	int act_frame = 0;
	int servo_index = 0;
	uint64_t act_deadline = 0;
	Dictionary servo_state;

	Array watch_expressions;
	Array watch_signals;
	Array watch_connections;
	Array signal_events;

	void _process_act();
	void _finish_act(const String &p_error = String());
	void _press_sustained(const Dictionary &p_input, String &r_signature);
	void _release_sustained(const String &p_signature);
	void _release_all_sustained();
	Dictionary _evaluate_probes(const Array &p_expressions);
	Variant _evaluate(const String &p_expression, String &r_error);
	void _drain_watch(Dictionary &r_state);
	void _connect_watches();
	void _disconnect_watches();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void hold(const Ref<InputEvent> &p_event);
	void release();
	void release_all(bool p_cancel_act = true);
	bool act_running() const { return act_active; }
	Dictionary evaluate_command(const Array &p_expressions);
	Dictionary watch_command(const Dictionary &p_args);
	void start_act(int64_t p_id, const Dictionary &p_args);
	Dictionary status_command();
	Variant _watch_signal(const Variant **p_args, int p_argcount, Callable::CallError &r_error);
};
void initialize_ai_runtime_capture();
void uninitialize_ai_runtime_capture();
