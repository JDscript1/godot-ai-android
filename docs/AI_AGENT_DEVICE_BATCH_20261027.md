# Probe native și corecția căilor — 27.10.2026

Reluarea rundei așteaptă deblocarea dispozitivului. Un turn `completed` nu înseamnă automat că proba a
trecut. Stările de mai jos reflectă verificările efective și variantele repetate.

## Mediu și păstrarea proiectelor

- APK instalat: `c418f972958644f7bb78cdf36cca3e77691007d9`, Godot 4.7.2 custom,
  panoul încorporat verificat prin SHA-256. Acest APK încă are plafonul de
  30 de cereri și dialogul vechi de permisiuni.
- Agentul nativ al aplicației, DeepSeek `deepseek-flash`, effort medium.
  YOLO era deja activ; evaluatorul nu a activat permisiuni suplimentare.
  Cererile sunt introduse prin driverul de dezvoltare în `_start_chat` normal.
  Runtime-ul agentului și uneltele sale native nu sunt înlocuite de evaluator.
- Proiect izolat: `Documents/GodotAI-Agent-Suite-20261027/project`.
  Director unic pentru probe: `res://agent_tests/test_XX/`. Aceste subfoldere
  sunt cerute explicit de suită. Nu s-au mutat sau șters proiectul Vampyr ori
  asseturile utilizatorului. Scenele de test nu devin scena principală.
- Dovezi private locale: `.ai-qa/native-agent-suite-20261027/`, separat pe
  caz/turn: loguri, conversație, checkpoint, hash-uri înainte/după, artefacte
  schimbate și captură. Seiful API nu este citit. `summary.json` și
  `transcript-turn.json` sunt sursele canonice; unele linii vechi din ledger
  preced corectarea colectorului și pot conține un răspuns din turnul anterior.

## Rezultate evaluate

| Caz | Rezultat | Dovadă și limită |
| --- | --- | --- |
| UC-10 | Parțial: citire corectă, numărătoare imprecisă | 4 cereri / 16,3 s; niciun tool de scriere/rulare. Raportul spune 6 scripturi dar enumeră 5 din proiect și 10 fișiere citite în loc de 12. |
| UC-11 | Trecut | 5 cereri / 15,6 s; fișier absent confirmat, fără conținut inventat și fără creare. Răspunsul îl numește inutil „blocaj”, deși absența era scopul probei. |
| UC-13 | Funcție verificată; workflow limitat | 30 cereri / 415,7 s; 9 verificări PASS, `VERIFY_RESULT=PASS`, `FAILURES=0`. API și marker păstrate. `step_limit`, fără raport final. |
| UC-14 | Funcție verificată după continuare; workflow limitat | Prima implementare: 14 cereri / 110,4 s, parser valid. Continuare UC-14b: 30 cereri / 328,8 s; 35 verificări PASS, apoi sondă suplimentară pe cazurile cerute. `step_limit`, fără raport final. |
| UC-15 | Trecut | 8 cereri / 29,7 s; numai `spawn_enemy` trece de la 4 la 7, `spawn_player` rămâne 4; citire și parser valide, un singur fișier schimbat. |
| UC-16 | Trecut după clarificarea textului literal | Prima cerere avea punctuație ambiguă. UC-16b: 9 cereri / 52,1 s; conținut exact `Începe jocul — Știință și țară.`, fără newline, cale cu spații. |
| UC-17 | Trecut în perechea repetată corect | UC-17d: 5 cereri / 28,1 s, ștergere și index real 17. UC-17e în același chat: 4 cereri / 19,7 s, restaurare prin index, bytes inițiali și KEEP identici. |

UC-19 este în curs, suspendat de Android când dispozitivul este blocat. La
ultima captură de stare avea 14 cereri, fără rezultat final. Colectorul a fost
oprit păstrând `pending.json`; la reluare adoptă aceeași cerere, fără retrimitere.
Dovezi parțiale: `UC-19-in-progress/`. Cazurile ulterioare nu au fost trimise.
Deblocarea și revenirea în Godot sunt necesare pentru continuarea probei.

Verificare independentă a copiilor nemodificate, în Godot Linux oficial:
**17 verificări / 0 eșecuri** pentru UC-13/14/15, plus **3 comparații de bytes/hash
trecute** pentru UC-16/17. Dovezi: `independent-cases-13-17/`. Este verificarea
evaluatorului, separată de acțiunile agentului Android. Prima rulare independentă
avea o așteptare greșită pentru valoarea markerului; așteptarea a fost corectată
după confruntarea cu originalul, fără modificarea artefactului agentului.

Modificarea `project.godot` și `.nomedia` din primul diff provine din deschiderea
proiectului în editor, înaintea cererii UC-10; prima citire a configurației de
către agent corespunde fișierului actual. Nu este o încălcare read-only a agentului.
Evaluatorul a adăugat cubul-fixture `test_30/probe_cube.glb` în timpul UC-11;
importul său a produs ulterior `.glb.import`. Aceste efecte sunt identificate
separat de scrierile agentului în `controller-fixture-additions.json`.

## Corecții ale procedurii de testare

În primele cereri, instrucțiunea comună a cerut prea general Playtest/input și
a asociat citirea cu lipsa rulării. A produs verificări inutile la UC-13 și
omiterea runtime-ului în prima variantă UC-14. Cerințele următoare precizează
numai criteriile cazului. Costul cererilor suplimentare nu este atribuit exclusiv
agentului. În UC-14b, parserul Godot acceptă JSON cu virgulă finală; agentul a
corectat fixture-ul „invalid” și a obținut 35 PASS. Nu există dovadă de Output
stale în această probă.

La UC-17 a fost intercalat greșit UC-14b între ștergere și restaurare, pierzând
contextul perechii. Varianta UC-17b a fost oprită de evaluator după 29 cereri;
UC-17c a restaurat asistat, cu indexul real 8 furnizat explicit. Aceste variante
nu demonstrează restaurare autonomă. Numai perechea UC-17d/e în același chat
este rezultatul valid al cazului.

Pentru UC-13, părintele a folosit patru copii Playtest nativi. Dovezile includ
cadre reale ale jocului, inclusiv cadrul gri așteptat al scenei fără UI. Playtest
expune observație, stare și input, dar nu citirea consolei sau evaluarea unei
funcții. Părintele poate citi Output. Cererea unei asemenea evaluări de la copil
a adăugat cost fără să înlocuiască cele 9 rezultate PASS din Output-ul părintelui.

Pentru scenele următoare, evaluatorul pregătește directoarele goale înaintea
cererilor și înregistrează pregătirea în `operator-fixture-events.jsonl`.
Aceasta izolează celelalte funcții de bug-ul salvării din APK; nu demonstrează
corecția Android. Prompturile cer explicit aceleași directoare și căi exacte.
UC-21 verifică scena existentă din `test_19`, fără a o copia în `test_21`.

## Corecție implementată în surse, nelivrată în APK

Reprodusă salvarea cu `ok=true, saved=false` într-un director părinte absent.
`godot_save_scene` creează părinții, validează destinația și întoarce eroare
dacă verificarea fișierului/căii active eșuează. Un părinte care este fișier,
un director numit `.tscn` și traversarea în afara proiectului sunt respinse.
Salvarea repetată păstrează aceeași cale și mecanismul de recuperare.

`godot_project` expune `scene_path`, `project_path` și până la 12 căi existente
din istoricul persistent. Contextul unei conversații noi le primește automat.
Instrucțiunile cer reutilizarea structurii proiectului și căutarea căii reale
înaintea oricărei alternative; subfolderele generărilor rămân în destinația
configurată. Regula de organizare este o instrucțiune a agentului, nu o interdicție
generală asupra creării legitime de directoare.

UC-19 a expus și AG-20: `godot_create_scene` întoarce un nod nou ca succes, deși
`add_root_node` refuză operația atunci când scena curentă are deja o rădăcină.
Rădăcina a rămas VerifyScores, iar două noduri au fost adăugate acolo; agentul
a observat discrepanța și le-a eliminat înaintea salvării. Defect consemnat în
TODO și confirmat în codul Godot; nu este corectat de schimbarea căilor.

Regresie în editor local: **45 verificări / 8 eșecuri** înainte de fix;
**50 / 0** în versiunea finală. Runtime local: **277 / 0**. Dovezi:
`.ai-qa/scene-path-fix-20261027/red2/`, `green3/`, `runtime/`.
Nu s-a compilat sau instalat APK; AG-01/19 rămân deschise pentru proba Android.
Nu au fost simulate toate erorile posibile de I/O la suprascrierea unui fișier
existent; verificarea folosește rezultatul pe disc și calea activă deoarece API-ul
editorului pentru `save_scene_as` nu întoarce direct eroarea internă de salvare.
