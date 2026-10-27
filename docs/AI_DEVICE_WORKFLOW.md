# Testarea rapida a agentului instalat pe Android

Metoda ruleaza cerinte in **panoul nativ al APK-ului instalat**, printr-un plugin
temporar intr-un proiect separat. Nu incarca sursele locale ale agentului, nu
inlocuieste furnizorii/tool-urile si nu extrage cheile API. Scriptul Python este
un controler de dezvoltare; harness-ul si generarea raman in aplicatia Android.
Nu este necesara recompilarea APK-ului pentru fiecare proba.

Conexiunea ADB este asociata explicit prin Android. Pluginul identifica
`AIAssistantPanel`, foloseste selectia furnizorului si apeleaza intrarea normala
`_start_chat`. Modul se alege explicit prin `--work-mode auto/default/plan`,
implicit Auto, iar selectia initiala se restaureaza la incheiere. Driverul
respecta permisiunea YOLO existenta; nu o activeaza. Pentru o continuare in
aceeasi conversatie se foloseste `--continue-conversation`. APK-ul 74887a1
nu mai are plafonul de 30 de pasi; driverul nu adauga unul.

Controlul foloseste fisiere locale in `control/`, fara server HTTP expus.
Comenzile au ID-uri persistate pentru a evita retrimiterea la repornirea
editorului. Jurnalul salvat exclude rationamentul intern si foloseste redactarea
normala a panoului. `collect` preia jurnalul complet JSONL, consola, checkpointul
si conversatia exacta a proiectului de proba, cu fisiere locale private (0600).
Conversatia contine metadata de protocol necesara furnizorului, care nu se
afiseaza in rapoarte. Nu se citesc vault-ul, cheile sau configuratia globala.
Identificatorii si caile sunt validate inainte de citirea prin `run-as`.
O generatie neconfirmata nu trebuie retrimisa: se recupereaza acelasi job.

## Folosire

Din Termux, dupa asocierea ADB, pregateste un director nou:

```sh
python modules/ai_assistant/tests/device_workflow.py prepare --root /storage/emulated/0/Documents/GodotAI-New-Workflow-Test
python modules/ai_assistant/tests/device_workflow.py open --root /storage/emulated/0/Documents/GodotAI-New-Workflow-Test --serial IP:PORT
python modules/ai_assistant/tests/device_workflow.py send --root /storage/emulated/0/Documents/GodotAI-New-Workflow-Test --prompt-file /cale/cerinta.txt --effort medium
python modules/ai_assistant/tests/device_workflow.py status --root /storage/emulated/0/Documents/GodotAI-New-Workflow-Test
python modules/ai_assistant/tests/device_workflow.py collect --root /storage/emulated/0/Documents/GodotAI-New-Workflow-Test --serial IP:PORT --output .ai-qa/proba-noua
```

Pentru un server ADB separat, adauga `--server-port PORT` operatiilor ADB.
`stop` cere oprirea, iar `capture` salveaza imaginea editorului. `prepare` refuza
directoare existente; `collect` cere un director de dovezi nou. Directorul
proiectului, `project/`, ramane disponibil pentru inspectie. Pluginul de proba
poate fi dezactivat din Project Settings / Plugins dupa incheiere.

Runda curenta si diferentele dintre APK-ul instalat, sursele noi si eventualele
probe cu adaptor de dezvoltare sunt in
[raportul de stabilitate din 27.10.2026](AI_AGENT_STABILITY_20261027.md).

## Proba fizica din 26.10.2026

- Dispozitiv: NX729J, Android 15, Adreno 740.
- APK: `com.jdscript.godotai.debug`, Godot 4.7.2, sursa `c418f97`.
- Hash-ul scriptului panoului incarcat corespunde exact sursei livrate.
- Furnizor agent: DeepSeek, modelul deja selectat; reasoning `medium`, Auto.
- Profiluri existente: Grok Imagine Image si TRELLIS.2 prin Runware.
- Proiect: `/storage/emulated/0/Documents/GodotAI-Workflow-Test-20261026/project`.
- Cerinta: Terrain3D, un singur copac generat, apoi 12-16 instante, poteca,
  poiana, lumina/camera si verificarea scenei. Generarile de referinta,
  eliminarea fundalului si un singur mesh au fost autorizate; fara variante.

Runda a durat **243,8 secunde** in harness: **30 cereri catre agent**,
**39 rezultate de tool**, dintre care **7 nereusite**. Statusul final real este
`limited / step_limit`; harta nu a fost finalizata. Durata exclude timpul de
pregatire a conectorului si inspectia ulterioara.

| Etapa | Dovada reala | Rezultat |
| --- | --- | --- |
| Cautare Terrain3D | `store_search` si `store_describe` au returnat addonul | Trecut |
| Instalare | `store_install`: 163 fisiere, versiunea v1.0.2 | Trecut |
| Extensie Android | Proba rulata in APK: clasa Terrain3D exista si poate fi instantiata | Trecut |
| Activare editor | Agentul a scris setarea pluginurilor; starea efectiva a pluginului nu a fost interogata separat | Neverificat complet |
| Generare imagine | Runware a raportat `success`, URL PNG si cost 0,02 USD pentru acelasi job | Furnizorul a raportat rezultat |
| Recuperare in aplicatie | HTTP 500 cu payload de succes; `asset_status` si `asset_wait` au respins raspunsul | Esuat |
| Import imagine | `asset_import` a respins jobul local nefinalizat | Esuat |
| Mesh, preview 3D, harta | Nu au fost obtinute in runda | Neatinse |

Jobul imaginii este `afa289b7-ed76-4676-83ff-c5995833cb92`. Nu a fost repetata
generarea. Evaluatorul a descarcat ulterior **acelasi original PNG** din URL-ul
returnat de furnizor, fara alta cerere de generare. Aceasta este o interventie
manuala de recuperare, in afara proiectului agentului; nu este prezentata ca
import autonom reusit. Imaginea are 1024 x 1024, RGBA cu alpha 255 peste tot:
eliminarea fundalului ar mai fi necesara inainte de reconstructie. Costul de
0,02 USD este cel raportat de Runware pentru imagine, nu factura totala a
probei; cererile DeepSeek sunt separate.

Constatari: tratarea recuperarii unui rezultat valid intr-un raspuns HTTP de
eroare necesita corectie; descoperirea/utilizarea tool-urilor a consumat multi
pasi, inclusiv doua editari respinse ale project.godot; planul nu a fost
actualizat corect la trecerea de la instalare la generare. Nu s-au modificat
adaptoarele de productie pentru a masca aceste probleme si nu s-a construit
manual harta in locul agentului.

Dovezi locale: `.ai-qa/device-world-workflow-20261026/report.json`,
`identity.json`, `events.jsonl`, `journal.json`, `editor.png`,
`recovered-original-tree.png`. Markerul original al proiectului a fost pastrat.
Sursele finale ale controlerului au verificare de compilare separata;
operatiile status/collect au fost rulate pe telefon. Oprirea in timpul unei
cereri nu a fost testata intr-o a doua runda platita.
