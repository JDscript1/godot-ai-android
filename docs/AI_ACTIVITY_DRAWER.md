# Bara de activitate și progresul sarcinilor

Actualizat: 24.10.2026. Implementare în surse, după APK-ul livrat `36457dd`.
Această etapă nu recompilează și nu înlocuiește APK-ul din Download.

## Comportament

Bara de status stă imediat deasupra câmpului de mesaj, în afara zonei derulabile
a conversației. Rămâne în aceeași poziție când agentul scrie sau când utilizatorul
citește mesaje anterioare. Forma închisă are un indicator discret, activitatea
curentă, progresul de tip `2/5` și săgeata de extindere.

Apăsarea barei deschide detaliile în sus, păstrând câmpul de mesaj accesibil:

- **Pași:** planul structurat al cererii, cu stări finalizat, în lucru și de făcut.
  Numărătoarea folosește numai pașii marcați efectiv `completed`.
- **Sarcini secundare:** lucrările Explore, General și Playtest existente,
  actualizate prin evenimentele executorului. Interfața nu lansează subagenți.
- **Operații:** apelurile efective ale harness-ului nativ, cu destinația relevantă
  și rezultatul: finalizat, blocat, eșuat, întrerupt sau recuperat. Apelurile de
  descoperire a tool-urilor și actualizarea planului nu dublează lista pașilor.

Detaliile au derulare proprie și înălțime limitată la aproximativ 30% din spațiul
chatului, cel mult 200 pixeli logici. Textele lungi se încadrează sau se scurtează;
nu apare derulare orizontală. Sunt afișate toate etapele planului și ultimele
24 de operații, cu numărul total indicat dacă lista este mai lungă.

Oprirea nu bifează pașii rămași. Operațiile fără rezultat confirmat devin
întrerupte, refuzul unei permisiuni rămâne blocat, iar progresul parțial rămâne
disponibil. După finalizare, bara poate fi redeschisă pentru verificare. Cererea
nouă începe cu o listă nouă și ignoră notificările sarcinilor vechi.

La reîncărcarea conversației, bara se reconstruiește din planul, mesajele și
rezultatele salvate ale ultimei cereri. Planurile istorice rămân și în conversație.
Un plan de execuție rămas activ în istoric este afișat ca întrerupt dacă nu există
o execuție curentă. Reconstrucția nu execută tool-uri și nu reia automat lucrul.

Mesajele informative fără sarcini rămân temporare. Indicatorul respectă
preferința existentă pentru mișcare redusă. Bara are focus și activare din
tastatură; pe touch folosește butonul și derularea native Godot.

## Implementare

- `chat_view.gd`: bara fixă, sertarul, contorul, stările și încadrarea; lista se
  reconstruiește numai când este deschisă și datele s-au schimbat.
- `panel.gd`: leagă cererea activă, planul, începutul/rezultatul apelurilor,
  oprirea și istoricul de widget; textele și destinațiile sunt redactate.
- `harness.gd`: include argumentele redactate în evenimentul `tool_started`.
- `agent_jobs.gd`: notifică schimbările sarcinilor secundare, cu filtrare după
  cererea părinte. Comportamentul de delegare și limitele existente nu se schimbă.

## Verificări

Probele editorului folosesc proiecte temporare și furnizori determinați de
fixturi. Ele verifică poziția deasupra composerului, deschiderea/închiderea,
stările mixte, actualizarea progresului, sarcinile secundare, oprirea parțială,
reinițializarea cererii și refacerea progresului din conversație.

Capturile sunt salvate ca `activity-collapsed.png`, `activity-expanded.png`
și `activity-interrupted.png`, cu fișiere de geometrie alăturate. Scenariul
poate fi rulat separat:

```sh
python modules/ai_assistant/tests/render.py --godot /cale/catre/godot --scenario activity --output .ai-qa/proba-activitate
```

În Termux se adaugă `--proot` pentru editorul Linux. Validarea touch pe Android
fizic și includerea în APK rămân probe separate de randările acestui editor.

La 24.10.2026, suita completă a editorului a trecut 353 verificări pentru fiecare
dintre cele cinci configurații: desktop, narrow, wide, phone_landscape și
phone_compact. Dovezile sunt în `.ai-qa/activity-drawer-final/`. Controlul
capturilor a dus apoi la rezervarea lățimii native a etichetelor de stare și la
o verificare suplimentară pentru încadrarea lor.

După ajustarea finală, scenariul dedicat a trecut **40 verificări la fiecare
dintre cele cinci configurații**, fără eșecuri. Rapoartele, capturile și geometria
sunt în `.ai-qa/activity-drawer-verified/`. Au fost inspectate capturile desktop,
cele înguste și cele cu scalare pentru telefon, inclusiv forma restrânsă,
sertarul deschis și oprirea parțială.

Suita completă desktop a fost apoi repetată pe sursele finale: **354 verificări,
zero eșecuri**, în `.ai-qa/activity-drawer-release-check/`.

Suita runtime a trecut 398 aserțiuni, fără eșecuri, în rularea izolată
`.ai-qa/activity-drawer-runtime-isolated.log`. O rulare concurentă cu randările
a expirat la proba de streaming cu termen inițial de 250 ms
(`.ai-qa/activity-drawer-runtime-final.log`); transportul și pragurile testului
nu au fost schimbate pentru această probă. Această etapă nu a folosit API-uri
plătite sau modele reale pentru testele vizuale.
