# Runtime Linux integrat în aplicație

Stare: **implementat în surse, 25.10.2026**. APK-ul din Downloads nu a fost
recompilat sau înlocuit. Testele de dezvoltare nu sunt prezentate drept probă
a serviciului din aplicația Godot instalată.

## Funcționare

În **Integrări → Runtime Linux**, butonul **Instalează Linux** extrage în
stocarea privată a aplicației un pachet Debian ARM64 inclus în build. După
pornirea și verificarea reală a shell-ului prin PRoot, apare **Linux activ**.
Nu sunt necesare Termux, copierea comenzilor sau o aplicație companion.

Utilitare opționale: **Python**, **Node.js și npm**, **Git**, **ripgrep** și
**Blender CLI**. Ele se descarcă din depozitele Debian la acțiunea explicită
de instalare. Sunt marcate instalate după verificarea executabilului. Baza
Linux este verificată înaintea activării comenzilor agentului. Verificarea
versiunii Blender nu dovedește încă modelare/randare în APK.

Runtime-ul oferă o bază pentru CLI-uri și harness-uri bazate pe Node/Python.
Nu înlocuiește automat harness-ul existent al agentului. Autentificarea,
protocolul de mesaje/tool-uri și compatibilitatea fiecărui harness extern
necesită integrare și probe proprii. Nu există în această etapă un harness
extern instalat, autentificat și validat în Godot.

## Implementare

- `tools/embedded-runtime/rootfs.json` fixează sursa oficială
  [debuerreotype](https://github.com/debuerreotype/docker-debian-artifacts),
  commitul, arhitectura, dimensiunea și SHA-256 ale stratului Debian.
- `rootfs.py` produce ZIP-ul cu bytes regulați și un manifest pentru directoare,
  permisiuni și legături. Arhiva este verificată înainte de extracție; fiecare
  fișier este verificat individual. Nu se scrie prin legături create de arhivă.
- `AILinuxRuntimeFiles.kt` instalează în staging și publică directorul propriu,
  pornește executabilele PRoot/loader din `nativeLibraryDir`, apoi shell-ul și
  programele Linux. Nu folosește prefixul sau executabilele Termux.
- `AILinuxRuntimeService` este neexportat, în procesul `:ai_runtime`, cu serviciu
  Android foreground pentru operații lungi și buton de oprire în notificare.
- Joburile au stare atomică, jurnal limitat, heartbeat, timeout și anulare.
  O operație întreruptă nu este relansată automat. Instalările APT verifică
  rezultatul; o eroare nu devine succes doar fiindcă descărcarea s-a încheiat.
- JNI injectează proiectul real deschis; modelul nu alege directorul gazdă.
  Linux vede proiectul la `/workspace`. Comenzile primesc un mediu controlat,
  fără cheile furnizorilor AI copiate automat din seiful aplicației.
- `linux_status`, `linux_execute` și `linux_install_tool` folosesc catalogul și
  permisiunile existente. Execuția este o operație externă: modul Plan nu o
  autorizează. Instrumentele active sunt oferite numai după verificarea Linux.
- Ștergerea Linux cere confirmare și elimină doar propriul filesystem/pachete.
  Proiectele montate sunt păstrate. Ștergerea recursivă nu urmărește symlink-uri.

PRoot este un mediu de compatibilitate, nu un sandbox de securitate sau o
mașină virtuală. Programele rulează cu permisiunile aplicației și kernelul
Android. Procesele daemon și CLI-urile interactive nu sunt transformate automat
în servicii MCP sau în adaptoare de agent prin această implementare.

## Pachetul de bază și build

Sursa: Debian trixie slim ARM64, commit
`9c4818e3bfd35139d3798b0420e9c46836658b2e`; strat gzip SHA-256
`ddc0c1e36a6793411b6c8d48e1ddad2987405d377da92bcf532ed3181c2e4d62`.
Pachetul rezultat are **32.789.398 bytes**, **104.455.032 bytes** de fișiere
regulate și **3.265 intrări**. Pachetele opționale ocupă spațiu suplimentar.

Gradle execută `rootfs.py` după buildul nativ PRoot. Sistemul de fișiere este
ambalat în assets, iar executabilele Android rămân în bibliotecile native
extrase de instalatorul Android. Rootfs-ul păstrează fișierele copyright ale
pachetelor. Livrarea efectivă a APK-ului și inventarul/sursele aferente
pachetelor distribuite trebuie verificate separat înaintea publicării.

## Dovezi și limite

- Kotlin: compilare reușită a managerului, serviciului și instalatorului cu
  clasele Android; aceasta nu este o compilare APK/Gradle completă.
- C++: verificare de sintaxă pentru puntea JNI și înregistrarea modulului.
- Teste de arhivă: 4 teste Python, plus 6 cazuri executate împotriva
  instalatorului Kotlin, inclusiv traversări și legături nepermise.
- Godot: 429 aserțiuni runtime, 426 verificări UI pe formatul tabletei și
  47 verificări focalizate pe runtime la fiecare dintre două dimensiuni.
  Interfața a fost inspectată vizual; puntea Android este simulată în fixture.
- Probă reală de dezvoltare: instalarea pachetului de bază și a Python
  3.13.5, Node 20.19.2, Git 2.47.3, ripgrep 14.1.1 într-un filesystem nou,
  separat de containerul Debian existent al utilizatorului. Au trecut
  execuția prin directorul proiectului, fișierul scris, limitarea ieșirii,
  timeout-ul și anularea.
- PRoot-ul compilat din sursele noastre a pornit aceleași patru utilitare
  în proba de control. Pentru această probă a fost folosit loader-ul deja
  ambalat al Termux; nu este dovada loader-ului nou din APK-ul Godot.

Dovezi locale: `.ai-qa/linux-runtime-package/`,
`.ai-qa/linux-runtime-kotlin.log`, `.ai-qa/linux-runtime-cpp.log`,
`.ai-qa/linux-runtime-godot.log`, `.ai-qa/linux-runtime-ui/`,
`.ai-qa/linux-runtime-narrow/`, `.ai-qa/linux-runtime-full/`,
`.ai-qa/linux-runtime-tools.log`, `.ai-qa/linux-runtime-execute.log`,
`.ai-qa/linux-runtime-custom-proot.log`, `.ai-qa/linux-runtime-custom-execute.log`,
`.ai-qa/linux-runtime-verification.json` și
`.ai-qa/linux-runtime-control/smoke-result.json`.

Urmează proba fizică în APK cu propriul loader, foreground service, instalare,
oprire și reluare după trecerea aplicației în fundal. Blender complet și un
harness extern sunt probe distincte. APK-ul stabil din Downloads rămâne intact.
