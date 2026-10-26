# TODO — agent și harness

Actualizat: **26.10.2026**. APK verificat: **c418f97**. Bifele se închid după
verificarea rezultatului; implementarea în sursă și livrarea în APK sunt stări
separate. Această etapă adaugă auditul și prioritățile, fără corecții runtime.

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

## P0 — corectitudinea operațiilor și livrare

- [ ] **AG-01 · Salvează scena în directoare noi.** Creează părinții prin
  operația nativă, cu verificările de cale și recuperare. `saved=false` trebuie
  să producă `ok=false`, cu motiv concret. În probă, două salvări au raportat
  succes fără fișier, apoi agentul a folosit o copie provizorie și Linux.
  **Acceptare:** destinație nouă și existentă, eroare de scriere raportată corect,
  conținut recitit; fără necesitatea unui workaround în shell.
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
  efectiv al turnului. **Acceptare:** citire din Termux fără copiere în chat,
  sesiuni peste 1.000 de evenimente și rezultate peste 12.000 de caractere.
- [ ] **AG-12 · Descoperire la mesaje noi și Resume.** Reîncarcă schemele
  necesare din catalogul permis, păstrând regulile Plan/permisiuni. În testul
  02, un mesaj nou în aceeași conversație a produs `godot_apply_patch /
  tool_not_loaded`, apoi încărcare și recuperare. **Acceptare:** continuare și
  Resume fără apeluri către scheme indisponibile sau expunerea tool-urilor excluse.

## P1 — interfața chatului, cerințe adăugate de utilizator

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

Aceste trei puncte sunt cerințe pentru implementare, nu modificări deja
aplicate sau validate în APK.

## Din probele anterioare — de reverificat separat

- [ ] **AG-10 · Setări tipizate.** `godot_set_setting` a acceptat anterior
  descriptorul PackedStringArray ca Dictionary. Decodează/validează tipul și
  recitește setarea; folosește `plugin_enable` pentru activarea addonurilor.
- [ ] **AG-11 · Recuperare Runware.** Gestionează răspunsul contradictoriu HTTP
  500 cu rezultat de succes numai după validarea jobului și payload-ului.
  Recuperează același job, fără generări plătite duplicate. Imaginea probei
  anterioare a fost ulterior importată; întregul flux până la mesh rămâne de probat.

## Probe următoare

1. Repetă cubul după AG-01/02/03, cu modul și reasoning-ul consemnate.
2. Refuz de permisiune, Stop și Resume; editarea și validarea au trecut în testul 02.
3. Terrain3D și recuperarea aceleiași generări Runware, apoi import/preview mesh.
4. Pilot Pi separat, cu același model și aceleași criterii; comparație înaintea
   înlocuirii motorului. Îmbunătățirea harness-ului nu înlocuiește corectarea
   contractelor instrumentelor.
