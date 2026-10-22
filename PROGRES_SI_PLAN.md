# Godot AI Android — implementări, verificări și plan

Ultima actualizare: **22 octombrie 2026**.

Acesta este documentul de lucru al proiectului. Se actualizează după fiecare
etapă importantă: implementare, verificare, compilare sau livrare. „Implementat
în surse”, „testat în editor”, „compilat în APK” și „verificat pe dispozitiv”
sunt stări distincte. Un plan sau un test cu furnizor simulat nu este prezentat
drept funcție validată cu un serviciu real.

## Proiect și versiuni

- Repository: `JDscript1/godot-ai-android`, ramura `ai/android-assistant`.
- Bază: Godot **4.7.2-stable**; modul propriu `modules/ai_assistant`.
- Ultimul commit de documentare existent la începutul etapei curente:
  `2d1a43a`.
- Ultimul APK livrat și verificat ca pachet este construit din **`e98ddb7`**.
- Harness-ul propriu, extinderile de tool use și noul selector din chat sunt modificări
  locale ulterioare acelui APK. Nu sunt încă incluse în installerul livrat.

## Implementări existente

### Integrarea în editor și interfața

- Tab principal **AI Assistant**, imediat după Asset Store; acces și din
  setările generale ale editorului.
- Interfață nativă de chat, temă graphite cu accente violet/albastru și gradient;
  coloană de lectură limitată, mesaje ale utilizatorului aliniate la dreapta.
- Istoric adaptiv, conversații noi, căutare, favorite, arhivare, redenumire,
  ramificare și export Markdown.
- Streaming cu actualizarea acelorași blocuri, cod evidențiat și copiere,
  activități grupate și detalii expandabile.
- Composer adaptiv, imagini și referințe la proiect, comenzi `/`, coadă de
  mesaje, Stop, Resume și Steer.
- Selectorul de model este în partea de jos, lângă câmpul de mesaj. Antetul
  afișează titlul conversației și acțiunile pentru istoric, conversație nouă,
  extindere și setări.
- Sertar nativ în interiorul chatului: **furnizor → modelele acelui profil →
  reasoning**. API cloud, abonamentele și modelele locale sunt grupate separat.
  Căutarea filtrează furnizorii sau modelele furnizorului ales.
- Alegerea devine activă numai după selectarea reasoning-ului. Înapoi permite
  corectarea alegerii; închiderea, apăsarea în exterior și Escape păstrează
  selecția anterioară. Butonul separat de reasoning deschide direct nivelurile
  modelului curent. Sunt oferite numai nivelurile declarate în catalog și Auto;
  un catalog fără niveluri configurabile oferă numai Auto.
- Pe lățimi mari, selectorul și reasoning-ul sunt pe rândul acțiunilor; pe
  lățimi mici au un rând propriu. Numele lungi sunt prescurtate vizual, cu
  detalii complete în tooltip. Listele sertarului se derulează separat.
- Iconuri vectoriale originale, generate local și păstrate în cache, pentru
  identitățile furnizorilor, sertare, reasoning, moduri, istoricul conversațiilor,
  categorii de setări, abonamente și tipurile de generare. Regiunile Qwen
  folosesc aceeași identitate; endpointurile custom au un simbol generic.
  Sunt simboluri proprii ale interfeței, nu logo-uri oficiale descărcate.
- Setări separate pentru furnizori, abonamente, generare, MCP, automatizări,
  jurnal, agent, voce și testarea jocului. Navigarea se adaptează ferestrelor
  înguste. Există preferință pentru reducerea animațiilor.

### Furnizori, conturi și date

- Adaptoare HTTP proprii pentru Chat Completions compatibil, Responses,
  Anthropic și Gemini; catalog de profile inclusiv DeepSeek, OpenRouter,
  Ollama, LM Studio și llama.cpp.
- Detectarea cheilor distinctive; cheile ambigue cer alegerea furnizorului.
  Listarea modelelor este separată de verificarea efectivă a tool calling.
- Păstrarea contextului la schimbarea furnizorului și a blocurilor specifice
  doar pentru profilul/modelul de origine.
- Flux ChatGPT SIWC implementat nativ; Claude, Copilot și Kimi au integrări
  opționale prin companion. Autentificările reale se verifică separat.
- Android Keystore pentru credențiale; date publice separate de secrete,
  redactarea credențialelor din context și jurnale.
- Conversații, memorii, jurnale, copii de recuperare și artefacte separate per
  proiect. Scripturile agentului sunt interne editorului, nu addon copiat în joc.

### Harness propriu, în surse

- Nucleu `runtime/harness.gd`, folosit de chat și de subagenții cu furnizori
  direcți; rulează în Godot fără Termux, consolă sau SDK extern de agent.
- Buclă model → unelte → rezultate → model, streaming, anulare, limite de pași,
  retry limitat pentru cereri temporar eșuate și stări finale distincte.
- Registru de unelte permise, verificarea identificatorilor de apel și
  reutilizarea rezultatului unui apel deja înregistrat, fără repetarea operației.
- Salvarea progresului înainte de execuție și după rezultate; o eroare de
  salvare oprește operațiile următoare. Apelurile întrerupte sunt închise explicit
  în istoric, fără reluarea automată a unor modificări neconfirmate.
- Modurile Analiză, Plan, Cu confirmare și Autonom folosesc permisiunile native.
  Editările de scenă folosesc Undo unde este posibil; fișierele au recuperare.

### Unelte și integrarea jocului

- Baza anterioară etapei curente: **43 unelte definite** — 31 pentru editor,
  4 pentru generare, 5 pentru sarcini/subagenți și 3 pentru Playtest.
- Citire/scriere/căutare fișiere, scene, noduri, semnale, scripturi, proprietăți,
  resurse, setări, animații, controale ale editorului și Output/Debugger.
- Descoperirea metodelor/proprietăților/semnalelor și apeluri prin handle-uri.
  Operațiile C++ private sau neexpuse necesită adaptoare dedicate.
- Explore și General returnează constatări/propuneri; părintele aplică scrierile.
  Limitele existente sunt doi copii pentru cloud și unul pentru local/companion.
- Playtest are capturi din joc, inspectarea stării și input limitat prin puntea
  debugger, plus eliberarea inputului și watchdog.
- MCP Streamable HTTP: inițializare, sesiuni, catalog paginat și apeluri.
  Serverele stdio arbitrare rămân găzduite separat.

### Generare, voce și automatizări

- Profile Runware și ComfyUI, joburi persistente, polling, descărcare și validare
  PNG/GLB, previzualizare și import fără suprascrierea fișierelor existente.
- Catalog public Runware verificat; acesta nu dovedește generare cu credite.
- Integrare de voce Android și endpoint compatibil Whisper. Verificarea completă
  a microfonului și a serviciilor instalate rămâne necesară pe dispozitiv.
- Automatizările sunt instrucțiuni salvate, lansate manual; nu există încă
  scheduler autonom sau serviciu permanent de fundal.

## Etapa curentă: extinderea tool use

Implementat în surse:

1. **`tool_search` și `tool_describe`**: registru separat per rulare, set inițial
   redus, căutare cu relevanță/paginare și încărcarea schemelor la cerere pentru
   următoarea cerere către model. Catalogul respectă permisiunile sesiunii.
2. **Validare comună a argumentelor**: obiecte și liste imbricate, câmpuri
   obligatorii, tipuri, limite, enum, pattern și referințe locale. Numerele
   fracționare nu sunt acceptate ca întregi. Schemele nesuportate sunt raportate
   explicit; acesta este un subset JSON Schema, nu implementarea întregului standard.
3. **`godot_apply_patch`**: înlocuiri exacte, hash de versiune, previzualizare
   implicită, refuzul contextului ambiguu sau al unui script deschis cu modificări
   nesalvate, copie de recuperare și înlocuire prin fișier temporar verificat.
4. **`godot_script_diagnostics`**: punte C++ către parserul/analyzer-ul GDScript,
   cu validitate, erori, avertismente, poziții și hash. Poate analiza un draft
   fără a-l salva. Codul C++ a trecut verificarea de sintaxă și tipuri; execuția
   punții necesită editorul nativ recompilat și nu este dovedită de testul upstream.
5. **`godot_read_range` și `godot_search_code`**: citire și căutare limitate, cu
   fișier, linie și coloană. Citirea returnează și hash-ul pentru pregătirea patch-urilor.
6. **Rezultate MCP normalizate**: text, date structurate, verificarea schemelor
   de rezultat suportate și `isError` propagat ca eșec. PNG/JPEG/WebP sunt trimise
   ca atașamente ale modelului; datele base64 nu umplu contextul text. Conținutul
   nesuportat, precum audio, este raportat explicit.
7. **Scanări de fișiere secvențiate**: schimbările apropiate folosesc cereri
   grupate de rescanare. Testul de editor salvează corect bufferul modificat
   intenționat înainte de ieșire.

Catalogul are acum **49 tipuri de unelte definite**: 35 pentru editor, 4 pentru
generare, 5 pentru sarcini/subagenți, 3 pentru Playtest și 2 pentru descoperire.
Uneltele MCP descoperite se adaugă dinamic; nu toate cele 49 sunt expuse simultan
în fiecare rol sau mod. Modulul încorporează acum **14 scripturi**.

## Dovezi de verificare

| Etapă | Dovezi | Limite |
| --- | --- | --- |
| APK `e98ddb7` | Workflow `39707618934`; semnătură, pachet, ARM64 și surse încorporate verificate | Precede harness-ul propriu și extinderile curente |
| Interfață și punte nativă anterioare | Rapoarte documentate în `docs/AI_ASSISTANT.md` | Randarea desktop nu dovedește comportamentul fizic Android |
| Harness propriu, prima etapă | 122 verificări funcționale, zero erori; 80 verificări în editor în fiecare dintre cinci configurații, zero erori; 13 surse încorporate verificate byte cu byte | Godot upstream ARM64, fixture izolat; fără recompilarea APK-ului |
| Extinderi tool use curente | **149 verificări funcționale**, zero erori; **91 verificări în editor în fiecare dintre cinci configurații**, zero erori; 14 scripturi verificate byte cu byte | Diagnosticarea nativă este verificată C++ static; execuția ei cere recompilare |
| Selector și sertare în composer | **149 verificări funcționale**, zero erori; **129 verificări în fiecare dintre cinci configurații de editor**, zero erori; 14 scripturi verificate byte cu byte | Randare cu Godot upstream ARM64 și date de probă; fără APK nou sau teste fizice Android |

Rapoartele extinderilor tool use sunt în `.ai-qa/tool-use-final/`, pentru `desktop`,
`narrow`, `wide`, `phone_landscape` și `phone_compact`. Manifestul local
`.ai-qa/tool-use-verification.json` înregistrează hash-urile surselor, verificarea
C++ și limitele validării. Randarea telefonului landscape a fost inspectată vizual.

Rapoartele finale ale selectorului sunt în `.ai-qa/composer-drawer-complete/`,
pentru aceleași cinci configurații. Fiecare include `editor-report.json`,
`editor.log`, `composer-selector.png` și capturi `drawer-providers.png`,
`drawer-models.png`, `drawer-reasoning.png`. Au fost inspectate vizual chatul,
setările, lista de modele și sertarele, inclusiv configurațiile la 150%.
Manifestul `.ai-qa/composer-drawer-verification.json` înregistrează sursele și
dovezile finale; `.ai-qa/composer-drawer-runtime.log` păstrează regresia funcțională.
Testele verifică separarea listelor între furnizori, selecția aplicată după
reasoning, anularea, Înapoi/Escape, păstrarea selecției mesajelor în coadă,
iconurile și limitele geometrice ale sertarului/composerului. Dimensiunile
folosesc fontul și scalarea efective pentru a evita derularea inutilă la liste
scurte. Iterațiile inițiale cu erori de dimensionare nu sunt numărate în aceste
rezultate finale; toate cele cinci procese finale au ieșit normal.

În timpul dezvoltării, primul test de editor a căzut în timpul scanării fișierelor;
un test ulterior a trecut aserțiunile, dar nu a ieșit normal. Au fost corectate
secvențierea scanărilor și salvarea bufferului modificat de fixture. Aceste
încercări nu sunt numărate ca teste trecute. Regresia finală de mai sus a ieșit
normal în toate cele cinci configurații. Avertismente ale mediului virtual
Proot/X11 pot apărea în loguri; acestea nu constituie validare fizică Android.

Ultimul installer:
`/storage/emulated/0/Download/Godot-AI-4.7.2-arm64-e98ddb7-debug.apk`.

SHA-256:
`9063d311384e365a3b502dc95ca6a103a4fbaffd37cb4b605030a9bc7d6053be`.

## Ce rămâne de făcut sau de validat

- Recompilarea și livrarea unui APK care include etapa curentă.
  Aceasta include și selectorul nou, sertarele și iconurile; installerul vechi
  nu a fost modificat în această etapă.
- Teste fizice Android: tastatură, atingere, rotație, suspendare/revenire,
  Keystore și microfon.
- Teste cu modele reale pentru coding și mai multe apeluri de unelte succesive;
  catalogul sau compatibilitatea API nu garantează calitatea modelului.
- Fluxuri reale de autentificare prin abonamente și tratarea reautentificării.
- Generare reală prompt → imagine/GLB → validare → import în Godot.
- Playtest condus efectiv de model, cu dovezi dintr-un joc real.
- Căutare în documentația API, unelte specializate suplimentare pentru scene,
  Git nativ printr-o bibliotecă integrată și integrări externe opționale.
- Compactare automată după bugetul de context, evaluări de fiabilitate și
  automatizări programate. Acestea nu sunt funcții finalizate.
- Inferența locală în interiorul APK-ului nu este implementată; profilele locale
  folosesc endpointuri de modele deja pornite.

## Jurnalul etapelor

- Fundație: modul C++/GDScript, furnizori direcți, secrete Android, MCP și generare.
- `91fc116`, `683c769`, `83f7c68`: ecran principal nativ, conversații/subagenți,
  Playtest/voce, restaurare cu verificarea conflictelor și confirmări serializate.
- `6efdea8`, `7a19230`, `66cd1fb`: scripturi interne la salvarea scenelor,
  context compactat la ramificare și comportamentul de urmărire a streamingului.
- `f89a0dc`, `2ae35f6`, `605654d`, `e98ddb7`: simplificarea interfeței mobile,
  separarea conturilor, navigare adaptivă și reproiectarea chatului/setărilor.
- **22.10.2026:** harness propriu extras și conectat, cu testele precizate mai sus.
- **22.10.2026:** extins tool use cu descoperire la cerere, validare comună,
  patch-uri, citire/căutare, punte de diagnosticare și rezultate MCP normalizate.
  Adăugat documentul de progres, legătura din README și instrucțiuni în `AGENTS.md`
  pentru actualizarea lui la etapele următoare. Etapa a încheiat 149 verificări
  funcționale și 91 × 5 verificări în editor, fără erori; puntea nativă rămâne
  verificată static până la recompilarea editorului.
- **22.10.2026:** selectorul de model mutat din antet în composer; adăugate
  sertare pentru furnizor, model și reasoning, aplicare atomică a selecției,
  anulare și acces direct la reasoning. Iconuri comune introduse în chat și
  setări, cu identități distincte pentru furnizori. Verificarea vizuală include
  capturi ale fiecărui sertar și ale selectorului din composer. Rezultat final:
  149 verificări funcționale și 129 × 5 verificări în editor, fără erori.

Detalii: [configurare și verificări](docs/AI_ASSISTANT.md),
[contractul harness-ului](docs/AI_HARNESS.md).
