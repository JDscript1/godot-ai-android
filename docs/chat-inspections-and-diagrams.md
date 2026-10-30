# Inspecții, navigare în proiect și diagrame în chat

Implementare nativă Godot AI, 30 octombrie 2026. Completează
[prezentarea conversației](chat-presentation.md); tabul oficial Ziva rămâne
independent. Aceste funcții nu solicită Node.js, PRoot, Termux sau un serviciu
web pentru afișarea lor.

## Ce a văzut agentul

În **Operații**, deschiderea unei citiri arată conținutul returnat de
`godot_read_file` / `godot_read_range`, cu numerele originale ale liniilor.
`godot_search_code` arată potrivirile și contextul returnat de instrument,
iar `godot_files` poate afișa o listă de căi accesibile prin atingere.

Rezultatul este o fotografie textuală a citirii originale. Restaurarea
conversației nu citește din nou discul și nu înlocuiește fragmentul vechi cu
versiunea curentă. Argumentele sunt asociate rezultatului apelului precedent,
inclusiv la paginarea istoricului și la reutilizarea unui ID de către furnizor.
Dacă argumentele sau conținutul original nu mai există, nu sunt inventate.

Previzualizarea este limitată la 100 de linii / 12.000 caractere; fiecare
linie are cel mult 800 caractere. Căutările arată cel mult 12 potriviri cu
contextul lor, listele de fișiere cel mult 30 de căi. Conținutul incomplet
este semnalat explicit. Codul lung păstrează extinderea/copierea din chat.
Redactorul existent maschează cheile cunoscute și modelele de credențiale
recunoscute înainte de limitarea fragmentelor. Nu garantează recunoașterea
oricărui secret arbitrar aflat într-un fișier.

Widgeturile conținutului sunt construite doar când utilizatorul deschide
operația. Payload-urile arbitrare ale furnizorilor, bytes și antetele HTTP
nu sunt adăugate cardurilor de inspecție.

## Căi către fișiere și linii

Sunt recunoscute linkuri Markdown și căi `res://` în text sau inline-code:

```text
[Player](res://scripts/player.gd:42:7)
`res://scripts/player.gd#L42`
res://scripts/player.gd:42
```

Numerele sunt de la 1. Atingerea unui script îl deschide în editorul Godot la
linia/coloana indicată. Scenele se deschid în editorul de scene, resursele în
editorul lor, iar directoarele sunt selectate în FileSystem. Fișierele text
UTF-8 uzuale și shaderele pot fi consultate într-o fereastră nativă doar pentru
citire, cu cursorul la linia cerută; limita este 1 MB. Celelalte tipuri rămân
selectate în FileSystem.

Navigarea se face numai la cererea utilizatorului. Apariția unui card nu
deschide automat fișierul sau previzualizatorul. Căile sunt verificate din nou
la atingere: traversarea proiectului, directoarele interne și legăturile
simbolice sunt respinse. Un fișier dispărut este raportat. Căile proiectului
nu sunt trimise handlerului de URL-uri al sistemului de operare.

## Diagrame native

Blocurile `mermaid` încheiate sunt desenate ca noduri și săgeți native.
În timpul unui bloc incomplet este arătată sursa. Un bloc valid păstrează
zoom-ul când răspunsul agentului se încheie.

Acesta este un subset al sintaxei Mermaid, **nu motorul Mermaid complet**:

- `flowchart` / `graph` cu direcțiile TD, TB, BT, LR, RL;
- noduri simple, dreptunghiuri `[text]`, rotunjiri `(text)` / `([text])`,
  decizii `{text}` și cercuri `((text))`;
- conectori `-->`, `---`, `-.->`, `==>`, etichete `|text|`, lanțuri,
  ramificații, cicluri și bucle către același nod;
- `stateDiagram-v2` plat, aliasuri `state "text" as ID`, descrieri,
  tranziții `A --> B: etichetă`, marcaje `[*]` și direcție.

Sunt acceptate ID-uri formate din litere ASCII/underscore urmate de litere,
cifre, underscore sau cratimă. Etichetele pot conține Unicode. Sintaxa este
bazată pe [flowchart](https://mermaid.js.org/syntax/flowchart.html) și
[state diagrams](https://mermaid.js.org/syntax/stateDiagram.html), cu limitele
native de mai sus.

Limite: 16.000 caractere sursă, 40 noduri, 80 legături, 240 caractere pentru
o etichetă de nod, 160 pentru o etichetă de legătură. Subgrafurile, diagramele
sequence/class și directivele de stil/configurare/click nu sunt interpretate.
La sintaxă nesuportată sau greșită apare explicația și sursa completă rămâne
disponibilă. Nu se execută HTML, JavaScript sau acțiuni încorporate.

**Sursă** comută codul, copierea păstrează întregul bloc. **+ / −** modifică
zoom-ul, iar **Încadrează** readuce întregul graf în cadru. Înălțimea cadrului
se adaptează spațiului conversației. Glisarea derulează chatul în mod normal;
**Explorează** permite deplasarea diagramei. Dezactivarea lui restabilește
derularea conversației. Căutarea unui termen din diagramă deschide sursa.

## Verificare și lucrări rămase

Scenariul `inspections` testează cardurile reale, navigarea la linie/coloană,
atingerea linkurilor, istoricul paginat cu ID-uri repetate, fereastra text,
diagramele, zoom/deplasare și fallback-ul. Este inclus și în scenariul `all`.
Testele runtime verifică parserul, limitele și mascarea datelor în fragmente.

Rezultatele efective și limitele probei sunt în `PROGRES_SI_PLAN.md`, AG-65,
iar dovezile locale în `.ai-qa/chat-inspections-20261030/`. Verificarea în
editor Linux și evenimentele tactile simulate nu țin locul testului fizic
Android. Această etapă nu schimbă APK-ul din Download.

Memoria automată de preferințe, subagenții configurabili, checkpoint-urile
vechi ale proiectului și integrarea video/audio rămân etape separate.
