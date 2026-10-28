# Audit interfață AI — 22 octombrie 2026

## Corecții după audit — 28 octombrie 2026

Aprobarea parțială lucrează pe o copie a argumentelor. Cererea originală rămâne
în istoric și identifică replay-ul; rezultatul arată explicit hunk-urile
acceptate/refuzate și hash-urile propunerii și conținutului aprobat. Probele din
editor execută atât scrierea, cât și patch-ul, păstrând partea respinsă pe disc
și argumentele originale în memorie. Succesul autorizării nu ascunde o eroare
ulterioară a uneltei.

Runtime: **600/0**; regresie completă narrow: **662/0**; aprobări
phone_compact: **117/0**, inclusiv geometria hunk-urilor fără selecție și a
selecției parțiale. Captura completă a editorului confirmă butoanele accesibile;
captura directă a subferestrei încorporate diferă de compoziția finală. Dovezi în
`.ai-qa/fixes-20261028/`. Corectate și continuarea Responses la limita de tokeni,
bugetul comun pentru 64 de rezultate și scanarea declarațiilor din stringuri.
Acestea sunt verificări automate în editor; APK-ul și proba tactilă Android
rămân separate.

## Actualizare 28 octombrie — continuare automată și review pe hunk-uri

Un răspuns oprit la limita de ieșire a modelului continuă automat de până la
două ori. Textul și continuarea sunt topite într-un singur mesaj, cu un singur
balon, iar statusul arată modul, „răspuns tăiat” și progresul continuării
(`1/2`). Instrucțiunea internă de continuare nu apare ca mesaj de utilizator; la
epuizarea bugetului, turul se încheie ca `limited`, păstrând textul complet.

Dialogul de aprobare pentru un fișier existent arată diff-ul unificat al
scrierii propuse și câte o bifă pentru fiecare hunk, cu numărul de linii
adăugate/șterse și linia de început. Toate bifele pornesc selectate; cele
nebifate sunt reverterite la liniile originale, iar **Permite** și **Permite
mereu** rămân dezactivate cât timp nu este selectat niciun hunk. Pentru
`godot_write_file`
selecția înlocuiește textul scris; pentru `godot_apply_patch` se aplică o
înlocuire exactă peste fișierul original, astfel încât verificarea hash-ului,
copia de recuperare și jurnalul rămân active. Fișierele noi păstrează preview-ul
textual integral de dinainte.

Verificat pe Godot 4.7.2 headless: suită runtime 558/0, scenariul QA `approval`
92/0 în cele cinci layout-uri, `--check-only` pe `diff.gd`, `editor_tools.gd`,
`harness.gd` și `panel.gd`. Probele fixture acoperă bifele per hunk, blocarea
aprobării și a grantului de sesiune fără selecție, reafișarea dialogului și
executarea reală a unui patch din care un hunk este respins. Capturile sunt în
`.ai-qa/continuare-simboluri-hunks-20261028/approval/`. APK-ul și proba tactilă
rămân separate.

## Actualizare 28 octombrie — corecțiile auditului independent

Coada are acum o zonă proprie de derulare, cu înălțime limitată și spațiu
rezervat conversației și composer-ului. Proba narrow cu 20 de mesaje păstrează
501 px pentru conversație și 120 px pentru coadă; ultimul card este accesibil
prin derulare și poate fi eliminat separat. QA chat: 67/0, captura inspectată în
`.ai-qa/fix-review-20261028/chat/narrow/chat-queue-20.png`. Proba tactilă în APK
rămâne separată.

La scalarea de telefon, înălțimea este rotunjită la pixeli întregi pentru a
evita decuparea ultimului card la capătul derulării. Cardurile permit propagarea
gesturilor către zona lor de derulare.
Pe copia finală a surselor, suita completă narrow trece **638/0**, iar chat
phone_compact **68/0**. Captura telefonului, inspectată, este în
`.ai-qa/fix-review-20261028/phone/phone_compact/chat-queue-20.png`; conversația
are 188 px, coada 155 px, ultimul card și composer-ul sunt complet vizibile.

## Actualizare 28 octombrie — experiența de chat

Ultimul răspuns încheiat are acum **Undo** și **Regenerează**. Undo restaurează
fișierele prin jurnal, salvează rezumatul modificărilor, elimină răspunsul cu
promptul lui și readuce promptul, fișierele și atașamentele în composer; pentru
tururile vechi acțiunea trimite la ramificare. Regenerează restaurează la fel și
retrimite cererea. Ambele sunt blocate în timpul execuției, iar Undo refuză o
scenă al cărei istoric nativ de Undo s-a pierdut în sesiune.

Coada apare ca un panou deasupra composer-ului, cu număr, buton **Reia** când
este oprită și carduri cu mutare înapoi în composer sau scoatere. Fiecare
răspuns afișează durata fără așteptarea aprobărilor, tokenii de ieșire (marcați
„≈” când sunt estimați) și costul din tarifele salvate. Gândirea furnizorului
apare pliată, numărată în cuvinte. Căutarea în conversație numără potrivirile
din mesajele încărcate și sare între ele, iar 15 s fără ieșire arată un
avertisment de stagnare.

Verificat pe Godot 4.7.2 headless: suită runtime 531/0, scenariul QA `chat`
narrow 62/0, scenariul complet narrow 604/0, todo 88/0 și `--check-only` pe
`panel.gd`, `chat_view.gd` și `icons.gd`. Capturile sunt în
`.ai-qa/ag32-20261028/`. Regenerează nu a fost probat cu o cerere live; APK-ul și
proba tactilă rămân separate.

## Actualizare 28 octombrie — aprobări de sesiune și predarea planului

Dialogul de aprobare are un al treilea buton, **Permite mereu**, care aprobă
automat aceeași unealtă până la închiderea editorului. Verificarea lui vine după
refuzul Plan și după YOLO, deci Plan rămâne doar pentru citire; decizia apare în
jurnal ca `approved_always`. Setări → General listează uneltele aprobate și le
poate revoca pentru sesiune; starea nu se salvează pe disc.

Un card de plan propus, complet, oferă **Implementează planul** și **Ajustează**.
Implementarea trece în Auto și trimite pașii propuși, cerând un `task_update` la
executing înainte de prima modificare; ajustarea deschide Plan cu pașii în
composer. Butonul brut **Aplică planul** de pe mesaj a fost eliminat.

Verificat pe Godot 4.7.2 headless: suită runtime 531/0, scenariul QA approval
84/0 și todo 88/0, `--check-only` pe `panel.gd`, `chat_view.gd` și
`agent_jobs.gd`. Capturile și raportul independent sunt în
`.ai-qa/review-playtest-20261028/`. APK-ul și proba tactilă rămân separate.

## Actualizare 25 octombrie — panouri de diagnostic

Captura `Screenshot_20261025_203433.jpg` arată Output deschis sub chat.
În APK-ul `afcf2cb`, săgeata din dreapta jos minimizează panoul inferior,
păstrând filele disponibile. Extinderea din antetul chatului restrânge și
Output, și dock-urile laterale. Revenirea păstrează fila anterioară, mesajele,
textul din composer și poziția chatului. Dacă utilizatorul alege altă filă
între timp, alegerea sa este păstrată. Încadrarea pe lățime acoperă și
chatul central extins.

Editorul nativ compilat a trecut 458 verificări la fiecare dintre cinci
dimensiuni și 56 pentru scenariul dedicat; capturile au fost inspectate vizual.
APK-ul a fost verificat și livrat în Download. Proba tactilă pe Android rămâne
separată. Dovezi: `.ai-qa/afcf2cb-native/`, `.ai-qa/delivery-afcf2cb.json`.

## Auditul inițial — 22 octombrie

Captura de referință: `Screenshot_20261022_200421.jpg`. Dock-ul stâng tăia
Setări și Trimite, iar Șterge impunea arhivarea fără să indice această condiție.

## Corecții

- Dock-ul stâng folosește coloana exterioară. Chatul ocupă zona reală a tabului,
  cu margini și înălțime recalculate după mutare, redimensionare și extindere.
  Limita se aplică și în dreapta. Vizibilitatea celorlalte coloane se restabilește
  la revenirea în centru; adaptarea la ecrane înguste rămâne temporară.
- Selectorii se dimensionează după spațiul alocat chatului. Bara de control
  trece pe rânduri suplimentare când nu încape; ultimul rând se aliniază la dreapta.
  Mesajul de întâmpinare se încadrează pe mai multe rânduri.
- Pe lățimi sub 900 unități, Istoric ocupă pagina chatului. Înapoi readuce chatul;
  selectarea sau crearea unei conversații închide istoricul compact. Redimensionarea
  respectă alegerea utilizatorului privind istoricul.
- Șterge confirmă numele conversației și funcționează pentru conversații normale
  sau arhivate. Anularea păstrează fișierul și indexul. Confirmarea activează o
  conversație rămasă; dacă a fost ultima, creează una goală.
- Transcriptul este păstrat temporar până la salvarea indexului; o eroare de
  scriere reface starea anterioară. La pornire se recuperează un transcript
  intermediar încă referit de index. Crearea eșuată nu înlocuiește chatul activ.
- Exportă deschide un dialog de salvare `.md`, cu titlul și mesajele conversației
  curente. Copierea unui răspuns rămâne o acțiune separată.
- Arhivează/Dezarhivează păstrează conversația selectată și schimbă lista corectă.
  Favoritele descriu acțiunea inversă. Un filtru fără conversația activă dezactivează
  acțiunile istoricului. Execuția agentului dezactivează acțiunile indisponibile.
- Redenumirea elimină spațiile marginale, refuză un nume gol și acceptă Enter.
- Ciornele și referințele sunt separate pe conversații în sesiunea editorului.
  Nu sunt prezentate drept ciorne persistente după închiderea aplicației.
- Ramificarea refuză un ID de mesaj expirat. Un plan propus complet oferă
  Implementează planul (Auto, cu pașii propuși) și Ajustează (Plan, cu pașii în
  composer); cardurile de execuție nu afișează aceste acțiuni. Modificări/Undo
  este dezactivat dacă răspunsul nu are modificări; Copiază este dezactivat
  pentru un răspuns fără text.

- Listele de profiluri și rezultate păstrează selecția după ID, inclusiv după
  actualizare sau reordonare. Rezultatul nou este selectat după trimitere.
- Acțiunile din setări care cer un profil, rezultat sau skill salvat sunt
  dezactivate până există selecția necesară. Previzualizare și Import cer un
  fișier finalizat și descărcat; Actualizează cere profilul conectat.

## Contracte verificate

| Control | Efect verificat în fixture izolat |
| --- | --- |
| Nou / deschide conversație | transcript păstrat, ciornă nouă goală, ciorna originală restaurată |
| Favorite | adăugare și eliminare, tooltip actualizat |
| Redenumește | anulare, nume gol refuzat, Enter, titlu actualizat |
| Exportă | fișier Markdown real cu titlu și mesaje |
| Arhivează / Dezarhivează | liste separate, selecție și acțiune inversă |
| Caută | conversații filtrate, acțiuni inactive pentru listă fără selecție |
| Șterge | nume în confirmare, anulare intactă, ștergere pe disc, index redeschis |
| Copiază răspuns | conținutul răspunsului ales în clipboard |
| Ramifică de aici | capătul corect al ramurii, originalul complet pe disc |
| Rezultate generate | selecție stabilă, preview cu pixeli reali, stări pending/completed |
| Șterge profil generare | profil eliminat, fișiere generate păstrate, acțiuni actualizate |
| Acțiuni setări | fără selecție și în timpul execuției sunt dezactivate |
| Setări / Închide | fereastra se deschide și se închide efectiv |
| Istoric / Înapoi | pagini alternative în dock îngust, fără lărgirea coloanei |
| Extinde / restrânge | centru și întoarcere la dock, preferință păstrată |
| Stop | vizibil lângă Trimite în timpul lucrului; anulează transcrierea fixture |
| Model / reasoning / mod | sertare, Înapoi/anulare, alegere atomică și niveluri ale modelului |
| Atașamente / Pin / Menționează / Trimite | suita de regresie pentru fișiere, preview și coadă |
| Imagini / 3D / diff / Store | suitele existente verifică starea reală în editorul izolat |

Verificarea încadrării include fiecare selector și controalele Setări, Extinde,
Context, Dictare, Stop și Trimite în ambele dock-uri limitate la 224 unități,
cu context de 100% și transcriere activă. Verificarea folosește dreptunghiurile
chatului și ale tabului, nu doar marginea ferestrei.

## Dovezi și limite

- Runtime local: **302 aserțiuni, zero eșecuri**,
  `.ai-qa/dock-audit-unit-final.log`. Include probe pentru erori de salvare,
  ștergerea ultimei conversații și recuperarea după întrerupere.
- Sintaxă C++ Android verificată pentru `ai_assistant_editor.cpp`.
- Editor upstream: 279 verificări fără eșecuri pe desktop și fereastră îngustă;
  după corectarea înălțimii barei, 279 fără eșecuri și pe fereastra mare
  (`.ai-qa/dock-audit-final/`, `.ai-qa/dock-audit-wrap-height/`).
- Dock-uri: **64 verificări × 5 dimensiuni**, zero eșecuri
  (`.ai-qa/dock-audit-responsive/`), cu capturi inspectate.
- Butoane setări: **286 verificări** fără eșecuri pe ecran compact la 150%
  (`.ai-qa/ui-settings-actions/`), inclusiv preview imagine real și păstrarea
  selecției la reordonare.
- `09103e8` a trecut workflow-ul `39833659749`: 297 aserțiuni runtime,
  286 verificări × 5 upstream și 296 × 5 în editor nativ. Inspecția capturii
  native compacte a arătat totuși suprapunerea coloanei 3D peste chat; acest
  pachet nu a fost livrat.
- Corecția suplimentară limitează coloana centrală la lățimea rămasă, urmărește
  modificarea coloanelor și restabilește limitele la revenirea în centru.
  Testele verifică și suprapunerea cu viewport-ul 3D și cu fiecare coloană
  vizibilă; capturile forțează o randare curentă și includ geometria în JSON.
  Proba locală compactă: 82 verificări fără eșecuri înainte de noul build
  (`.ai-qa/dock-center-bounds/`). Download conține încă pachetul anterior.
- Butoanele care depind de microfon, autentificare, provideri, servicii de generare,
  servere MCP și catalogul public Store necesită separat verificare cu dispozitivul
  sau serviciul real. Fixture-urile nu confirmă un cont sau serviciu live.


## Validare finală a surselor `2538551`

Workflow [39835516663](https://github.com/JDscript1/godot-ai-android/actions/runs/39835516663)
încheiat cu succes: runtime, native-editor și Android.

- Runtime CI: 297 aserțiuni fără eșecuri; local 302, inclusiv cinci probe Blender.
- Editor upstream: 305 verificări × 5 dimensiuni, zero eșecuri.
- Editor nativ: 315 verificări × 5 dimensiuni, zero eșecuri.
- Revalidare locală a dock-urilor: 83 verificări × 5 dimensiuni, zero eșecuri.
- Trei teste de livrare, regresia timestamp și nouă teste companion au trecut;
  build-ul TypeScript a trecut în CI.
- Inspectate capturile native `phone_compact/dock-left.png` și
  `phone_landscape/dock-left.png`: întregul chat și controalele sunt vizibile,
  iar viewport-ul 3D nu se suprapune peste el.

Dovezi: `.ai-qa/dock-center-responsive/`, `.ai-qa/2538551-native-ci/`,
`.ai-qa/2538551-runtime-ci.log`, `.ai-qa/2538551-native-ci.log`.
APK-ul final este verificat și livrat la `Download/Godot-AI-Android-arm64-debug.apk`,
22.10.2026, 21:11:14 CEST; 145,157,425 bytes, semnătură persistentă și
25 surse încorporate verificate. În Download există un singur installer al fork-ului.
Validarea fizică Android și serviciile live rămân separate.
