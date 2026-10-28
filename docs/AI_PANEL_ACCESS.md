# Citirea panourilor editorului de către agent

AG-54 extinde accesul la datele panourilor standard Godot și la controalele
standard folosite de pluginuri. Citirea nu deschide file, nu extinde arbori,
nu pornește profilarea și nu execută expresii în joc. Implementarea nativă
necesită recompilare; un APK anterior nu demonstrează funcționarea acesteia.

## Instrumente

| Instrument | Conținut |
| --- | --- |
| `godot_panels` | Inventarul controalelor instantiate, inclusiv interne, file ascunse, ferestre și pluginuri. Returnează handle, clasă, cale, etichetă, rol, vizibilitate și tipul cititorului. `handle` restrânge inventarul la un subarbore. |
| `godot_panel_read` | Conținutul unui control: Tree cu ramuri colapsate, liste, meniuri, file, text/cod, tooltip, valori numerice, butoane, culori, texturi și grafuri standard. |
| `godot_panel_data` | Datele native/publice ale surselor din tabelul următor. |
| `godot_debugger` | Lista structurată de erori/avertismente, cu sursă, linie, stack și sesiune; AG-53. |
| `godot_output` | Ultimele 40 de mesaje Output native și erorile Debuggerului. Fallback-ul fără bridge rămâne limitat la text vizibil. Mesajele Output mai vechi se paginează prin `godot_panel_data`. |

Inventarul general exclude interfața proprie a asistentului și nodurile scenei
editate. Pentru acestea există deja contextul conversației, instrumentele pentru
scene/proprietăți și cele pentru jocul rulat. O scenă cu multe noduri nu trebuie
să consume bugetul inventarului UI. Un subarbore de scenă cerut explicit prin
handle poate fi inspectat separat. Câmpurile secrete sunt protejate; numele unui
contor de joc precum `TokenCounter` nu este tratat drept cheie API.

## Surse `godot_panel_data`

| `section` | Date citite | Condiții și limite |
| --- | --- | --- |
| `output` | Mesaje păstrate de EditorLog, tip, număr de repetări, index și revizie. | Independent de vizibilitate și filtrul UI. Mesajele pot proveni din mai multe rulări; textul de peste 8.000 de caractere este marcat trunchiat. |
| `profiler` | Cadru, timpi de frame/proces/fizică, categorii, funcții, apeluri, timpi self/total/internal și surse. | Date colectate anterior; unitatea este secunda. `frame=-1` citește ultimul cadru, un număr concret permite paginarea aceluiași cadru reținut. Citirea nu activează profilerul. |
| `visual_profiler` | Cadru, zone, cale, CPU/GPU și informații hardware. | Timpi în milisecunde. Eșantioanele păstrate dintr-o sesiune anterioară au generația lor și `stale_session=true`. |
| `monitors` | Monitoare builtin/custom, valoare recentă, maxim, număr de eșantioane și unitate. | Fără eșantioane nu există un consum măsurat zero. Cu `monitor=name` sunt paginate valorile istorice, de la cele mai vechi; adăugarea de eșantioane nu deplasează indicii existenți. |
| `vram` | Resurse, tip, format și bytes. | Ultimul răspuns primit de panoul Video RAM; citirea nu apasă Refresh. Generația răspunsului este păstrată și comparată cu sesiunea actuală. |
| `stack` | Fișier, funcție, linie, index și cadru selectat. | Numai stack-ul primit pentru o sesiune întreruptă. Starea necolectată este explicită. |
| `variables` | Variabile locale/membri/globale/evaluate deja primite, tipuri și valori scalare. | Raportează numărul așteptat/primit și `loading`. Numerele și booleenii își păstrează tipul. Valorile complexe sunt rezumate și cer inspectarea UI extinse sau o interogare explicită; identificatorii obiectelor remote nu sunt handle-uri locale. |
| `threads` | Firele oprite în Debugger, motiv, nume și selecție. | Nu este o enumerare a tuturor firelor OS din proces. |
| `breakpoints` | Fișiere și linii ale breakpoint-urilor afișate. | Citirea nu activează sau elimină breakpoint-uri. |
| `inspector` | Obiect inspectat, handle și descriptorii proprietăților editorului. | Valorile necesare se citesc explicit cu `godot_get`; nu sunt executați în masă getterii proprietăților. |
| `selection` | Nodurile selectate și handle-urile lor. | Nu schimbă selecția. |
| `audio_buses` | Magistrale, volum, mute/solo/bypass, rutare, efecte și resursele lor; peak-uri și, cu bridge-ul nativ, starea activă a canalului. | AudioServer-ul editorului; nu reprezintă măsurarea procesului separat al jocului. |
| `animation` | Animațiile unui AnimationPlayer, pistele și cheile lor. | Player selectat sau `handle` explicit. `animation` alege clipul, `track` alege pista. Citirea nu face play, seek sau evaluarea unui AnimationTree. |

Debuggerul nativ expune sesiunea, generația, starea active/paused și proveniența
datelor. Cache-urile păstrate din sesiuni vechi nu sunt prezentate drept măsurători
noi. Variabilele nu sunt declarate colectate înainte de primirea tuturor
mesajelor așteptate pentru cadrul selectat.

## Alte panouri și pluginuri

Scene, FileSystem, Import, History, semnale/grupuri, setările proiectului/editorului,
editorul de scripturi, animațiile, shader-ele și dock-urile pluginurilor folosesc
inventarul și cititorul UI, împreună cu instrumentele existente pentru scene,
fișiere, resurse și proprietăți. Codul nesalvat dintr-un TextEdit/CodeEdit poate fi
citit direct din control. GraphEdit expune conexiunile, iar GraphNode expune
titlul, porturile și poziția. TextureRect expune resursa și dimensiunile.

Acesta nu este un decodor universal pentru datele private ale oricărui plugin.
Un control desenat custom poate avea numai metadate și copii standard lizibili.
În acel caz `contents_readable=false`/`custom_draw_data=false` este explicit;
citirea unui container gol nu dovedește lipsa conținutului. Sunt necesare un
adaptor dedicat, o proprietate/API expusă sau o captură cu un model vizual.
Panourile încă neinstantiate și datele necolectate nu sunt inventate. Captura
nu dezvăluie automat conținutul unei ferestre ascunse.

## Paginare și prospețime

Inventarul și conținutul UI folosesc snapshot-uri consistente. `next_offset`
continuă rândurile, iar `text.next_offset` continuă textul. `item`/`column`
selectează o celulă, iar `field=tooltip` citește tooltip-ul. Mutarea UI între
pagini nu schimbă datele snapshot-ului. O citire nouă fără ID produce o observație
nouă. Sunt păstrate cel mult patru snapshot-uri, cu expirare după cinci minute
fără acces; vârsta observației este vizibilă.

Limite explicite: 30.000 de noduri examinate/inventar, 10.000 de rânduri,
30.000 de celule și 32 de coloane/Tree. Valorile text au limite de patru milioane
de caractere, iar paginile text cel mult 16.000. Depășirea limitelor marchează
`partial`; inventarul poate fi restrâns prin handle. Un extras de celulă nu este
confundat cu textul complet, care poate fi cerut separat.

La scurtarea unui răspuns pentru contextul modelului, harness-ul păstrează ID-ul,
cursorii, proveniența și rândurile consecutive care au încăput. Cursorul nu sare
peste rândurile omise. Pentru text avansează numai cu caracterele livrate.
Agentul primește instrucțiuni să ceară pagini mai mici când este necesar.

Snapshot-urile reutilizate, sursele native necolectate sau din sesiuni vechi și
controalele opace nu emit dovezi noi de citire completă. Aceste instrumente emit
cel mult dovezi de inspecție; nu demonstrează singure rularea sau mecanicile unui
joc. Un Output gol nu confirmă un proiect fără erori.

## Verificare și livrare

Raportul local este în `.ai-qa/panels-20261028/report.md`. Probele upstream folosesc
controale Godot reale, grafuri, animații și snapshot-uri; adaptorul nativ lipsă
este raportat explicit. Verificarea C++ acoperă sintaxa și tipurile, nu execuția
într-un editor linkat. Fixture-ul nativ adăugat verifică toate cele nouă surse
native de bază și măsurători reale din Monitors/istoric/Profiler, inclusiv pagini
ale aceluiași cadru. Aceste probe și acceptarea pe Android necesită recompilare.
În această etapă APK-ul instalat și cel din Download nu sunt înlocuite.
