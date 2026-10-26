# Evaluare Claude Code 2.1.112 ca motor al agentului

26.10.2026. **Propunere verificată prin documentație și probe locale de pornire;
nu este implementare în APK.** Recomandare: pilot în Linuxul integrat, păstrând
chatul, seiful și uneltele Godot; trecerea motorului principal se decide după
o probă reală completă. Furnizorii incompatibili păstrează ruta nativă.

## Ce este confirmat

- Pachetul local Termux `@anthropic-ai/claude-code` este 2.1.112. Metadatele
  locale și registrul npm indică `cli.js` și Node >=18. `claude --version` și
  `--help` au ieșit cu succes; nu s-a trimis o inferență plătită.
- CLI-ul local are intrare/ieșire stream-json, reluare de sesiune, MCP strict
  și mesaje parțiale. Flagurile și mesajele pentru aprobări trebuie verificate
  pe protocolul versiunii fixate; documentația curentă include funcții mai noi.
- DeepSeek documentează conectarea la Claude Code prin endpointul său Anthropic.
  Harness-ul Claude Code poate astfel utiliza un model DeepSeek. Nu dovedește
  compatibilitatea fiecărui furnizor OpenAI-compatible sau a fiecărui model local.
- Claude Code are licență proprietară. Nu reprezintă o bază open source pe
  care să o copiem în motorul Godot; condițiile distribuției trebuie verificate
  pentru forma de livrare aleasă.
- În repository există deja un adaptor SDK în companion, cu SDK 0.3.233 și
  CLI 2.1.233. Acesta nu este integrat în Linuxul Android și nu constituie o
  probă de compatibilitate cu CLI 2.1.112.

## Integrarea propusă

Chatul Godot transmite mesaje unui proces supravegheat în Linuxul propriu al
aplicației. Un adaptor normalizează evenimentele CLI/SDK pentru text, tool-uri,
plan, consum, jurnal, oprire și reluarea conversației. Godot expune uneltele sale
prin MCP: scene, fișiere, Store, generare Runware, import și preview 3D.

Cheile rămân în seif și sunt transmise doar procesului necesar; nu intră în
comenzi vizibile, configurări de proiect sau jurnal. Proiectul rămâne montat
prin calea controlată de aplicație. Nu se folosește instalarea Termux existentă
ca dependență a produsului.

Auto / Default / Plan și YOLO rămân controale Godot. Aprobările trebuie să
acopere și eventualele tool-uri native Claude de scriere/shell, pentru a păstra
politica aleasă de utilizator. Pilotul poate folosi mutațiile prin puntea Godot;
editările directe trebuie legate de protecția bufferelor nesalvate, scanarea
resurselor, diff și recuperare. Panoul de aprobare și conversia tipurilor din
tool-uri rămân responsabilitatea aplicației.

**Nu este suficient `linux_execute("claude ...")`.** Runnerul actual limitează
comenzile la 600 s, iar monitorizarea GDScript are termen total de 30 minute.
Acestea sunt limite pentru comenzi, nu o gazdă de sesiuni de agent. Integrarea
cere I/O bidirecțional, evenimente incrementale, proces de durată și anulare/
reluare controlate, fără un plafon total implicit de pași sau de durată pentru
conversație. Timeouturile de conexiune și detectarea blocajelor rămân distincte.

Versiunea 2.1.112 se fixează împreună cu adaptorul/SDK-ul compatibil și se testează
fără actualizare automată în timpul probei. Pornirea în Termux nu certifică
funcționarea în filesystemul, serviciul foreground și loader-ul APK-ului.

## Proba care decide înlocuirea

1. Pornire în Linuxul aplicației și o conversație cu profilul DeepSeek existent.
2. Citire, editare, verificare și corectarea unei erori reale prin tool-uri Godot.
3. Aprobare/refuz, Plan fără scriere, Stop, reluare și revenire din fundal.
4. O generare Runware autorizată, recuperarea aceluiași job, import și card de
   preview; verificare alpha pentru imagini și încărcare GLB pentru mesh-uri.
5. Aceeași sarcină și model ca la harness-ul nativ, comparate prin rezultate
   verificate, intervenții necesare, cost și erori. Nu se fabrică manual scena
   pentru a declara testul autonom reușit.

Surse primare consultate:

- [Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview)
- [Execuție programatică și streaming](https://code.claude.com/docs/en/headless)
- [Permisiuni](https://code.claude.com/docs/en/agent-sdk/permissions)
- [DeepSeek cu Claude Code](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/)
- [Licența Claude Code](https://github.com/anthropics/claude-code/blob/main/LICENSE.md)

Niciun harness nu a fost înlocuit, nu s-au extras sau schimbat chei,
iar APK-ul nu a fost recompilat în această evaluare.
