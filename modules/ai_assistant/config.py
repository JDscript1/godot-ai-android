def can_build(env, platform):
    env.module_add_dependencies("ai_assistant", ["gdscript", "websocket", "gltf"])
    return env.editor_build


def configure(env):
    pass
