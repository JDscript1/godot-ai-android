@tool
extends RefCounted

class CatalogTransport:
	extends RefCounted
	var rows: Array = [{"id": "ds/catalog-chat", "type": "chat", "context_length": 131072}]
	var fail = false
	var requests: Array = []
	func request(url: String, method: int, headers: PackedStringArray, _body: Variant, _options: Dictionary) -> Dictionary:
		requests.append({"url": url, "method": method, "authenticated": "Authorization: Bearer omniroute-fixture-key" in headers})
		return {"ok": false, "status": 401, "error": "Fixture rejected key"} if fail else {"ok": true, "json": {"data": rows.duplicate(true)}}

func run(host: EditorPlugin, panel: Control, output: String) -> void:
	var original: Array = panel.config["providers"].duplicate(true)
	var selection: Dictionary = panel._selection().duplicate(true)
	var original_transport: RefCounted = panel.providers.transport
	var transport = CatalogTransport.new()
	panel.providers.transport = transport
	panel.config["providers"] = []
	panel._refresh_lists()
	panel._new_provider()
	panel.open_settings("providers")
	var form: Dictionary = panel.forms["provider"]
	panel._select_issuer("omniroute")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	form["url"].text = "100.101.102.103:20128"
	form["key"].text = "omniroute-fixture-key"
	form["manual_model"].text = "combo/private-route"
	await panel._provider_save_action()
	var id = str(form["editing"])
	var profile: Dictionary = panel._profile_by_id(id)
	host._check(not profile.is_empty() and profile.get("url") == "http://100.101.102.103:20128/v1", "OmniRoute saves an authenticated Tailscale endpoint through the actual Connect action")
	if not profile.is_empty():
		host._check(panel.vault.read(id) == "omniroute-fixture-key" and not JSON.stringify(profile).contains("omniroute-fixture-key"), "OmniRoute stores the gateway credential only in the vault")
		var manual_id = "combo/private-route"
		host._check(profile["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id and item.get("manual", false)), "Connect persists the explicit route alongside the discovered catalog")
		panel._edit_provider(0)
		await host.get_tree().create_timer(.15).timeout
		host._check(form["groups"]["url"].visible and form["url"].is_visible_in_tree() and form["url"].text == profile["url"], "Saved OmniRoute profiles retain a visible editable server address")
		host._check(form["key"].text.is_empty() and panel.provider_advanced.visible, "Reediting exposes advanced controls without exposing the saved gateway key")
		panel._choose({"profile": id, "model": manual_id})
		transport.rows.append({"id": manual_id, "type": "chat", "context_length": 65536})
		var refreshed: bool = await panel._test_provider(id)
		var records: Array = profile["models"].filter(func(item: Dictionary) -> bool: return item["id"] == manual_id)
		host._check(refreshed and records.size() == 1 and records[0].get("manual", false) and records[0]["context"] == 65536 and records[0]["source"] == "live", "Catalog refresh retains manual intent and adopts fresh model metadata without duplicates")
		transport.rows = [{"id": "ds/new-catalog-chat", "type": "chat", "context_length": 131072}]
		refreshed = await panel._test_provider(id)
		host._check(refreshed and profile["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id and item.get("manual", false)) and panel._selection().get("model") == manual_id, "A route disappearing from discovery remains selected after refresh")
		host._check(not profile["models"].any(func(item: Dictionary) -> bool: return item["id"] == "ds/catalog-chat"), "Refresh removes stale automatic entries while keeping manual routes")
		var unlisted: Dictionary = profile["models"].filter(func(item: Dictionary) -> bool: return item["id"] == manual_id)[0]
		host._check(unlisted["source"] == "manual" and unlisted.get("context", 0) == 0, "An unlisted manual route no longer claims stale catalog context as live metadata")
		# Re-enter through draft discovery, the other catalog replacement path.
		panel._edit_provider(0)
		await panel._discover_provider_draft()
		host._check(form["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id and item.get("manual", false)), "Draft discovery also preserves manual routes for the same saved endpoint")
		host._check(panel._save_provider() and panel._profile_by_id(id)["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id), "Saving a rediscovered draft cannot erase the manual route")
		profile = panel._profile_by_id(id)
		transport.rows = []
		refreshed = await panel._test_provider(id)
		host._check(refreshed and profile["models"].size() == 1 and profile["models"][0]["id"] == manual_id, "An empty successful discovery preserves the configured manual route without keeping stale automatic entries")
		transport.fail = true
		refreshed = await panel._test_provider(id)
		host._check(not refreshed and profile["models"].size() == 1 and profile["models"][0]["id"] == manual_id and panel.vault.read(id) == "omniroute-fixture-key", "Authentication failure never deletes saved manual routes or their credential")
		transport.fail = false
		panel._edit_provider(0)
		if not output.is_empty():
			await host.get_tree().create_timer(.2).timeout
			panel.settings_window.get_texture().get_image().save_png(output.path_join("omniroute-saved.png"))
		form["url"].text = "100.101.102.103:20129"
		host._check(not panel._save_provider() and panel._profile_by_id(id)["url"].ends_with(":20128/v1") and panel.vault.read(id) == "omniroute-fixture-key", "Saving a changed endpoint without a replacement key is refused before credential or model carry")
		form["key"].text = "omniroute-fixture-key"
		transport.rows = [{"id": "different-endpoint-chat", "type": "chat"}]
		await panel._discover_provider_draft()
		host._check(not form["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id) and panel._profile_by_id(id)["url"].ends_with(":20128/v1"), "A different endpoint draft cannot inherit the old server's manual routes or mutate the saved connection")
		transport.rows = []
		form["manual_model"].text = "combo/other-endpoint"
		await panel._discover_provider_draft()
		host._check(form.get("catalog_verified", false) and form["models"].size() == 1 and form["models"][0]["id"] == "combo/other-endpoint", "An authenticated empty catalog permits a newly explicit manual route")
		form["manual_model"].text = ""
		await panel._discover_provider_draft()
		host._check(not form.get("catalog_verified", false) and form["models"].is_empty(), "An empty catalog without manual intent remains unavailable")
		host._check(transport.requests.all(func(item: Dictionary) -> bool: return item["authenticated"] and item["method"] == HTTPClient.METHOD_GET and item["url"].ends_with("/v1/models")), "Every catalog check uses the exact gateway URL and its own bearer credential")
		transport.rows = [{"id": "different-endpoint-chat", "type": "chat"}]
		await panel._discover_provider_draft()
		host._check(panel._save_provider() and panel._profile_by_id(id)["url"].ends_with(":20129/v1") and not panel._profile_by_id(id)["models"].any(func(item: Dictionary) -> bool: return item["id"] == manual_id), "Saving a verified replacement endpoint uses its new catalog without the previous server's manual routes")
		panel.vault.erase(id)
	panel.provider_cancel["cancelled"] = true
	panel.provider_epoch += 1
	panel.providers.transport = original_transport
	panel.config["providers"] = original
	panel._refresh_lists()
	panel._choose(selection)
	if original.is_empty(): panel._new_provider()
	else: panel._edit_provider(0)
	panel.settings_window.hide()
