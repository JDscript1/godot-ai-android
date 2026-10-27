# TODO — agent și harness

Actualizat: **27.10.2026**. APK verificat: **c418f97**. Bifele se închid după
verificarea rezultatului; implementarea în sursă și livrarea în APK sunt stări
separate. Implementarea punctelor AG-01–AG-20 este pregătită pentru noul APK;
confirmările fizice rămân distincte de testele locale și compilare.

## Aplicare în această livrare — 27.10.2026

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
fizică Android sau generare plătită live. Regresiile complete și compilarea
nativă sunt consemnate în documentul de progres și în raportul de livrare.

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

**Stare:** eliminarea plafonului este deja în sursă; APK-ul verificat c418f97
încă are limita veche. Livrarea și confirmarea pe dispozitiv rămân la AG-03.

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
  Livrarea în APK și repetarea fizică rămân deschise.
- [ ] **AG-02 · Compară numeric proprietățile cu toleranță.** Rotația cerută
  `(-50,-35,0)` a devenit `(-49.999996,-34.999996,0)` și a fost declarată greșit
  neaplicată. Toleranță potrivită tipului pentru numere/vectori/transformări;
  referințele și valorile discrete trebuie verificate în continuare exact.
  **Acceptare:** rotația din probă trece; o valoare realmente diferită e respinsă.
- [ ] **AG-03 · Fără plafon de pași, până la livrarea rezultatului.** Livrează
  eliminarea plafonului (`309c4f6`) și aprobările accesibile (`226c519`), deja
  implementate și testate în sursă, dar absente din APK-ul c418f97. Continuarea
  trebuie să urmărească rezultatul verificat, inclusiv când rămân pași după un
  răspuns intermediar. **Acceptare:** APK nou verificat, depășirea limitelor vechi
  fără alt plafon ascuns, finalizarea cerinței și verificărilor, Stop și
  aprobare/refuz funcționale pe dispozitiv. Compilarea/livrarea se face într-o
  etapă cerută explicit.

## P1 — verificare, continuitate și eficiență

- [ ] **AG-19 · O singură structură de proiect, căi reutilizate.** Inspectează
  structura existentă, păstrează directorul convenit și calea exactă confirmată
  la salvare. La continuare sau eroare de deschidere, caută scena existentă;
  nu crea alt folder la rădăcină, copii ori mutări ca substitut. Subfolderele
  numite ale generărilor rămân în destinația configurată. **În surse:** regula
  și contextul cu `scene_path`/`recent_paths` sunt implementate; testul confirmă
  persistența și contextul unei conversații noi. **Acceptare rămasă:** APK nou,
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
  Defect confirmat în APK-ul vechi; corecția pentru noul tab este implementată separat de AG-19 și intră în verificarea nativă a livrării.
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
