# Stabilitate agent — probe și praguri de acceptare, 27.10.2026

Scop: jocuri construite și verificate prin agentul din Godot. Lucrul pe proiecte
mari cere continuitate, verificări reproductibile și controlul regresiilor.
Un mini-joc funcțional nu dovedește încă pregătirea pentru producție AAA.

## Mediul și limitele probei

- NX729J, Android, editorul instalat `com.jdscript.godotai.debug`, sursa
  `74887a1fc49bc2a969ef33c9a9ac1d6f293f6d8e`.
- SHA-256 al APK-ului instalat egal cu instalatorul livrat în Download:
  `389b43bd9370d41ac23bb0ede3139fbc221b5a2f0ddaf215a57ec8da457f0890`.
- DeepSeek `deepseek-flash`, profilul deja configurat în aplicație. Cheia nu
  este exportată. YOLO era deja activ; driverul nu l-a activat.
- Proiect nou izolat:
  `Documents/GodotAI-Stability-20261027T150114Z/project`.
- Comenzile intră prin panoul nativ, iar rezultatele provin din uneltele și
  rularea APK-ului. Nu s-au construit manual scenele în locul agentului.
- Fără generări plătite de asseturi, instalări de pluginuri sau comenzi Linux
  în această rundă. Cererile DeepSeek folosesc API-ul real și pot avea cost.

## Rezultatele din APK-ul instalat

| Probă | Rezultat observat | Stare |
| --- | --- | --- |
| Două scene în același director | `arena.tscn` și `menu.tscn` salvate și redeschise separat, rădăcini și noduri confirmate; 21 cereri, 63,4 s | Trecut |
| Mini-joc cu 3 monede | Script și scenă în `game/`, colectare prin input, contor 0→1→2→3, victorie, Restart și R; 46 cereri, 397,8 s | Trecut |
| Păstrarea fișierelor | Configurația, pluginul, markerul și scenele existente păstrate identic; fără alt director principal | Trecut în primele două probe |
| Funcționare peste vechiul plafon | Mini-jocul a ajuns la 46 cereri și a încheiat planul | Confirmat |
| Layout adaptat și Stop controlat | Stop după prima scriere reală; modificarea rămâne salvată și raportul precizează lipsa verificării ulterioare | Oprire corectă; layout încă nevalidat |
| Continue după Stop, APK nemodificat | Același turn reluat prin butonul nativ; DeepSeek returnează HTTP 400 privind metadata de protocol | Eșec reprodus |
| Continue după repornirea editorului, adaptor corectat | Același turn, 58 cereri, 466,0 s, fără HTTP 400; colectare/victorie/Restart/R și oprire confirmate | Trecut cu adaptor temporar, încă nelivrat în APK |
| Corectarea layoutului îngust | Agentul repară suprapunerile și adaugă o probă runtime: 492 verificări, 0 eșecuri; 59 cereri, 633,1 s | Trecut cu adaptor temporar |
| Salvare/încărcare după oprirea procesului jocului | 1/3 și apoi 3/3 sunt salvate și refăcute după pornire nouă; 938 verificări, 0 eșecuri; 62 cereri, 574,5 s | Fluxul normal trecut; validarea numerică a necesitat încă o corecție |
| Validarea exactă a salvărilor | Agentul respinge versiune/număr de monede fracționare, extinde proba și o rerulează: 946 verificări, 0 eșecuri; 14 cereri, 85,2 s | Trecut; confirmare independentă 34/34 |

Proba mecanicilor a folosit input injectat prin uneltele native în jocul Android,
nu setarea directă a contorului sau teleportarea jucătorului. Capturile reale
confirmă starea inițială, victoria și resetarea. Atingerea fizică a degetului și
redimensionarea nu sunt demonstrate de această probă. Captura inițială arată
margini gri: de aici pornește sarcina separată de layout.

## Corecții în surse, după constatări

1. **Protocol la reluare:** notificările locale despre Stop/eroare, drafturile
   întrerupte și cardurile de fișiere sunt marcate ca mesaje ale aplicației.
   Contextul lor util este transmis separat de răspunsurile modelului, inclusiv
   pentru înregistrări vechi. Nu se inventează metadata de raționament. Datele
   confirmate ale furnizorului se păstrează și la ramificarea conversației.
2. **Rezultate mari:** rezumatul pentru model păstrează `ok`, erori, ID-uri și
   metadate compacte ale artefactelor. Limita de 24.000 caractere se măsoară
   după serializarea JSON, inclusiv escape-uri; jurnalul complet rămâne separat.
3. **Inspectarea API-ului Godot:** `godot_describe` are paginare alfabetică,
   totaluri, `next_offset` și filtru literal cu alternative `|`. Implicit 16
   intrări/categorie, maximum 50. Pentru Node: 48.786 caractere integral față de
   7.342 în pagina implicită. Nu este o măsurare înainte/după a facturii API.
4. **Evaluator:** păstrează permisiunile existente, permite continuarea aceluiași
   chat și colectează JSONL complet, checkpoint și conversație în fișiere 0600.
   Starea se actualizează și după o reluare declanșată din interfață.

Contractul actual DeepSeek pentru continuări cu unelte este descris în
[documentația oficială](https://api-docs.deepseek.com/guides/thinking_mode/).

Validări locale cu Godot Linux ARM64 prin Debian/PRoot:

- Regresii reproduse înaintea fixurilor; pentru reluare: 516 aserțiuni / 6 eșecuri.
- **518 aserțiuni runtime / 0 eșecuri**, inclusiv cerere HTTP invalidă respinsă
  și aceeași continuare cu context corect acceptată de fixture-ul strict.
- **514 verificări în editor / 0 eșecuri**, configurația narrow; capturile
  cardurilor și ale sarcinii întrerupte inspectate vizual.
- Driverul normal și driverul temporar al probei de adaptor trec parserul Godot;
  scripturile Python se compilează.

Aceste surse nu sunt încă într-un APK nou. Prima repetare live a fost oprită de
blocarea automată a telefonului. După reconectarea autorizată la portul 37421,
adaptorul de furnizor din surse a fost încărcat temporar în proiectul de probă.
Panoul, harness-ul și uneltele au rămas cele native din APK. Vault-ul nu a fost
exportat. SHA-256 adaptor:
`1957cc86b843271ff64249b5687eb534195cead5ef668a1e6849c691bd10850e`.

Reluarea prin intrarea nativă `_resume_chat` a recuperat turnul original după
repornirea editorului: **58 cereri, 161 rezultate de tool, 466,0 s**, `completed`.
Au existat șase refuzuri/erori recuperate (fază de plan, valoare neaplicată,
atașare de script, două interogări fără joc pornit și finalizare fără input după
ultima rulare). Gardul de verificare a cerut o probă nouă și agentul a executat-o.
Scenele existente, configurația, markerul și pluginul sunt identice; numai cele
două fișiere cerute diferă. Capturile reale confirmă 3/3, victoria și resetarea.
Nu este o recompilare a APK-ului sau validarea lui cu toate fixurile noi incluse.

Verificarea independentă în șase SubViewport-uri a găsit **5 eșecuri / 78
controale** în layoutul rezultat: suprapuneri de butoane și HUD la 480×900 și
320×568, plus contor în afara viewportului la 320×568. Agentul a declarat sincer
că nu verificase redimensionarea runtime. Defectele au fost trimise agentului
ca sarcină separată. Agentul a scris proba `game/tests/layout_probe.gd`, a găsit
trei probleme suplimentare și le-a reparat până la **492 / 0** în Android.
Verificarea independentă a copiei corectate a trecut cu **84 / 0**. Randări
Linux ale aceleiași scene la 320×568, 480×900 și 640×360 au fost inspectate;
nu se prezintă drept capturi fizice de telefon la aceste trei dimensiuni.

În continuare, agentul a adăugat SaveButton, LoadButton și StatusLabel, scriere
temporară cu verificare și backup, validare înainte de aplicarea stării și
mesaje scurte de rezultat. Proba existentă a fost extinsă, păstrând toate cele
16 linii de aserțiuni inițiale; comparația textuală nu este o dovadă formală de
echivalență, dar împreună cu rerularea verifică păstrarea regresiilor originale.
Scorul, poziția și monedele au fost observate prin uneltele native înainte și
după oprirea și pornirea procesului jocului: 1/3→salvare→pornire 0/3→încărcare
1/3 și 3/3→salvare→pornire 0/3→încărcare 3/3/victorie. Capturile reale confirmă
starea și comenzile. Aceasta nu este suspendarea întregului Android sau
simularea unei căderi de alimentare.

Evaluatorul independent a rulat **34 controale de persistență** pe o copie
Linux izolată, cu user data temporară separată de Android: patru eșecuri pentru
`version=1.5` și `coin_count=3.5`. Trunchierea prin `int()` accepta datele și
modifica starea curentă. Agentul a reparat comparația numerică exactă și a adăugat
cazurile în proba sa: **946 / 0** în Android, apoi **34 / 0** în evaluatorul
independent. Acesta verifică și păstrarea octeților salvării bune când calea
fișierului temporar este blocată intenționat de un director. Nu este o eroare
fizică de disc sau un disc plin. Semnalele UI și logica de coliziune din evaluator
nu sunt prezentate drept input fizic de deget.

Regresia geometrică independentă finală, extinsă cu noile butoane, are **156
controale / 0 eșecuri**, cu o verificare duplicată eliminată din runda preliminară
de 162. Scenele arena/meniu, configurația, markerul și pluginul au rămas identice;
schimbările proiectului sunt în cele două fișiere cerute și în probele din
`game/tests/`. Jocul generat și validarea salvărilor sunt în proiectul de probă,
nu funcții de gameplay încorporate în APK-ul editorului.

Observate și două probleme de comportament: planul a rămas pe construcția scenei
în timpul testării, iar răspunsul final a avut 2.286 caractere, cu coordonate și
proprietăți inutile utilizatorului. Sursele cer acum actualizarea planului la
schimbarea etapei și, implicit, trei puncte concise, aproximativ 120 cuvinte,
cu limitele materiale păstrate. Validarea comportamentului după aceste
instrucțiuni noi rămâne separată de testele de compilare.

Ghidajul din surse cere și gruparea inspecțiilor independente/tap-urilor deja
cunoscute, plus rezumate de teste cu număr de controale și eșecuri. Nu există o
comparație de cost înainte/după pentru sarcini identice. **518 aserțiuni runtime
/ 0 eșecuri** au trecut din nou după aceste modificări; driverul trece parserul
Godot. Driverul persistă și selecția restaurată după probe pentru rundele viitoare;
această ultimă schimbare are verificare de parser, fără o nouă rundă API.

La încheiere, adaptorul nativ original a fost restaurat, copia temporară de
furnizor eliminată și editorul repornit cu driverul normal. SHA-256 al APK-ului
instalat corespunde în continuare instalatorului inițial. Scena mini_game este
deschisă, jocul oprit, Output minimizat și modul UI readus la Default. Nu rămâne
o comandă de generare, reluare sau trimitere în așteptare. Cheia API a rămas în
aplicație; nu s-a compilat sau înlocuit un APK în această rundă.

## Ordinea următoarelor probe

Fiecare probă are snapshot inițial, jurnal complet, rezultat observat și lista
fișierelor modificate. Un blocaj se păstrează pentru reluare; nu încheie artificial
criteriul. Nu se reintroduce o limită totală de pași.

Stare după rundă: ST-01 a trecut cu adaptor temporar, inclusiv layoutul; ST-02
este verificat numai pentru repornirea editorului înainte de Resume, fără
întrerupere forțată de rețea. ST-05 a trecut fluxurile și cazurile negative de
mai sus. Aprobările/refuzurile, compactarea forțată, Runware, performanța 3D și
exportul jocului nu au fost validate de această rundă.

| Prioritate / ID | Sarcină pentru agent | Condiție de acceptare |
| --- | --- | --- |
| P0 / ST-01 | Reia exact sarcina de layout oprită | Același turn, fără HTTP 400, fără scene/foldere duplicate; layout și mecanici verificate după ultima modificare |
| P0 / ST-02 | Oprește și reia după repornirea editorului, apoi după eroare de conexiune | Plan, fișiere, unelte încărcate și ID-uri păstrate; nicio operație externă repetată automat |
| P0 / ST-03 | Refuză o scriere, apoi aprobă o cerere nouă distinctă | Refuzul este respectat, dialogul accesibil, nicio modificare neautorizată |
| P0 / ST-04 | Repară un script invalid fără a altera funcțiile corecte | Parser roșu→verde, test comportamental și diff limitat la fișierele cerute |
| P1 / ST-05 | Salvează și reîncarcă progresul mini-jocului | Restart de proces real; monede/scor/poziție corecte; salvare invalidă tratată explicit |
| P1 / ST-06 | Adaugă meniu, pauză și trecere între două niveluri | Tranziții și input verificate; revenirile nu dublează monede, semnale sau noduri |
| P1 / ST-07 | Îmbunătățește același proiect într-o conversație lungă | Recuperează structura și deciziile după compactare; nu recreează scene sau rescrie configurația |
| P1 / ST-08 | Folosește o imagine și un mesh deja existente | Carduri în chat, observație în background, preview numai la cerere; fișierele originale păstrate |
| P1 / ST-09 | Reia un job Runware existent până la import | ID unic, fără regenerare accidentală, transparență și mesh real verificate; cost consemnat separat |
| P2 / ST-10 | Construiește o felie 3D jucabilă: personaj, cameră, coliziuni, obiectiv | Parcurs complet prin input, geometrie fără blocaje evidente, salvare și rerulare reproductibilă |
| P2 / ST-11 | Măsoară și optimizează scena 3D pe dispozitivul țintă | Bugete FPS/timp de cadru, memorie și încărcare stabilite pe proiect; comparație repetată înainte/după |
| P2 / ST-12 | Exportă și pornește un build de joc separat | Artefact instalabil, pornire reală și regresie după export; build-ul editorului nu este dovada exportului jocului |

## Capacități necesare pentru proiecte mari

- Criterii de acceptare explicite pentru fiecare etapă și legarea lor de probe
  concrete. Verificarea generică a oricărui tool nu dovedește toate mecanicile.
- Hartă persistentă a proiectului, dependențe între scene/resurse și decizii
  verificate. Recuperare după compactare și schimbarea sesiunii/furnizorului.
- Detectarea ciclurilor de investigație fără progres, inclusiv citiri reușite
  repetate; întâi reformularea planului și păstrarea stării, fără plafon global.
- Regresii automate pentru mecanici, input, stări salvate și tranziții; build-uri
  reproductibile și verificarea asseturilor, coliziunilor, LOD-urilor și licențelor.
- Bugete și profilare pe dispozitivul țintă, încărcare/streaming de resurse,
  organizarea conținutului și controlul versiunilor.

Acestea sunt praguri de implementat și demonstrat, nu funcții deja validate.
Înlocuirea harness-ului cu Pi sau alt runtime nu elimină nevoia acestor probe.

## Dovezi locale

`.ai-qa/harness-stability-20261027/` conține `session.json`, snapshot-uri,
`scene-paths-native/`, `mini-game-native/`, `responsive-stopped-native/`,
`responsive-resume-failed-native/`, `runtime-resume-red.log`,
`runtime-final-518.log`, `render/narrow/editor-report.json` și capturi.
Continuarea are `resume-development-native/`, `narrow-development-native/`,
`persistence-development-native/`, `strict-development-native/`,
`layout-matrix-final.json`, `persistence-matrix-first.json`,
`persistence-matrix-final.json`, `narrow-rendered/`,
`probe-regression-integrity.json`, `device-restoration-final.json`,
`final-editor.png` și `runtime-guidance-final.log`.
Conversațiile și checkpointurile pot conține metadata privată de protocol;
rapoartele prezintă numai starea și rezultatele utile. Nu se publică chei sau
raționamentul intern al modelului.
