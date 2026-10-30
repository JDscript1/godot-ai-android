# Analiză Ziva și îmbunătățiri ale harness-ului Godot AI

Data: 30 octombrie 2026. Versiunea inspectată: **Ziva v3.3.2 Linux ARM64**.

## Ce a fost analizat

Executabilul oficial `zivacode`, de 116.771.624 bytes, SHA-256
`7797be07153d515fb0a96a8438f811d633610e4e39caa582334e87cc5ef6c200`.
Originalul a fost păstrat intact. Analiza a extras fișierele incluse în
secțiunea ELF `.bun`, folosind structura containerului Bun și verificând
limitele și numele din tabelul de module. Codul extras nu a fost executat.

Rezultatul: **194 de fișiere**, 26.450.119 bytes de conținut: 155 de fișiere
JavaScript, un entrypoint, un GDScript, un WASM, HTML/CSS, fonturi și imagini.
Aceasta este extragerea bundle-ului distribuit, nu reconstrucția proiectului
TypeScript original sau decompilarea bibliotecilor native C++/CEF.

Fișierele vendor extrase rămân exclusiv în directorul local ignorat
`.ai-qa/ziva-harness-analysis-20261030/extracted/`; nu sunt incluse în sursele,
APK-ul sau commit-urile Godot AI. Implementarea de mai jos este originală,
în harness-ul GDScript existent.

## Ce putem confirma despre backend

Bundle-ul include componente **Pi**, cu nume de pachete
`@earendil-works/pi-agent-core`, `@earendil-works/pi-ai` și
`@earendil-works/pi-coding-agent`, plus aliasuri pentru namespace-ul anterior
`@mariozechner`. Conține exporturi și folosiri pentru sesiuni Pi, providerul
`PiNativeProviders`, compactare automată și recuperare după depășirea
contextului. Prin urmare există dovezi locale că Ziva distribuie și folosește
componente Pi; concluzia anterioară bazată numai pe documentația publică era
incompletă. Nu identificăm astfel versiunea exactă Pi, toate modificările
Ziva sau echivalența cu o anumită versiune upstream.

Referințele OpenCode din catalog includ modele, furnizori, endpoint-uri și
variabile de mediu. Numărul lor nu demonstrează singur că orchestrarea este
un fork OpenCode. Nici posibilitatea de conectare la Claude Code/Codex nu
dovedește folosirea harness-ului lor pentru toate sesiunile.

Repere reproductibile, fără publicarea codului vendor:

| Reper | Fișier extras | Offset de caractere |
| --- | --- | ---: |
| `PiNativeProviders` | `001-chunk-q55k9fd0.js` | 1.797.283 |
| `@earendil-works/pi-agent-core` | același | 3.264.675 |
| `createAgentSessionRuntime` — export și folosire | același | 360.739 / 4.206.792 |
| `_overflowRecoveryAttempted` | același | 3.407.685 |
| `checkpoint-repositories` | același | 4.741.477 |

SHA-256 al chunk-ului:
`f6103e581bf85ef4cab498cb6b9a0d6645447702275150db8d8e20cff3e8f45b`.
Offset-urile sunt în textul decodat, nu în binarul ELF.

Surse publice pentru formatul și componentele identificate:

- [Bun — executabile standalone](https://bun.sh/docs/compiler/executables).
- [Bun — formatul grafului încorporat](https://github.com/oven-sh/bun/blob/main/src/standalone_graph/StandaloneModuleGraph.rs).
- [Pi agent core — context, evenimente, execuție](https://github.com/earendil-works/pi/tree/main/packages/agent).
- [Distribuția oficială Ziva v3.3.2](https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/tag/v3.3.2).

## Ce am schimbat în agentul nostru

Harness-ul rămâne în Godot și funcționează direct cu furnizorii configurați.
Tabul și backend-ul Ziva rămân independente. Nu este adăugată o dependență
de Bun, Pi, Node.js, shell sau PRoot pentru agentul propriu.

1. **Context în sarcini lungi.** Înaintea fiecărei cereri, bugetul euristic
   include mesajele și schemele instrumentelor. Când este depășit, doar
   rezultatele vechi și mari ale instrumentelor primesc o reprezentare
   compactă. Cererea utilizatorului, instrucțiunile, mesajele planului,
   identificatorii apelurilor și ultimul lot de instrumente rămân intacte.
   Contractele JSON compacte păstrează starea, erorile și identificatorii
   artefactelor în limita bugetului. Istoricul salvat, dovezile verificării
   și registrul operațiilor executate nu sunt rescrise.
2. **Overflow confirmat de furnizor.** Un prompt refuzat explicit pentru
   context prea mare poate primi o singură reluare, cu rezultate vechi
   reduse, numai dacă vederea trimisă modelului chiar se schimbă. Nu se
   reia după text parțial afișat, nu se repetă instrumente și nu se consumă
   bugetul separat de reîncercări pentru conexiune. Stop rămâne activ.
3. **Citiri proaspete.** Reutilizarea de către model a unui ID de apel nu
   mai întoarce automat o citire veche din registru. Starea proiectului și
   a joburilor este recitită. Protecția împotriva repetării scrierilor și
   generărilor plătite este păstrată.
4. **Erori intercalate.** Citirile reușite fără legătură nu mai ascund o
   aceeași operație eșuată repetată. La trei eșecuri apare îndrumarea de
   schimbare a strategiei, iar la șase fără progres agentul se oprește
   distinct. O modificare reușită sau reușita operației resetează evidența
   relevantă. Nu există o limită generală nouă de pași.

Jurnalul include `agent_context_pruned`, motivul, numărul de rezultate și
bytes economisiți, fără copierea payload-urilor în evenimentul de recuperare.

## Verificări și limite

- Suită runtime Godot 4.7.2 ARM64 în Debian/PRoot: **770 aserțiuni, 0 eșecuri**.
- Editor real, scenariul `compact`, interfață îngustă: **91 verificări,
  0 eșecuri**.
- Probele noi acoperă contextul redus, scheme mari, păstrarea sarcinii și a
  ultimului lot, date JSON necunoscute, ID-uri de job și calitate, recuperarea
  unică după overflow, refuzuri de autentificare, text parțial, Stop,
  reutilizarea jobului plătit, citiri proaspete și eșecuri intercalate.

Estimarea de tokeni este euristică, nu tokenizer-ul exact al fiecărui model.
Reducerea rezultatelor vechi nu înlocuiește compactarea semantică: un sistem
de instrucțiuni foarte mare, un ultim lot prea mare sau foarte mult text
netrunchiabil pot continua să depășească fereastra. Nu eliminăm cererea
utilizatorului ca să forțăm o cerere să încapă.

Acestea sunt probe locale cu furnizori simulați și un editor Linux real.
Nu sunt o probă live DeepSeek/Runware, un test al noului comportament pe
Android sau o livrare APK. Instalatoarele din Download nu au fost înlocuite.

Dovezi locale: `.ai-qa/ziva-harness-analysis-20261030/`: `binary.json`,
`module-table.json`, `extraction.json`, `findings.json`, `runtime.log`,
`rendered/narrow/editor-report.json` și `rendered/narrow/compact-regressions.json`.

## Următoarele îmbunătățiri propuse

- Compactarea semantică în interiorul sarcinii, Queue/Steer și Ask au fost
  implementate ulterior, după cererea de implementare a workflow-ului.
  [Starea și verificările workflow-ului nativ](agent-workflow.md).
- Istoric ramificat și comparație de checkpoint-uri, fără dependența de
  hardlink-uri Git în runtime-ul mobil.
- Evaluări pe proiecte reale pentru depanare, scene, generare, coliziuni,
  interacțiune și reluare după oprire, cu rata de succes și cost măsurate.

Istoricul ramificat și evaluările live rămân planificate. Analiza statică Ziva
nu constituie o dovadă de execuție a acestor funcții în Godot AI.
