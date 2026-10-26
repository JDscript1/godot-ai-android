@tool
extends RefCounted
## Provider catalogs and price semantics; no credentials or paid requests.
const CHECKED_ON = "2026-10-26"
const SOURCES = {"meshy": "https://docs.meshy.ai/en/api/pricing", "tripo": "https://developers.tripo3d.ai/en/pricing", "openai_image": "https://developers.openai.com/api/docs/guides/image-generation#calculating-costs", "runware": "https://runware.ai/docs/models-api/pricing"}

static func price(amount: float, currency: String, condition: String, provider: String, basis: String = "from") -> Dictionary:
	return {"amount": amount, "currency": currency, "condition": condition, "basis": basis, "source": SOURCES.get(provider, ""), "checked_on": CHECKED_ON}

static func presets(provider: String, kind: String) -> Array:
	var result = []
	if provider == "meshy":
		if kind == "image":
			for entry in [["nano-banana", "Nano Banana", 3], ["nano-banana-2", "Nano Banana 2", 6], ["nano-banana-2-lite", "Nano Banana 2 Lite", 3], ["nano-banana-pro", "Nano Banana Pro", 9], ["gpt-image-2", "GPT Image 2", 9], ["gpt-image-2-5-flare", "GPT Image 2.5 Flare", 9], ["gpt-image-2-5-sunburst", "GPT Image 2.5 Sunburst", 9]]:
				result.append({"id": entry[0], "name": entry[1], "price": price(float(entry[2]), "credits", "Text → imagine", provider, "fixed")})
		else:
			for entry in [["meshy-7.1", "Meshy 7.1", 20], ["meshy-6", "Meshy 6", 20], ["meshy-6-lite", "Meshy 6 Lite", 5], ["meshy-t2.5", "Meshy T2.5", 5], ["meshy-t2", "Meshy T2", 5]]:
				var item = {"id": entry[0], "name": entry[1], "price": price(float(entry[2]), "credits", "Geometrie din text; imagine + texturi: %s credite" % (30 if entry[2] == 20 else 15), provider)}
				if str(entry[0]).begins_with("meshy-t"): item["options"] = {"model_type": "smart-topology"}
				result.append(item)
	elif provider == "tripo":
		if kind == "image":
			for entry in [["seedream_v5", "Seedream V5", 5], ["seedream_v4", "Seedream V4", 5], ["banana", "Banana", 5], ["banana2", "Banana 2", 10], ["banana_pro", "Banana Pro", 15], ["chat_image_2", "GPT Image 2", 10], ["chat_image_2.5_flare", "GPT Image 2.5 Flare", 10], ["chat_image_2.5_sunburst", "GPT Image 2.5 Sunburst", 10]]:
				result.append({"id": entry[0], "name": entry[1], "price": price(float(entry[2]), "credits", "Rezoluție ≤ 2K, calitate implicită; opțiunile pot costa suplimentar", provider)})
		else:
			for entry in [["v3.1-20260211", "Tripo H3.1"], ["v3.0-20250812", "Tripo H3.0"], ["v2.5-20250123", "Tripo H2.5"]]:
				result.append({"id": entry[0], "name": entry[1], "price": price(20, "credits", "Text + texturi standard; imagine + texturi: 30 credite", provider)})
	return result

static func openai_price(id: String) -> Dictionary:
	# Exact account model IDs are retained; never infer a price for a new model.
	var alias = id
	for prefix in ["gpt-image-2.5-flare", "gpt-image-2.5-sunburst", "gpt-image-1.5", "gpt-image-1-mini", "gpt-image-2"]:
		if id == prefix or (id.begins_with(prefix + "-") and id.trim_prefix(prefix + "-").begins_with("20")):
			alias = prefix
			break
	var amounts = {"gpt-image-2": 0.006, "gpt-image-1.5": 0.009, "gpt-image-1-mini": 0.005}
	if amounts.has(alias): return price(float(amounts[alias]), "USD", "Exemplu 1024 × 1024, low; ieșire + cost prompt. Calitatea automată poate costa mai mult.", "openai_image", "from")
	if alias in ["gpt-image-2.5-flare", "gpt-image-2.5-sunburst"]:
		return {"basis": "usage", "condition": "30 USD / 1M tokeni imagine generați + 5 USD / 1M tokeni text; costul pe imagine variază", "source": SOURCES["openai_image"], "checked_on": CHECKED_ON}
	return {"basis": "unknown", "source": SOURCES["openai_image"]}

static func runware_models(entries: Array, kind: String) -> Array:
	var result = []
	var seen = {}
	for entry in entries:
		if not entry is Dictionary or entry.get("status", "live") != "live": continue
		var id = str(entry.get("air", ""))
		if id.is_empty() or seen.has(id) or id.begins_with("meta:sam@3d"): continue
		var capabilities: Variant = entry.get("capabilities", [])
		if not capabilities is Array: continue
		var suitable = "text-to-image" in capabilities if kind == "image" else ("text-to-3d" in capabilities or "image-to-3d" in capabilities)
		if not suitable: continue
		seen[id] = true
		result.append({"id": id, "name": str(entry.get("name", id)), "capabilities": capabilities, "asset_kind": kind, "schema": str(entry.get("schema", "")), "price": {"basis": "loading"}})
	return result

static func runware_price(schema: Dictionary, kind: String = "") -> Dictionary:
	var info: Variant = schema.get("info", {})
	var raw: Variant = info.get("x-pricing", {}) if info is Dictionary else {}
	if not raw is Dictionary: raw = {}
	var source = {"source": SOURCES["runware"], "checked_on": Time.get_date_string_from_system(true), "condition": "", "basis": "unknown"}
	if raw.get("currency", "USD") != "USD": return source
	var lowest = INF
	var condition = ""
	var count = 0
	var rates: Variant = raw.get("rates", [])
	if not rates is Array: rates = []
	for rate in rates:
		if not rate is Dictionary or rate.get("unit") != "output" or not rate.get("amount") is float and not rate.get("amount") is int: continue
		var amount = float(rate["amount"])
		if not is_finite(amount) or amount < 0: continue
		count += 1
		if amount < lowest:
			lowest = amount
			condition = str(rate.get("label", ""))
	if lowest != INF:
		source.merge({"amount": lowest, "currency": "USD", "condition": condition, "basis": "from" if count > 1 or raw.has("basis") else "fixed"}, true)
		if raw.has("basis"): source["condition"] += " · tarif variabil (" + str(raw["basis"]) + ")"
		return source
	# GPU-time and token prices are samples, never fixed prices per generation.
	var samples: Array = []
	for field in ["measured", "examples"]:
		if raw.get(field) is Array: samples.append_array(raw[field])
	for sample in samples:
		if not sample is Dictionary or not sample.get("price") is float and not sample.get("price") is int: continue
		var configuration = str(sample.get("configuration", "")).to_lower()
		if kind == "image" and ("image-to-image" in configuration or "edit" in configuration or "inpaint" in configuration or "upscale" in configuration): continue
		var amount = float(sample["price"])
		if is_finite(amount) and amount >= 0 and amount < lowest:
			lowest = amount
			condition = str(sample.get("configuration", "Exemplu furnizor"))
	if lowest != INF: source.merge({"amount": lowest, "currency": "USD", "condition": condition + " · exemplu măsurat, costul variază", "basis": "estimate"}, true)
	elif not rates.is_empty(): source.merge({"basis": "usage", "condition": "Tarif după utilizare; consultă tarifele furnizorului."}, true)
	return source

static func price_label(value: Dictionary) -> String:
	var basis = str(value.get("basis", "unknown"))
	if basis == "loading": return "Se încarcă…"
	if basis == "usage": return "Variabil"
	if not value.has("amount"): return "Indisponibil"
	var amount = float(value["amount"])
	if not is_finite(amount) or amount < 0: return "Indisponibil"
	var number = ("%.5f" % amount).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",")
	return ("≈ " if basis == "estimate" else "") + number + (" cr." if value.get("currency") == "credits" else " USD") + ("+" if basis == "from" else "")

static func price_detail(model: Dictionary, kind: String) -> String:
	var value: Dictionary = model.get("price", {})
	var label = price_label(value)
	var unit = "imagine" if kind == "image" else "model 3D"
	if value.has("amount"): label += " / " + unit
	var condition = str(value.get("condition", ""))
	return label + (" · " + condition if not condition.is_empty() else "")
