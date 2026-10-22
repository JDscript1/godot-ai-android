# Godot AI Android project guidance

- Preserve user projects, assets and unrelated worktrees.
- On every APK delivery, verify the new installer first, then replace older
  Godot AI fork installers and their checksum files in Android Download. Keep
  one current installer there, using a stable filename. Do not remove other
  applications or user downloads. Build evidence may stay in the project.
- For substantive AI assistant, companion, build or delivery changes, update
  `PROGRES_SI_PLAN.md` in Romanian before finishing the task. Record what changed,
  checks actually run, evidence paths, limitations and remaining work. Keep its
  latest-update date current and add a short milestone to its journal.
- Distinguish source implementation, static/automated checks, rendered editor
  checks, compiled APKs, physical Android behavior and live provider checks.
  Do not mark a plan or a simulated provider test as a verified live feature.
- The direct-provider harness must run inside Godot without requiring Termux,
  a shell, Node.js, Python or a separately installed agent runtime on the user's
  device. Development/test tooling is separate from that runtime requirement.
- Keep companion-backed subscriptions and externally hosted MCP programs
  explicitly optional. Do not represent them as native Android integrations.
- Test changes using the relevant module tests and local tools. Never treat an
  older delivered APK as proof of current unbuilt source changes.
