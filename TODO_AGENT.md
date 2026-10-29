# TODO — agent și harness

Actualizat: **29.10.2026**. APK livrat în Download: **090b939**, cu AG-01–AG-55.
Ultima instalare verificată prin jurnalul dispozitivului: **47cc26e**, la 28.10.2026.
Bifele de acceptare nu se închid numai
din compilare: gesturile fizice, aprobările și probele reale de workflow se
confirmă separat. În noua rundă au trecut două scene și un mini-joc cu input
real prin unelte, inclusiv **46 cereri**. Continue a expus o eroare DeepSeek,
apoi a trecut cu adaptorul corectat temporar: **58 cereri**, același turn după
repornirea editorului. Layoutul îngust a fost reparat de agent în altă probă de
**59 cereri**. [Raport și următoarele 12 probe](docs/AI_AGENT_STABILITY_20261027.md).

## AG-56 — Ziva independent, preview în surse / APK separat ulterior

- [x] Secțiune Ziva separată, instalare opțională verificată, proces propriu și fereastră cu UI-ul original.
- [x] Configurație `ziva-preview`: `com.jdscript.godotai.ziva.debug`, nume Godot AI Ziva și livrare care păstrează instalatorul standard.
- [x] Verificări Kotlin, arhive, Godot și identitate Gradle; starea procesului nu este prezentată drept conectare la editor.
- [x] Punte nativă MCP separată de harness: scene/fișiere/panouri, autentificare locală, anulare, recuperare și refuzul modificărilor simultane.
- [x] `.mcp.json` temporar cu restaurarea configurației utilizatorului; copiere de Config fără token real pentru conectare manuală în Ziva.
- [x] Dialog WebView în aceeași activitate, pentru a evita pauza editorului produsă de o activitate separată; comportamentul Android rămâne de testat.
- [ ] Conectare reală Ziva → editorul Android prin protocol/SDK suportat.
- [ ] Confirmă discovery-ul din clientul Ziva sau fallback-ul Settings → MCP servers; proba standalone fără chat nu s-a conectat automat în 35 s.
- [ ] Probă WebView, autentificare și prompt → tool → rezultat pe dispozitiv.
- [ ] Compilare și livrare **Godot-AI-Ziva-arm64-debug.apk**, păstrând APK-ul actual conform cererii utilizatorului.

[Contract, limite și compilare separată](docs/AI_ZIVA.md). Dovezi de dezvoltare:
`.ai-qa/ziva-native/`, `.ai-qa/ziva-rendered/`, `.ai-qa/ziva-full-render-final/`.

## AG-55 — playtest și conversație, în APK 090b939

- [x] Refolosirea sesiunii și închiderea testelor agentului la final/Stop; protecția sesiunilor manuale, inclusiv aceeași scenă repornită.
- [x] Capturi automate noi deduplicate, cu limite de număr, spațiu și vârstă; pin și expirare vizibilă; fără copii permanente suplimentare.
- [x] Săgeată către ultimul mesaj și urmărire controlată de derularea utilizatorului.
- [x] Composer deasupra zonei tastaturii, cu derularea drafturilor lungi.
- [x] Verificări runtime, editor, randări și probe cu sesiuni reale; tastatură simulată.
- [x] APK recompilat, semnat, verificat și livrat; probe native chat/playtest 68/0.
- [ ] Acceptare pe Android cu tastatură reală și agent prin API.

[Comportament și retenție](docs/AI_CHAT_AND_PLAYTEST.md). Fișierele vechi și asseturile utilizatorului sunt păstrate.

## AG-54 — acces extins la panouri, în APK 090b939

- [x] Inventar de controale vizibile/ascunse/interne, cu handle și acoperire.
- [x] Citire paginată Tree/listă/meniuri/file/text/cod/tooltip/valori/grafuri.
- [x] Surse native pentru Output, Profiler, Visual Profiler, Monitors/istoric,
  VRAM, stack/variabile/fire/breakpoint-uri; API-uri publice Inspector/selecție,
  audio și animații/piste/chei.
- [x] Date necolectate, variabile încărcate parțial și generații vechi declarate
  explicit; compactarea păstrează cursorii fără a omite rânduri.
- [x] Probe cu controale reale upstream și verificare C++ de sintaxă/tipuri.
- [x] Execuție în editor recompilat: panouri 64/0 și regresie nativă 772/0 × 5.
- [ ] Acceptare fizică Android.

[Acoperire și limite](docs/AI_PANEL_ACCESS.md); dovezi în `.ai-qa/panels-20261028/`.
Panourile custom opace rămân marcate ca atare și necesită adaptor sau captură;
nu există o promisiune de decodare universală a datelor private din orice plugin.

## AG-53 — citirea nativă a Debuggerului, în APK 090b939

- [x] Înregistrare structurată a mesajelor primite de Debugger, inclusiv sursă,
  linie, stack, erori/avertismente și proveniență pe sesiune; panoul poate fi ascuns.
- [x] Lista rămâne accesibilă după oprirea jocului și se resetează cu o sesiune
  nouă sau cu lista UI; limitele și lipsa accesului sunt declarate explicit.
- [x] `godot_debugger`, integrare în `godot_diagnostics`, `godot_output` și
  `godot_run_state`; instrucțiuni pentru verificare după remediere.
- [x] Rezultatul gol al consolei și diagnosticul incomplet nu devin dovezi
  de rulare fără erori; observațiile reținute rămân dovezi de inspecție.
- [x] Recompilare și probă nativă: erori reale cu Debugger ascuns,
  joc oprit, reluare curată și proveniență distinctă, în cele cinci configurații.
- [ ] Acceptare fizică pe Android. Dovezi în raportul buildului 090b939.

## Corecții AG-34–AG-52 — incluse în APK 47cc26e

Build verificat: runtime 703/0, upstream 716/0 × 5 și nativ 732/0 × 5.
Cele 34 de surse încorporate, semnătura și baza Linux sunt verificate. Notele
«în surse» de mai jos descriu etapele de dinaintea recompilării. Toate aceste
corecții sunt acum în APK; acceptarea fizică și probele live rămân deschise.

| ID | Schimbare | Verificare și livrare |
| --- | --- | --- |
| AG-34 | Running Tools rămâne ascuns când nu rulează o unealtă; afișează numele apelului curent și dispare la rezultat, refuz, Stop, finalizare sau schimbarea conversației. | QA phone_compact 94/0 și regresie completă narrow 641/0, cu tranzițiile reale din evenimentele harness-ului și capturi inspectate. Dovezi în `.ai-qa/running-tools-20261028/`. Nu este încă în APK-ul 1c7c777 din Download; acceptarea fizică rămâne deschisă. |
| AG-35 | Cardul Plan activ urmărește ultimele mesaje și carduri, fără duplicare sau trunchiere după layout și fără a forța citirea la final; planurile încheiate rămân în istoric. | Navigare phone_compact 115/0, cu poziție, identitate, limita de jos și păstrarea derulării; captura finală inspectată. Dovezi în `.ai-qa/navigation-20261028/`; în surse, fără APK nou. |
| AG-36 | Nume specifice pentru operații: generator de imagini sau 3D determinat din profil/job, inclusiv la așteptare; identificatorul tehnic rămâne în tooltip și Jurnal. | Inclus în proba de 115/0, cu ambele tipuri și job necunoscut; în surse, fără consum de credite. |
| AG-37 | Zoom 3D prin magnify nativ Android, pan, butoane Zoom + / − și taste; limite de distanță păstrate. | Preview phone_landscape 79/0 și regresie narrow 649/0, prin fereastra viewer-ului, cu cameră și geometrie reale; verificarea fizică Android rămâne deschisă. |
| AG-38 | Glisare verticală peste text, cod, media și margini; mouse emulat interceptat înaintea selecției, pan nativ, mențiuni orizontale, tap-uri și meniul apăsării lungi pe carduri păstrate. | Navigare phone_compact 115/0 prin viewport cu secvența mouse emulat + touch; meniul nu blochează gestul următor. Acceptarea pe APK instalat rămâne deschisă. |
| AG-39 | Continuare automată la limita de ieșire, până la două reluări; Responses și adaptorul de abonament traduc `response.incomplete/max_output_tokens` în `length`, păstrând textul, consumul și elementele native. Apelurile de funcție incomplete nu se execută; alte motive rămân erori. | Runtime 600/0, inclusiv adaptorul real cu evenimente simulate pentru ambele tipuri, continuare reușită, lipsa deltelor, apel trunchiat și motive de eșec. Dovezi în `.ai-qa/fixes-20261028/`; modelul real și APK-ul nou rămân deschise. |
| AG-40 | `godot_symbols`: declarații top-level GDScript cu cale, linie, semnătură, filtre și cache după hash. Stringurile și comentariile sunt mascate, inclusiv ambele stiluri triple, delimitatori escapați și stringuri din corpul funcțiilor. | Runtime 600/0: scanare multi-fișier, filtre, cache și trei regresii lexicale; proba inițială mai întoarce numai `help` și `real`, fără declarațiile false. În surse. |
| AG-41 | Review pe hunk-uri pentru fișiere existente. Execuția folosește o copie a argumentelor; istoricul și identitatea apelului rămân originale. Rezultatul raportează selecția și hash-uri separate; replay-ul nu repetă scrierea. Hash-ul de versiune, recuperarea și jurnalul rămân active. | Runtime 600/0 cu replay, deduplicare și istoric restaurat; editor narrow complet 662/0, cu scriere și patch reale aprobate parțial. Detaliile aprobării sunt păstrate și în rezumate. În surse, fără APK nou sau acceptare tactilă. |
| AG-42 | Verdict automat de sintaxă după `godot_write_file`/`godot_apply_patch` pe `.gd`, prin puntea nativă: `valid`, până la 20 de erori cu linie, coloană și mesaj, plus `truncated`; preview-ul patch-ului validează textul propus. Fără punte, câmpul `syntax` lipsește. | Runtime 569/0 cu punte simulată; fixture stock verifică ramura fără verdict inventat; parserul real rulează în editorul recompilat. APK nou deschis. |
| AG-43 | `godot_search_code` cu `context` 0–4, linii vecine fără repetiție între potriviri apropiate, limite 24.000 de caractere pe rezultat și sărirea legăturilor simbolice. | Runtime 569/0 pe fișiere temporare reale: context, margini de fișier, suprapunere suprimată și forma compactă fără context. |
| AG-44 | Maximum 48.000 de caractere pentru rezultatele tuturor apelurilor unui pas; se rezervă 512 caractere pentru fiecare apel rămas, fără minim suplimentar după epuizare. JSON valid, contract de succes/eroare, identitate și verdict de sintaxă compact; detaliile aprobării pot deveni numere de hunk-uri. | Runtime 600/0: 64 de rezultate mari, cu succes/eșec, escape-uri, aprobare și diagnostice lungi. Proba auditului: 78.291 → 46.587 caractere pentru 64 de rezultate, sub plafon. Dovezi în `.ai-qa/fixes-20261028/`. |

| AG-45 | Hartă persistentă a proiectului, cu scanare pe scop, dependențe literale/inverse, simboluri, hash-uri, UID-uri rezolvate dinamic și acoperire explicită. Lexer cu căutări native pe fragmente. | În surse; verificări pentru cache, invalidare, anulare, scopuri înguste și rezolvarea UID-ului după import. Fără execuția scripturilor proiectului. |
| AG-46 | Diagnostic unificat: parser nativ, referințe lipsă, observații din editor și joc, shader/avertismente, gruparea repetițiilor și invalidarea surselor învechite. | Puntea C++ trece verificarea de sintaxă/tipuri; collectorul și cache-ul sunt probate automat. Captura nativă cere editor recompilat; lipsa parserului/runtime-ului este raportată explicit. |
| AG-47 | Recuperare adaptivă după conflicte, referințe învechite, erori de tip/cale și joburi neconfirmate; schimbarea strategiei după citiri identice fără progres. | Runtime probează indicațiile, refuzul retry-ului automat pentru scrieri/generări și protecția refuzurilor. Fără plafon global de pași. |
| AG-48 | Criterii în `task_update.criteria`, dovezi emise de executor și `task_check`: condiții măsurate, scop, revizie și hash-uri. Finalizarea nu poate ocoli verificarea printr-un răspuns fără apeluri. | Probe pentru fișier salvat, Undo/Redo, editări externe, draft/preview neaplicat, dovezi inventate/învechite și condiție de gameplay nereușită. Criteriile modelului încă trebuie evaluate pe sarcini reale. |
| AG-49 | Pregătire de loturi UTF-8 dependente: hash-uri/absență explicită, copii private, diff-uri, limite per operație fără limită nouă de pași. | În surse; probele și limitele sunt în [AI_CHANGE_SETS.md](docs/AI_CHANGE_SETS.md). |
| AG-50 | Aplicare cu verificarea tuturor membrilor și rollback compensatoriu la Stop/eroare; editările ulterioare sunt conflicte păstrate. | Teste cu fișiere reale temporare și eroare de I/O; tranzacția nu este atomică global. |
| AG-51 | Manifest persistent, status după întrerupere și rollback fără reaplicare automată; integrare în jurnal și Restore turn. | Checkpoint de crash simulat cu un coordonator nou; crash Android real rămâne de probat. |
| AG-52 | Aprobări cu diff-urile lotului, Plan doar pregătire/citire, protejarea bufferelor nesalvate și invalidarea dovezilor la scrieri parțiale. | QA în editor; puntea nativă pentru starea scenei are verificare C++, necesită editor recompilat. |

Verificat AG-49–AG-52: **703/0 runtime**, **716/0 editor narrow**,
**60/0 changesets phone_compact**, C++ fără erori de sintaxă/tipuri și 34 de
scripturi încorporate identice cu sursele. Dovezi: `.ai-qa/changesets-20261028/`.
AG-45–AG-48 au avut anterior 654/0, 697/0 și 52/0. Aceste schimbări sunt livrate acum în APK 47cc26e.

[Contracte și limite AG-45–AG-48](docs/AI_HARNESS_INTELLIGENCE.md). Dovezi:
`.ai-qa/intelligence-20261028/`. Prima etapă este în surse; APK-ul livrat rămâne
`1c7c777`. Modificările coordonate între fișiere, verificatorul independent,
alegerea modelelor și evaluarea cu API-uri reale rămân etapele următoare.

## Stabilizare după probele reale — inclusă în APK 1c7c777

Toate schimbările de mai jos sunt compilate și livrate. CI: **537 aserțiuni
runtime**, **641 × 5** verificări upstream și **654 × 5** native, fără eșecuri.
Puntea C++ este construită pentru editorul nativ și Android. Semnătura, cele
30 de scripturi și baza Linux au fost verificate înaintea înlocuirii.
[Dovadă de compilare](https://github.com/JDscript1/godot-ai-android/actions/runs/40617637786),
dovadă locală de livrare: `.ai-qa/delivery-1c7c777.json`.
Acceptările fizice și probele cu furnizori reali rămân deschise unde sunt indicate.

| ID | Constatare și schimbare | Acceptare |
| --- | --- | --- |
| AG-21 | Rezultatele mari pierdeau `ok` și ID-urile la trunchiere; rezumatul păstrează contractul și identitatea artefactelor, cu limita măsurată după serializarea JSON. | Regresie reprodusă, fixture verde; inclus în APK 1c7c777, workflow-ul real pe noua versiune rămâne de confirmat. |
| AG-22 | Inspectarea claselor încărca prea mult context și filtrul `shader\|color` nu avea alternative; paginare stabilă și filtru OR literal. | Acoperirea tuturor paginilor verificată; Node 48.786→7.342 caractere în pagina implicită. Cost live înainte/după încă nemăsurat. |
| AG-23 | Continue după Stop produce HTTP 400 DeepSeek; notificarea locală era trimisă ca răspuns al modelului. Proveniență explicită, context de aplicație separat, metadata confirmată păstrată inclusiv la ramificare. | Eșec live reprodus; fixture HTTP roșu→verde; reluare DeepSeek real trecută cu adaptor temporar. Livrat în APK 1c7c777; acceptarea live pe noua versiune rămâne deschisă. |
| AG-24 | Driverul seta YOLO și nu actualiza starea finală pentru Continue din UI. Păstrează permisiunea, actualizează snapshot-ul și colectează JSONL complet. Persistă selecția restaurată la finalul probelor viitoare. | Confirmat pe telefon: permisiune păstrată, starea finală actualizată după Resume și JSONL complet colectat. Ultima persistență a selectorului are verificare de parser; revenirea după restart mai cere o probă. Nu extrage vault-ul sau cheile. |
| AG-25 | Planul vizibil rămâne pe construcție în timpul verificării, timp de mai multe minute. Instrucțiuni explicite pentru schimbarea pasului și a fazei la încheierea etapei. | Ghidaj în surse; comportamentul implicit pe APK nou încă de evaluat. Nu este o sincronizare automată garantată. |
| AG-26 | Răspunsuri finale prea lungi, cu proprietăți și coordonate inutile. Implicit trei puncte concise, aproximativ 120 cuvinte, cu limitele materiale păstrate. | Instrucțiuni în surse; respectarea lor în noul APK rămâne de confirmat. |
| AG-27 | Tap-uri cunoscute și inspecții independente consumă multe runde; sute de mesaje PASS pot ascunde eșecurile în coada Output. Ghidaj pentru gruparea apelurilor și rapoarte compacte cu număr de verificări/eșecuri. | Fără plafon nou de pași; eficiența înainte/după nu este încă măsurată în condiții identice. |
| AG-28 | Plan interactiv: întrebări cu opțiuni simple/multiple și text propriu în chat; trimitere explicită, ciorne salvate, răspunsuri persistente și reluarea aceleiași sarcini după Stop/întrerupere. | Livrat în APK 1c7c777; selecția și gesturile simulate, refuzul scrierilor, persistența și recuperarea probate în editor. [Raport](docs/AI_INTERACTIVE_PLAN.md). Gesturile fizice și alegerea întrebărilor cu un model real rămân deschise. |
| AG-29 | Playtest măsurabil: `playtest_act` cu intrări ținute, probe înainte/după, `until` și servo; `playtest_watch` pentru expresii și semnale; consolă de dovezi cu verdict în chat. | Livrat în APK 1c7c777; runtime 537/0 și C++ compilat pentru editorul nativ și Android. Consola și playtest-ul condus de model nu sunt încă probate pe noul APK instalat. [Harness](docs/AI_HARNESS.md). |
| AG-30 | Aprobări de sesiune cu **Permite mereu** (revocabile din Setări → General, niciodată peste refuzul Plan); predarea planului prin **Implementează planul**/**Ajustează** pe cardul propunerii; corecția celor șase probleme din auditul independent AG-29: compilare C++, probe `const_calls_only`, Stop anulează actul, garda rămâne în procesare, expirarea nu mai raportează `until_met=true`, refuzul repetării după măsurători. | Livrat în APK 1c7c777; runtime 537/0, todo nativ 90/0, punte compilată și probă headless pe regula de repetare (copil și părinte). Aprobările fizice și proba playtest pe dispozitiv rămân deschise. |
| AG-31 | Compactare automată a contextului după fluxul Ziva, rescris independent: prag `limită - rezervă` (16384 implicit, redus la ferestre mici; sub 8192 tokeni compactarea automată nu pornește), păstrare ~20000 tokeni recenți, tăiere pe mesaj de utilizator fără a rezuma ultima cerere, rezumat incremental cu cel anterior, detectarea overflow, persistență, stare anulabilă și comutator în Setări → General. | Livrat în APK 1c7c777, cu regresiile suplimentare AG-33. Tura eșuată după overflow nu este reluată automat. Proba pe dispozitiv și consumul real de tokeni rămân deschise. |
| AG-32 | Experiența de chat după inventarul Ziva, doar elementele utile: Undo/Regenerează pe ultimul răspuns încheiat (restaurare fișiere prin jurnal, prompt și atașamente înapoi în composer), coadă vizibilă cu restore/remove/reia, metrici pe tur (durată fără aprobări, tokeni măsurați sau estimați, cost din tarife), blocuri Gândire pliate, căutare în conversație și avertisment după 15 s fără ieșire. | Livrat în APK 1c7c777; chat phone_compact 68/0 și editor nativ complet 654/0 × 5. Regenerează a fost verificat doar pe calea de gardă, nu cu o cerere live; Undo refuză scena pierdută din sesiune. Acceptarea fizică și Regenerează live rămân deschise. |
| AG-33 | Corecțiile auditului: rezumate validate și salvate înaintea schimbării contextului; loturi adaptate modelului, fără omiterea mesajelor lungi sau a rezumatului anterior; rezervă de ieșire și reducerea lotului la overflow; recuperarea rezumatelor vechi goale; coadă derulabilă cu înălțime limitată. | Livrat în APK 1c7c777; runtime 537/0, compact narrow 82/0, suita completă upstream 641/0 × 5 și nativă 654/0 × 5. Regresii pentru răspuns gol/incomplet, Stop, salvare eșuată, eșec intermediar, istoric lung și 20 de mesaje în coadă. Capturi inspectate; 30 de surse comparate exact în APK. Proba tactilă rămâne deschisă. |

Sursele trec **537 aserțiuni runtime**, **641 verificări editor upstream × 5** și
**67 × 5** verificări dedicate Planului interactiv, fără
eșecuri; cardurile media, întrebările și starea întreruptă inspectate în randări.
AG-30 adaugă QA narrow **84/0** (approval) și **88/0** (todo), verificarea de
sintaxă C++ și o probă headless pentru regula de repetare. AG-31 adaugă scenariul
QA **compact**, narrow **54/0**: comutator, prag și rezervă, tăiere pe mesaj de
utilizator, excluderea ultimei cereri, persistență/restaurare, refuzul compactării
fără interval nou, eșec fără retry până la următoarea cerere și ferestre mici
ignorate. AG-32 adaugă scenariul QA **chat**, narrow **62/0**: gating pe ultimul
tur, restaurarea unui fișier scris de agent, trunchierea istoricului, coada
vizibilă, metrici măsurate și estimate, blocuri Gândire, căutare cu wraparound și
avertismentul de stagnare. Playtest-ul, compactarea și chatul sunt incluse în
APK-ul 1c7c777. AG-33 adaugă validarea și salvarea tranzacțională a rezumatelor, loturi
adaptate modelului și coada cu înălțime limitată: compact narrow **82/0**, suita
completă narrow **638/0**, chat phone_compact **68/0**. Dovezi în
`.ai-qa/fix-review-20261028/`. Compilarea și livrarea AG-21–AG-33 sunt documentate
în `.ai-qa/recompile-20261028/`. AG-39–AG-41 adaugă continuarea automată,
`godot_symbols` și review-ul pe hunk-uri: runtime **558/0**, approval narrow
**92/0 × 5**, chat narrow **68/0**, todo narrow **115/0**, suita completă narrow
**657/0** și `--check-only` pe `diff.gd`, `editor_tools.gd`, `harness.gd` și
`panel.gd`. Dovezi în `.ai-qa/continuare-simboluri-hunks-20261028/`. AG-42–AG-44
adaugă verdictul de sintaxă după scriere, contextul căutării și bugetul pe rundă:
runtime **569/0** și suita completă narrow **658/0**, dovezi în
`.ai-qa/harness-20261028/`. Sunt în surse; APK-ul 1c7c777 nu le include.
Pragurile ST-01–ST-12 din raport
păstrează distincte stabilitatea sesiunii, gameplay-ul, generarea și producția 3D.

## Aplicare în APK 7576033 — 27.10.2026

Utilizatorul a cerut implementarea TODO-ului și un APK nou. Lista de mai jos
descrie codul rezultat; criteriile fizice încă neexercitate nu sunt bifate automat.

| ID | Implementare |
| --- | --- |
| AG-01/19 | Salvare în directoare noi, erori reale, calea scenei și căi persistente în context; aceeași structură la continuare. |
| AG-02 | Toleranță numerică la verificarea proprietăților, cu egalitate exactă pentru valori discrete și referințe. |
| AG-03 | Livrare a eliminării plafonului de cereri, inclusiv copii/companion, și a dialogului de aprobare încadrat. |
| AG-04 | La întrerupere, raport persistent derivat din schimbări, verificări și pași rămași; fără finalizare falsă. |
| AG-05 | Contract explicit pentru handle-ul Window; captură/input/stare de joc disponibile și părintelui. |
| AG-06 | `godot_run_state`: scenă cerută, scenă rulată, Output după cerere, UID principal nerezolvat; fără rescrierea configurației. |
| AG-07/12 | Grupuri utile de scheme și restaurarea lor din conversație/Resume, numai din catalogul permis. |
| AG-08 | Schimbările observate după Linux sunt separate de recuperarea nativă; raport cu limitele observației și fără restaurare garantată. |
| AG-09 | JSONL complet, fișiere succesive de 8 MiB, export automat opțional într-un director ales; build/model/effort/mod/YOLO și decizii de autorizare. Imaginile, binarele și cheile sunt excluse. Consola ascunsă nu se reconstruiește la fiecare eveniment. |
| AG-10 | Decodează/validează setările tipizate, verifică valoarea aplicată; pluginurile se activează prin unealta dedicată. |
| AG-11 | HTTP 500 contradictoriu se recuperează numai pentru același job finalizat, cu artefact valid; fără altă trimitere plătită. |
| AG-13 | Running Tools: etichetă fără dropdown, numele real al uneltei și resetare la final/Stop. Istoricul operațiilor rămâne în Jurnal. |
| AG-14 | Carduri media compacte și persistente; deschiderea de către agent este blocată fără cerere explicită. Observarea în background rămâne separată. |
| AG-15 | Card de plan cu lățime adaptată și plafon vizual de 440 unități editor, verificat și în dockuri. |
| AG-16 | Gesturile tactile peste text/cod derulează chatul; apăsarea lungă selectează intenționat și oferă copiere. Mouse-ul și gesturile cardurilor sunt păstrate. |
| AG-17 | Finalizarea unui plan executat cere verificări după ultima modificare și un raport al lor. Tipul `interaction` cere input și observație/stare runtime. Alegerea corectă a tipului de probă rămâne responsabilitatea agentului și trebuie evaluată cu modele reale. |
| AG-18 | Schema declară limita reală de text pentru fiecare pas, iar erorile indică câmpul, lungimea și limita. Nu se adaugă un plafon de execuție. |
| AG-20 | Punte nativă pentru scenă nouă într-un tab separat; rădăcina activă este verificată înainte de a raporta succes. |

Probe locale inițiale: **495 aserțiuni runtime**, inclusiv recuperare Runware
prin HTTP real către fixture și descărcarea artefactului fără trimitere duplicată;
**84 verificări editor dedicate** în configurație phone landscape. Randările
chatului și dockurilor au fost inspectate. Regresia completă locală are
**514 verificări / 0 eșecuri**. Aceste probe nu sunt utilizare
fizică Android sau generare plătită live. CI: **527 verificări × 5** în editorul nativ, **86** dedicate în nativ și
**495** aserțiuni runtime, toate fără eșecuri. Installer verificat, aceeași
semnătură persistentă, toate cele **30** surse runtime și Linux încorporat.
Dovadă de livrare: `.ai-qa/delivery-7576033.json`.

Rămân de confirmat pe noul APK: gesturi fizice și aprobări/refuz, sarcini reale
peste plafonul vechi, aceeași probă înainte/după pentru costul descoperirii și
workflow-ul Runware real până la mesh. Pilotul Pi nu face parte din această
livrare; motorul rămâne harness-ul nativ Godot.

## Cerință principală — continuă până la rezultatul cerut

Agentul nu are plafon total de pași, cereri sau runde, inclusiv la subagenți și
reluări. Continuă implementarea, verificarea și corectarea până livrează
rezultatul cerut; un răspuns intermediar nu încheie un plan încă nefinalizat.
Finalizarea se bazează pe criteriile cerinței și pe verificări efective.
Stop, permisiunile și blocajele reale rămân respectate. Un blocaj se explică și
se păstrează pentru reluare, fără a declara sarcina terminată. Timeoutul unei
operații și detectarea unei bucle fără progres nu înlocuiesc plafonul eliminat
cu altă limită totală de pași.

**Stare:** eliminarea plafonului este inclusă și în APK-ul curent **1c7c777**.
Confirmare live: mini-joc terminat după **46 cereri** în noua rundă. Reluarea
după Stop are un blocaj separat, AG-23; nu este o nouă limită de pași.

## Suita extinsă — 50 de use case-uri

[Catalogul de teste](docs/AI_AGENT_USE_CASES.md) conține cerințe gata de trimis,
precondiții, moduri și criterii de verificare. Include cele două probe existente
și **48 de scenarii suplimentare**: control/permisiuni, cod și fișiere, scene,
media, integrări, generare, sarcini complete, UI și conexiuni. UC-03 a trecut
între timp. Probele următoare sunt trimise acum direct agentului nativ, într-un
proiect izolat; [raportul rundei](docs/AI_AGENT_DEVICE_BATCH_20261027.md) separă
funcționalitatea verificată, opririle la limită și variantele asistate.

Pentru permisiuni, ordinea rămâne **UC-04 Refuz → UC-05 Aprobare**; sunt probe
distincte de runda automată cu YOLO deja activ.
UC-04 necesită refacerea separată a stării inițiale înaintea repetării; jurnalul și
hash-urile a opt fișiere sunt salvate în `.ai-qa/agent-suite-20261026T214251Z/`.
Utilizatorul a trimis primul fișier și agentul a executat cerința UC-04. Precondițiile și
costurile de generare se verifică înaintea fiecărui caz, nu pentru tot catalogul.

Copie pentru citire pe dispozitiv:
`Documents/Godot-AI-Agent-Tests/SUITA_AGENT_50.md`.

Predare completă la 27.10.2026: [toate cele 47 de probe rămase](docs/AI_AGENT_REMAINING_TESTS.md),
cu mesaje de copiat, intervenții separate și criterii. Copia `TESTE_RAMASE_47.md`
și șase fișiere TXT mici sunt în același folder Documents; includ și subproba
fizică de scroll AG-16. Predarea inițială a fost numai pregătire/documentare;
execuțiile ulterioare sunt în raportul separat, fără închiderea prematură a TODO-urilor.

## Test 01 — cub verde, proiect Vampyr

**Scena a reușit; workflow-ul a rămas neterminat.** Există
`res://agent_tests/test_01.tscn`, cu Node3D, BoxMesh verde, cameră activă și
DirectionalLight3D. Utilizatorul confirmă afișarea preview-ului și precizează că
l-a închis manual înaintea capturii agentului. O randare independentă a copiei
nemodificate confirmă cubul vizibil. Captura editorului după închiderea manuală
și starea `running=false` nu sunt contabilizate ca eșecuri ale agentului.

- **137,3 secunde**, **30 cereri**, **39 operații executate** și **4 descoperiri**.
- Sfârșit: `limited / step_limit`; plan în `verifying`, fără răspuns final.
- `project.godot` este identic cu citirea inițială a agentului. UID-ul principal
  nerezolvat exista în configurație înaintea testului; declanșarea mesajului
  după oprire necesită analiză separată.
- Citite integral cele **149 de evenimente ale turnului**; niciun rezultat din
  acest turn nu atinge limita de trunchiere a jurnalului. Jurnalul proiectului
  colectat conține 158 de înregistrări, inclusiv evenimentele anterioare.
- Dovezi locale: `.ai-qa/manual-agent-test-result-20261026T200312Z/`, inclusiv
  `report.json`, `REPORT.md`, jurnal, conversație, checkpoint, diff, captura
  editorului, copia scenei și `control-render/scene.png`.

## Test 02 — depanare GDScript, trecut

**Cerința a fost îndeplinită în APK.** Agentul a reparat exact două linii din
`res://agent_tests/test_02/counter.gd`: colonul lipsă și acumularea prin `+=`.
Parserul nativ a confirmat eroarea inițială și apoi `valid=true`. Agentul a
rulat scena test_02, a citit `TEST_02_TOTAL=20`, a oprit rularea și a confirmat
`running=false`. Raportul final de trei rânduri corespunde rezultatelor.

- **48,8 secunde**, **17 cereri**, **13 operații executate**, **3 descoperiri**
  și **un apel blocat înainte de execuție**: `godot_apply_patch / tool_not_loaded`.
  Agentul a încărcat schema și a continuat corect; constatarea actualizează AG-12.
- KEEP_MARKER, semnătura, KEEP.txt, scena test_02, configurația, icon.svg și
  scena test_01 sunt identice cu snapshot-urile inițiale.
- **6/6 cazuri independente** au trecut pe copia exactă a scriptului reparat,
  inclusiv array gol și valori negative. Sunt verificări ulterioare ale
  evaluatorului în Godot Linux, distincte de proba agentului Android.
- Proba a avut loc în aceeași conversație ca testul 01, cu istoric existent;
  nu este un benchmark cu context proaspăt. Citite cele 69 de evenimente ale
  turnului, fără trunchieri. Nu s-au instalat utilitare sau generat asseturi cloud.
- Pregătire: `.ai-qa/manual-agent-test-02-20261026T205531Z/`; rezultat și dovezi:
  `.ai-qa/manual-agent-test-02-result-20261026T212532Z/`.

## UC-03 — plan fără modificări, trecut

**6 cereri, 25,9 s.** Agentul a inspectat proiectul și a publicat numai planul,
fără scriere, rulare sau generare. Prima publicare a fost respinsă pentru un
pas de 604 caractere; limita internă de 600 nu era declarată în schema tool-ului.
A scurtat pașii și a recuperat. Comportamentul cerut este verificat; nu s-a
efectuat o probă forțată de ocolire a modului UI Plan.

După mesajul separat **„continuă”**, utilizatorul a autorizat implementarea.
Agentul a creat șase fișiere în `res://mini_coins/`, a validat trei scripturi,
a rulat și a oprit scena: **17 cereri, 109,7 s**, Output `CONNECTED_COINS=3`.
Cele opt fișiere protejate sunt identice. Agentul nu a testat colectarea și a
declarat această limită în răspuns, deși planul și harness-ul erau `completed`.

Verificarea ulterioară a evaluatorului, pe copia exactă în Godot Linux, a trecut:
deplasare prin input, fără teleportare, colectare 0/3→1/3→2/3→3/3 și zero monede
rămase. Nu este o verificare efectuată de agentul Android. Dovezi:
`.ai-qa/manual-agent-uc03-result-20261026T215150Z/`. Constatările actualizează
AG-17/18; derularea tactilă raportată separat de utilizator este AG-16.

## UC-04 — încercat, refuzul nu este demonstrat

Reconectare ADB reușită la 27.10.2026. Primul fișier UC-04–UC-09 a fost trimis
integral; agentul a executat numai UC-04: **7 cereri, 26,37 s**, șase tool-uri
executate, o descoperire și un apel `godot_write_file / tool_not_loaded`, recuperat.
A citit originalul, a scris `APPROVED_TEST_04`, apoi a recitit ținta și KEEP.txt.
Numai fișierul de probă diferă dintre cele opt urmărite; KEEP este intact.

Nu există refuz în jurnal, iar YOLO și decizia efectivă de autorizare nu sunt
confirmate de dovezile colectate. Agentul a declarat explicit că testul nu poate
trece în aceste condiții. Nu se consemnează o ocolire de permisiune sau un UC-05
trecut. UC-04 se repetă după pregătirea originalului, cu Default, YOLO oprit și
Refuză exercitat efectiv. UC-05–UC-09 rămân neexecutate. Actualizate AG-09/12.
Dovezi: `.ai-qa/manual-agent-part01-result-20261027T043339Z/`.
Evaluatorul a citit datele, fără resetarea probei sau cereri noi către agent.

## Corecție în surse — salvare și organizare, 27.10.2026

Raportul utilizatorului despre foldere și scene pierdute a dus la reproducerea
unui defect concret: `godot_save_scene` raporta succes cu `saved=false` dacă
directorul părinte nu exista. Corecția creează părinții necesari și întoarce eroare
la eșecul verificării salvării. `godot_project` expune scena activă și ultimele
căi existente din istoricul persistent, inclusiv într-o conversație nouă.
Instrucțiunile cer reutilizarea structurii și a căilor confirmate; o scenă
negăsită nu justifică un alt folder sau o copie de înlocuire.

**50 verificări în editor / 0 eșecuri**, după reproducere cu **8 eșecuri / 45
verificări**, plus **277 aserțiuni runtime / 0 eșecuri**. Dovezi:
`.ai-qa/scene-path-fix-20261027/green3/` și `runtime/`. Aceste probe locale nu
demonstrează livrarea în Android. Nu s-au mutat sau șters proiectele utilizatorului.

## P0 — corectitudinea operațiilor și livrare

- [ ] **AG-01 · Salvează scena în directoare noi.** Creează părinții prin
  operația nativă, cu verificările de cale și recuperare. `saved=false` trebuie
  să producă `ok=false`, cu motiv concret. În probă, două salvări au raportat
  succes fără fișier, apoi agentul a folosit o copie provizorie și Linux.
  **Acceptare:** destinație nouă și existentă, eroare de scriere raportată corect,
  conținut recitit; fără necesitatea unui workaround în shell.
  **În surse:** corecție testată la 27.10.2026; directoare imbricate, spații,
  salvare repetată, reîncărcare, părinte care este fișier și cale invalidă.
  Livrat în APK-ul 7576033; repetarea fizică rămâne deschisă.
- [ ] **AG-02 · Compară numeric proprietățile cu toleranță.** Rotația cerută
  `(-50,-35,0)` a devenit `(-49.999996,-34.999996,0)` și a fost declarată greșit
  neaplicată. Toleranță potrivită tipului pentru numere/vectori/transformări;
  referințele și valorile discrete trebuie verificate în continuare exact.
  **Acceptare:** rotația din probă trece; o valoare realmente diferită e respinsă.
- [ ] **AG-03 · Fără plafon de pași, până la livrarea rezultatului.** Livrează
  eliminarea plafonului (`309c4f6`) și aprobările accesibile (`226c519`), deja
  incluse în APK-ul 7576033, înlocuind installerul c418f97 din Download. Continuarea
  trebuie să urmărească rezultatul verificat, inclusiv când rămân pași după un
  răspuns intermediar. **Acceptare:** APK nou verificat, depășirea limitelor vechi
  fără alt plafon ascuns, finalizarea cerinței și verificărilor, Stop și
  aprobare/refuz funcționale pe dispozitiv. Compilarea/livrarea a fost autorizată și încheiată la 27.10.2026;
  proba fizică rămâne distinctă.

## P1 — verificare, continuitate și eficiență

- [ ] **AG-19 · O singură structură de proiect, căi reutilizate.** Inspectează
  structura existentă, păstrează directorul convenit și calea exactă confirmată
  la salvare. La continuare sau eroare de deschidere, caută scena existentă;
  nu crea alt folder la rădăcină, copii ori mutări ca substitut. Subfolderele
  numite ale generărilor rămân în destinația configurată. **În surse:** regula
  și contextul cu `scene_path`/`recent_paths` sunt implementate; testul confirmă
  persistența și contextul unei conversații noi. **Acceptare rămasă:**
  continuare fizică fără directoare alternative și deschidere/rulare la aceeași
  cale. În suita curentă, `test_XX` sunt directoare cerute explicit de probe,
  toate sub `agent_tests`; nu sunt dovada unor foldere arbitrare create la rădăcină.
- [ ] **AG-20 · Creare de scenă cu confirmarea rădăcinii active.** În UC-19,
  `godot_create_scene(Control)` a întors succes și un handle nou, dar scena activă
  a rămas `VerifyScores`. Nodurile următoare au fost adăugate acolo; agentul a
  observat și le-a eliminat înaintea salvării. `EditorInterface.add_root_node`
  refuză o scenă care are deja rădăcină, iar unealta nu verifică efectul.
  **Acceptare:** scenă nouă într-un tab separat, păstrarea scenei anterioare,
  rădăcină activă egală cu handle-ul returnat; eșec explicit dacă nu poate crea.
  Defect confirmat în APK-ul vechi; corecția pentru noul tab este implementată separat de AG-19 și a trecut verificarea editorului nativ compilat.
- [ ] **AG-04 · Încheiere clară la întrerupere.** La Stop, limită sau blocaj,
  afișează un raport scurt derivat din operații: rezultat salvat, verificări
  efectuate, pași rămași și posibilitatea de reluare. În test nu există răspuns
  final, deși scena era deja creată. **Acceptare:** progresul verificat rămâne
  vizibil fără declararea întregului task ca finalizat.
- [ ] **AG-05 · Capturi și intervenții manuale.** Pentru `target=window`, cere
  un handle Window descoperit; descrierea/schema să reflecte cerința. Separă
  captura editorului de observarea jocului și expune ruta de captură a jocului
  când este disponibilă. După închiderea manuală, reobservă starea și raportează
  exact limita verificării. **Acceptare:** preview deschis/închis, handle lipsă
  și revenire în editor; închiderea de către utilizator nu devine eșec inventat.
- [ ] **AG-06 · Diagnostic pentru UID și rulare.** Corelează pornirea/oprirea
  cu Output-ul și diferențiază o eroare preexistentă de una introdusă de task.
  **Acceptare:** rulează scena explicită chiar dacă scena principală are un UID
  invalid; explică diagnosticul fără a modifica scena principală în această probă.
- [ ] **AG-07 · Mai puține cereri pentru descoperire.** Patru căutări au ocupat
  patru cereri înaintea construirii scenei. Îmbunătățește gruparea și indicațiile
  pentru uneltele uzuale; măsoară aceeași sarcină înainte/după, fără un plafon nou
  de pași. **Acceptare:** rezultat și permisiuni corecte, traseu mai scurt și
  consum comparabil documentat; fără promisiuni de accelerare dintr-o singură probă.
- [ ] **AG-08 · Fișiere temporare, diff și recuperare.** Preferă uneltele native
  pentru operații deja acoperite. În probă s-au folosit `mkdir` și `rm` prin Linux
  pentru o scenă temporară. **Acceptare:** efectele shell asupra proiectului sunt
  urmărite separat; o copie ștearsă manual nu este prezentată ca recuperare
  executată de instrumentul de restaurare.
- [ ] **AG-09 · Jurnal detaliat accesibil direct.** Flux JSONL separat de consola
  compactă, cu fișiere succesive și export automat într-un director ales pentru
  diagnostic. Păstrează rezultatele text complete și maschează cheile; nu exporta
  seiful sau datele binare ca dump. Înregistrează build, model, reasoning și modul
  efectiv al turnului, YOLO și decizia de autorizare pentru fiecare operație
  protejată (aprobare, refuz sau permisiune deja acordată). În UC-04 lipsa acestor
  date împiedică verdictul privind configurația permisiunilor. **Acceptare:**
  citire din Termux fără copiere în chat, decizii de autorizare verificabile,
  sesiuni peste 1.000 de evenimente și rezultate peste 12.000 de caractere.
- [ ] **AG-12 · Descoperire la mesaje noi și Resume.** Reîncarcă schemele
  necesare din catalogul permis, păstrând regulile Plan/permisiuni. În testul
  02, un mesaj nou în aceeași conversație a produs `godot_apply_patch /
  tool_not_loaded`, apoi încărcare și recuperare. UC-04 a repetat problema cu
  `godot_write_file` și a recuperat după `tool_describe`. **Acceptare:** continuare și
  Resume fără apeluri către scheme indisponibile sau expunerea tool-urilor excluse.
- [ ] **AG-17 · Verifică mecanica înainte de finalizarea planului.** Conectarea
  a trei monede nu dovedește colectarea și actualizarea contorului. În continuarea
  UC-03, agentul a marcat planul `completed`, dar a declarat colectarea neverificată.
  Verifică disponibilitatea rutei Playtest/input înainte de a afirma că inputul
  necesită intervenție manuală; existența ei în surse nu dovedește funcționarea
  pe dispozitiv. **Acceptare:** criteriile sunt probate efectiv sau rămân marcate
  neconfirmate/blocate; nu se închide un pas de verificare numai după pornire.
- [ ] **AG-18 · Publică limitele de format ale planului în schema tool-ului.**
  Un pas de 604 caractere a fost respins generic, deși schema nu declară limita
  internă de 600. Declară `maxLength` pentru text și raportează precis câmpul,
  lungimea și limita. **Acceptare:** pași conciși acceptați și erori utile pentru
  text prea lung; această regulă de format nu limitează numărul total de operații
  sau cereri ale agentului.

## P1 — interfața chatului, cerințe adăugate de utilizator

- [ ] **AG-16 · Derulare tactilă printre mesaje.** Utilizatorul raportează că
  glisarea verticală peste text selectează mesajele în loc să deruleze conversația.
  Prioritizează derularea la glisare, inclusiv peste text și blocuri de cod;
  selecția/copierea să pornească intenționat prin apăsare lungă. Păstrează
  selecția cu mouse-ul și gestul de menționare a fișierelor. **Acceptare:**
  derulare în ambele sensuri pe Android, fără selecții accidentale; apăsare lungă
  pentru selecție funcțională. Gesturi simulate și selecție prin apăsare lungă probate în editor; confirmarea fizică pe Android rămâne separată.
- [ ] **AG-13 · Running Tools fără dropdown.** Înlocuiește zona „Operațiuni”
  cu eticheta exactă **Running Tools**. În dreptul ei se afișează unealta
  folosită în acel moment, actualizată automat la fiecare operație următoare.
  Zona nu se extinde și nu are săgeată sau comportament de dropdown.
  **Acceptare:** numele urmărește execuția reală și nu rămâne blocat pe o unealtă
  după finalizare sau Stop; planul agentului rămâne în cadrul său separat.
- [ ] **AG-14 · Generări compacte în chat, preview la cerere.** După generare,
  imaginile și mesh-urile apar automat în conversație ca mici carduri cu
  miniatură, nume și acces la fișier. Agentul nu deschide automat viewer-ul și
  nu schimbă ecranul utilizatorului. Preview-ul se deschide la apăsarea cardului
  sau când utilizatorul îi cere explicit agentului să deschidă generarea.
  Observarea de către agent în background rămâne disponibilă fără deschiderea
  viewer-ului. **Acceptare:** imagine și mesh finalizate apar compact în chat,
  rămân accesibile și după reluarea conversației și se deschid numai la cerere.
- [ ] **AG-15 · Cadru mai îngust pentru pașii agentului.** Limitează adaptiv
  lățimea cardului TODO/plan, cu text încadrat și margini compacte. Cadrul
  trebuie să ocupe mai puțin spațiu vizual în conversație și să se încadreze în
  dockurile înguste. **Acceptare:** verificare pe telefon/tabletă și chat
  central/stânga/dreapta; fără depășire, scroll orizontal sau lățime minimă care
  forțează extinderea panoului; pașii și stările rămân lizibile.

Implementările acestei livrări sunt descrise la începutul documentului.
Criteriile fizice nu sunt declarate validate numai din cod sau compilare.

## Din probele anterioare — de reverificat separat

- [ ] **AG-10 · Setări tipizate.** `godot_set_setting` a acceptat anterior
  descriptorul PackedStringArray ca Dictionary. Decodează/validează tipul și
  recitește setarea; folosește `plugin_enable` pentru activarea addonurilor.
- [ ] **AG-11 · Recuperare Runware.** Gestionează răspunsul contradictoriu HTTP
  500 cu rezultat de succes numai după validarea jobului și payload-ului.
  Recuperează același job, fără generări plătite duplicate. Imaginea probei
  anterioare a fost ulterior importată; întregul flux până la mesh rămâne de probat.

## Probe următoare

1. UC-04/05 pentru refuz și aprobare; apoi UC-06–09 pentru continuitate. UC-03
   a trecut pentru cerința de plan fără modificări.
2. Cod/fișiere și scene din catalog; repetă cubul după AG-01/02/03, cu modul și
   reasoning-ul consemnate. Editarea și validarea au trecut în UC-02.
3. Integrări și generare numai după precondiții, cu păstrarea aceluiași job la
   recuperare; apoi sarcinile complete, UI și conexiunile din catalog.
4. Pilot Pi separat, cu același model și aceleași criterii; comparație înaintea
   înlocuirii motorului. Îmbunătățirea harness-ului nu înlocuiește corectarea
   contractelor instrumentelor.
