# Audit interfață AI — 22 octombrie 2026

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
- Ramificarea refuză un ID de mesaj expirat. Aplică planul trimite textul planului
  ales. Modificări/Undo este dezactivat dacă răspunsul nu are modificări;
  Copiază este dezactivat pentru un răspuns fără text.

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
