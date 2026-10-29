# Ziva independent în Godot AI — preview

## Tab principal Ziva — 29.10.2026

Ziva are propriul tab de sus, lângă **AI Assistant**, atât în editor, cât și
în managerul de proiecte. Tabul folosește interfața web oficială integrală,
fără rescrierea frontend-ului și fără acces la cheile, mesajele sau uneltele
agentului nostru. Backend-ul rămâne pluginul oficial într-un editor Godot Linux
ARM64 separat, sub PRoot, pe fișierele proiectului ales.

WebView-ul este atașat în interiorul tabului și se ascunde când tabul devine
invizibil sau apare o fereastră Godot. Starea frontend-ului se păstrează între
schimbările de tab; doar **Reîncarcă** reîncarcă pagina. Încadrarea se raportează
la suprafața Godot și se actualizează la redimensionare, rotație și tastatură.
Autentificarea HTTPS se deschide în browserul Android; selecția fișierelor
folosește selectorul sistemului. Nu se injectează un bridge JavaScript nativ.

**Configurare** deschide setările de instalare, reparare și Runtime Linux.
În lista de proiecte se poate instala Ziva; pornirea cere un proiect deschis.
Un backend asociat altui proiect nu poate fi afișat în tabul curent. Închiderea
tabului nu oprește backend-ul; **Oprește** îl oprește explicit.

Validarea Android a WebView-ului, autentificării, selectorului de fișiere,
tastaturii și unei sarcini Ziva reale rămâne necesară pe dispozitiv. Testele
Godot cu backend simulat verifică plasarea, ascunderea, reluarea și separarea
stării, nu frontend-ul proprietar sau un furnizor real.

Ziva are propria secțiune în setări, propria interfață web oficială, proces,
autentificare și date. Mesajele, cheile și modelul Ziva nu trec prin harness-ul
nostru. Varianta curentă rulează **pluginul oficial Ziva v3.3.2 într-un editor
Godot Linux separat, headless**, iar editorul Android și agentul nostru continuă
în paralel. Integrarea rămâne experimentală: verificarea pe dispozitiv și un tur complet
cu model real sunt încă necesare. Livrarea APK-ului este consemnată în
`PROGRES_SI_PLAN.md`.

## De ce un editor separat

Pluginul oficial este o extensie GDExtension Linux ARM64 (glibc), cu server,
interfață și CEF proprii. Editorul Android nu poate încărca o bibliotecă glibc
într-un proces Bionic și nu există un binar Android al pluginului. Fluxul ales:

1. La cerere, aplicația descarcă arhiva oficială completă v3.3.2 și Godot
   4.7.2 Linux ARM64 din release-urile oficiale.
2. Serviciul Android pornește Godot-ul oficial headless pe proiect, sub PRoot,
   cu addon-ul montat în `/workspace/addons/ziva_agent`.
3. Pluginul își pornește serverul și interfața oficială pe `127.0.0.1`, în
   intervalul 7012–7041.
4. Fereastra WebView afișează interfața oficială; editorul Android rămâne activ
   și agentul nostru își păstrează executorul nativ.

Procesele, datele și autentificarea sunt separate. Ziva nu primește prompturi,
profiluri sau chei ale agentului nostru, iar harness-ul nostru nu primește
conversațiile sau cheile Ziva. Ziva lucrează cu propriile unelte în editorul ei
headless; nu controlează editorul Android și nu vede starea lui nesalvată.
Agentul nostru nu folosește furnizorul sau uneltele Ziva.

## Pachet Android separat

Utilizatorul a cerut compilarea ulterioară a unui pachet care păstrează aplicația
actuală. Se folosește proprietatea Gradle explicită:

```sh
cd platform/android/java
./gradlew :editor:assembleAndroidDebug -PgodotAiDistribution=ziva-preview
```

Compilarea bibliotecii Godot ARM64 și pregătirea SDK/NDK rămân cele din fluxul
normal al repository-ului. Proprietatea nu compilează singură motorul nativ.

| Distribuție | Application ID debug | Nume |
| --- | --- | --- |
| implicită / `standard` | `com.jdscript.godotai.debug` | Godot AI |
| `ziva-preview` | `com.jdscript.godotai.ziva.debug` | Godot AI Ziva |

Ambele se pot instala în paralel și au date Android separate. Furnizorii salvați
în aplicația existentă nu se migrează automat. Distribuția implicită nu permite
pornirea sau instalarea componentei Ziva. Workflow-ul Android are selectorul
`distribution`; push-ul păstrează implicit `standard`. Pentru livrare se
transmite `--distribution ziva-preview` către
`misc/scripts/deliver_ai_android.py`. Cele două distribuții nu își curăță
reciproc instalatoarele sau checksum-urile din Download.

## Instalarea la cerere

APK-ul nu include binare, CEF sau interfața proprietară Ziva; totul se descarcă
la instalare, direct de la furnizor. Ambele descărcări sunt opționale și sunt
verificate înainte de activare.

| Componentă | Arhivă | SHA-256 arhivă | Conținut verificat |
| --- | --- | --- | --- |
| Ziva v3.3.2 Linux ARM64 | 217.601.938 bytes | `0a852ea62028d6fa1dce10693b20a66ce208b338b778eaecf09ee55e00fd5d66` | `zivacode` 116.771.624 bytes, `7797be07153d515fb0a96a8438f811d633610e4e39caa582334e87cc5ef6c200` |
| Godot 4.7.2 Linux ARM64 | 77.008.699 bytes | `5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d` | executabil 137.953.888 bytes, `3fcb80f4fe794e3859360eb641d8c41d8ffe2c2e54ba1981e55a76851d5ed1f4` |

Pentru Ziva se extrage numai subarborele `addons/ziva_agent/` (261 fișiere,
aproximativ 503 MB): GDExtension, manifestul, licența, bibliotecile și
executabilul. Instalatorul verifică dimensiunea și SHA-256 arhivei, limitează
fiecare fișier la 320 MiB, totalul la 600 MiB și numărul la 4000, refuză căile
`..`/absolute/duplicate și legăturile simbolice și acordă drept de execuție
pentru `bin/`, `bin-deps/` și `zivacode/`. Instalarea se face în staging, se
validează, apoi se activează printr-o redenumire atomică; instalarea anterioară
este păstrată până la succes, iar un eșec nu atinge datele Ziva.

Godot se extrage dintr-un singur membru fix al arhivei oficiale, cu hash și
dimensiune verificate, apoi primește drept de execuție. Ambele instalatoare
refuză un root simbolic, o versiune care iese din director și spațiul insuficient.
Cerința de spațiu acoperă arhiva, conținutul dezarhivat, o eventuală instalare
veche păstrată temporar și o marjă; în practică sunt necesari aproximativ 1 GB
la instalare. Descărcările sunt de circa 295 MB.

După instalare, serviciul rulează `zivacode --version` și `godot --version` prin
PRoot; instalarea este confirmată numai pentru `v3.3.2`, respectiv
`4.7.2.stable`. Binarele ajung sub
`/opt/godot-tools/ziva/v3.3.2/addons/ziva_agent/` și
`/opt/godot-tools/godot/4.7.2/godot` în filesystem-ul Linux al aplicației.

Licența Ziva este proprietară. Descărcarea opțională nu acordă drepturi de
redistribuire a binarului într-un APK; pentru o distribuție care îl include este
necesară autorizarea furnizorului.

## Pornirea editorului oficial

`AIZivaService` rulează într-un proces Android separat, cu notificare și oprire
explicită. La pornire:

- verifică ambele pachete și proiectul canonic (`project.godot`, cale absolută);
- refuză pornirea dacă un server Ziva răspunde deja pe unul dintre porturi;
- creează directoare private pe proiect pentru `local-share`, `cache`, `config`
  și pentru cache-ul Godot `.godot`, ca cele două editoare să nu împartă
  cache-ul de import;
- montează proiectul în `/workspace` și addon-ul în
  `/workspace/addons/ziva_agent`;
- lansează Godot-ul oficial cu `--headless --editor --path /workspace`, cu
  `ZIVA_ENABLE_HEADLESS=1`.

Pornirea este declarată reușită numai după trei probe: răspuns HTML 200 pentru
interfață, handshake MCP cu identitatea `ziva-godot` v3.3.2 și un apel de
citire `tools/call get_project_info` cu rezultat nevid. Abia atunci serviciul
publică portul în `state.json` și permite deschiderea ferestrei. Limita de
pornire este de 180 secunde; primul import poate fi lent. Un heartbeat verifică
interfața la fiecare 2 secunde și oprește sesiunea după 30 de eșecuri
consecutive sau când editorul se închide. Ultimele 128 KB din ieșirea editorului
rămân în `ai-ziva/projects/<project-id>/godot.log`.

Oprirea din notificare sau din panou scrie un fișier privat de anulare, termină
procesul și păstrează datele proiectului. Android poate opri serviciul
`dataSync`, inclusiv la limitele platformei; aplicația nu promite execuție
nelimitată și afișează starea întreruptă la următoarea citire.

## Interfața în WebView

WebView-ul este un copil nativ al activității Android, ancorat exclusiv în corpul
tabului Ziva. Nu deschide o altă Activity și nu suspendă editorul Android.
Încarcă `http://127.0.0.1:<port>/` cu JavaScript și DOM storage; navigarea rămâne
pe același host și port, iar linkurile HTTPS externe și popup-urile cerute de
utilizator se deschid în browser. Nu se injectează un bridge JavaScript
privilegiat și nu se reproduce protocolul privat CEF. La schimbarea tabului,
WebView-ul se ascunde și păstrează pagina; **Reîncarcă** este explicit. La
schimbarea activității sau închiderea aplicației se eliberează vizualizarea.

Selectorul de fișiere folosește `onShowFileChooser` și rezultatul Android.
Încadrarea urmărește suprafața Godot și zona vizibilă, inclusiv tastatura;
aceste comportamente sunt implementate și compilate, dar necesită test fizic.

## Controalele din panoul nostru

`ziva.gd` face controlul `install`, `start`, `stop` și afișarea `embed`.
Butonul din setări deschide tabul principal; nu mai lansează un Dialog.
Panoul arată instalarea (`~295 MB`), spațiul total de aproximativ 1 GB și
faptul că backend-ul rulează într-un editor separat. WebView-ul se afișează
numai când serviciul raportează un port valid pentru proiectul curent.
Oprirea readuce controlul de pornire, iar o eroare de pachet oferă repararea
fără ștergerea istoricului. Controalele Ziva nu modifică istoricul sau
profilurile agentului nostru.

## Ce s-a eliminat

Varianta anterioară încerca să conecteze Ziva la editorul Android printr-o
punte MCP proprie (`editor_mcp.gd`), cu token în `.mcp.json` și un fallback
«Copiază conexiunea». Soluția a fost eliminată, împreună cu
`AIZivaMcpConfig`, testele ei și starea `editor_connected`: interfața oficială
rulează acum în propriul editor și își folosește propriile unelte native, deci
puntea era un al doilea traseu de control, neverificat, fără beneficiu. Panoul
nu mai oferă «connect», token sau configurație MCP.

## Verificări și limite

Proba separată, în Debian/PRoot, a folosit exact montările serviciului: addon-ul
oficial complet montat peste `/workspace/addons/ziva_agent`, cache `.godot` și
directoare XDG private. A confirmat interfața HTML la `127.0.0.1:7012`,
identitatea MCP `ziva-godot` v3.3.2 și apelul de citire `get_project_info` fără
inițializare prealabilă. Proiectul gazdă a rămas nemodificat, iar CEF nu a fost
inițializat în modul headless. Această probă nu este rularea din APK.

Testele Kotlin acoperă instalatoarele: 33/0 pentru pachetul Ziva și 19/0 pentru
Godot, inclusiv refuzul căilor nesigure, hash-urilor greșite, anulării și
păstrarea instalării anterioare. Aceleași clase au extras arhivele oficiale
reale din cache: `zivacode` 116.771.624 bytes și Godot 137.953.888 bytes, cu
drept de execuție. Fixture-ul Godot verifică panoul și independența față de
istoricul/profilurile agentului: 55/0. Regresia runtime a trecut 750/0, iar
regresia completă a editorului pe aspectul îngust a trecut **756/0** (exit 0,
`editor-report.json`). Compilarea Kotlin împotriva SDK Android nu reprezintă o
compilare APK.

Dovezi locale: `.ai-qa/full-final/narrow/` (raportul regresiei complete),
`.ai-qa/ziva-final/narrow/` (captură și raport focalizat),
`.ai-qa/ziva-native/` (loguri Kotlin, `ZivaLiveInstallTest.kt`) și
`.ai-qa/ziva-native/runtime-final.log`.

Varianta separată `234893bf` a fost compilată și livrată în Download la
29.10.2026, după CI 40870748187: runtime 751/0, upstream 768/0 × 5,
nativ 792/0 × 5, Ziva focalizat 67/0 și manager nativ 68/0. S-au verificat
semnătura, identificatorul separat, toate cele 37 de scripturi și pachetul
Linux. Dovezi: `.ai-qa/compile-ziva-tab-20261029T115729Z/`.

Rămân de verificat pe dispozitiv: instalarea APK-ului, descărcarea completă
prin serviciu, durata primului import, WebView, autentificare, selectorul
fișierelor, tastatura, descărcări, un tur complet prompt → răspuns → unealtă
cu un furnizor real și supraviețuirea serviciului sub politicile Android.
Ziva nu accesează imaginile sau mesh-urile private din chatul agentului nostru.

Limitări de proiectare: cele două editoare partajează fișierele proiectului,
deci editările simultane se pot suprascrie; Ziva vede propria stare de editor,
nu modificările nesalvate din editorul Android, și invers. PRoot nu constituie
o izolare de securitate. Instalarea consumă aproximativ 1 GB și necesită
rețea; Android poate opri serviciul în fundal.

Surse: [instalare oficială](https://ziva.sh/docs/installation),
[release v3.3.2](https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/tag/v3.3.2),
[Godot 4.7.2 Linux ARM64](https://github.com/godotengine/godot/releases/tag/4.7.2-stable),
[condiții Ziva](https://ziva.sh/terms).
