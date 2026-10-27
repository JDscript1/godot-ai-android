# Plan interactiv — 27.10.2026

Stare: implementat și testat local în surse. APK-ul livrat `74887a1` nu include
această funcție; instalatorul din Download nu a fost modificat.

## Comportament

În modul Plan, agentul inspectează proiectul și clarifică deciziile relevante
care lipsesc: de exemplu perspectiva jocului, mecanicile sau stilul vizual.
Unealta `plan_ask` afișează direct în conversație 1–3 întrebări, fiecare cu 2–4
opțiuni. O întrebare poate permite o singură alegere sau mai multe. Utilizatorul
poate înlocui ori completa opțiunile printr-un răspuns propriu.

Nicio variantă nu este preselectată. Butonul **Trimite răspunsurile** devine
disponibil când fiecare întrebare are cel puțin o alegere sau text propriu.
Agentul așteaptă trimiterea explicită, apoi folosește răspunsurile pentru plan.
Nu face cereri repetate către model cât așteaptă și nu există termen automat
de răspuns. O cerere deja precisă sau o întrebare simplă nu necesită chestionar.

După trimitere rămâne un rezumat compact al alegerilor. Implementarea proiectului
necesită în continuare modul de lucru și permisiunile aferente; răspunsurile
nu acordă drepturi de scriere și nu activează YOLO. Modul Plan rămâne numai
pentru citire.

## Persistență și interfață

- Ciornele se salvează cu o scurtă amânare de 350 ms; răspunsurile se salvează
  înainte să fie returnate modelului. Textul propriu este limitat la 2000 de
  caractere pentru fiecare întrebare.
- Stop păstrează întrebările și răspunsurile începute. Trimiterea cardului
  restaurat reia aceeași sarcină, fără alt mesaj utilizator inventat.
- Dacă aplicația se întrerupe după salvarea răspunsului, dar înaintea rezultatului
  uneltei, se recuperează răspunsul real și apare **Continuă planul**.
- În contextul agentului se păstrează și ultimele patru grupuri de răspunsuri
  confirmate, inclusiv după compactare. Cerințele ulterioare ale utilizatorului
  au prioritate.
- Cardurile sunt legate de conversație și sarcină. O cerere nouă dezactivează
  întrebările vechi. Clickurile duplicate sau întârziate nu modifică răspunsurile.
- Reluarea păstrează furnizorul, modelul și modul cererii inițiale; dacă profilul
  nu mai există, nu se trimite automat către alt furnizor.
- Lățimea este adaptivă, cu plafon de 440 unități editor. Opțiunile se pot apăsa
  pe rândul întreg; pe touch, selecția are loc la eliberare. Glisarea derulează
  fără să selecteze accidental o variantă.

## Verificare

Furnizorul simulat rulează prin panoul, catalogul și harness-ul reale din Godot.
Probe: selecție exclusivă și multiplă, text propriu, lipsa trimiterii automate,
mouse/touch simulat, ciorne pe disc, rezumat restaurat, Plan numai pentru citire
chiar cu YOLO, Stop, recuperarea apelului întrerupt, fereastra de întrerupere
după salvarea răspunsului, acțiuni duplicate și din altă conversație.
Se verifică și dezactivarea cardului după o cerere nouă, profilul dispărut și
mascarea cheilor configurate în ciorne înainte de salvare.
Captura finală așteaptă actualizarea cadrului și confirmă indicatorul
**Plan pregătit**, cu butonul Stop ascuns.

- Runtime: **531 aserțiuni, 0 eșecuri**.
- Regresie editor narrow: **548 verificări, 0 eșecuri**, inclusiv fluxul Plan.
- Scenariu interactiv: **67 verificări × 5 configurații, 0 eșecuri**.
- Probe dedicate și capturi: `.ai-qa/interactive-plan-final/`.
- Jurnale: `.ai-qa/interactive-plan-runtime.log`,
  `.ai-qa/interactive-plan-regression-final.log`, `.ai-qa/interactive-plan-final.log`.

Dimensiunile efective ale capturilor dedicate:

| Configurație | Fereastră randată |
| --- | --- |
| desktop | 1280 × 900 |
| narrow | 768 × 900 |
| wide | 1920 × 1080 |
| phone_landscape, scară mărită | 2048 × 922 |
| phone_compact, scară mărită | 1536 × 900 |

Editorul oficial impune lățimi minime; `narrow` nu este dovadă de randare fizică
la 480 px. Cardurile mai înalte se parcurg prin scroll în conversație.

Comenzi din rădăcina repository-ului:

```sh
python modules/ai_assistant/tests/run.py --proot --godot /data/data/com.termux/files/home/godot-engine/Godot_v4.7.2-stable_linux.arm64
python modules/ai_assistant/tests/render.py --proot --godot /data/data/com.termux/files/home/godot-engine/Godot_v4.7.2-stable_linux.arm64 --scenario planning --timeout-seconds 180 --output .ai-qa/interactive-plan-final
```

Probele randate folosesc editorul oficial Linux ARM64 și evenimente injectate;
nu sunt validare fizică Android sau rulare cu DeepSeek/alt API real. Compilarea
APK și evaluarea calității întrebărilor cu modelul real rămân separate.
