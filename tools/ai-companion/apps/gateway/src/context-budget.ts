import type { ConversationHistoryEntry } from "../../../packages/core/src/index.js";

export type ToolSelectionInput = {
  text: string;
  history?: ConversationHistoryEntry[];
  mode?: "agent" | "plan";
  skillInstructions?: string[];
};

const CORE_TOOLS = [
  "godot_project_snapshot",
  "godot_read_file",
  "godot_list_files",
  "godot_scene_tree",
  "godot_editor_errors",
];

const AUTHORING_TOOLS = [
  "godot_write_file",
  "godot_scene_create_node",
  "godot_scene_set_property",
  "godot_scene_save",
  "godot_editor_undo",
];

const ANIMATION_CORE_TOOLS = [
  "godot_skeleton_inspect",
  "godot_animation_list",
  "godot_animation_analyze_skeletal",
  "godot_animation_preview",
];

const PUBLIC_STORAGE_TOOLS = [
  "godot_public_storage_roots",
  "godot_public_storage_list",
  "godot_public_storage_search",
  "godot_public_storage_read_text",
  "godot_public_storage_import",
];

const UI_TOOLS = [
  "godot_editor_screenshot",
  "godot_editor_ui_tree",
  "godot_editor_ui_action",
  "godot_editor_send_key",
];

export function selectGodotToolNames(input: ToolSelectionInput): string[] {
  const recentHistory = input.history?.slice(-4).map((message) => message.text).join("\n") ?? "";
  const query = normalize(`${recentHistory}\n${input.text}`);
  const selected = new Set(CORE_TOOLS);
  const mutation = has(query, [
    "create", "add", "change", "fix", "implement", "generate", "modify", "write", "delete", "remove", "import",
    "creeaza", "adauga", "schimba", "repara", "implementeaza", "genereaza", "modifica", "sterge", "copiaza",
  ]);
  const animation = has(query, [
    "animation", "animatie", "animatii", "skeleton", "schelet", "bone", "oase", "rig", "mixamo", "retarget",
    "keyframe", "walk cycle", "run cycle", "mers", "alergare", "atac", "root motion",
  ]);
  const publicStorage = has(query, [
    "download", "downloads", "descarcat", "descarcare", "public storage", "memoria telefonului", "memorie publica",
    "fisier public", "shared storage", "/storage/emulated", "dcim", "pictures", "documents",
  ]);
  const editorUi = has(query, [
    "interfata", "interface", "layout", "buton", "button", "tab", "meniu", "menu", "dock", "panel",
    "screenshot", "print screen", "ecran", "control ui",
  ]);
  const scene = has(query, [
    "scene", "scena", "node", "nod", "camera", "collision", "coliziune", "character", "personaj", "player",
    "sprite", "mesh", "resource", "resursa", "2d", "3d",
  ]);
  const settings = has(query, [
    "project setting", "project.godot", "setare proiect", "export", "renderer", "rendering", "display setting",
  ]);
  const runtime = has(query, [
    "error", "eroare", "debug", "depanare", "crash", "run", "ruleaza", "ruleaza", "test", "output", "console",
  ]);
  const skillManagement = has(query, ["skill", "workflow reutilizabil", "flux reutilizabil"]);
  const sourceCode = has(query, [
    "script", "cod", "code", "gdscript", "shader", "fisier", "file", ".gd", ".tscn", ".tres", "json",
  ]);
  const retarget = has(query, ["retarget", "transfer animation", "transfera animatia", "mapare oase", "bone mapping"]);

  if ((input.mode ?? "agent") === "agent" && mutation) {
    selected.add("godot_scene_save");
    selected.add("godot_editor_undo");
    if (scene || sourceCode || (!animation && !publicStorage && !editorUi && !settings)) {
      addAll(selected, AUTHORING_TOOLS);
    }
  }
  if (scene || animation) selected.add("godot_editor_open_scene");
  if (runtime || (mutation && (scene || sourceCode))) addAll(selected, ["godot_editor_run", "godot_editor_stop"]);
  if (animation) {
    addAll(selected, ANIMATION_CORE_TOOLS);
    if (retarget) addAll(selected, ["godot_skeleton_suggest_mapping", "godot_animation_retarget_skeletal"]);
    else if (mutation) selected.add("godot_animation_generate_skeletal");
    selected.add("godot_editor_screenshot");
  }
  if (publicStorage) addAll(selected, PUBLIC_STORAGE_TOOLS);
  if (editorUi) addAll(selected, UI_TOOLS);
  if (settings) {
    selected.add("godot_project_get_setting");
    if (mutation) selected.add("godot_project_set_setting");
  }
  if (mutation && has(query, ["delete", "remove", "sterge", "elimina"])) {
    selected.add("godot_delete_file");
    if (scene) selected.add("godot_scene_remove_node");
  }
  if (skillManagement) addAll(selected, ["agent_skill_list", "agent_skill_propose"]);
  return [...selected];
}

function addAll(target: Set<string>, values: string[]): void {
  for (const value of values) target.add(value);
}

function has(query: string, terms: string[]): boolean {
  return terms.some((term) => query.includes(term));
}

function normalize(value: string): string {
  return value.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
}
