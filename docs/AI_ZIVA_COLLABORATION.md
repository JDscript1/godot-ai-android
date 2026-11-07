# Colaborarea dintre Godot AI și Ziva

Actualizat: 7 noiembrie 2026. Inclus în APK-ul Ziva `c4b9431`, verificat și livrat.
Starea sursei, verificărilor și APK-ului livrat este
în [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).

Cei doi agenți pot comunica și primi sarcini în același proiect salvat. Fiecare
folosește propriul model, propriile unelte și propriile permisiuni. Legătura nu
unește istoricul sau cheile API. Rezultatul confirmat al unui job este separat
de simpla acceptare a mesajului.

## Corecții în APK `c4b9431` — 7 noiembrie 2026

Pentru o cerere doar despre pornirea/starea Ziva, ghidajul indică `ziva_status`,
fără pornirea suplimentară a unei sarcini de model. `finish=aborted` este raportat ca întrerupere,
nu succes, chiar dacă Ziva a executat deja unelte. Finalizarea fără text sau cu
`finish=error` raportează eroare. Contextul `synthetic` este exclus din textul
folosit pentru corelarea cererii; mesajele altor utilizatori/ture nu sunt preluate.

În fila Ziva, gazda nu mai repară manual cursorul și nu întrerupe focusul la
începutul apăsării pe Trimite. Handlerul oficial citește ciorna înainte de
ascunderea tastaturii, iar compoziția IME se încheie înaintea acelei ascunderi.
Verificările locale sunt automate; acceptarea pe tastatura fizică rămâne deschisă.
Verificările CI și livrarea acestui APK sunt în documentul de progres.

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

În această versiune livrată, joburile pornite de un tur devin dependențe
obligatorii. Bariera de finalizare așteaptă rezultatul real, îl transmite modelului
și respinge verdictul de succes dacă jobul încă rulează, a eșuat, a fost anulat
sau așteaptă permisiune/întrebare. Citirea repetată a aceluiași rezultat nu
invalidează din nou probele locale. Un flag de fundal scris de model nu elimină
această obligație. Reluarea păstrează identitatea jobului fără retrimitere automată.

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
var peer = load("/run/godot-ai-agent-link/client.gd").new()
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
În versiunea livrată, joburile sunt salvate în directorul privat al proiectului.
Rezultatele și identitățile cererilor rămân disponibile după repornire, inclusiv
prin chitanțe arhivate după evacuarea din cache. Un job care rula revine ca
`interrupted`; nu își reia automat modificările. Un jurnal deteriorat ori o
salvare eșuată refuză pornirea. Refolosirea unui request_id cu alt text sau altă
acțiune este un conflict. Răspunsurile sunt păstrate cu un buget de 128.000 de
caractere; paginarea acoperă fragmentul păstrat, iar `truncated` și
`original_characters` semnalizează o trunchiere.

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
