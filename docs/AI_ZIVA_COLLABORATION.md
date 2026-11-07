# Colaborarea dintre Godot AI și Ziva

Actualizat: 7 noiembrie 2026. Inclus în APK-ul Ziva `53a50e8`, verificat și livrat.
Starea sursei, verificărilor și APK-ului livrat este
în [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).

Cei doi agenți pot comunica și primi sarcini în același proiect salvat. Fiecare
folosește propriul model, propriile unelte și propriile permisiuni. Legătura nu
unește istoricul sau cheile API. Rezultatul confirmat al unui job este separat
de simpla acceptare a mesajului.

## Din agentul nostru către Ziva

Exemple de cereri în chat:

- „Întreabă Ziva ce a constatat despre scena principală și compară cu analiza ta.”
- „Dă-i lui Ziva verificarea scriptului player.gd; urmărește rezultatul.”
- „Verifică starea sarcinii Ziva și oprește acel job.”

Harness-ul oferă `ziva_status`, `ziva_task_start`, `ziva_task_status`,
`ziva_task_poll`, `ziva_task_result` și `ziva_task_cancel`. `ziva_task` păstrează
și delegarea care așteaptă rezultatul. Varianta `start` returnează imediat un
`job_id`, astfel încât agentul poate continua cu alte operații. Continuarea unei
conversații cunoscute este posibilă prin `chat_id` când conversația este liberă.
O a doua sarcină simultană în aceeași conversație este refuzată explicit.

Citirea stării arată și întrebările/permisiunile pe care Ziva le așteaptă.
Utilizatorul le rezolvă în Ziva. Agentul nostru nu aprobă acele dialoguri.
Anularea unui job încheiat nu oprește o cerere nouă din aceeași conversație.
Anularea nu anulează retroactiv fișierele deja modificate.

## Din Ziva către agentul nostru

Exemple pentru conversația Ziva:

- „Întreabă agentul Godot AI ce știe despre scena curentă.”
- „Trimite agentului Godot AI sarcina aceasta și urmărește răspunsul.”
- „Verifică progresul agentului Godot AI și ajustează cererea activă.”

Contextul global al sesiunii Ziva descrie clientul și operațiile disponibile.
Clientul este livrat de APK în directorul privat al sesiunii; proiectul nu
primește scripturi de integrare. Ziva îl apelează prin unealta sa verificată
`execute_script`, de exemplu:

```gdscript
var peer = load("/run/godot-ai-ziva/agent-link/client.gd").new()
print(JSON.stringify(peer.request("status")))
```

| Operație | Argumente | Comportament |
| --- | --- | --- |
| `status` | `{}` | Cererea activă, modul, coada, stările de așteptare și joburile legăturii. |
| `query` | `{"text":"..."}` | Întrebare executată prin modul Ask, cu unelte numai pentru citire. |
| `task` | `{"text":"..."}` | Sarcină în modul selectat, cu permisiunile normale ale agentului. |
| `poll`, `result` | `{"job_id":"...","offset":0,"limit":6000}` | Starea și un fragment al răspunsului acelui job. |
| `steer` | `{"turn_id":"...","text":"..."}` | Intervenție la următorul pas al cererii active identificate. |
| `cancel` | `{"job_id":"..."}` sau `{"turn_id":"..."}` | Oprește numai jobul sau cererea identificată. |

Răspunsurile folosesc `{ok, result}` sau `{ok:false, code, error}`. Un job primit
poate fi `queued`, `running`, `completed`, `failed`, `cancelled`, `blocked` sau
`limited`. `next_offset` indică următorul fragment; `-1` indică sfârșitul.
Joburile legăturii sunt urmărite în sesiunea curentă a editorului. După
repornire, un identificator vechi poate fi necunoscut; acesta nu devine dovadă
că cererea a fost executată sau reluată.

O cerere nouă așteaptă dacă agentul lucrează deja. O coadă oprită rămâne oprită.
O intervenție sau anulare cu `turn_id` vechi este refuzată. Ciorna utilizatorului
și atașamentele ei nu sunt preluate ori șterse de o cerere Ziva.

## Confirmări și limite

Transportul invers folosește fișiere private per proiect, scriere atomică și un
identificator al sesiunii. Nu deschide un server accesibil în rețea. Clientul
GDScript rulează în subprocessul Ziva; harness-ul nostru rămâne nativ în Godot,
fără Termux, Node sau Python necesare utilizatorului.

Un mesaj nu poate aproba dialoguri de permisiune. O întrebare Ask nu poate
executa scrieri nici când modelul încearcă să invoce o unealtă ascunsă. Dacă
agentul nostru așteaptă Ziva, o cerere trimisă înapoi lui este refuzată cu
`peer_cycle`; starea poate fi consultată în continuare. O cerere provenită din
Ziva nu poate fi delegată automat înapoi către Ziva.

Ziva folosește un editor Linux separat. Fișierele salvate sunt comune; scenele
nesalvate, importurile și starea runtime ale celor doi editori pot diferi.
Agentul trebuie să precizeze ce editor și ce dovezi a folosit. Textul răspunsului
Ziva nu înlocuiește verificările cerute în editorul Android.

Verificările locale includ widgeturi reale, harness-ul cu furnizor simulat,
clientul GDScript real conectat la transportul Kotlin și un server RPC local de
probă. Ele nu confirmă o conversație între două modele reale sau comportamentul
Android după instalare. Comenzi reproductibile:

```sh
python modules/ai_assistant/tests/run.py --godot godot
python tools/embedded-runtime/test_agent_link.py --godot godot
python modules/ai_assistant/tests/render.py --godot godot --scenario ziva
```

Testul JVM descarcă în cache compilatorul Kotlin al versiunii proiectului și
dependențele de test din Maven Central; acest tooling este numai pentru dezvoltare.
