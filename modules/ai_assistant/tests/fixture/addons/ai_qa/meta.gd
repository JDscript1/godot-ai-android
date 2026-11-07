@tool
extends RefCounted

class CatalogTransport:
	extends RefCounted
	var requests: Array = []
	var rows: Array = [{"id": "muse-wonder-1.0"}, {"id": "muse-spark-1.3"}, {"id": "muse-image-1.0"}, {"id": "muse-spark-1.3-contributor"}, {"id": "sam-3.1"}, {"id": "muse-voice-transcribe-1.0"}]
	func request(url: String, method: int, headers: PackedStringArray, _body: Variant, _options: Dictionary) -> Dictionary:
		requests.append({"url": url, "method": method, "headers": headers})
		return {"ok": true, "json": {"data": rows.duplicate(true)}}

func run(host: EditorPlugin, panel: Control, output: String) -> void:
	var original: Array = panel.config["providers"].duplicate(true)
	var selection: Dictionary = panel._selection().duplicate(true)
	var original_transport: RefCounted = panel.providers.transport
	var transport = CatalogTransport.new()
	panel.providers.transport = transport
	panel.config["providers"] = [] # Exercise the very first provider too.
	panel.vault.store("meta-qa-deepseek", "deepseek-separate-fixture")
	panel._refresh_lists()
	panel._new_provider()
	panel.open_settings("providers")
	panel._select_issuer("meta")
	var form: Dictionary = panel.forms["provider"]
	form["issuer"].item_selected.emit(form["issuer"].selected)
	host._check(form["name"].text == "Meta Model API" and form["url"].text == "https://api.meta.ai/v1" and not form["allow_http"].button_pressed and not form["local_connection"].visible, "Meta has its own cloud preset and official HTTPS endpoint")
	host._check(panel.chat.provider_icon({"issuer": "meta"}) != panel.chat.provider_icon({"issuer": "custom"}), "Meta retains its own infinity brand emblem instead of the generic API icon")
	form["key"].text = "meta-only-fixture"
	await panel._provider_save_action()
	var id = str(form["editing"])
	var profile: Dictionary = panel._profile_by_id(id)
	host._check(profile.get("issuer") == "meta" and profile.get("kind") == "responses" and profile.get("url") == "https://api.meta.ai/v1", "Connect saves the native Meta Responses provider")
	if not profile.is_empty():
		host._check(panel.vault.read(id) == "meta-only-fixture" and panel.vault.read("meta-qa-deepseek") == "deepseek-separate-fixture" and not JSON.stringify(profile).contains("meta-only-fixture"), "Meta and DeepSeek credentials remain separate vault entries")
		host._check(profile["models"].size() == 3 and profile["models"].all(func(model: Dictionary) -> bool: return model["id"].begins_with("muse-spark-") or model["id"].begins_with("muse-wonder-")), "The Meta chat picker excludes image, speech and segmentation models")
		host._check(panel._selection().get("model") == "muse-spark-1.3-contributor", "A new Meta connection prefers the exact Contributor model even when Standard and Wonder appear first")
		var contributor: Dictionary = profile["models"].filter(func(model: Dictionary) -> bool: return model["id"] == "muse-spark-1.3-contributor")[0]
		host._check(contributor["context"] == 1048576 and contributor["capabilities"].get("vision", false) and contributor["capabilities"].get("tools", false), "An ID-only Meta catalog receives documented context, image and tool capabilities")
		host._check("xhigh" in contributor["efforts"] and not "max" in contributor["efforts"] and not "none" in contributor["efforts"], "Contributor never offers unsupported max or none reasoning effort")
		host._check(not contributor.get("pricing", {}).has("input") and contributor.get("pricing", {}).get("mode") != "local", "Meta API pricing is not invented or labeled local/free")
		panel.config["providers"].push_front({"id": "meta-qa-deepseek", "issuer": "deepseek", "kind": "chat", "name": "DeepSeek fixture", "url": "https://api.deepseek.com", "models": []})
		panel._refresh_lists()
		panel._edit_provider(panel.config["providers"].size() - 1)
		host._check(form["key"].text.is_empty() and form["key"].placeholder_text.contains("Cheie salvată"), "Reopening Meta hides its saved credential")
		host._check(transport.requests.all(func(item: Dictionary) -> bool: return item["url"] == "https://api.meta.ai/v1/models" and item["method"] == HTTPClient.METHOD_GET and "Authorization: Bearer meta-only-fixture" in item["headers"]), "Meta discovery uses only its own bearer key and official model endpoint")
		if not output.is_empty():
			await host.get_tree().create_timer(.2).timeout
			panel.settings_window.get_texture().get_image().save_png(output.path_join("meta-saved.png"))
		panel._choose({"profile": id, "model": "muse-spark-1.3"})
		panel._edit_provider(panel.config["providers"].size() - 1)
		await panel._provider_save_action()
		host._check(panel._selection().get("model") == "muse-spark-1.3", "Resaving Meta respects an explicit user model choice")
		panel._new_provider()
		panel._select_issuer("meta")
		form["issuer"].item_selected.emit(form["issuer"].selected)
		transport.rows = [{"id": "muse-spark-1.3"}]
		form["key"].text = "meta-only-fixture"
		var prior = panel.config["providers"].size()
		await panel._provider_save_action()
		host._check(panel.config["providers"].size() == prior and str(form["editing"]).is_empty(), "Missing Contributor stops a new Meta connection instead of silently substituting Standard")
		form["selected_model"] = "muse-spark-1.3"
		await panel._provider_save_action()
		host._check(panel.config["providers"].size() == prior + 1 and panel._selection().get("model") == "muse-spark-1.3", "A user can explicitly choose another available Meta model")
		panel.vault.erase(str(form["editing"]))
		panel.vault.erase(id)
	panel.vault.erase("meta-qa-deepseek")
	panel.provider_cancel["cancelled"] = true
	panel.provider_epoch += 1
	panel.providers.transport = original_transport
	panel.config["providers"] = original
	panel._refresh_lists()
	panel._choose(selection)
	if original.is_empty(): panel._new_provider()
	else: panel._edit_provider(0)
	panel.settings_window.hide()
