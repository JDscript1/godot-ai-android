# Stabilitate agent — probe și praguri de acceptare, 27.10.2026

Scop: jocuri construite și verificate prin agentul din Godot. Lucrul pe proiecte
mari cere continuitate, verificări reproductibile și controlul regresiilor.
Un mini-joc funcțional nu dovedește încă pregătirea pentru producție AAA.

## Mediul și limitele probei

- NX729J, Android, editorul instalat `com.jdscript.godotai.debug`, sursa
  `74887a1fc49bc2a969ef33c9a9ac1d6f293f6d8e`.
- SHA-256 al APK-ului instalat egal cu instalatorul livrat în Download:
  `389b43bd9370d41ac23bb0ede3139fbc221b5a2f0ddaf215a57ec8da457f0890`.
- DeepSeek `deepseek-flash`, profilul deja configurat în aplicație. Cheia nu
  este exportată. YOLO era deja activ; driverul nu l-a activat.
- Proiect nou izolat:
  `Documents/GodotAI-Stability-20261027T150114Z/project`.
- Comenzile intră prin panoul nativ, iar rezultatele provin din uneltele și
  rularea APK-ului. Nu s-au construit manual scenele în locul agentului.
- Fără generări plătite de asseturi, instalări de pluginuri sau comenzi Linux
  în această rundă. Cererile DeepSeek folosesc API-ul real și pot avea cost.

## Rezultatele din APK-ul instalat

| Probă | Rezultat observat | Stare |
| --- | --- | --- |
| Două scene în același director | `arena.tscn` și `menu.tscn` salvate și redeschise separat, rădăcini și noduri confirmate; 21 cereri, 63,4 s | Trecut |
| Mini-joc cu 3 monede | Script și scenă în `game/`, colectare prin input, contor 0→1→2→3, victorie, Restart și R; 46 cereri, 397,8 s | Trecut |
| Păstrarea fișierelor | Configurația, pluginul, markerul și scenele existente păstrate identic; fără alt director principal | Trecut în primele două probe |
| Funcționare peste vechiul plafon | Mini-jocul a ajuns la 46 cereri și a încheiat planul | Confirmat |
| Layout adaptat și Stop controlat | Stop după prima scriere reală; modificarea rămâne salvată și raportul precizează lipsa verificării ulterioare | Oprire corectă; layout încă nevalidat |
| Continue după Stop | Același turn reluat prin butonul nativ; DeepSeek returnează HTTP 400 privind metadata de protocol | Eșec reprodus |

Proba mecanicilor a folosit input injectat prin uneltele native în jocul Android,
nu setarea directă a contorului sau teleportarea jucătorului. Capturile reale
confirmă starea inițială, victoria și resetarea. Atingerea fizică a degetului și
redimensionarea nu sunt demonstrate de această probă. Captura inițială arată
margini gri: de aici pornește sarcina separată de layout.

## Corecții în surse, după constatări

1. **Protocol la reluare:** notificările locale despre Stop/eroare, drafturile
   întrerupte și cardurile de fișiere sunt marcate ca mesaje ale aplicației.
   Contextul lor util este transmis separat de răspunsurile modelului, inclusiv
   pentru înregistrări vechi. Nu se inventează metadata de raționament. Datele
   confirmate ale furnizorului se păstrează și la ramificarea conversației.
2. **Rezultate mari:** rezumatul pentru model păstrează `ok`, erori, ID-uri și
   metadate compacte ale artefactelor. Limita de 24.000 caractere se măsoară
   după serializarea JSON, inclusiv escape-uri; jurnalul complet rămâne separat.
3. **Inspectarea API-ului Godot:** `godot_describe` are paginare alfabetică,
   totaluri, `next_offset` și filtru literal cu alternative `|`. Implicit 16
   intrări/categorie, maximum 50. Pentru Node: 48.786 caractere integral față de
   7.342 în pagina implicită. Nu este o măsurare înainte/după a facturii API.
4. **Evaluator:** păstrează permisiunile existente, permite continuarea aceluiași
   chat și colectează JSONL complet, checkpoint și conversație în fișiere 0600.
   Starea se actualizează și după o reluare declanșată din interfață.

Contractul actual DeepSeek pentru continuări cu unelte este descris în
[documentația oficială](https://api-docs.deepseek.com/guides/thinking_mode/).

Validări locale cu Godot Linux ARM64 prin Debian/PRoot:

- Regresii reproduse înaintea fixurilor; pentru reluare: 516 aserțiuni / 6 eșecuri.
- **518 aserțiuni runtime / 0 eșecuri**, inclusiv cerere HTTP invalidă respinsă
  și aceeași continuare cu context corect acceptată de fixture-ul strict.
- **514 verificări în editor / 0 eșecuri**, configurația narrow; capturile
  cardurilor și ale sarcinii întrerupte inspectate vizual.
- Driverul normal și driverul temporar al probei de adaptor trec parserul Godot;
  scripturile Python se compilează.

Aceste surse nu sunt încă într-un APK nou. Testul HTTP controlat nu închide
acceptarea la DeepSeek real. Repetarea pe telefon a fost pregătită cu un adaptor
de dezvoltare temporar, separat de panoul/harness-ul nativ. Telefonul s-a blocat
automat înaintea încărcării adaptorului; este necesară deblocarea pentru proba
live. Proba temporară a fost dezactivată, iar driverul normal restaurat; nu
rămâne un adaptor modificat sau o reluare automată în așteptare pe dispozitiv.
Nu se prezintă o intervenție de evaluator drept funcție livrată în APK.

## Ordinea următoarelor probe

Fiecare probă are snapshot inițial, jurnal complet, rezultat observat și lista
fișierelor modificate. Un blocaj se păstrează pentru reluare; nu încheie artificial
criteriul. Nu se reintroduce o limită totală de pași.

| Prioritate / ID | Sarcină pentru agent | Condiție de acceptare |
| --- | --- | --- |
| P0 / ST-01 | Reia exact sarcina de layout oprită | Același turn, fără HTTP 400, fără scene/foldere duplicate; layout și mecanici verificate după ultima modificare |
| P0 / ST-02 | Oprește și reia după repornirea editorului, apoi după eroare de conexiune | Plan, fișiere, unelte încărcate și ID-uri păstrate; nicio operație externă repetată automat |
| P0 / ST-03 | Refuză o scriere, apoi aprobă o cerere nouă distinctă | Refuzul este respectat, dialogul accesibil, nicio modificare neautorizată |
| P0 / ST-04 | Repară un script invalid fără a altera funcțiile corecte | Parser roșu→verde, test comportamental și diff limitat la fișierele cerute |
| P1 / ST-05 | Salvează și reîncarcă progresul mini-jocului | Restart de proces real; monede/scor/poziție corecte; salvare invalidă tratată explicit |
| P1 / ST-06 | Adaugă meniu, pauză și trecere între două niveluri | Tranziții și input verificate; revenirile nu dublează monede, semnale sau noduri |
| P1 / ST-07 | Îmbunătățește același proiect într-o conversație lungă | Recuperează structura și deciziile după compactare; nu recreează scene sau rescrie configurația |
| P1 / ST-08 | Folosește o imagine și un mesh deja existente | Carduri în chat, observație în background, preview numai la cerere; fișierele originale păstrate |
| P1 / ST-09 | Reia un job Runware existent până la import | ID unic, fără regenerare accidentală, transparență și mesh real verificate; cost consemnat separat |
| P2 / ST-10 | Construiește o felie 3D jucabilă: personaj, cameră, coliziuni, obiectiv | Parcurs complet prin input, geometrie fără blocaje evidente, salvare și rerulare reproductibilă |
| P2 / ST-11 | Măsoară și optimizează scena 3D pe dispozitivul țintă | Bugete FPS/timp de cadru, memorie și încărcare stabilite pe proiect; comparație repetată înainte/după |
| P2 / ST-12 | Exportă și pornește un build de joc separat | Artefact instalabil, pornire reală și regresie după export; build-ul editorului nu este dovada exportului jocului |

## Capacități necesare pentru proiecte mari

- Criterii de acceptare explicite pentru fiecare etapă și legarea lor de probe
  concrete. Verificarea generică a oricărui tool nu dovedește toate mecanicile.
- Hartă persistentă a proiectului, dependențe între scene/resurse și decizii
  verificate. Recuperare după compactare și schimbarea sesiunii/furnizorului.
- Detectarea ciclurilor de investigație fără progres, inclusiv citiri reușite
  repetate; întâi reformularea planului și păstrarea stării, fără plafon global.
- Regresii automate pentru mecanici, input, stări salvate și tranziții; build-uri
  reproductibile și verificarea asseturilor, coliziunilor, LOD-urilor și licențelor.
- Bugete și profilare pe dispozitivul țintă, încărcare/streaming de resurse,
  organizarea conținutului și controlul versiunilor.

Acestea sunt praguri de implementat și demonstrat, nu funcții deja validate.
Înlocuirea harness-ului cu Pi sau alt runtime nu elimină nevoia acestor probe.

## Dovezi locale

`.ai-qa/harness-stability-20261027/` conține `session.json`, snapshot-uri,
`scene-paths-native/`, `mini-game-native/`, `responsive-stopped-native/`,
`responsive-resume-failed-native/`, `runtime-resume-red.log`,
`runtime-final-518.log`, `render/narrow/editor-report.json` și capturi.
Conversațiile și checkpointurile pot conține metadata privată de protocol;
rapoartele prezintă numai starea și rezultatele utile. Nu se publică chei sau
raționamentul intern al modelului.
