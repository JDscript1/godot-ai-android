# Afișarea conversației în Godot AI

Implementare nativă GDScript; actualizat 7 noiembrie 2026. Se aplică panoului
agentului Godot AI. Interfața oficială din tabul Ziva rămâne independentă.

## Referință vizuală Ziva — 6 noiembrie 2026

Comparația folosește [captura oficială din pagina Ziva](https://ziva.sh/)
(`hero-img.0nqz82eb5mpe9.webp`) și widgeturile reale ale chatului nostru.
În exemplul public, actualizările scurte, operațiile discrete și răspunsul
final apar într-un flux continuu. Detaliile operațiilor sunt expandabile, iar
rezultatul spune ce s-a schimbat, ce a fost verificat și cum se încearcă jocul.
Aceasta este o referință de prezentare, nu o probă a sesiunii Ziva instalate.

Adaptarea nativă păstrează identitatea și stările agentului nostru:

- Uneltele reușite sau în lucru apar ca rânduri fără chenar. Săgeata arată
  starea extins/restrâns; antetul include fișierul din rezultatul uneltei,
  când acesta există, iar tooltip-ul păstrează calea completă.
- Erorile și rezultatele neconfirmate păstrează fundalul de atenție și
  deschiderea automată a detaliilor. Succesul nu devine dovadă de gameplay.
- Textul are font de 15 unități editor, aceeași mărime pentru bold/italic,
  contrast clar și spațiu distinct între paragrafe. Scalarea editorului este
  aplicată în continuare.
- Acțiunile și metadatele sunt într-un footer comun, care trece automat pe
  alt rând când spațiul disponibil nu ajunge.
- Instrucțiunile agentului cer un rezultat direct, progres numai la constatări
  utile, liste doar când ajută, verificări reale și o indicație de încercare
  când e cazul. Șablonul obligatoriu de trei bullet-uri a fost înlocuit cu
  paragrafe naturale; jurnalele și sursele deja modificate nu se repetă în chat.

Captura `chat-response-ziva-style.png` este un exemplu UI etichetat explicit,
cu rezultate deterministe. Nu confirmă un joc construit sau un răspuns de la
un model real. Referința, capturile și rapoartele sunt păstrate în
`.ai-qa/ziva-chat-style-20261106/`. Modificările sunt incluse în APK-ul Ziva
`65a99a4`, verificat și livrat în Download pe 6 noiembrie. Identitatea de
semnare și cele 44 de surse runtime au fost verificate în noul artefact.

## Mesaje și sarcini

Conversația este plată, fără carduri sau bule: mesajele utilizatorului sunt
text aliniat la dreapta, etichetat discret „Tu”, iar răspunsurile agentului
folosesc text liber, cu lățimea adaptată spațiului disponibil și un singur
antet pentru intervențiile consecutive ale aceleiași sarcini. Doar câmpul de
compunere păstrează o suprafață proprie, discretă.


O sarcină afișează, în ordine cronologică:

1. Identitatea agentului și starea răspunsului.
2. Toate actualizările asistentului, inclusiv explicațiile dintre unelte.
3. Fiecare apel de unealtă inline, cu stare, durată și detalii la cerere.
4. Răspunsul curent sau rezultatul final.
5. Cardurile fișierelor, fără duplicate în același grup.
6. Un singur set principal de acțiuni și metadatele de consum.

Deasupra câmpului de mesaj, bara de activitate restrânsă ocupă un singur rând
cu starea curentă sau unealta în lucru și numărul operațiilor efective. Nu
repetă ultimele evenimente deja afișate în conversație. Extinderea dezvăluie
feed-ul complet, cu maximum 30 de evenimente, deasupra pașilor planului. Feed-ul
este tranzitoriu: după terminare, panoul se ascunde dacă nu mai există pași
sau sarcini persistente. Nu este afișat raționamentul privat al modelului.

Intervenția utilizatorului întrerupe gruparea vizuală, chiar dacă este Steer
în aceeași sarcină. Mesajele vechi nu sunt mutate după intervenție. Consumul
cumulat apare pe ultimul segment al sarcinii. Istoricul original al mesajelor
și relațiile dintre apeluri și rezultate rămân păstrate.

Stările **Rezultat**, **Întrerupt**, **Blocat**, **Eșuat** și **Necesită verificare**
sunt distincte. „Rezultat” descrie încheierea rulării, fără să pretindă că
gameplay-ul a fost verificat; criteriile și dovezile existente rămân separate.
Publicarea unei stări terminale oprește și indicatorul de lucru al aceleiași
cereri. Un rezultat întârziat al unei cereri vechi nu oprește cererea nouă.
Mesajele utilizatorului sunt măsurate cu fontul și mărimea folosite efectiv
la randare; mesajele lungi rămân limitate la lățimea conversației. Antetele
uneltelor omit separatorul de fișier când calea este doar `res://`.

## Spațiu fix, blocare și erori

Chatul rămâne pe loc când o scenă pornește: ecranele principale AI Assistant
și Ziva nu lasă editorul să deschidă automat Output sau Debugger-ul la rulare.
Erorile raportate de Debugger apar ca un indicator compact în antet
(„1 eroare”/„N erori”); până la prima citire folosește culoarea de atenție.
Atingerea lui deschide Debugger-ul direct pe tabul **Errors**, la cerere, iar
indicatorul rămâne disponibil în stilul mut cât timp există erori în sesiune.

Butonul de extindere intră în modul **fereastră blocată**. Pe lângă ascunderea
panourilor laterale și a Output-ului, orice panou inferior deschis ulterior este
închis din nou, iar spațiul conversației rămâne neschimbat. Indicatorul de erori
deblochează explicit fereastra și restaurează panoul anterior înainte de a
deschide Debugger-ul. Astfel, agentul nu este ridicat sau micșorat de panourile
de jos atât timp cât blocarea este activă.

Butonul plutitor de salt la ultimul mesaj se ascunde când ar acoperi un buton
acționabil, de exemplu trimiterea răspunsurilor unui card Plan. Tapul ajunge la
controlul real, iar săgeata reapare când spațiul de sub ea este liber.

## Streaming și formatare

Paragrafele și blocurile de cod sunt widgeturi separate. La primirea textului,
blocurile neschimbate nu sunt rerandate. Textul este livrat în loturi scurte,
fără animație artificială de tastare. Un fence incomplet nu apare temporar
drept cod sau text al răspunsului.

Parserul recunoaște fence-uri pe linii, inclusiv `~~~`, și păstrează backtick-urile
literale din interiorul codului. Markdown-ul rămâne sigur: textul modelului
nu este interpretat ca HTML sau BBCode executabil. Titlurile nu introduc
suplimentar rânduri goale față de sursă.

Codul de peste 18 linii arată inițial primele 12. **Arată tot codul** îl extinde
în conversație, iar **Copiază codul complet** păstrează toate liniile și când
previzualizarea este restrânsă. Evidențierea sintaxei ține cont de limbaj.

## Unelte și fișiere

Fiecare apel de unealtă apare inline în fluxul răspunsului, în ordinea reală.
Antetul are iconiță de stare, titlu, durată și o zonă de atingere de 30 px;
succesele au detaliile închise, iar erorile și rezultatele neconfirmate le
deschid automat. Rezumatul rămâne vizibil numai pentru erori. Argumentele
arbitrare și payload-urile furnizorilor nu sunt copiate în widget. Detaliile pot
fi deschise, copiate sau urmărite în jurnalul existent. Istoricul persistă după
încheierea turului și după redeschiderea conversației.

**Running Tools** rămâne ascuns ca element legacy: starea uneltei are un
singur loc durabil, în timeline-ul inline. Panoul live de deasupra composer-ului
rezumă evenimentele curente fără să dubleze cardurile din conversație.

Imaginile și modelele păstrează miniaturile existente și un buton explicit
**Deschide**. Fixarea rămâne disponibilă direct; menționarea, trimiterea și
compararea sunt în meniul cardului. Afișarea unui card nu deschide viewer-ul.
Planurile, întrebările interactive și cardurile de verificare sunt păstrate.

## Emoji, copiere și mesagerie Ziva

Blocurile de text folosesc fallbackul de emoji al sistemului, fără să schimbe
textul Markdown sau evidențierea codului. Mesajele utilizatorului au un buton
compact **Copiază mesajul** lângă eticheta „Tu”; clipboard-ul primește textul
original, fără prefixe sau metadate.

Panoul Ziva păstrează interfața oficială. Din meniul `⋮`, **Trimite mesaj
agentului** deschide un câmp separat și trimite textul către agentul nostru;
dacă agentul este ocupat, mesajul intră în coadă. În sens invers, comanda
`/ziva <mesaj>` trimite cererea către Ziva și afișează răspunsul ei în chatul
nostru. Puntea nu copiază istoricul, cheile sau uneltele dintre cei doi agenți.

## Telefon și navigare

Modificările fișierelor sunt diffuri direct în conversație, fără carduri:
numele fișierului deasupra, ștergeri roșii (`-`), adăugări verzi (`+`) și context
neutru. Fragmentul inițial are cel mult 40 de linii; **Arată restul** extinde
conținutul, în loturi de maximum 500 de linii pentru diffuri foarte lungi.
Codul este literal, fără interpretarea BBCode. Derularea rămâne cea a
conversației; accesul existent la jurnal și restaurare este păstrat.

Indicatorul de context poate fi atins pentru consumul ultimei cereri, fereastra
modelului, rezerva pentru răspuns și pragul compactării. `≈` indică o estimare;
după un răspuns cu usage, estimarea următoare folosește măsurătoarea furnizorului
plus conținutul nou. Consumul cumulat al sarcinii este o metrică separată.
Rezervarea contextului tratează imaginile separat de codificarea lor Base64.

Glisarea pe mesaje navighează în conversație. Apăsarea lungă oferă copierea;
o atingere scurtă pe un link folosește hit-testing-ul nativ, fără selectarea
accidentală a textului. Linkurile HTTP(S) sunt validate; căile proiectului
folosesc navigarea nativă descrisă în
[Inspecții și diagrame](chat-inspections-and-diagrams.md).

Derularea în istoric oprește urmărirea automată. Săgeata în jos revine la
ultimul mesaj și reactivează urmărirea. Mesajele noi nu trag cititorul la
final; căutarea deschide progresul sau codul restrâns pentru a arăta rezultatul.
Adaptarea existentă la tastatură păstrează câmpul și cursorul deasupra ei.

## Inspecții și diagrame

Cardurile de citire/căutare arată fragmentele originale cu linii numerotate.
Căile din carduri și răspunsuri deschid explicit fișierele în Godot. Blocurile
Mermaid flowchart și state simple au randare nativă, sursă, zoom și deplasare.
Sintaxa avansată rămâne sursă; nu este motorul Mermaid complet. Limitele și
interacțiunile sunt documentate în
[Inspecții și diagrame](chat-inspections-and-diagrams.md).

## Rectificări verificate pe 7 noiembrie 2026

Proba nouă reproducea șase eșecuri în sursa anterioară. După corecții,
`presentation` trece **158/0** pe narrow și phone_landscape, runtime **949/0**,
`activity` **73/0**, `chat` **82/0**, `chat_lifecycle` **88/0** și `inspections`
**79/0**. Capturile `chat-rectified-status.png` au fost inspectate pe ambele
layouturi. Dovezi: `.ai-qa/chat-rectifications-20261107/`.

Proba de rezultat final este etichetată explicit ca probă UI; nu inspectează
proiectul utilizatorului. Recuperarea răspunsului gol este verificată cu un
furnizor simulat, separat de răspunsurile unui model real și de gesturile Android.
Starea APK-ului și rezultatele CI sunt în [progres](../PROGRES_SI_PLAN.md).

## Verificare din 6 noiembrie 2026

Runtime **945/0**, `presentation` **150/0** pe narrow și **150/0** pe
phone_compact, `chat` **82/0**, `chat_lifecycle` **88/0**. Probele exercită
rândurile reușite fără chenar, erorile evidențiate, fișierele din antet,
indicatoarele expandabil/restrâns, footer-ul adaptabil, istoricul, copierea,
tastatura simulată și navigarea. Capturile narrow și phone_compact au fost
inspectate. Dovezi: `.ai-qa/ziva-chat-style-20261106/`.

Aceste probe UI nu reprezintă o probă tactilă Android sau o conversație live
cu un furnizor. APK-ul a fost compilat ulterior din `65a99a4`; jobul Android a
trecut și artefactul a fost verificat local. CI desktop/narrow/wide a trecut cu
980/0 fiecare; phone landscape păstrează un eșec de derulare a cozii, iar editorul
nativ aceleași 38 de eșecuri de layout ca buildul precedent. Detaliile sunt în
[PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).

## Verificare

Scenariile `presentation`, `activity`, `chat`, `inspections`, `planning`,
`ziva`, `workspace` și `controls` testează widgeturile reale și fluxurile din
editor. Pe 5 noiembrie 2026 au trecut cu 143/0, 73/0, 82/0, 79/0, 81/0, 88/0,
70/0, respectiv 82/0; suita runtime a avut 945/0. Dovezile locale sunt în
`.ai-qa/chat-ziva-live-20261105/`.

Aceste probe folosesc Godot Linux în PRoot și rezultate deterministe. APK-ul
Ziva `66cdb44` include aceste surse și a fost verificat, dar probele nu sunt o
probă fizică Android și nu confirmă un furnizor live.
