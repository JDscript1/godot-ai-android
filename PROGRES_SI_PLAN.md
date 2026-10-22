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
- Ultimul commit livrat și verificat ca pachet: **`9a019f6`**
  (`9a019f60290ee2b0d6f5ce5883e64d7f1246a47f`).
- APK-ul include Auto/Plan, progres structurat, Markdown nativ, harness-ul,
  extinderile de tool use, sertarele, controalele compacte și logo-urile upstream.
  Este livrat cu numele stabil `Godot-AI-Android-arm64-debug.apk`. Versiunea
  `12794c4` a fost înlocuită atomic; în Download rămâne un singur APK al fork-ului.

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
- Controale compacte în composer: înălțime de 32 unități, iconuri de 16 unități,
  text de 12 unități și margini reduse. Selectorul ocupă lățimea textului, până
  la 150 unități; reasoning-ul până la 104. Valorile se adaptează scalei editorului.
- **57 SVG-uri preluate din surse upstream**: logo-uri de furnizori din Lobe
  Icons, logo llama.cpp din repository-ul ggml-org și acțiuni Lucide. Acestea
  înlocuiesc aproximările desenate anterior. Sunt încorporate local, fără acces
  la internet la afișare. Sursele, reviziile fixe, hash-urile și licențele sunt în
  `modules/ai_assistant/icons/`; cache-ul folosește scala editorului.
- La fiecare livrare se păstrează un singur installer al acestui fork în
  Download, cu numele stabil `Godot-AI-Android-arm64-debug.apk` și checksum-ul
  asociat. Installerul nou se verifică înainte de înlocuire; celelalte aplicații
  și fișiere ale utilizatorului nu sunt șterse. Regula este în `AGENTS.md`, iar
  livrarea verificată este automatizată în `misc/scripts/deliver_ai_android.py`.
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
- Două moduri vizibile: **Auto** (implicit) și **Plan**. Confirmarea fiecărei
  modificări este o preferință separată; valorile vechi sunt migrate. Auto poate
  modifica proiectul cu permisiunea sesiunii activată; Plan rămâne doar pentru
  citire. Editările de scenă folosesc Undo; fișierele au recuperare.
- Auto cere modelului să aleagă planificarea după complexitate, incertitudine și
  dependențe. `task_update` acceptă pași structurați și faze de planificare,
  execuție, verificare, finalizare sau blocaj. Planificarea blochează scrierile,
  iar pașii neîncheiați continuă în bucla limitată a harness-ului. Stop și limitele
  păstrează progresul întrerupt. Un plan propus nu declanșează execuția.
- Planul se afișează într-un card pliabil din conversație, cu un singur pas în
  lucru, stări distincte și restaurare din istoric. **Aplică planul** trece în
  Auto; preferința de confirmare rămâne activă dacă a fost aleasă.
- Textul conversației are titluri, liste, citate, cod inline, tabele și linkuri
  HTTP(S) validate, fără interpretarea HTML/BBCode din răspunsuri. Blocurile de
  cod și identitatea furnizorului au o prezentare compactă.

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

## Etapa încheiată la 22.10.2026: tool use și composer

Implementat în surse și inclus în APK-ul `588bef1`:

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
în fiecare rol sau mod. Modulul încorporează acum **17 scripturi**, inclusiv
datele SVG pentru iconuri.

## Etapa Auto/Plan și lizibilitate — livrată în APK `9a019f6`

Selectorul de model este redus la maximum 150 unități logice, reasoning la 104.
Auto planifică intern când modelul consideră necesar, apoi continuă execuția;
această fază internă nu schimbă selecția utilizatorului în modul Plan. Plan este
alegerea explicită pentru inspectare și propuneri. Nu există clasificator local
care să garanteze dificultatea sau calitatea deciziilor unui furnizor real.

Au trecut **167 verificări funcționale**, zero erori, și **3 teste de livrare**.
Regresia de editor a trecut **142 verificări în fiecare dintre cinci configurații**,
fără erori și cu ieșire normală. Au fost inspectate capturile de chat formatat,
plan și opțiuni Auto/Plan. Verificarea C++ și încorporarea celor 17 surse au trecut.
Editorul nativ recompilat a trecut **152 × 5 verificări**, fără erori. Cele trei
joburi ale [workflow-ului `39740297032`](https://github.com/JDscript1/godot-ai-android/actions/runs/39740297032) au reușit.
APK-ul `9a019f6` a fost verificat și livrat; toate cele 17 surse corespund byte
cu byte bibliotecii ARM64. Companionul a trecut 9 teste și build-ul TypeScript
local și în CI, cu runtimes simulate. Dovezi: `.ai-qa/auto-plan-final/`,
`.ai-qa/auto-plan-native-ci/.ai-qa/native-rendered/`,
`.ai-qa/auto-plan-verification.json` și `.ai-qa/delivery-9a019f6.json`.

## Dovezi de verificare

| Etapă | Dovezi | Limite |
| --- | --- | --- |
| APK `9a019f6` — Auto/Plan și lizibilitate | [Workflow `39740297032`](https://github.com/JDscript1/godot-ai-android/actions/runs/39740297032) reușit: 167 aserțiuni, 142 × 5 verificări upstream, 152 × 5 verificări native, 3 teste de livrare, 9 teste companion + build, C++ și 17 surse încorporate verificate | Livrat atomic în Download; fără teste fizice Android sau furnizori reali |
| APK `12794c4` (istoric) | [Workflow `39733876322`](https://github.com/JDscript1/godot-ai-android/actions/runs/39733876322): android, runtime și native-editor reușite; semnătură, pachet, ARM64 și hash verificate local; **15 surse comparate byte cu byte cu biblioteca din APK** | Teste fizice Android și servicii live neefectuate de agent; nume stabil în Download |
| APK `588bef1` (istoric) | Workflow `39725331751`: joburile android, runtime și native-editor încheiate cu succes; semnătură, pachet, ARM64 și SHA-256 verificate; cele 14 scripturi au trecut verificarea de încorporare byte cu byte | Fără teste fizice Android sau servicii live; semnătura de dezvoltare persistentă păstrată |
| APK `e98ddb7` (istoric) | Workflow `39707618934`; semnătură, pachet, ARM64 și surse încorporate verificate | Înlocuit la 22.10.2026 de APK-ul `588bef1` |
| Interfață și punte nativă anterioare | Rapoarte documentate în `docs/AI_ASSISTANT.md` | Randarea desktop nu dovedește comportamentul fizic Android |
| Harness propriu, prima etapă | 122 verificări funcționale, zero erori; 80 verificări în editor în fiecare dintre cinci configurații, zero erori; 13 surse încorporate verificate byte cu byte | Godot upstream ARM64, fixture izolat |
| Extinderi tool use | **149 verificări funcționale**, zero erori; **91 verificări în editor în fiecare dintre cinci configurații**, zero erori; 14 scripturi verificate byte cu byte | Puntea nativă a fost compilată și executată în jobul native-editor al workflow-ului `39725331751` (**139 verificări × 5**, zero erori) |
| Selector și sertare în composer | **149 verificări funcționale**, zero erori; **129 verificări în fiecare dintre cinci configurații de editor**, zero erori; 14 scripturi verificate byte cu byte | Randare cu Godot upstream ARM64 și date de probă; APK-ul include codul, dar testarea fizică rămâne separată |
| Controale compacte și artwork upstream | **150 verificări funcționale** și **132 × 5 verificări în editor**, fără erori; 15 surse încorporate verificate byte cu byte; 57 SVG-uri verificate față de hash-urile upstream | APK `12794c4` compilat și livrat; editorul nativ al fork-ului a trecut **142 × 5 verificări**, fără erori |

Rapoartele extinderilor tool use sunt în `.ai-qa/tool-use-final/`, pentru `desktop`,
`narrow`, `wide`, `phone_landscape` și `phone_compact`. Manifestul local
`.ai-qa/tool-use-verification.json` înregistrează hash-urile surselor, verificarea
C++ și limitele validării. Randarea telefonului landscape a fost inspectată vizual.

Jobul `native-editor` al workflow-ului `39725331751` a compilat editorul desktop
al fork-ului și a executat fixture-ul în cele cinci configurații: **139 de
verificări în fiecare**, zero erori și ieșire normală. Acesta este primul
rezultat care include execuția reală a punții `script_diagnostics`: script salvat
valid cu hash, draft invalid cu diagnosticare structurată și verificarea că
draftul nu este salvat. Execuția pe Android fizic rămâne separat de validat.

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
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
(144.960.817 bytes, pachet `com.jdscript.godotai.debug`, numai `arm64-v8a`).
Fișierul `.sha256` este lângă APK. Versiunea `12794c4` a fost înlocuită atomic
la aceeași cale stabilă, după verificarea noii versiuni; în Download rămâne un
singur APK al fork-ului.

SHA-256:
`82e62aa5b2165511bfc6ef866b77846842f9a896ed1a778620d823a632941f7b`.

Certificatul de dezvoltare a rămas neschimbat:
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.

## Ce rămâne de făcut sau de validat

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
- **22.10.2026:** APK compilat din `588bef1` prin workflow-ul `39725331751`
  (joburile android, runtime și native-editor reușite). Installerul
  `Godot-AI-4.7.2-arm64-588bef1-debug.apk`, cu SHA-256 `e208b1e7…`, a fost
  instalat în Download, iar APK-ul `e98ddb7` a fost eliminat. Semnătura de
  dezvoltare persistentă a rămas aceeași. Jobul native-editor a executat
  fixture-ul pe editorul fork-ului: 139 × 5 verificări, zero erori.
- **22.10.2026:** controale de jos reduse de la 44 la 32 unități, cu lățimi
  limitate după text; înlocuite simbolurile aproximative cu 57 SVG-uri upstream
  Lobe Icons, Lucide și llama.cpp. Testele locale au încheiat 150 verificări
  funcționale și 132 × 5 verificări în editor, fără erori. Adăugate verificarea
  și înlocuirea atomică a installerului, cu nume stabil în Download.
- **22.10.2026:** compilare și livrare finală `12794c4`, workflow `39733876322`.
  Controalele compacte și logo-urile upstream sunt incluse în APK. Au trecut
  150 verificări funcționale, 3 teste de livrare, 132 × 5 verificări upstream
  și 142 × 5 verificări pe editorul nativ. Toate cele 15 surse au fost găsite
  identic în biblioteca ARM64 din APK; semnătura persistentă a fost verificată
  local. Înlocuire atomică în Download și eliminarea installerului `588bef1`.
  Dovezi: `.ai-qa/delivery-12794c4.json`, `.ai-qa/compact-authentic-icons-final/`
  și `.ai-qa/compact-icons-native-ci/.ai-qa/native-rendered/`.

- **22.10.2026:** implementate Auto/Plan, plan structurat cu faze și continuare
  limitată, migrarea preferințelor, selector mai scurt, Markdown nativ și carduri
  de progres. Verificare funcțională locală: 167 aserțiuni, zero erori; APK nou
  încă nelivrat la această etapă.

- **22.10.2026:** livrare finală Auto/Plan `9a019f6`, workflow `39740297032` reușit.
  167 aserțiuni, 142 × 5 verificări upstream și 152 × 5 verificări native, fără
  erori. Companion: 9 teste și TypeScript build trecute local și în CI. APK de
  144.960.817 bytes verificat: pachet, ARM64, certificat persistent, SHA-256 și
  toate cele 17 scripturi identice sursei. Versiunea anterioară a fost înlocuită
  atomic la numele stabil din Download; nu s-au creat installere duplicate.
  Testarea fizică Android și planificarea/coding cu modele reale rămân de validat.

Detalii: [configurare și verificări](docs/AI_ASSISTANT.md),
[contractul harness-ului](docs/AI_HARNESS.md).
