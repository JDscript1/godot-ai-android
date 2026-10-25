# Fișiere în chat, preview și control vizual al editorului

Data: 23.10.2026. **Inclus în APK `13456af`; verificările și livrarea sunt urmărite
în PROGRES_SI_PLAN.md.** Documentul păstrează cerințele aprobate și
limitele implementării. Nu adaugă o pagină duplicată în Integrări.

## Actualizare în surse — 25.10.2026

Descărcarea unei generări finalizate înregistrează automat fișierul și păstrează
cardul în conversație, inclusiv după reîncărcare. `file_preview` îi permite
agentului să deschidă direct previzualizatorul Godot; `file_observe` inspectează
în fundal. Pentru GLB/glTF, ambele folosesc rendererul nativ și nu cer Blender
CLI. Confirmarea deschiderii verifică rezultatul încărcării. Exporturile
FBX/BLEND păstrează originalul GLB pentru preview; această actualizare nu
adaugă un cititor nativ al acelor formate. Verificat cu un GLB real și pixeli
randați în fixture. **Actualizarea nu este încă în APK-ul din Download.**

## Implementarea acestei etape

| Componentă | Implementare |
| --- | --- |
| Fișiere | `file_registry.gd`: versiuni după SHA, dependențe glTF, scope pe conversație, căutare, catalog și pin |
| Chat | Carduri cu miniaturi, swipe și apăsare lungă, mențiuni, trimitere/coadă, restaurare și ramificare |
| Imagini | `media_view.gd`: galerie, pinch zoom/pan, crop/săgeți și comparație cu zoom comun |
| 3D | `model_preview.gd`: GLB/glTF, orbită/pan/zoom, materiale/wireframe, grilă/lumină/animație, trei vederi offscreen cached |
| Editor | `editor_control.gd`: captură de fereastră/control/viewport, frame unic, layout/expirare, input și preluare manuală |
| Punte nativă | Inputul editorului actualizează hover-ul din coordonatele capturate; API-ul existent `Viewport.push_input` rămâne compatibil |
| Store | `store.gd`: protocol v1, versiuni compatibile, preflight ZIP, staging, instalator nativ, activare și manifest pentru dezinstalare |
| Modificări | `diff.gd`: Myers limitat, hunks și totaluri reale; propuneri dry-run separate, scene cu operații Undo |

Dock-ul păstrează chatul în lățimea ferestrei. Când spațiul este insuficient,
panourile secundare se pliază temporar și revin la poziția centrală sau după
mărirea ferestrei.

Runtime-ul direct rămâne în Godot; nu cere Termux, Python, Node sau shell pe
telefon. Fișierele alese explicit și folderele accesibile sunt citite prin
FileAccess/DirAccess. APK-ul are deja permisiunea de acces general la stocare;
utilizatorul trebuie să o acorde în Android. Integrarea dedicată MediaStore și
persistența URI-urilor SAF nu sunt implementate în această etapă.

Limite explicite: 6 fișiere/mesaj, 4 imagini în context, 512 MB cache local,
128 MB/fișier (100 MB pentru GLB), 32 MB/imagine, 24 megapixeli pentru preview. Preview-ul 3D
acceptă cel mult 5.000 noduri, un milion de triunghiuri și aproximativ 256 MB
pentru texturi. Importul nativ GLTFDocument este sincron; Stop este verificat
înainte/după import și între randări. Nu promitem anularea importului la mijloc.
Scenelor inactive li se eliberează resursele la închiderea viewerului.

Backend-ul de captură operează Godot, inclusiv ferestrele sale; MediaProjection,
controlul altor aplicații și preview-ul direct OBJ/FBX sunt extensii separate.
Exporturile OBJ/STL/PLY/glTF și conversiile furnizorilor FBX/USDZ/3MF/BLEND sunt
descrise separat în [generare/export](AI_GENERATION.md); preview-ul păstrează GLB/glTF.
Unele cataloage omit modalitățile de intrare. În Furnizori → Opțiuni avansate,
utilizatorul poate selecta modelul și alege Din catalog / Permite imagini / Doar
text; alegerea este separată pentru fiecare model și se salvează cu profilul.
Aplicația nu deduce vision din numele modelului.

Pachetele Store cu GDExtension pot fi instalate când manifestul referă un binar
Android ARM64 prezent în arhivă, cu antet ELF AArch64 valid. Activarea rămâne
separată, iar încărcarea efectivă se verifică în Output/Debugger.
Dezinstalarea folosește și puntea nativă pentru cache-ul GDScript;
editorul upstream raportează explicit lipsa acesteia. API-ul public a returnat
Terrain3D în căutarea live; parserul folosește acum identitatea `publisher/slug`
și adresele publice corecte. Arhiva oficială Terrain3D v1.0.2 a trecut
preflight-ul și s-a instalat într-un proiect temporar al editorului de test.
Încărcarea/activarea addonului pe Android necesită încă o probă pe dispozitiv.

## Baza existentă înainte de această etapă


- `runtime/chat_view.gd`: miniaturi PNG în mesajele cu attachments și chip-uri
  pentru imaginile/referințele pregătite de utilizator. Miniaturile nu deschid
  încă un viewer complet și nu au swipe-to-mention.
- `runtime/panel.gd`: atașare manuală de imagini, coadă cu selecții proprii,
  istoric și preview pentru joburi de generare. Preview-ul GLB folosește
  GLTFDocument și SubViewport, în pagina Generare, fără un viewer universal.
- `runtime/agent_jobs.gd` și `ai_runtime_bridge.cpp`: captură din jocul pornit,
  inspectare runtime și input limitat, inclusiv eliberarea tastelor la oprire.
  Acest mecanism nu capturează automat toate ferestrele editorului/dispozitivului.
- `runtime/editor_tools.gd`: `godot_ui_tree` și `godot_ui_action` descoperă și
  operează controale ale editorului. Acțiunile existente sunt press, text, select,
  popup, menu și focus; nu reprezintă control universal al tuturor pluginurilor.
- Există jurnal de fișiere, recuperare și afișarea modificărilor pe tură.
  `diff_turn()` afișează în prezent toate liniile versiunii vechi cu minus și
  toate liniile versiunii curente cu plus. Nu este un diff minimal și nu trebuie
  folosit pentru statistici reale de linii adăugate/șterse.
- Editorul conține deja Asset Store și instalatorul său nativ. Agentul nu are
  un adaptor dedicat, complet, pentru căutare → instalare → activare → verificare.
- APK-ul editorului declară MANAGE_EXTERNAL_STORAGE; accesul efectiv depinde
  de aprobarea și disponibilitatea permisiunii pe dispozitiv. Declararea nu
  echivalează cu acces deja acordat sau cu o unealtă de căutare pentru agent.

## 1. Fișiere găsite de agent și carduri în conversație

La „am făcut un screenshot”, agentul caută în sursele de stocare disponibile
și prezintă un grup mic de rezultate recente. Fiecare card arată miniatura,
numele, data și sursa. Utilizatorul poate confirma vizual care rezultat este
relevant. Nu se presupune că primul fișier găsit este întotdeauna cel corect.

- Registru comun de atașamente pentru rezultate ale agentului, fișiere alese de
  utilizator, rezultate de generare și capturi ale editorului/jocului.
- Identificator stabil, tip MIME, dimensiune, origine, revizie/hash, locație sau
  URI, stare de acces și referință la miniatură. Textul vizibil nu este identitatea.
- Fișierele mari rămân pe disc; istoricul salvează referințe și cache controlat,
  fără repetarea binarelor/base64 în fiecare mesaj sau checkpoint.
- Fișierele originale sunt păstrate. O copie capturată pentru context și fișierul
  sursă sunt versiuni distincte; cardul indică dacă sursa s-a schimbat/dispare.
- Android: folosirea accesului deja acordat, MediaStore pentru imagini și
  document providers/SAF pentru fișiere/foldere selectate. Lipsa accesului se
  raportează; unealta nu declară rezultate din foldere pe care nu le poate citi.
- Căutare după dată, tip și nume; listare paginată și generare leneșă de miniaturi.
  Se evită scanarea întregii stocări la fiecare mesaj.

## 2. Mențiuni prin gesturi

- Swipe spre dreapta pe card adaugă referința în composer, cu miniatură și ×.
  Nu șterge textul deja scris și permite menționarea mai multor fișiere.
- Acțiunea explicită „Trimite referința” poate trimite imediat fișierul ales.
  Gestul implicit pregătește mesajul, pentru a evita trimiterea accidentală în
  timpul derulării. Aceleași acțiuni sunt disponibile prin apăsare lungă/buton.
- Prag de gest și separare între mișcare orizontală și verticală; feedback vizual
  și, opțional, haptic. Zoom/pan în viewer nu activează gestul din conversație.
- Referința se rezolvă la atașamentul și revizia alese, inclusiv după schimbarea
  modelului, coadă, restart și restaurarea conversației. Fișierele din altă
  conversație nu devin implicit parte din context.

## 3. Viewer de imagini

- Apăsare pe miniatură: viewer pe suprafața disponibilă completă, cu zonele
  sigure Android respectate, pinch zoom, pan și dublă apăsare pentru fit/100%.
- Galerie pentru imaginile aceluiași grup, nume și dimensiuni disponibile discret.
- Înapoi închide viewerul și păstrează poziția chatului, mesajul și atașamentele.
- Acțiuni: menționează, crop, marchează o zonă/săgeată și păstrează originalul.
- Selecția unui crop poate fi trimisă modelului fără a retransmite mereu imaginea
  integrală. Cache-ul local și trimiterea către furnizor sunt operații distincte.
- PNG/JPEG/WebP în prima etapă; alte formate sunt declarate separat, fără preview
  fals pentru un tip pe care decodorul nu îl poate încărca.

## 4. Preview 3D comun pentru chat și agent

Prima etapă: GLB și glTF 2.0 cu dependențele rezolvate. OBJ/FBX urmează numai
cu un importator verificat în build-ul folosit. Fișierele .blend necesită
conversie prin Blender pe desktop sau un flux extern opțional; nu se pretinde
că APK-ul Android conține Blender.

- Card cu randare statică și nume; încărcarea scenei interactive începe la apăsare.
- Viewer cu orbită, pinch zoom, pan, încadrare automată, reset și vederi standard.
- Moduri: materiale, wireframe dacă suportă backend-ul, lumină și grilă.
  Afișare discretă a geometriei, materialelor, texturilor și animațiilor detectate.
- Serviciu unic bazat pe GLTFDocument/SubViewport pentru randare interactivă și
  randare offscreen. Pentru agent: 3–6 unghiuri și metadate, fără popup vizibil.
- „În fundal” înseamnă fără deschiderea viewerului, în aplicația activă. Nu
  garantează randare continuă când Android suspendă aplicația.
- Randarea și manipularea scenei respectă cerințele thread-ului principal Godot;
  încărcarea grea este programată, anulabilă și limitată ca memorie/rezoluție.
- Preview-ul este separat de scena proiectului și nu rulează scripturile unei
  scene atașate. Nu este prezentat drept sandbox complet de proces.
- Rezultatele randării sunt cached după hash, unghi și preset. Limite interne,
  o coadă de lucrări și oprirea randării inactive protejează dispozitivul mobil.
- Modelul primește imagini numai dacă suportă vision. Un model numai text primește
  metadate; aplicația nu pretinde că acesta a văzut obiectul și nu schimbă
  furnizorul fără alegerea utilizatorului.

## 5. Capturi și operarea editorului

Extindem uneltele semantice existente, cu o punte C++ pentru operațiile interne
neexpuse și input ca alternativă pentru suprafețe care nu au controale semantice.

- Captură cu țintă explicită: editor, dialog/popup Godot, viewport 2D/3D, joc,
  control sau dreptunghi. Rezultatul păstrează fereastra, scara și momentul.
- Observe → action → wait for state → observe, cu dovada rezultatului; fără
  raportarea succesului doar pentru că evenimentul de click a fost trimis.
- Identități de controale și stare vizibil/activ; input cu coordonate numai
  pentru fereastra/versiunea de layout observată. Țintele vechi se redescoperă.
- Tastare, combinații, click, drag, scroll și touch unde sunt aplicabile.
  Stop și preluarea controlului de către utilizator eliberează toate tastele.
- Capturile și inputul păstrează delimitarea editor vs joc vs sistem.
  Controalele desenate personalizat ale unui plugin pot necesita adaptor dedicat.
- Captura întregului dispozitiv sau a altei aplicații pe Android este un flux
  separat MediaProjection, cu dialogul de consimțământ al sistemului. YOLO nu
  înlocuiește această cerință. Nici acest API nu oferă automat control de input
  asupra altor aplicații.
- Plan permite inspecția; modificările, inputul cu efecte și operațiile externe
  respectă regulile de permisiuni existente. Nu se introduc confirmări duplicate.

## 6. Asset Store și pluginuri

- Adaptor pentru protocolul Asset Store folosit de această versiune a editorului,
  conectat cu instalatorul nativ, nu cu endpointuri legacy presupuse.
- Căutare, filtrare, descriere, autor, versiune, licență, compatibilitate și
  fișiere propuse, prezentate într-un card compact în chat.
- Descărcare, validare arhivă/căi, verificare hash dacă este furnizat de sursă,
  detectare conflicte, instalare și urmărire progres/anulare.
- Instalarea și activarea sunt pași distincți. Agentul verifică rescanarea,
  activarea, erorile și necesitatea restartului; simpla descărcare nu înseamnă
  plugin funcțional. Pachetele native trebuie să suporte arhitectura/platforma.
- Operațiile au același control YOLO/Plan ca restul uneltelor. Restaurarea se
  limitează la fișierele instalate urmărite, fără ștergerea editărilor utilizatorului.
- UI rămâne în Asset Store/chat; nu se reintroduc scurtături duplicate în Integrări.

## 7. Sneak peek al modificărilor

Un card actualizat pe tură, cu un rând pe fișier, de exemplu:

```
player.gd     +18  −4      Aplicat
hud.tscn      +12  −2      Aplicat
```

- Diff real pe linii, cu hunks și context, nu întreaga versiune veche ștearsă și
  cea nouă adăugată. Pentru fișiere mari, calculele sunt limitate/anulabile.
- Contoarele folosesc starea inițială și starea curentă a aceleiași ture;
  editările repetate ale fișierului nu dublează artificial totalurile.
- Stări Propus / Aplicat / Restaurat / Conflict. Drafturile și dry-run nu sunt
  numărate ca fișiere deja modificate. Modificările nesalvate au stare explicită.
- Apăsare: diff colorat, navigare la linie și recuperare cu verificarea conflictelor.
- Operațiile de scenă afișează noduri/proprietăți modificate; fișierele binare
  afișează tip/dimensiune, fără numere de linii inventate.

## Îmbunătățiri suplimentare recomandate

1. Atașamente și răspunsuri legate prin ID, cu selecție multiplă și anularea gestului.
2. Comparație între două imagini sau două versiuni de model, inclusiv cameră comună.
3. Crop și adnotare pentru „repară zona aceasta”, păstrând coordonatele originalului.
4. Căutare a fișierelor deja discutate și reutilizare fără atașare repetată.
5. Pin pentru referințele proiectului; excludere explicită din context când nu mai
   sunt necesare. „Doar afișare” este diferit de „trimis modelului”.
6. Estimarea contextului pentru imagini și limitarea unghiurilor 3D trimise simultan.
7. Preview leneș, miniaturi persistente și închiderea scenelor 3D inactive.
8. Mesaje scurte cu dovada vizuală și rezultat, fără catalog de funcții la un salut.
9. Layout verificat și în dock îngust, cu tastatură și safe areas: capturile fizice
   din 22.10 arată decupare în dreapta, care nu trebuie propagată în noile viewers.
10. Alternative la gesturi și suport pentru atingere, tastatură și mouse.

## Ordine de implementare și criterii de acceptare

1. Registru atașamente + căutare locală + carduri. La „am făcut două screenshot-uri”,
   apar cele două rezultate corecte cu miniaturi și sursă verificabilă.
2. Viewer imagini + mențiuni. Swipe pe a doua imagine → referință corectă în
   mesaj → analiză a acelei imagini; Back păstrează draftul și poziția conversației.
3. Diff real + carduri compacte. Un test cu editări repetate, dry-run, revert și
   schimbare manuală dovedește totaluri și stări corecte.
4. Viewer GLB/glTF + observare offscreen. Utilizatorul și agentul inspectează
   aceeași revizie; sunt verificate materialele, încadrarea, lipsa texturilor,
   fișier corupt/mare, anulare și memoria eliberată.
5. Capturi editor + extinderea inputului. Sunt verificate ferestre, popupuri,
   schimbarea scalei, ținte expirate, Stop și revenirea controlului manual.
6. Asset Store. Se validează un addon real compatibil, instalare/activare și
   verificare după rescanare; conflictele și incompatibilitățile au rezultate clare.

Pentru fiecare etapă: teste relevante, randare cu surse reale, verificări în
fork recompilat și validare fizică Android distinctă. Testele cu fixture nu
țin loc de acces real la stocare, furnizor vision sau instalare reală de addon.

## Surse tehnice

- https://developer.android.com/training/data-storage/shared/media
- https://developer.android.com/training/data-storage/shared/documents-files
- https://developer.android.com/media/grow/media-projection
- https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html
- https://docs.godotengine.org/en/stable/classes/class_subviewport.html
- https://docs.godotengine.org/en/stable/classes/class_editorinterface.html
- https://docs.godotengine.org/en/stable/classes/class_input.html
