# Evaluarea agentului cu API real

Actualizat: 23.10.2026. Sursă după APK-ul livrat `36457dd`; această etapă nu
recompilează și nu înlocuiește installerul din Download.

## Metodă

Furnizorul ales de utilizator este DeepSeek, prin cheia din configurația sa
locală, cu identificatorul `deepseek-v4-flash`. Catalogul real afișează
`deepseek-flash` și `deepseek-v4-pro`; numele cerut este acceptat ca alias.
[Documentația oficială](https://api-docs.deepseek.com/guides/agent_integrations/openclaw)
explică faptul că aliasul Flash vechi este servit de modelul Flash actual.
Nu prezentăm rezultatele drept măsurători ale vechilor ponderi V4 Flash.

`modules/ai_assistant/tests/evaluate.py` pornește Godot 4.7.2 Linux ARM64 în
proot și Xvfb, cu un proiect și directoare de configurare temporare. Folosește
panoul, instrucțiunile, adaptoarele HTTP, harness-ul, descoperirea tool-urilor,
permisiunile, planificatorul și tool-urile editorului din sursele aplicației.
Modelul răspunde efectiv prin API; răspunsurile și selecția tool-urilor nu sunt
simulate. Nu este un test fizic al APK-ului Android.

Driverul și criteriile de evaluare stau în afara `res://`, pentru ca tool-urile
de fișiere să nu poată citi răspunsurile așteptate. Fiecare probă începe într-o
conversație nouă; fișierele inițiale și rezultatele sunt comparate prin hash.
Refuzul permisiunii este aplicat prin dialogul normal al panoului. Pentru
editările autorizate, YOLO este activat doar în configurația temporară de test.
Nu sunt configurate chei de generare, GitHub sau servere MCP.

Cheia este citită dintr-o variabilă de mediu explicită și transmisă printr-un
fișier temporar cu permisiuni 0600, șters după citire. Nu apare în argumentele
procesului sau în rapoarte. Traseele exclud raționamentul intern. Rularea are
limite de cereri și timp, persistă probele finalizate și nu intră automat în CI.

## Probleme reproduse și corecții

În prima probă de scenă, `godot_set(mesh)` a primit un obiect codificat greșit,
a lăsat mesh-ul gol și a raportat succes. Încercarea ulterioară prin
`godot_call(set_mesh)` a primit Dictionary în loc de Object, a produs o eroare
Godot și a raportat tot succes. Agentul a consumat bugetul de pași fără rezultat.

Au fost corectate contractul și verificările:

- Rezultatele cu obiecte includ `reference: {"$handle":"obj_..."}`; descrierile
  tool-urilor arată exact forma de folosit. Forma explicită
  `{"$type":"Object","handle":"obj_..."}` este decodată și ea.
- Referințele expirate, argumentele incompatibile și clasele Resource greșite
  sunt respinse înaintea mutației. După setarea unei proprietăți, valoarea este
  recitită și comparată cu valoarea cerută. Numerele JSON și array-urile packed
  compatibile sunt convertite explicit.
- Metadatele metodelor păstrează tipurile și clasele argumentelor. Limita JSON
  anterioară tăia aceste informații la `[depth limit]`; StringName/NodePath sunt
  acum serializate ca șiruri obișnuite.
- Răspunsul final al unei implementări obișnuite este cerut compact: ce s-a
  modificat, ce s-a verificat și eventualul blocaj, fără dump de hash-uri sau cod.

Validarea reflectată nu poate captura orice eroare produsă în interiorul unei
metode sau orice efect asincron. Tool-ul cere în continuare verificarea
rezultatului și a Output-ului; un apel fără eroare de tip nu este dovada că
întreaga sarcină a reușit.

## Jurnalul de activitate

Jurnalul normal al panoului include acum:

- `agent_request`: model, profil, pas și încercare;
- `agent_response`: durata cererii, motivul încheierii, numărul apelurilor și
  usage-ul raportat de furnizor;
- `agent_tool_result`: ID-ul apelului, tool, argumente, durată, execuție/reutilizare,
  succes și codul/mesajul erorii, inclusiv operațiile blocate înainte de execuție;
- `agent_retry` și `agent_settled`, cu durata totală și contoarele execuției.

În paralel se păstrează jurnalul existent al operațiilor și rezultatele detaliate.
Raportul de evaluare salvează `journal.json`, `events.jsonl`, `report.json` și
`REPORT.md`. Sunt jurnale reale produse în timpul probelor API; nu sunt exportul
istoricului APK-ului utilizatorului. Spațiul privat Android nu este accesibil
din această sesiune, iar ADB nu are un dispozitiv conectat. Exportul din pagina
Jurnal poate fi analizat separat când este furnizat.

## Rezultate

Runda completă, cu driverul separat de proiect, a inclus **10 scenarii și 57
cereri reale**: nouă au îndeplinit integral criteriile. La depanare, scriptul
a fost reparat corect și a trecut parserul independent, însă agentul a publicat
un plan blocat de lipsa bridge-ului nativ. Harness-ul a etichetat greșit sfârșitul
buclei drept `completed`. Corecția introduce `blocked_reason`, statusul `blocked`
și păstrează reluarea în chat. Testele automate verifică statusul în harness,
checkpoint și conversație; nu prezentăm această regresie deterministă drept o
nouă probă live a aceluiași blocaj.

După corecțiile de stare și indicațiile explicite pentru căile `res://`, am
repetat **editarea, depanarea și scena: toate trei au trecut, în 26 de cereri**.
Tabelul folosește ultimul rezultat al fiecărui scenariu din aceste două runde;
nu reprezintă o singură rulare finală 10/10.

| Scenariu | Rezultat verificat | Cereri în ultima probă |
| --- | --- | ---: |
| Identitate | Răspuns compact, fără tool-uri | 1 |
| Inspectare | Citire exactă, proiect nemodificat | 2 |
| Editare și recitire | Patch exact, marker și alte fișiere păstrate | 6, repetat |
| Depanare GDScript | Corecție validă, limitarea diagnosticului nativ raportată | 11, repetat |
| Scenă în Auto | BoxMesh atribuit, poziție verificată, scenă salvată | 9, repetat |
| Plan | Propunere structurată, fără modificări | 5 |
| Refuz de permisiune | Un singur dialog refuzat, fișier păstrat | 5 |
| Curățare | Șters numai fișierul cerut, fără generare | 5 |
| Fișier lipsă | Eroarea reală raportată, fără conținut inventat | 2 |
| Asset Store | Căutare și detalii Terrain3D prin API-ul public, fără instalare | 4 |

Exemplu concret de traseu reușit pentru editare: `godot_read_file` →
`tool_search` → `godot_read_range` → `godot_apply_patch(dry_run=false)` →
`godot_read_file`. În ultima probă de scenă, agentul a publicat planul înainte
de mutații, a creat nodul și resursa, a setat mesh-ul și poziția, a salvat și a
verificat arborele și conținutul scenei. Fișierul salvat conține BoxMesh-ul și
transformarea cerută.

Rămân variații de eficiență: în unele încercări modelul folosește o cale relativă
sau încearcă o modificare înaintea planului Auto. Host-ul respinge acele apeluri,
iar modelul le corectează. Rezultatele diferă între runde și nu dovedesc o
accelerare statistică. În runda repetată, depanarea a mai avut un `plan_required`
și un `native_bridge_unavailable`; scenele și editarea nu au avut erori de tool.
O singură familie de modele, un nivel implicit de reasoning și acest set mic
nu acoperă toate sarcinile sau toți furnizorii.

Verificările surselor finale au trecut: **398 aserțiuni runtime**, zero eșecuri,
și **340 verificări în editorul desktop**, zero eșecuri, inclusiv regresiile
pentru argumente reflectate, mesh, referințe expirate și plan blocat.
Hash-urile celor 27 de surse runtime din ultima probă live corespund fișierelor
curente. Am verificat că artefactele evaluării nu conțin cheia folosită.

Dovezi: `.ai-qa/deepseek-api-review/REPORT.md` și `report.json`,
`.ai-qa/deepseek-api-verified/`, `.ai-qa/deepseek-api-corrections/`,
`.ai-qa/api-behavior-runtime-settled.log`, `.ai-qa/api-behavior-editor-settled/`.
Primele directoare `deepseek-api-baseline-*` sunt probe de diagnostic, iar
`deepseek-api-final/` este o rundă întreruptă, nu un raport final complet.

Nu au fost instalate pluginuri, nu s-au trimis generări plătite și nu au fost
modificate proiectele utilizatorului. Bridge-ul de diagnostic nativ nu există
în editorul upstream folosit de evaluator; aceasta este o limită a mediului
de test, nu o dovadă că lipsește din APK. Nu a fost introdus un harness extern.

## Reproducere

Setează cheia privat în `GODOT_AI_EVAL_API_KEY`, apoi rulează din repository:

```sh
python modules/ai_assistant/tests/evaluate.py --godot /cale/catre/godot --model deepseek-v4-flash --output .ai-qa/proba-api-noua
```

În Termux, adaugă `--proot` pentru binarul Linux. `--check` verifică încărcarea
fără rețea sau cheie. `--cases` permite repetarea unei probe, iar `--effort`
selectează nivelul trimis API-ului. Output-ul trebuie să fie un director nou,
pentru păstrarea probelor anterioare. Nu se citește automat o configurație cu
chei din altă aplicație; configurația locală a fost folosită la cererea explicită
a utilizatorului.
