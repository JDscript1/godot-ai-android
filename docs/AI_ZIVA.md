# Ziva independent în Godot AI — preview

Ziva are propria secțiune în setări și propria interfață web, proces, autentificare
și bază de date. Mesajele și cheile Ziva nu sunt transferate către harness-ul
nostru. Puntea nativă **MCP → editor** este implementată și verificată cu un
client de probă. **Conectarea automată din Ziva nu este confirmată**; pornirea
interfeței nu înseamnă controlul editorului. Integrarea rămâne experimentală,
fără APK nou sau probă completă cu un model real.

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
în aplicația existentă nu se migrează automat. La livrarea viitoare se folosește
`Godot-AI-Ziva-arm64-debug.apk`; instalatorul curent
`Godot-AI-Android-arm64-debug.apk` trebuie păstrat conform cererii utilizatorului.
Distribuția implicită nu permite pornirea sau instalarea componentei Ziva.
Workflow-ul Android are selectorul `distribution`; push-ul păstrează implicit
`standard`. Pentru livrare se transmite `--distribution ziva-preview` către
`misc/scripts/deliver_ai_android.py`. Cele două distribuții nu își curăță
reciproc instalatoarele sau checksum-urile din Download.

## Ce este implementat în surse

- Secțiunea **Ziva**, accesibilă și înainte de alegerea unui proiect. Instalarea
  este globală; pornirea și deschiderea cer un proiect selectat.
- Descărcarea opțională direct din release-ul oficial **v3.3.2 Linux ARM64**.
  Arhiva este de 217.601.938 bytes, SHA-256
  `0a852ea62028d6fa1dce10693b20a66ce208b338b778eaecf09ee55e00fd5d66`.
  APK-ul nu include binare, CEF sau interfața proprietară Ziva.
- Extragerea strictă a executabilului ZivaCode și licenței: dimensiune/hash
  arhivă, hash executabil, căi fixe, refuzul legăturilor simbolice și păstrarea
  instalării anterioare până la validarea înlocuitorului.
- Proba `--version` prin PRoot înainte de confirmarea instalării.
- Serviciu Android separat, cu notificare și oprire. Procesul persistent nu
  folosește coada comenzilor Linux cu timeout de 600 secunde și nu consumă pași
  ai harness-ului nostru. Android poate opri serviciul, inclusiv la limita
  platformei pentru servicii `dataSync`; aplicația nu promite execuție nelimitată.
- Date Ziva distincte pentru fiecare proiect, proiect montat în `/workspace`,
  refuzul deschiderii unei sesiuni a altui proiect și detectarea portului ocupat.
- Verificarea identității serverului local prin handshake MCP standard, fără
  executarea uneltelor. Acest handshake nu demonstrează conectarea la editor.
- Fereastră Android WebView cu UI-ul original local, DOM storage, JavaScript,
  redimensionare la tastatură și navigare HTTPS externă în browser. Nu injectează
  un bridge JavaScript privilegiat și nu reproduce protocolul privat CEF.
  Fereastra este un Dialog în activitatea editorului: o activitate separată ar
  apela pauza Godot și ar putea suspenda executorul MCP. Comportamentul fizic
  al Dialogului/WebView trebuie încă verificat pe Android.
  Numai distribuția preview adaugă excepție HTTP pentru `127.0.0.1`/`localhost`,
  necesară interfeței și probelor native; manifestul standard este păstrat.
- Starea procesului este separată de starea MCP. Panoul confirmă «editor conectat»
  numai după inițializarea unui client autentificat; afișează separat numărul
  apelurilor efectuate. O simplă probă HTTP nu setează `ready`.

## Conexiunea experimentală MCP

`editor_mcp.gd` publică instrumentele native din `editor_tools.gd` prin
Streamable HTTP, pe un port ales de sistem la `127.0.0.1`. Endpoint-ul există
numai în sesiunea Ziva a proiectului. Are autentificare Bearer aleatorie,
validare Host/Origin, limite pentru antete/corp/conexiuni/răspunsuri și sesiuni
MCP, listare paginată, erori JSON-RPC și anulare explicită. Apelurile sunt
serializate; repetarea aceluiași ID de cerere nu repetă modificarea executată.
Cache-ul are limite de memorie și de cereri pe sesiune; la epuizare clientul
trebuie să închidă sesiunea și să inițializeze alta. Aceste limite de transport
nu sunt o limită de pași impusă agentului Ziva.

Ziva are o instanță separată de instrumente, handle-uri și jurnal de recuperare.
Nu folosește `_execute_call`, planificatorul, aprobările sau furnizorii agentului
nostru. Modificările sunt refuzate cât timp agentul nostru lucrează, iar
conversațiile/profilurile lui rămân păstrate. Citirea continuă să fie permisă.
Sunt expuse instrumentele native pentru fișiere, scene, resurse, setări,
diagnostice, panouri și pornire/oprire proiect. Nu sunt expuse profilurile noastre
de generare, subagenții sau driverul nostru de captură/input de playtest.
Citirea Debuggerului/panourilor în APK necesită bridge-ul C++ existent;
proba MCP locală upstream nu dovedește date Debugger reale din Android.

Serviciul pregătește o intrare `godot_ai_editor` în `.mcp.json`, conform
[configurației MCP documentate de Ziva](https://ziva.sh/docs/mcp-servers).
Cheia din antet este `${GODOT_AI_EDITOR_MCP_TOKEN}`; valoarea reală este transmisă
numai prin Intent privat și mediul procesului Linux. Nu apare în proiect,
clipboard, jurnalul activității sau `state.json`. Tokenul nu este o cheie API.
La oprire configurația originală este restaurată; alte servere, formatarea
originală nemodificată și modificările concurente ale utilizatorului sunt
păstrate. Un conflict în intrarea proprie păstrează copia privată de recuperare
și oprește înlocuirea ei la următoarea pornire. Legăturile simbolice sunt refuzate.

În proba fără chat, ZivaCode a rămas pornit și a servit HTML, dar nu a inițializat
serverul nostru în 35 de secunde. **Autoload-ul descris de documentație nu este
confirmat în această pornire standalone.** Panoul oferă «Copiază conexiunea la
editor»: în Ziva → Settings → Models & Providers → MCP servers → Add manually,
alege Remote URL, lipește Config, apoi Test connection și Save and connect.
Configurația copiată nu conține tokenul real. Acest fallback este implementat;
folosirea lui în UI-ul original nu a fost verificată încă. URL-ul este valabil
pentru sesiunea curentă; la repornire se poate schimba portul.

Oprirea Ziva sau închiderea editorului oprește endpoint-ul și anulează lotul în
curs. Playtesturile temporare pornite prin această punte se închid la oprire
sau după 120 de secunde; `keep_open` explicit și sesiunile pornite manual sunt
respectate în timpul sesiunii. Serviciul se oprește dacă editorul/interfața nu
mai răspund în mod repetat. Nu promite acces la editor când Android îl suspendă.

Executabilul se instalează în filesystem-ul Linux al aplicației, sub
`/opt/godot-tools/ziva/v3.3.2/`. Datele proprii Ziva sunt sub
`/var/lib/godot-ai-ziva/<project-id>/`. Oprirea sau repararea executabilului nu
șterge baza de date a conversațiilor. PRoot nu constituie o izolare de securitate.

## Verificări și limite

Proba reală separată din Debian/PRoot Termux a confirmat `--version`, pornirea
serverului la `127.0.0.1:7012`, răspuns HTML și handshake MCP cu identitatea
`ziva-godot`, versiunea `v3.3.2`. Jurnalul original raportează lipsa
`ZIVA_BRIDGE_HANDSHAKE_FILE`, publicat în mod normal de pluginul desktop.
Aceste probe nu reprezintă rulare în APK-ul nostru.
Instalatorul Kotlin propriu a descărcat și verificat arhiva oficială completă,
apoi a extras executabilul de 116.771.624 bytes și licența în directorul QA;
proba nu se limitează la un fixture sau la descărcarea parțială a ZIP-ului.

Testele Kotlin acoperă arhiva și fișierele reale; fixture-ul Godot verifică UI-ul
și faptul că istoricul/profilurile agentului existent nu se schimbă. Compilarea
Kotlin împotriva SDK Android nu reprezintă o compilare sau instalare APK.
Regresia locală are 750/0 aserțiuni runtime, 754/0 verificări editor îngust,
53/0 pentru panoul Ziva, 61/0 pentru managerul de proiecte, 13/0 arhivă Ziva,
6/0 arhivă Linux și 5/0 pentru livrare. Gradle a generat cele două BuildConfig;
proba locală de configurare a folosit NDK 27 existent în locul NDK 29 incomplet.
Fuziunea manifestelor preview a trecut prin Gradle și păstrează overlay-ul
Android existent, alături de identitatea separată și excepția loopback.
Chromium din mediul de dezvoltare se oprește cu SIGTRAP inclusiv pe o pagină
goală; această probă nu confirmă comportamentul interfeței Ziva în WebView.

Continuarea din 29.10 a verificat puntea proprie prin TCP într-un editor Godot
real: citire proiect, argumente/căi nepermise, scriere și restaurare, lot de două
fișiere cu aplicare/rollback asincron, creare/salvare/citire scenă, refuzul
modificărilor concurente, anulare și sesiuni MCP. Testele dedicate sunt în
`tests/test_editor_mcp.py` și `tools/embedded-runtime/tests/ZivaMcpConfigTest.kt`.
Dovezile sunt în `.ai-qa/editor-mcp-final/`, `.ai-qa/editor-mcp-live-final/` și
`.ai-qa/ziva-native/*mcp*`. Proba live este numai pornire/discovery, fără model.

Rezultatele continuării: **38/0** MCP, **15/0** configurare Kotlin, **751/0**
runtime, **759/0** editor îngust și **59/0** panou Ziva. Ultima ajustare a
instrucțiunilor vizibile în setări are proba focalizată 59/0; runda completă
759/0 pornise înaintea acestei ajustări. Captura finală a fost inspectată.
Compilarea Kotlin și manifestul preview au trecut; nu s-a construit APK.

Rămân de verificat: conectarea efectivă Ziva → MCP → editor în APK, comportamentul
UI-ului original în WebView, autentificarea și un tur complet
prompt → răspuns → unealtă → rezultat cu un furnizor real. Nu sunt implementate
upload-ul din WebView sau accesul Ziva la imaginile/mesh-urile din chatul nostru.

Licența din release este proprietară. Descărcarea opțională nu acordă drepturi
de redistribuire a binarului într-un APK; pentru o distribuție care îl include
este necesară autorizarea furnizorului.

Surse: [instalare oficială](https://ziva.sh/docs/installation),
[release v3.3.2](https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/tag/v3.3.2),
[MCP Ziva](https://ziva.sh/docs/ziva-mcp-server),
[MCP extern în Ziva](https://ziva.sh/docs/mcp-servers),
[transport MCP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports),
[condiții Ziva](https://ziva.sh/terms).
