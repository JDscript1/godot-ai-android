# Rotirea preview-ului și regulile imaginilor

Actualizat: 24.10.2026. Modificări în surse, după APK-ul `36457dd`.

## Previzualizarea 3D

Chatul și secțiunea Generare folosesc același viewer interactiv. Generare folosea
anterior un viewport static, fără tratarea gesturilor; această cale a fost
înlocuită. Imaginile din Generare folosesc de asemenea canvas-ul comun.

Navigarea are un strat GUI propriu deasupra SubViewport-ului; inputul scenei
randate este dezactivat. Trage cu un deget sau cu mouse-ul pentru orbitare pe
orizontală și verticală. Două degete controlează zoom-ul și deplasarea. Roata
mouse-ului controlează zoom-ul. Cele patru butoane din colț permit rotirea
stânga/dreapta/sus/jos. Săgețile tastaturii rotesc, iar Home reface încadrarea.

Sensibilitatea ține cont de scalarea editorului. Ascunderea ferestrei sau
pierderea focusului eliberează gesturile active. Mișcarea afectează camera de
previzualizare; fișierul GLB și transformările proiectului nu se modifică.

Testul anterior apela `_orbit()` direct. Proba introdusă acum trimite evenimente
touch și mouse prin fereastra reală și verifică transformarea camerei. În
editorul Linux, gestul touch al viewer-ului din chat funcționa și înaintea
schimbării. Preview-ul static din Generare nu avea însă controale, conform
sursei. Noua probă trimite gesturi și prin fereastra setărilor, pentru un GLB
generat, și verifică schimbarea ambelor unghiuri. Folosirea pe Android fizic
rămâne de verificat în APK-ul care va include aceste surse.

## Utilizarea imaginilor

`asset_generate` primește `purpose` și `background`. Opțiunile sunt transmise
separat de promptul utilizatorului, în metadatele sarcinii, și nu schimbă
destinația sau formatul preferat al mesh-ului.

| Utilizare | Reguli adăugate cererii | Fundal implicit |
| --- | --- | --- |
| `reference_3d` | Un obiect complet, izolat, cu margini libere și volum lizibil; fără decor, podea, soclu, umbră proiectată sau colaj, în lipsa unei cereri explicite | Transparent |
| `sprite` | Artă de joc 2D, siluetă lizibilă; păstrează stilul, direcția, numărul de cadre și aranjarea cerute | Transparent |
| `texture` | Suprafață plană, ortografică, repetabilă; fără obiect pus în scenă sau perspectivă | Opac |
| `background` | Compoziție completă pentru decor; păstrează mediul | Opac |
| `generic` | Ilustrație obișnuită, fără reguli suplimentare de decupare | Alegerea furnizorului |

Un `background` explicit are prioritate. Parametrii pentru imagini sunt refuzați
pe un profil de mesh dacă sunt diferiți de valorile generale implicite.
În generarea manuală, opțiunile apar numai pentru rezultatele de tip imagine.

Promptul original rămâne sursa numelui fișierului. Cererea completată cu reguli
este salvată separat ca `generation_prompt`. ComfyUI necesită legarea nodului de
prompt pentru a aplica aceste reguli unui workflow cu utilizare specifică.

## Transparență și eliminarea fundalului

Formatul PNG sau un canal RGBA nu confirmă existența unor pixeli transparenți.
La descărcare, `quality` verifică alfa real și existența unui conținut vizibil.
O imagine opacă pentru care s-a cerut transparență rămâne salvată și accesibilă,
dar are `quality.ready_for_use = false` și o explicație. Lista rezultatelor
afișează „Necesită verificare”. Un fișier complet transparent este de asemenea
respins ca resursă utilizabilă.

Înaintea conversiei 3D, o referință generată și recunoscută în registrul
sarcinilor este recitită și verificată conform fundalului cerut. Un rezultat
necorespunzător blochează trimiterea conversiei către furnizor. Imaginile
existente ale utilizatorului nu primesc automat această regulă de cutout.

`asset_remove_background` folosește un profil Runware salvat și cererea nativă
`removeBackground`, cu modelul `runware:109@1`, rezultat PNG și alfa transparent.
Este o operație separată, cu cost la furnizor și aceleași reguli de plan și
permisiune ca generarea. Are propriul UUID și checkpoint înainte de POST;
`asset_wait` și `asset_status` urmăresc aceeași sarcină. Harness-ul principal
deduplică repetarea aceleiași cereri în turnul curent, inclusiv la reluare.
Adaptorul nativ reutilizează și sarcina existentă pentru același hash al imaginii,
profil și utilizare, inclusiv când referința este calea importată în locul copiei
din cache. Conținutul modificat este o intrare distinctă.

Originalul este păstrat. Rezultatul decupat primește propriul folder și un nume
derivat din obiectul inițial, cu sufixul `cutout`. La reluare se recuperează
sarcina existentă. Lipsa confirmării este tratată ca trimitere neconfirmată;
nu se retrimite automat. Nicio eliminare de fundal nu este declanșată automat
de verificarea PNG-ului; agentul folosește tool-ul explicit.

În viewer, carourile sunt desenate de interfață numai când imaginea are alfa
real. Ele nu se scriu în imagine și nu apar în exportul zonei selectate.

Verificarea locală a alfa nu certifică identitatea obiectului, încadrarea,
perspectiva sau calitatea segmentării. Agentul trebuie să examineze rezultatul
și să semnaleze limitările modelului vizual. Parametrii de transparență nu sunt
inventați pentru alte modele sau servicii, iar lipsa unui profil de eliminare
a fundalului este raportată ca blocaj.

Surse API: [Runware RemBG](https://runware.ai/docs/models/rembg-v1-4/examples),
[formate cu alfa](https://runware.ai/docs/models/birefnet-general).

## Verificări

Probele folosesc editorul Linux ARM64 prin proot/Xvfb și un server HTTP local
determinist. Nu se folosesc chei reale sau generări plătite. Capturile și
rapoartele finale ale editorului sunt în `.ai-qa/mesh-image-contract-verified/`.
Au trecut **363 verificări pentru fiecare dintre cele cinci configurații**,
fără eșecuri. Proba dedicată preview-ului a fost repetată pe desktop cu
**60 verificări, zero eșecuri**, în `.ai-qa/mesh-preview-capture/`.
Suita runtime finală are **413 aserțiuni, zero eșecuri**, în
`.ai-qa/mesh-image-contract-runtime-final.log`. Proba include și reutilizarea
aceleiași eliminări de fundal prin aliasul importat al imaginii, fără un POST nou.

Au fost inspectate capturile viewer-ului pe desktop, în format îngust și cu
scalare pentru telefon. Captura din setările Generare poate include dialogul
de import al editorului upstream; probele de input verifică separat schimbarea
camerei. Nu este o captură de pe dispozitivul Android.

Rulările intermediare care au identificat marginile butoanelor și au precedat
unificarea viewer-ului sunt păstrate separat; ele nu reprezintă validarea finală.
Inclusiv directorul `mesh-image-contract-final/` este o rundă intermediară;
raportul final al acestei etape folosește sufixul `-verified`.

Această etapă nu compilează și nu înlocuiește APK-ul din Download. Rezultatele
unui serviciu plătit și gesturile pe Android fizic sunt probe separate.
