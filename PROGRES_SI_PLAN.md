# Godot AI Android — implementări, verificări și plan

Ultima actualizare: **23 octombrie 2026**.

Acesta este documentul de lucru al proiectului. Se actualizează după fiecare
etapă importantă: implementare, verificare, compilare sau livrare. „Implementat
în surse”, „testat în editor”, „compilat în APK” și „verificat pe dispozitiv”
sunt stări distincte. Un plan sau un test cu furnizor simulat nu este prezentat
drept funcție validată cu un serviciu real.

## Proiect și versiuni

- Repository: `JDscript1/godot-ai-android`, ramura `ai/android-assistant`.
- Bază: Godot **4.7.2-stable**; modul propriu `modules/ai_assistant`.
- Ultimul commit livrat și verificat ca pachet: **`978a6d3`**
  (`978a6d332edd1204baeb0f5fed0634345b16645d`).
- APK-ul include **Auto / Default / Plan**, control YOLO, context, dock-uri,
  sunete, Integrări, Skills, Jurnal, AGENT.MD, generare Meshy/Tripo/OpenAI,
  fișiere în chat, preview imagini/GLB/glTF, control editor, Store și diff real.
  Include exporturi 3D extinse, GitHub cu token personal,
  separatoare Cloud/Local și căutare LAN explicită.
- Livrat cu numele stabil `Godot-AI-Android-arm64-debug.apk`; `13456af` a fost
  înlocuit atomic după verificare. În Download rămâne un singur APK al fork-ului.
- Compilarea și testele automate au trecut. Utilizarea fizică pe Android și
  generarea cu chei plătite rămân de validat separat.

APK-ul curent include și eliminarea cardului Servicii și a scurtăturilor
MCP / Generare 2D/3D din Integrări. Aceste servicii au paginile lor.

## Etapa curentă — Store, rețea locală și generare, 23.10.2026

Implementat în surse; compilarea și livrarea acestei etape sunt în verificare:

- Integrarea GitHub a fost simplificată la token personal: câmp vizibil, salvare
  în vault, verificare cont/repository, alegere repository și deconectare.
  Fluxul OAuth/Device Flow și Client ID-ul au fost scoase din aplicație.

- `store_search` citește structura reală `hits` din API-ul nou și returnează
  `publisher/slug`; `store_describe` folosește această identitate și rutele
  publice corecte. Terrain3D a apărut în răspunsul live al căutării. Instalarea
  permite GDExtension numai când manifestul indică un binar Android ARM64 din
  arhivă, cu antet ELF AArch64 verificat. Arhiva oficială Terrain3D v1.0.2 a
  trecut verificarea ZIP și s-a instalat în proiectul editorului de test, cu
  29 verificări randate fără eșecuri. Activarea rămâne separată; aceasta nu
  dovedește că pluginul se încarcă pe telefon.
- Selectorul tuturor serviciilor Cloud/Local rămâne vizibil și la editarea unui
  profil. Adresa API/LAN este vizibilă pentru profilurile locale. Descoperirea
  probează întâi adresele Wi-Fi private, înaintea celor VPN/mobile, și are
  fallback de enumerare; mesajul explică activarea „Serve on Local Network” din LM Studio
  și introducerea manuală a URL-ului. Rețeaua utilizatorului nu a fost probată.
- Generare folosește o cheie comună per furnizor cloud pentru profilurile de
  imagini și 3D, cu credențiale ComfyUI separate. Butonul de test face ping
  autentificat Runware fără generare, apoi afișează catalogul. Configurarea are
  folder principal și format 3D preferat; comenzile manuale sunt într-un sertar.
  PNG/GLB se importă automat într-un folder propriu, numit după prompt și ID;
  exporturile finalizate se păstrează lângă original cu nume corespunzător.
  Scanarea incrementală a fișierelor evită suprapunerea importurilor editorului.
  Conversiile la furnizor nu pornesc doar prin alegerea formatului.
- Skills și Sarcini au pagini principale separate imediat sub Integrări. Baza
  rămâne Godot **4.7.2-stable**, identică cu ultima ediție oficială Android
  verificată; versiunea APK precedent era deja `4.7.2.stable`. Eșecul Store
  provenea din adaptor, nu din eticheta versiunii.

Verificări locale: **361 aserțiuni runtime**, zero eșecuri, cu arhiva oficială
Terrain3D furnizată testului; fixturile acoperă API-ul Store, GDExtension ELF
ARM64, cheia Runware, prioritatea Wi-Fi, importul și exportul în foldere.
Instalarea arhivei reale a trecut **29 verificări** într-un proiect temporar.
Randarea editorului a trecut **319 verificări × 5 configurații**, zero eșecuri;
capturile Furnizori, Generare, Skills și dockul îngust au fost inspectate.
Dovezi: `.ai-qa/terrain-generation-runtime-final.log`,
`.ai-qa/terrain-real-install/` și `.ai-qa/terrain-generation-all-final/`.
APK-ul nou urmează. Serviciile live cu cheile utilizatorului,
încărcarea Terrain3D pe Android fizic și rețeaua Wi-Fi a utilizatorului rămân
probe separate.

Jurnal: 23.10.2026 — corectat Store, păstrat selectorul Cloud/Local la vedere,
clarificată conexiunea LM Studio și organizată generarea per obiect/furnizor.

## Etapa curentă — rafinare vizuală, livrată 23.10.2026

Implementată în surse și inclusă în APK-ul **`978a6d3`**:

- Bara de chat are câmpul de mesaj, atașarea, microfonul și Trimitere pe primul
  rând; modelul, reasoning-ul unde încape, modul Auto/Default/Plan și contextul
  sunt pe al doilea. În dockul foarte îngust, indiciul devine „Mesaj…”, iar
  butoanele nu se întind pe înălțimea textului. Nivelul de reasoning rămâne
  accesibil prin sertarul modelului și apare în tooltip când nu încape separat.
- Activitatea este un control compact; acțiunea Modificări apare numai când
  există modificări. Codul din răspunsuri se poate încadra în dockul îngust.
- În Furnizori, sigla nu se dublează, iar serviciul unui profil existent se
  schimbă din Opțiuni avansate; la profil nou selectorul rămâne la vedere.
  Meniurile furnizorilor folosesc aceeași paletă cu restul agentului.
- În Setări, acțiunile primare sunt evidențiate, ștergerea/deconectarea au
  culoare distinctă, controalele sunt mai compacte, iar subfilele Integrări
  folosesc paleta agentului. Cardul GitHub arată întâi starea și conectarea;
  Skills afișează descrierea, păstrând identificatorul în detalii.
- La Generare, rezultatul selectabil este înaintea formatelor de export;
  lista goală se ascunde, iar tipul și starea au etichete lizibile.

Verificări locale: **340 aserțiuni runtime**, fără eșecuri; **319 verificări × 5
configurații randate** (desktop, narrow, wide, phone_landscape, phone_compact),
fără eșecuri. Capturile pentru furnizori, Integrări, chat și dockul stâng/îngust
au fost inspectate în `.ai-qa/premium-ui-final-all/`. În CI, cele trei joburi
au trecut, iar editorul nativ compilat a trecut **329 verificări × 5 configurații**;
capturile sale compacte pentru chat, dockul îngust, Furnizori și Integrări au fost
inspectate. APK-ul a fost verificat și livrat. Atingerea și tastatura pe un
dispozitiv Android real rămân de validat separat.

Jurnal: 23.10.2026 — compactat chatul, îndreptat dockul foarte îngust,
unificate meniurile și ierarhia acțiunilor, simplificate Furnizori, Integrări,
Skills și rezultatele de generare; verificare randată în cinci configurații.

## Etapa anterioară — exporturi 3D, GitHub și LAN, 23.10.2026

Implementate și incluse în APK-ul `13456af`, care înlocuiește `2538551`:

- GLB original păstrat pentru preview/import; export glTF în ZIP cu dependențe,
  OBJ/STL/PLY native pentru geometrie statică și conversii FBX/USDZ/3MF prin
  Meshy/Tripo, plus BLEND prin Meshy. Formatele native nu includ materiale,
  rig sau animații; nu pretindem suport pentru toate formatele la fiecare API.
- Selector și buton de export pe rezultatul selectat, destinație aleasă de
  utilizator, fără suprascriere. Tool `asset_export` disponibil agentului.
  Cache după hash pentru exporturi locale; task ID persistent și reluare pentru
  conversii. Răspunsul pierdut la POST blochează retrimiterea plătită oarbă și
  permite recuperare după ID-ul sarcinii existente.
- Istoric, înlocuit ulterior: GitHub **Sign in**, Device Flow nativ, cod public/copiere/browser, validarea
  contului înainte de salvarea tokenului, selectare repository cu paginare și
  fallback manual. Client ID public comun editorului; repo/activare per proiect.
  Tokenurile rămân în vault, fără Client Secret sau credențiale externe împrumutate.
- **Istoric, nu mai este necesar:** nu avem o aplicație OAuth proprie înregistrată.
  Interfața explică înregistrarea și Device Flow; login real nu este încă validat.
- Separatoare vizuale Cloud / Local-self-hosted în serviciile/profilurile din
  Furnizori, selecție după ID stabil și clasificare unitară în sertarul din chat.
  Adresele LAN sunt recunoscute; domeniile proprii pot declara explicit găzduirea.
- Căutare LAN nativă pornită explicit, limitată la două segmente IPv4 private și
  porturile 11434/1234/8080, apoi verificare `/v1/models`, fără trimiterea cheilor.
  Alegerea rezultatului doar completează formularul; salvarea este explicită.
  IP/port/adresă HTTPS pot fi introduse manual, inclusiv când scanarea nu ajunge.
- Documentație: [generare/export](docs/AI_GENERATION.md),
  [autentificare/integrări](docs/AI_INTEGRATIONS.md),
  [conectare Wi-Fi](docs/AI_ASSISTANT.md#local-servers-over-wi-fi),
  [lista de priorități](docs/AI_ROADMAP.md).

Verificări locale: **340 aserțiuni**, fără eșecuri, prin Godot ARM64 în proot.
Acestea includ geometrie reală în OBJ/STL/PLY, glTF cu dependențe, original
nemodificat, conversii HTTP simulate FBX/USDZ/3MF/BLEND, cache/reluare/recuperare,
fără chei pe CDN, OAuth pending/slowdown/refuz/anulare/expirare și endpoint LAN
local izolat. Nu s-a scanat rețeaua utilizatorului. Verificarea randată a trecut: **314 verificări × 5 configurații**, fără eșecuri.
Capturile desktop, înguste și compacte au fost inspectate. Ultima extindere verifică
și exportul deschis chiar din fereastra modală Setări, cu dialog copil corect.
CI a trecut integral: **335 aserțiuni runtime**, **314 verificări × 5** upstream
și **324 verificări × 5** în editorul nativ, fără eșecuri. Capturile native compacte
pentru Furnizori, Integrări, export și dock stânga au fost inspectate.
Dovezi locale: `.ai-qa/new-integrations-unit-final.log`,
`.ai-qa/new-integrations-final-render/`, `.ai-qa/new-integrations-nested/`,
`.ai-qa/13456af-native-ci/`, `.ai-qa/13456af-runtime-ci.log`,
`.ai-qa/13456af-native-ci.log` și `.ai-qa/delivery-13456af.json`.
APK-ul nou a fost livrat în Download după verificarea locală; detalii la final.

Jurnal: 23.10.2026 — extinse exporturile 3D, pregătit GitHub Sign in și selectarea
repository-ului, separate găzduirile și adăugată căutarea LAN. Serviciile live și
validarea fizică Android rămân probe distincte.

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
- **76 SVG-uri preluate din surse upstream**: logo-uri de furnizori din Lobe
  Icons, logo llama.cpp din repository-ul ggml-org și acțiuni Lucide. Acestea
  înlocuiesc aproximările desenate anterior. Sunt încorporate local, fără acces
  la internet la afișare. Sursele, reviziile fixe, hash-urile și licențele sunt în
  `modules/ai_assistant/icons/`; cache-ul folosește scala editorului.
- La fiecare livrare se păstrează un singur installer al acestui fork în
  Download, cu numele stabil `Godot-AI-Android-arm64-debug.apk` și checksum-ul
  asociat. Installerul nou se verifică înainte de înlocuire; celelalte aplicații
  și fișiere ale utilizatorului nu sunt șterse. Regula este în `AGENTS.md`, iar
  livrarea verificată este automatizată în `misc/scripts/deliver_ai_android.py`.
- Setări pentru control, furnizori, abonamente, generare, MCP, Integrări,
  Jurnal, AGENT.MD, voce și testarea jocului. Navigarea se adaptează ferestrelor
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
- Trei moduri vizibile: **Auto / Default / Plan**. Default este inițial pentru
  configurații noi; selecțiile vechi Plan sunt migrate fără a permite scrierea.
  Auto cere un plan scurt înaintea modificărilor/operațiilor externe, verificat
  și de dispatcher. Default permite lucrul direct pentru sarcini simple și
  planifică după complexitate. Plan rămâne doar pentru citire, indiferent de YOLO.
- YOLO este implicit oprit și controlează confirmările în Auto și Default.
  `task_update` publică pași și faze; planning și propunerile blochează scrierile,
  iar faza executing permite modificări. Ambele moduri de execuție continuă
  planurile neîncheiate în limitele harness-ului. Stop păstrează progresul.
- Planul se afișează într-un card pliabil din conversație, cu un singur pas în
  lucru, stări distincte și restaurare din istoric. **Aplică planul** trece în
  Auto și păstrează preferința YOLO.
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

- Profile Runware, ComfyUI, Meshy, Tripo și OpenAI Images, joburi persistente, polling, descărcare și validare
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
în fiecare rol sau mod. Sursele curente încorporează **19 scripturi**, inclusiv
datele SVG pentru iconuri.

## Etapa control și Integrări — inclusă în APK `db5343b`

- Indicator separat de context în bara de jos: inel, procent și detalii la hover.
  Folosește consumul/capacitatea cunoscută a modelului ales; lipsa limitei arată
  „—”, fără procent inventat. Se resetează între modele și conversații.
- General conține YOLO, poziția chatului și sunetele. Preferințele se salvează
  imediat. Limitele tehnice și activarea asistentului au dispărut din interfață.
  Meniul Auto/Default/Plan nu mai conține permisiuni, context sau extindere duplicată.
- Poziție Centru / Stânga / Dreapta prin `EditorDock`; se mută același panel,
  cu aceeași conversație. Mutarea este refuzată în timpul lucrului sau dictării.
  Extinderea de sus mută temporar dock-ul în centru și îl restaurează la
  restrângere, fără schimbarea preferinței salvate.
- Sunet scurt original, sintetizat în PCM, cu volum moderat și previzualizare;
  opțiunea este implicit oprită. Nu sună pentru eșec, anulare sau plan neterminat.
- Integrări are Conexiuni, Skills și Sarcini. GitHub oferă citire repository,
  branches, issues, PR-uri și fișiere, plus creare issue la cererea utilizatorului.
  Tokenul rămâne în vault; repository-ul și activarea sunt salvate per proiect.
- Blender CLI este numai pentru Windows/Linux: executabil configurabil, test de
  versiune, script Python din proiect, fundal fără shell, ieșire limitată,
  anulare/timeout și coduri reale de eroare. Nu este instalat în APK/Android.
  MCP și generarea au pagini proprii; scurtăturile duplicate din Integrări au
  fost eliminate și sunt absente în APK-ul curent.
- Skills sunt fișiere `res://.godot_ai/skills/<id>/SKILL.md`, cu manager de creare,
  editare, activare/dezactivare și ștergere cu recuperare. Agentul are
  `skill_list`, `skill_read`, `skill_save`; actualizările verifică hash-ul,
  iar Plan/confirmările sunt respectate. Instrucțiunile nu se execută automat.
- AGENT.MD editează `res://AGENT.md`, inclus în context, cu migrare la salvare din
  memoria privată veche, reîncărcare și protecție împotriva suprascrierii unui
  fișier modificat între timp. `AGENTS.md` existent rămâne separat și păstrat.
- Jurnalul este consolă cronologică pentru cereri, unelte, rezultate și finalizare,
  cu filtru, Live și copiere. Datele sunt redactate; afișarea este limitată pentru
  a menține editorul responsiv.

Catalogul maxim ajunge la **55 tipuri de unelte** pe desktop (54 pe Android),
prin cele 3 unelte de skills și integrările opționale GitHub/Blender. Nu toate
sunt expuse simultan. Există 19 scripturi și 61 SVG-uri upstream în surse.

Verificări deja încheiate: 187 aserțiuni funcționale, fără erori, incluzând Blender
real 4.3.2 în Debian ARM64: script → GLB → import în Godot, erori Python, anulare
și timeout. Adaptorul nativ GitHub a citit efectiv repository-ul public
`godotengine/godot` fără autentificare; crearea issue a fost testată doar cu server
simulat, fără publicare reală. C++ a trecut verificarea de sintaxă și tipuri.
Regresia finală a trecut **172 verificări în fiecare dintre cinci configurații**
(desktop, narrow, wide, phone_landscape, phone_compact), fără erori și cu ieșire
normală. Capturile finale pentru General, Integrări, Skills, AGENT.MD, consola
de jurnal, context și dock-uri au fost inspectate vizual. Încorporarea celor
**19 scripturi** și hash-urile celor **61 SVG-uri** au fost verificate.

Prima iterație a fost păstrată numai în surse. Ulterior, APK-ul `db5343b` include
această etapă: puntea C++ a fost compilată și executată în editorul nativ
(188 verificări × 5 configurații, fără erori). Windows, Android fizic și
sunetul pe hardware rămân de validat.
Dovezi: `.ai-qa/control-settings-runtime-complete.log`,
`.ai-qa/control-settings-complete/`, `.ai-qa/github-read-live.json` și
`.ai-qa/control-settings-verification.json`.

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
| APK `6539a44` — fișiere, preview și control vizual | [Workflow `39823384697`](https://github.com/JDscript1/godot-ai-android/actions/runs/39823384697) reușit; 295 aserțiuni locale / 290 CI, 233 × 5 verificări upstream și 243 × 5 native; 25 scripturi comparate exact cu APK-ul, 76 SVG-uri | Livrat atomic; modele/servicii simulate, testarea fizică Android și Store public rămân separate |
| APK `db5343b` — moduri, Integrări și generare (istoric) | [Workflow `39772723053`](https://github.com/JDscript1/godot-ai-android/actions/runs/39772723053) reușit; 237 aserțiuni locale / 232 în CI, 178 × 5 verificări upstream și 188 × 5 native, trei teste livrare, nouă teste companion + build; 19 scripturi comparate exact cu biblioteca APK, 65 SVG-uri | Livrat atomic în Download; fără teste fizice Android sau generare plătită reală |
| APK `9a019f6` — Auto/Plan și lizibilitate (istoric) | [Workflow `39740297032`](https://github.com/JDscript1/godot-ai-android/actions/runs/39740297032) reușit: 167 aserțiuni, 142 × 5 verificări upstream, 152 × 5 verificări native, 3 teste de livrare, 9 teste companion + build, C++ și 17 surse încorporate verificate | Livrat atomic în Download; fără teste fizice Android sau furnizori reali |
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
(145.141.041 bytes, pachet `com.jdscript.godotai.debug`, numai `arm64-v8a`).
Fișierul `.sha256` este lângă APK. Versiunea `db5343b` a fost înlocuită atomic
la aceeași cale stabilă, după verificarea noii versiuni; în Download rămâne un
singur APK al fork-ului.

SHA-256:
`0cc48766d215068d5e914a7a65f56f5377c1ef7eb146ff3aa1451f0dadeae6ba`.

Certificatul de dezvoltare a rămas neschimbat:
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.

## Ce rămâne de făcut sau de validat

- Teste fizice Android: swipe/preview/capturi, tastatură, atingere, rotație, suspendare/revenire,
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
- Catalog Store public și addon public real: verificarea locală a catalogului a primit HTTP 403; instalarea/activarea/dezinstalarea sunt probate cu un addon fixture în fork-ul nativ.
- MediaStore/URI SAF persistente, MediaProjection Android și preview pentru OBJ/FBX/.blend nu sunt implementate. GLB/glTF și accesul filesystem deja autorizat sunt disponibile.
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

- **22.10.2026, 09:50 CEST:** recopiat APK-ul `9a019f6` la calea stabilă din
  Download după semnalarea orei 08:34. Hash-ul corespundea deja versiunii noi;
  recopia a actualizat inode-ul și ora modificării, verificată prin `stat`.
  SHA-256 și unicul installer au fost reverificate; solicitată reindexarea
  Android, fără confirmarea vizibilității în managerul de fișiere. Nu este o
  recompilare. Dovezi: `.ai-qa/download-refresh-9a019f6.json`.

- **22.10.2026:** reorganizare control/Integrări/Skills/Jurnal/AGENT.MD,
  indicator permanent de context și dock-uri. Numai surse, fără recompilare APK,
  conform cererii utilizatorului. Final: 187 aserțiuni și 172 × 5 verificări
  upstream, fără erori; Blender real și citire GitHub public verificate. C++
  verificat static, 19 surse și 61 SVG-uri verificate. Commit păstrat local pentru
  a evita declanșarea workflow-ului Android; limitele sunt în etapa curentă.

Detalii: [configurare și verificări](docs/AI_ASSISTANT.md),
[contractul harness-ului](docs/AI_HARNESS.md).

## Etapa Auto / Default / Plan și generare directă — 22.10.2026

- Auto planifică proactiv și cere `task_update` înaintea primei modificări;
  Default este echilibrat, Plan este strict read-only. Selecția salvată are nume
  stabil; vechiul index Plan=1 este migrat la Plan=2, fără escaladare de acces.
- Promptul comun cere răspunsuri de una-două propoziții pentru saluturi,
  identitate și întrebări simple, fără liste de funcții sau planuri inutile.
- Adaptoare native REST: Meshy text→GLB preview și imagine→GLB texturat;
  Tripo v3 text/imagine→3D și text→PNG; OpenAI Images GPT Image text→PNG.
  Runware și ComfyUI sunt păstrate. Configurare separată, chei în vault,
  endpointuri cloud fixe HTTPS și logo-uri originale Meshy/Tripo/ComfyUI.
- Persistență, polling, upload multipart Tripo, validare PNG/GLB și import
  fără suprascriere; cheile API nu sunt trimise la CDN. Oprirea urmăririi nu
  anulează sarcina taxabilă deja acceptată de furnizor. Meshy din text oferă
  geometria inițială; rafinarea/texturarea în a doua etapă nu este automatizată.
- Verificări locale: **237 aserțiuni runtime** și **178 × 5 verificări în editor**
  fără erori; trei teste de livrare, C++ syntax/format, 19 scripturi încorporate
  exact și 65 SVG-uri cu hash valid. Inspectate capturile pentru cele trei moduri
  și formularele Meshy/Tripo/OpenAI. Workflow-ul `39772723053` a trecut, inclusiv
  188 × 5 verificări în fork-ul nativ și 232 aserțiuni în CI. APK verificat: semnătură
  persistentă, pachet, ARM64 și toate cele 19 surse identice cu biblioteca nativă.
- Documentație: `docs/AI_GENERATION.md`; dovezi în `.ai-qa/modes-generation-*`.
  Testele de generare folosesc fixture HTTP, nu chei plătite reale.

Jurnal: **22.10.2026** — adăugate cele trei moduri, politica Auto, răspunsuri
compacte și adaptoarele Meshy/Tripo/OpenAI; compilarea APK este autorizată din nou.

- **22.10.2026 — livrare:** APK `db5343b`, workflow `39772723053` reușit,
  înlocuire atomică la calea stabilă din Download, un singur installer și checksum
  valid. Dovezi: `.ai-qa/delivery-db5343b.json`, `.ai-qa/modes-generation-verification.json`,
  `.ai-qa/db5343b-native-ci/`, `.ai-qa/db5343b-runtime-ci.log`.
  Verificările cu chei plătite și Android fizic rămân distincte și neefectuate.

- **Livrare / metadate Android:** după înlocuirea atomică, stocarea partajată a
  păstrat timestamp-ul anterior, deși hash-ul și conținutul APK erau noi.
  Scriptul de livrare actualizează acum explicit data APK/checksum și o include
  în raport. Fișierul curent indică **22.10.2026, 13:53 CEST**. Trei teste
  existente de livrare și noua regresie de timestamp au trecut local
  (`python misc/scripts/tests/test_ai_delivery_timestamp.py`). Broadcast-ul de
  scanare media a fost trimis; afișarea în managerul Android de fișiere rămâne
  verificabilă pe dispozitiv. A fost schimbat doar ajutorul de livrare, fără
  schimbarea surselor încorporate în APK-ul deja verificat.

- **22.10.2026 — curățare Integrări:** eliminat cardul „Servicii”, inclusiv
  „Servere MCP” și „Generare 2D / 3D”. Integrări păstrează GitHub, Blender CLI pe
  desktop, Skills și Sarcini; MCP și Generare au paginile lor. Verificare în
  editor Godot upstream, configurația phone_landscape: **178 verificări, zero
  erori**, captură inspectată vizual. Dovezi: `.ai-qa/integrations-without-services/`
  și `.ai-qa/integrations-without-services.log`. Modificare numai în surse,
  fără recompilare sau înlocuire APK în această iterație.

- **22.10.2026 — specificație fișiere în chat și control vizual:** adăugat
  `docs/AI_CHAT_FILES_AND_EDITOR_CONTROL.md`, cu cerințe, îmbunătățiri, etape și
  criterii de acceptare pentru carduri locale, mențiuni prin swipe, imagini
  fullscreen, preview 3D comun, capturi/control editor, Asset Store și diff real.
  Baza existentă a fost verificată în cod; uneltele UI semantice există deja,
  dar preview-ul universal și statisticile reale +/− nu sunt implementate.
  Consultate documentațiile Android/Godot. Este o propunere documentată, fără
  schimbări de runtime, teste noi sau recompilare APK în această etapă.

## Fișiere în chat și control vizual — jurnalul implementării, inclusă în APK `6539a44`

- În surse: registru cu versiuni imutabile și acces separat pe conversație,
  căutare nativă în proiect/stocare autorizată, carduri cu miniaturi și mențiuni
  prin swipe, referințe în mesajele puse în coadă, viewer de imagini cu zoom,
  decupare și adnotări. Originalele sunt păstrate.
- Renderer GLB/glTF comun pentru viewer și inspecție în fundal; capturi și
  input în editor cu frame ID, limită de timp și eliberarea inputurilor la Stop.
  În curs de verificare randarea 3D și controlul efectiv al interfeței.
- Diff cu linii reale adăugate/șterse, hunks și carduri per execuție; ZIP Store
  pregătit separat, fără suprascriere, cu verificarea fișierelor instalate.
- Verificare intermediară: `.ai-qa/store-compile2.log`, 269 aserțiuni fără erori.
  Testele vizuale noi au expus un crash al editorului upstream la trecerea spre
  editorul scripturilor; investigația este în curs. Această etapă nu este încă
  declarată validată în editor sau inclusă într-un APK nou.
- Limite de platformă: capturile/controlul vizează Godot, nu alte aplicații;
  MediaProjection Android necesită integrare separată și acordul sistemului.
  Preview 3D v1: GLB/glTF. Addonurile cu binare native necesită verificare
  specifică platformei. Providerii fără vision primesc metadate, fără afirmații
  de analiză vizuală a imaginii.

Jurnal: 22.10.2026 — implementare autorizată pe etape; verificările runtime trec,
QA vizual și adaptorul Store sunt în lucru. APK-ul din Download rămâne db5343b.

- **22.10.2026 — consolidare în surse:** modulele noi sunt încorporate în
  runtime (25 scripturi). Referințele glTF includ hash-urile dependențelor;
  pin/catalog și ramurile păstrează izolarea conversațiilor. Viewerul permite
  comparație și eliberează scenele la închidere. Imaginile sunt trimise numai
  modelelor cu vision declarat, cu buget comun de patru imagini în context.
- Adăugate 11 SVG-uri Lucide originale pentru preview/crop/adnotare/comparație,
  total 76, cu surse fixate, hash-uri și licențe. Headerul și dock-ul au controale
  compacte; păstrat HBox în composer după izolarea crash-ului HFlow upstream.
- Captura solicită explicit randarea, inclusiv în low-processor mode. Puntea
  nativă rutează hover-ul după coordonatele capturate, fără a modifica semnătura
  publică `Viewport.push_input`. Click-ul din fixture upstream folosește touch;
  verificarea mouse-ului nativ necesită recompilarea fork-ului.
- Store urmărește fișierele proprii, refuză conflictele/editările nesalvate și
  detașează resursele cached la ștergere, conform fluxului nativ Godot. Catalogul
  public a răspuns HTTP 403 local; verificarea REST folosește fixture HTTP.
  Nu este declarată verificare cu un addon public sau cu un furnizor vision real.

- **Verificări înainte de compilare:** 290 aserțiuni runtime fără erori
  (`.ai-qa/files-frozen-runtime.log`); 223 verificări în editor upstream desktop
  fără erori (`.ai-qa/files-private-fixtures/desktop/`), cu imagini și GLB reale,
  comparație, input, capturi mascate și fluxul Store disponibil upstream.
  C++ syntax verificat pentru modul, Viewport și instalator; 25 scripturi
  încorporate și 76 hash-uri SVG, plus trei teste de livrare și regresia mtime.
  Verificările pe cinci dimensiuni continuă în `.ai-qa/files-release-render/`.
  Compilarea fork-ului și APK-ului urmează; nu sunt încă declarate livrate.

- **Fork compilat, etapă intermediară:** sursa `cdc6834`, workflow
  `39817624076`: compilarea Android a reușit; 234 verificări desktop în fork-ul
  nativ au trecut, inclusiv inputul real cu mouse și dezinstalarea addonului.
  Workflow-ul complet a eșuat la marginea dock-ului drept în configurația narrow;
  APK-ul intermediar nu a fost livrat în Download.
- Corectată adaptarea la lățimea viewport-ului: limitarea cadrului editorului,
  pliere temporară a panourilor secundare și restaurare când chatul revine în
  centru. Scenariul izolat narrow trece cu 36 verificări; captură inspectată în
  `.ai-qa/dock-viewport-fit/narrow/dock-right.png`. Reluăm suita completă înaintea
  unei noi compilări/livrări. Runnerul QA oprește grupul propriu de procese la
  timeout pentru a evita servere Xvfb rămase active.

- **Validare layout completă:** 228 verificări × 5 configurații locale fără
  eșecuri (`.ai-qa/files-responsive-final/`): desktop, narrow, wide,
  phone_landscape și phone_compact. Include limitele dock/Trimite și revenirea
  panourilor după chat central.
- **Capabilități imagini:** catalogul poate omite modalitățile de intrare. În
  opțiunile furnizorului există acum control salvat separat pentru fiecare
  model: Din catalog / Permite imagini / Doar text. Numele modelului nu este
  folosit pentru a presupune vision. 294 aserțiuni runtime fără eșecuri în
  `.ai-qa/files-capabilities-unit.log`; verificarea formularului este separată.

- **Formular și carduri:** 231 verificări în configurația phone_compact fără
  eșecuri (`.ai-qa/files-vision-ui/`), inclusiv persistența politicii de imagini
  pentru fiecare model. Fixarea/eliberarea unei referințe sincronizează toate
  cardurile aceluiași fișier; la eroare de salvare se păstrează starea anterioară.
  Scenariul izolat pentru fișiere: 39 verificări fără eșecuri
  (`.ai-qa/files-pin-sync/`).

- **Fișiere invalide:** metadatele glTF/GLB sunt validate înainte de parcurgerea
  dependențelor; preview-urile eșuate eliberează referințele de animație. Numărul
  de noduri glTF este verificat și înainte de generarea scenei. O copie schimbată
  în timpul citirii este eliminată din cache, fără atingerea sursei.
  295 aserțiuni runtime fără eșecuri (`.ai-qa/files-invalid-models.log`).


## Livrare finală — 22.10.2026, 19:50 CEST

- Sursă **6539a444278b828b35baa53e9df1f1d7f3e243ed**, workflow
  [39823384697](https://github.com/JDscript1/godot-ai-android/actions/runs/39823384697):
  android, runtime și native-editor încheiate cu succes.
- **290 aserțiuni CI**, **233 verificări × 5** în editor upstream și
  **243 verificări × 5** în fork-ul nativ, fără eșecuri. Local: 295 aserțiuni;
  diferența de cinci provine din probele Blender disponibile local. Au trecut
  și cele trei teste de livrare și nouă teste companion, cu build TypeScript.
- Probe reale în editor: miniaturi, swipe/mențiuni/coadă, crop/comparație,
  geometrie GLB și randare offscreen, click efectiv și capturi mascate,
  sincronizare Pin, politici imagini per model, ZIP/activare/dezinstalare,
  diff colorat și Undo. Aserțiunile nu sunt prezentate drept validare a unui
  model cloud, addon public sau dispozitiv Android fizic.
- Inspectate vizual capturile native pentru chat/referințe, imagini și 3D,
  dock drept îngust și diff. Dovezi: `.ai-qa/6539a44-native-ci/`,
  `.ai-qa/6539a44-ci.log`, `.ai-qa/delivery-6539a44.json`.
- APK: **145.141.041 bytes**, pachet `com.jdscript.godotai.debug`, numai ARM64;
  semnătura persistentă verificată. Toate **25 sursele încorporate** sunt identice
  byte cu byte cu commit-ul compilat. **76 SVG-uri** au hash-uri valide.
- Înlocuire atomică la `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`,
  cu checksum-ul alăturat și mtime **22.10.2026, 19:50:44 CEST**. Verificată
  existența unui singur installer al acestui fork; alte descărcări sunt păstrate.
- SHA-256: `0cc48766d215068d5e914a7a65f56f5377c1ef7eb146ff3aa1451f0dadeae6ba`.

Jurnal: 22.10.2026 — pachetul de fișiere/preview/control/Store/diff este compilat,
verificat și livrat. Android fizic, providerii vision reali și catalogul Store
public rămân de verificat separat; limitele de format/platformă sunt în
`docs/AI_CHAT_FILES_AND_EDITOR_CONTROL.md`.


## Audit dock și butoane — 22.10.2026

- Analizată captura `Screenshot_20261022_200421.jpg`: control tăiat în dock-ul
  stâng. Corectate limitele reale ale tabului, înălțimea, coloana stângă și
  adaptarea barei la lățimi mici. Istoricul compact are pagină proprie.
- Ștergerea nu mai cere arhivare. Confirmarea numește conversația; anularea,
  erorile de salvare, ultima conversație și redeschiderea indexului au probe pe
  fișiere reale izolate. Exportul salvează Markdown prin dialog.
- Corectate favorite/arhivare/redenumire, ciorne pe conversații în sesiune,
  ramificarea unui mesaj expirat și alegerea planului. Controalele indisponibile
  sunt dezactivate explicit.
- Auditul și limitele sunt în [docs/AI_UI_AUDIT.md](docs/AI_UI_AUDIT.md).
  Runtime local: 302 aserțiuni fără eșecuri. Sintaxa C++ Android a trecut.
  279 verificări randate fără eșecuri pe desktop și îngust; 279 pe fereastra mare
  după corectarea înălțimii barei (`.ai-qa/dock-audit-wrap-height/`).
  Revalidarea dock-urilor pe cinci dimensiuni și noua compilare sunt în curs; APK-ul anterior
  nu dovedește aceste modificări. Android fizic și serviciile live rămân separate.

Jurnal: 22.10.2026 — corecții de încadrare și audit al efectelor butoanelor;
verificările exercită fișiere, indexuri, dialoguri și tranziții reale în editor.


### Extindere audit la acțiunile din setări

- Listele păstrează selecția prin ID la actualizare/reordonare, inclusiv
  rezultatele de generare. Rezultatul nou devine selecția curentă.
- Ștergere/testare profiluri, rezultate, skills și sarcini reflectă selecția
  disponibilă și execuția curentă. Preview și import sunt disponibile pentru
  fișiere finalizate descărcate, iar refresh cere profilul aferent.
- 286 verificări în editor upstream compact, fără eșecuri, inclusiv apăsarea
  butonului Preview și verificarea pixelilor reali; ștergerea unui profil
  păstrează fișierul generat. Dovezi: `.ai-qa/ui-settings-actions/`.
- Dock-uri: 64 verificări × 5 dimensiuni fără eșecuri
  (`.ai-qa/dock-audit-responsive/`). Baza auditului `db972be` a trecut complet
  workflow-ul 39832915947; nu a fost livrată ca versiune intermediară în Download.
  Extinderea pentru setări se compilează separat înaintea înlocuirii APK-ului.


### Inspecție nativă suplimentară

- Workflow-ul 39833659749 (`09103e8`) a trecut: 297 aserțiuni runtime,
  286 verificări × 5 upstream și 296 × 5 native. Captura nativă compactă
  a arătat însă coloana centrală peste chat; testele măsurau încadrarea
  controalelor, fără suprapunerea dintre coloane. APK-ul nu a fost livrat.
- Adăugată limitarea temporară a coloanei centrale la spațiul rămas și
  recalcularea după schimbarea coloanelor. Limita originală se restabilește
  la revenirea în centru. Verificările includ viewport-ul 3D, celelalte coloane,
  marginea stângă a ferestrei și geometria JSON; capturile forțează randarea.
- 82 verificări locale compacte fără eșecuri înaintea noului build;
  `.ai-qa/dock-center-bounds/`. Capturile native noi sunt obligatorii înainte
  de livrare. Download păstrează momentan versiunea 6539a44.


### Validare finală audit — sursă 2538551

- Workflow [39835516663](https://github.com/JDscript1/godot-ai-android/actions/runs/39835516663):
  toate cele trei etape încheiate cu succes. 297 aserțiuni runtime CI, 305
  verificări × 5 upstream și 315 × 5 native, fără eșecuri; local 302 aserțiuni
  și 83 verificări de dock × 5. Nouă teste companion și build TypeScript trecute.
- Capturile native compacte și landscape sunt inspectate: chat complet vizibil,
  cu Setări, Dictare și Trimite în interior, fără suprapunerea viewport-ului 3D.
- Dovezi: `.ai-qa/2538551-native-ci/`, `.ai-qa/2538551-runtime-ci.log`,
  `.ai-qa/2538551-native-ci.log`, `.ai-qa/dock-center-responsive/`.
- APK final compilat; descărcarea și verificarea locală sunt în curs. Niciunul
  dintre APK-urile intermediare nu a înlocuit pachetul din Download.


## Livrare audit interfață — 22.10.2026, 21:11:14 CEST

- Sursă **25385516d329a373d37196148e293ca7fa05733a**, workflow
  [39835516663](https://github.com/JDscript1/godot-ai-android/actions/runs/39835516663): runtime, native-editor și Android trecute.
- 297 aserțiuni CI; 305 verificări × 5 în editor upstream și 315 × 5 în editor
  nativ, fără eșecuri. Local: 302 aserțiuni și 83 verificări de dock × 5.
- Capturile native compacte și landscape confirmă chat complet vizibil,
  fără suprapunerea viewport-ului 3D. Auditul include efectele reale ale
  dialogurilor, fișierele/indexurile conversațiilor, export, ciorne, selecții
  stabile, preview și dezactivarea acțiunilor indisponibile.
- APK: **145,157,425 bytes**, `com.jdscript.godotai.debug`, numai ARM64.
  Semnătura persistentă și toate cele 25 de surse încorporate sunt verificate.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  la **21:11:14 CEST**, cu checksum alăturat. Verificat un singur installer
  al fork-ului în Download; alte descărcări sunt păstrate.
- SHA-256: `f8d4d2d208d06655d2b731872423260b02fb2ccbcd7ba8485eaa3932c4bd8a52`.
- Dovezi: `.ai-qa/delivery-2538551.json`, `.ai-qa/ui-audit-verification.json`,
  `.ai-qa/2538551-native-ci/`, `.ai-qa/2538551-runtime-ci.log`,
  `.ai-qa/2538551-native-ci.log`.
- Validarea fizică Android, microfonul și serviciile live rămân separate.

Jurnal: 22.10.2026 — livrat auditul de încadrare și comportament al butoanelor;
versiunile intermediare nu au fost livrate. Documentația curentă indică sursa,
testele și APK-ul verificat.


## Livrare exporturi 3D, GitHub și LAN — 23.10.2026, 08:02:45 CEST

- Sursă **13456afe2ca741c5b658ae5df76d1f98b8c8d5d7**, workflow
  [39908354563](https://github.com/JDscript1/godot-ai-android/actions/runs/39908354563):
  runtime, native-editor și Android trecute.
- Local: **340 aserțiuni**, 3 teste de livrare, **314 verificări × 5** randate și
  repetare desktop pentru export din Setări. CI: **335 aserțiuni**, **314 × 5**
  upstream, **324 × 5** native, 3 teste de livrare, 9 teste companion + build TS.
- APK **145.190.193 bytes**, `com.jdscript.godotai.debug`, numai ARM64; certificatul
  persistent și toate cele **26 de surse încorporate** verificate byte cu byte.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  la **08:02:45 CEST**, cu checksum alăturat. Verificat un singur APK al fork-ului;
  celelalte descărcări sunt păstrate. Pachetul nu a fost instalat automat.
- SHA-256: `6b1178452b49fff41309a75eefeb313ba237ab7584ae0e290144515f3f71b110`.
- Dovezi: `.ai-qa/delivery-13456af.json`, `.ai-qa/13456af-native-ci/`,
  `.ai-qa/13456af-runtime-ci.log`, `.ai-qa/13456af-native-ci.log`,
  `.ai-qa/new-integrations-unit-final.log`, `.ai-qa/new-integrations-final-render/`,
  `.ai-qa/new-integrations-nested/`.
- Această versiune istorică folosea OAuth; sursele curente folosesc doar token personal.
  Testele furnizorilor plătiți, rețeaua Wi-Fi între dispozitive și comportamentul
  fizic Android rămân de validat; testele simulate nu țin locul acestor probe.

Jurnal: 23.10.2026 — livrat `13456af`; exporturile, GitHub Sign in și căutarea LAN
sunt în APK. Actualizate documentația și lista priorităților. Rețeaua utilizatorului
nu a fost scanată, iar conturi/chei ale dezvoltatorului nu au fost împrumutate aplicației.

## Livrare rafinare vizuală — 23.10.2026, 11:40 CEST

- Sursă **`978a6d332edd1204baeb0f5fed0634345b16645d`**; [workflow-ul
  `39932275075`](https://github.com/JDscript1/godot-ai-android/actions/runs/39932275075)
  a încheiat cu succes joburile runtime, native-editor și android.
- Local: **340 aserțiuni runtime** și **319 verificări randate × 5 configurații**,
  fără eșecuri. CI nativ: **329 verificări × 5 configurații**, fără eșecuri;
  inspectate capturile compilate pentru chat, dock îngust și setări.
- APK **145.206.577 bytes**, `com.jdscript.godotai.debug`, numai ARM64;
  certificatul persistent și toate cele **26 de scripturi încorporate** au fost
  verificate. SHA-256:
  `2ed475190032e253ff8ce1fc7f6593774488e22ed80ed47cab0022f6bceae689`.
- Înlocuit atomic APK-ul vechi din
  `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, cu checksum
  alăturat. Verificat un singur installer al fork-ului în Download; celelalte
  descărcări au fost păstrate. Pachetul nu a fost instalat automat.
- Dovezi: `.ai-qa/delivery-978a6d3.json`, `.ai-qa/978a6d3-artifact/`,
  `.ai-qa/978a6d3-native-ci/`, `.ai-qa/premium-ui-final-all/`.
- Validarea pe un dispozitiv Android fizic, GitHub cu token personal real,
  furnizorii plătiți și rețeaua Wi-Fi reală rămân probe separate.
