"""Opt-in live API evaluation of the production panel, harness and editor tools.

Credentials come from an explicit environment variable, never command arguments.
The project and editor settings are temporary; only redacted evidence is retained.
This command is deliberately separate from deterministic CI tests.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


CASES = ("identity", "inspect", "edit_verify", "debug_script", "scene_auto",
         "plan_only", "permission_denied", "cleanup", "missing_file", "store_search")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--proot", action="store_true")
    parser.add_argument("--issuer", default="deepseek")
    parser.add_argument("--kind", choices=("chat", "responses", "anthropic", "gemini"), default="chat")
    parser.add_argument("--url", default="https://api.deepseek.com")
    parser.add_argument("--model", default="deepseek-v4-flash")
    parser.add_argument("--effort", default="")
    parser.add_argument("--credential-env", default="GODOT_AI_EVAL_API_KEY")
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument("--case-timeout", type=int, default=180)
    parser.add_argument("--max-requests", type=int, default=80)
    parser.add_argument("--output", default=".ai-qa/live-api-evaluation")
    parser.add_argument("--check", action="store_true", help="Compile/setup only; no network or credentials")
    args = parser.parse_args()
    if not 5 <= args.case_timeout <= 600 or not 1 <= args.max_requests <= 200:
        parser.error("Use a case timeout of 5..600 seconds and a request cap of 1..200")
    secret = "" if args.check else os.environ.get(args.credential_env, "").strip()
    if not args.check and not secret:
        parser.error(f"Set {args.credential_env} privately before running live evaluation")
    source = Path(__file__).resolve().parent.parent
    spec = importlib.util.spec_from_file_location("ai_runtime_builder", source / "runtime_builder.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "report.json").exists():
        parser.error("Choose a fresh evidence directory; previous evaluations are preserved")
    with tempfile.TemporaryDirectory(prefix="godot-ai-live-") as directory:
        temporary = Path(directory)
        fixture = temporary / "project"
        addon = fixture / "addons/ai_evaluation"
        addon.mkdir(parents=True)
        shutil.copy2(source / "tests/evaluation/bootstrap.gd", addon / "plugin.gd")
        (addon / "plugin.cfg").write_text('[plugin]\nname="Godot AI API evaluation"\n'
                                        'description="Isolated live evaluation"\n'
                                        'author="JDscript1"\nversion="1.0"\nscript="plugin.gd"\n')
        (fixture / "project.godot").write_text('config_version=5\n[application]\n'
            'config/name="Isolated AI API evaluation"\n[editor_plugins]\n'
            'enabled=PackedStringArray("res://addons/ai_evaluation/plugin.cfg")\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        credential = temporary / "credential"
        descriptor = os.open(credential, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(secret)
        secret = ""
        request = temporary / "request.json"
        request.write_text(json.dumps({"source": str(source), "output": str(output),
            "bindings": builder.SCRIPT_BINDINGS, "credential_file": str(credential),
            "profile": {"id": "live-api-evaluation", "name": "API evaluation", "issuer": args.issuer,
                        "kind": args.kind, "url": args.url, "hosting": "cloud", "models": []},
            "model": args.model, "effort": args.effort, "cases": args.cases,
            "case_timeout": args.case_timeout, "max_requests": args.max_requests, "check": args.check}))
        environment = {"GODOT_AI_EVALUATION": str(request),
                       "XDG_CONFIG_HOME": str(temporary / "config"),
                       "XDG_DATA_HOME": str(temporary / "data")}
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x900x24 -ac", args.godot,
                   "--editor", "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                   "--resolution", "1280x900", "--path", str(fixture)]
        if args.proot:
            command = ["proot-distro", "login", "debian", "--shared-home", "--", "env",
                       *(f"{key}={value}" for key, value in environment.items()), *command]
        # Pass only the credential file, not a secret in proot's command line/environment.
        child_env = {key: value for key, value in os.environ.items()
                     if key != args.credential_env and not any(word in key.upper()
                     for word in ("API_KEY", "AUTH_TOKEN", "ACCESS_TOKEN"))}
        with (output / "editor.log").open("w") as stream:
            process = subprocess.Popen(command, env={**child_env, **environment},
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                process.wait(timeout=(args.case_timeout + 15) * len(args.cases) + 90)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
        report_path = output / "report.json"
        if not report_path.exists():
            raise SystemExit(f"Evaluation setup failed; see {output / 'editor.log'}")
        report = json.loads(report_path.read_text())
        print(json.dumps({"model": report.get("model"), "real_api": report.get("real_api"),
                          "results": [{"case": item["case"], "passed": item["passed"],
                                       "verdict": item.get("verdict"),
                                       "requests": item.get("outcome", {}).get("requests", 0)}
                                      for item in report.get("results", [])]}, ensure_ascii=False))
        lines = ["# Probe API ale agentului", "", f"Model: `{args.model}`. Furnizor: `{args.issuer}`.", "",
                 "Panoul, contextul, harness-ul și tool-urile provin din sursele curente.",
                 "Proiect și setări izolate; aceste probe nu citesc istoricul APK-ului Android.", "",
                 "| Probă | Rezultat | Cereri | Durată | Tool-uri |", "| --- | --- | ---: | ---: | --- |"]
        for item in report.get("results", []):
            tools = " → ".join(entry["name"] for entry in item.get("tools", [])) or "—"
            lines.append(f"| {item['case']} | {item.get('verdict', 'PASS' if item['passed'] else 'FAIL')} | "
                         f"{item.get('outcome', {}).get('requests', 0)} | "
                         f"{item['milliseconds'] / 1000:.1f} s | {tools} |")
        lines.extend(["", "Raportul JSON include verificările, răspunsurile publice, argumentele și rezultatele.",
                      "`events.jsonl` păstrează traseul apelurilor, iar `journal.json` jurnalul real al panoului.",
                      "Raționamentul intern și cheia API nu sunt incluse în aceste rapoarte.", ""])
        (output / "REPORT.md").write_text("\n".join(lines))
        if process.returncode or not report.get("ok", False):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
