# Dezvoltare verificată a jocurilor — etapa AG-66

Cererea utilizatorului include toate cele opt direcții. Agentul propriu rămâne
nativ în Godot; runtime-urile externe sunt opționale. APK-ul nu este regenerat
în această etapă. Originalele și schimbările manuale sunt păstrate.

Toate cele opt direcții sunt implementate în surse. Coloana de verificare
distinge probele efectuate de integrarea nativă care necesită următorul APK.

| Funcție | Instrumente | Verificare în această etapă |
| --- | --- | --- |
| Reparații cu dovezi | `repair_start`, `repair_check` | Diagnostic și joc simulate, rapoarte/fișiere reale; respinge ipoteze neobservate și probe vechi |
| Relații și impact | `godot_impact`, `godot_project_map` | Noduri, scripturi atașate, semnale, comentarii și dependențe tranzitive |
| Recuperare durabilă | `task_recovery`, `task_reconcile` | Restart al stării, apel plătit incert, reluare fără execuție dublă, coadă și rotația chitanțelor |
| Gameplay repetabil | `qa_save/list/run/report` | Condiții măsurate, eroare la pornire, întrerupere, surse schimbate, eliberare/închidere; peer de joc simulat |
| Experimente | `experiment_create/read/write/compare/stage` | Copie reală, editări independente, hash-uri și conflicte; lansatorul nativ compilat ca obiect C++ |
| Asseturi pentru joc | `asset_audit`, `asset_prepare` | GLB real exportat/importat; prefab reîncărcat cu scară, pivot și coliziune; original intact |
| Performanță | `profile_run`, `profile_compare` | Comparator numeric și cod nativ compilat; colectarea în joc pe Android rămâne de validat |
| Memorie și specialiști | `memory_search/remember/forget`, `agent_profiles`, `agent_profile_save` | Proveniență, ștergere, conflicte, allowlist în dispatcher și raport de copil întrerupt |

## Un test salvat

`qa_save` păstrează definiția în stocarea privată a proiectului. Exemplu:

```json
{
  "id": "player-health",
  "scene": "res://scenes/game.tscn",
  "steps": [
    {"kind": "watch", "expressions": ["Player.health"], "signals": []},
    {"kind": "act", "inputs": [{"kind": "action", "action": "move_right"}], "advance_frames": 30},
    {"kind": "assert", "expression": "Player.health", "op": "gt", "expected": 0}
  ]
}
```

Expresiile sunt probe doar pentru citire în scena reală, prin puntea existentă.
Numele/proprietățile trebuie adaptate jocului; exemplul nu certifică niciun joc.
Scenariul reia inputul și condițiile, dar nu impune determinism asupra RNG-ului
sau fizicii jocului. Folosește condiții și semnale măsurate, apoi repetă proba
pentru comportamente dependente de timp sau de întâmplare.
`qa_run` refuză un joc deja pornit de utilizator. Confirmă proiectul, scena,
sesiunea și generația nouă a debuggerului. La final eliberează inputul și
închide doar procesul propriu, inclusiv la eroare sau Stop. Un raport de execuție
întreruptă rămâne întrerupt; actualizarea definiției cere hash-ul curent.

Într-o reparație, agentul reproduce defectul, înregistrează `repair_start`,
formulează ipoteza și modifică sursele prin instrumentele recuperabile. Apoi
rulează aceleași scenarii, fără schimbarea condițiilor inițiale pentru a fabrica
un rezultat, și cere `repair_check`. Sunt necesare o eroare inițială observată,
acoperire de diagnostic suficientă și cel puțin o regresie trecută pe sursele
actuale. Erorile vechi din sesiuni oprite nu sunt prezentate drept erori curente.

## Copii și asseturi

Experimentele folosesc fișiere copiate, nu hardlink-uri. Includ cache-urile de
import necesare jocului și exclud VCS, starea editorului și fișierele evidente
de credențiale. `experiment_write` cere hash-ul proaspăt sau `missing`.
`qa_run` poate primi `experiment`; `experiment_stage` cere un raport trecut pe
digestul actual al copiei și verifică dacă originalul a fost editat între timp.
Selecția care omite alte modificări ale copiei este refuzată: acel subset
necesită propria probă. Produce un lot normal pentru `godot_changes_apply`; nu aplică automat.
Lansatorul propriu evită salvarea/construirea proiectului original.

`asset_prepare` produce un prefab nou, cu înălțime opțională în metri,
centrare/ancorare la sol, generare nativă LOD și coliziune convexă/trimesh.
Originalul GLB rămâne intact, iar prefab-ul intră în jurnalul de restaurare.
Numărul efectiv al LOD-urilor este raportat; o geometrie prea simplă poate
produce zero niveluri suplimentare. Auditul nu certifică stilul vizual,
animațiile sau potrivirea pentru gameplay.

## Recuperare, memorie și cost

Intenția unei operații este salvată înainte de execuție și rezultatul înainte
de confirmare. Un efect rămas incert nu este repetat automat. Pentru un job
plătit se verifică exact ID-ul original; fără acel ID se raportează blocajul.
Chitanțele confirmate sunt arhivate individual, astfel încât memoria activă
limitată să nu impună un plafon de pași productivi. Execuțiile fără progres,
oprirea utilizatorului, erorile și imposibilitatea salvării rămân condiții de
oprire. Coada restaurată este pusă pe pauză pentru a preveni trimiterea ei
accidentală la pornirea aplicației.

Preferințele automate provin numai din formulări explicite ale utilizatorului;
pot fi dezactivate și inspectate/uitate în **Setări → Dezvoltare verificată**.
Agentul nu poate inventa un citat al utilizatorului pentru `memory_remember`.
Procedurile verificate sunt scrise numai după un `repair_check` reușit și
conțin ID-urile dovezilor. Memoria nu prevalează asupra cererii curente sau a
permisiunilor. `AGENT.md` rămâne separat.

Un specialist poate avea instrucțiuni, rol, model/furnizor și allowlist de
instrumente proprii. Restricțiile sunt aplicate în catalog și în dispatcher.
Copiii returnează constatări/propuneri; părintele verifică și aplică. Pentru
Playtest rămân necesare instrumentele de input și alegerea unui profil vizual.
Nu există o limită generală de pași; concurența și bugetele operațiilor sunt
distincte. Un raport de copil rămas `running` după restart este citit ca
`interrupted`, fără relansare automată a cererilor cloud.

## Metrici și limite

Profilarea colectează intervalele cadrelor jocului: medie, p95 și maxim,
precum și monitoarele native de proces/physics, memorie statică a motorului,
draw calls și primitive. Include warmup, număr de cadre, viewport, dispozitiv,
renderer și versiunea motorului. Draw calls și memoria sunt eșantioane ale
monitoarelor de la final, nu statistici ale tuturor cadrelor. Comparația cere
aceleași condiții și raportează delte; măsurarea trebuie repetată pentru zgomot.
Nu este profilare GPU, memorie totală Android sau benchmark independent de
hardware. Erorile jocului sau probele incomplete împiedică un rezultat valid.

Bugetele sunt explicite: 64 pași/scenariu, cel puțin o condiție, 2.000 fișiere
/512 MB per snapshot experimental, 1 MB per editare text a copiei, GLB până
la 100 MB, 5.000 noduri și bugete de geometrie/texturi în audit. Integrarea
textului folosește limitele loturilor existente; fișierele binare se păstrează
separat. Harta este conservatoare pentru referințe literale; încărcările
dinamice și nodurile create la runtime cer probe reale. Copia nu este un
sandbox de securitate pentru cod arbitrar. Proiectele mari cer lucru pe arii
mai mici; nu pretindem că toate erorile posibile pot fi detectate automat.

Dovezi locale: `.ai-qa/engineering-20261030/verification.json`. Runtime: 922/0,
44 scripturi încorporate verificate octet cu octet și două obiecte C++ ARM64
compilate local. Rularea completă `full-traced`
a trecut 895 verificări, iar `phone-engineering` 65; harness-ul focalizat final 78. Au existat anterior căderi
native intermitente în suita grafică, fără eroare GDScript; cauza nu este
declarată rezolvată de o singură rulare trecută. APK, gesturi pe Android,
profilare reală și furnizori cloud nu au fost validate în această etapă.
Comparația cu Ziva necesită aceleași sarcini, modele și dispozitive.
