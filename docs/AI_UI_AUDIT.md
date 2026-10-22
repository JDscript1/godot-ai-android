# Audit interfață AI — 22 octombrie 2026

Captura de referință: `Screenshot_20261022_200421.jpg`. Dock-ul stâng tăia
Setări și Trimite, iar Șterge impunea arhivarea fără să indice această condiție.

## Corecții

- Dock-ul stâng folosește coloana exterioară. Chatul ocupă zona reală a tabului,
  cu margini și înălțime recalculate după mutare, redimensionare și extindere.
  Limita se aplică și în dreapta. Vizibilitatea celorlalte coloane se restabilește
  la revenirea în centru; adaptarea la ecrane înguste rămâne temporară.
- Selectorii se dimensionează după spațiul alocat chatului. Bara de control
  trece pe rânduri suplimentare când nu încape; ultimul rând se aliniază la dreapta.
  Mesajul de întâmpinare se încadrează pe mai multe rânduri.
- Pe lățimi sub 900 unități, Istoric ocupă pagina chatului. Înapoi readuce chatul;
  selectarea sau crearea unei conversații închide istoricul compact. Redimensionarea
  respectă alegerea utilizatorului privind istoricul.
- Șterge confirmă numele conversației și funcționează pentru conversații normale
  sau arhivate. Anularea păstrează fișierul și indexul. Confirmarea activează o
  conversație rămasă; dacă a fost ultima, creează una goală.
- Transcriptul este păstrat temporar până la salvarea indexului; o eroare de
  scriere reface starea anterioară. La pornire se recuperează un transcript
  intermediar încă referit de index. Crearea eșuată nu înlocuiește chatul activ.
- Exportă deschide un dialog de salvare `.md`, cu titlul și mesajele conversației
  curente. Copierea unui răspuns rămâne o acțiune separată.
- Arhivează/Dezarhivează păstrează conversația selectată și schimbă lista corectă.
  Favoritele descriu acțiunea inversă. Un filtru fără conversația activă dezactivează
  acțiunile istoricului. Execuția agentului dezactivează acțiunile indisponibile.
- Redenumirea elimină spațiile marginale, refuză un nume gol și acceptă Enter.
- Ciornele și referințele sunt separate pe conversații în sesiunea editorului.
  Nu sunt prezentate drept ciorne persistente după închiderea aplicației.
- Ramificarea refuză un ID de mesaj expirat. Aplică planul trimite textul planului
  ales. Modificări/Undo este dezactivat dacă răspunsul nu are modificări;
  Copiază este dezactivat pentru un răspuns fără text.

## Contracte verificate

| Control | Efect verificat în fixture izolat |
| --- | --- |
| Nou / deschide conversație | transcript păstrat, ciornă nouă goală, ciorna originală restaurată |
| Favorite | adăugare și eliminare, tooltip actualizat |
| Redenumește | anulare, nume gol refuzat, Enter, titlu actualizat |
| Exportă | fișier Markdown real cu titlu și mesaje |
| Arhivează / Dezarhivează | liste separate, selecție și acțiune inversă |
| Caută | conversații filtrate, acțiuni inactive pentru listă fără selecție |
| Șterge | nume în confirmare, anulare intactă, ștergere pe disc, index redeschis |
| Copiază răspuns | conținutul răspunsului ales în clipboard |
| Ramifică de aici | capătul corect al ramurii, originalul complet pe disc |
| Setări / Închide | fereastra se deschide și se închide efectiv |
| Istoric / Înapoi | pagini alternative în dock îngust, fără lărgirea coloanei |
| Extinde / restrânge | centru și întoarcere la dock, preferință păstrată |
| Stop | vizibil lângă Trimite în timpul lucrului; anulează transcrierea fixture |
| Model / reasoning / mod | sertare, Înapoi/anulare, alegere atomică și niveluri ale modelului |
| Atașamente / Pin / Menționează / Trimite | suita de regresie pentru fișiere, preview și coadă |
| Imagini / 3D / diff / Store | suitele existente verifică starea reală în editorul izolat |

Verificarea încadrării include fiecare selector și controalele Setări, Extinde,
Context, Dictare, Stop și Trimite în ambele dock-uri limitate la 224 unități,
cu context de 100% și transcriere activă. Verificarea folosește dreptunghiurile
chatului și ale tabului, nu doar marginea ferestrei.

## Dovezi și limite

- Runtime local: **302 aserțiuni, zero eșecuri**,
  `.ai-qa/dock-audit-unit-final.log`. Include probe pentru erori de salvare,
  ștergerea ultimei conversații și recuperarea după întrerupere.
- Sintaxă C++ Android verificată pentru `ai_assistant_editor.cpp`.
- Editor upstream: 279 verificări fără eșecuri pe desktop și fereastră îngustă;
  după corectarea înălțimii barei, 279 fără eșecuri și pe fereastra mare
  (`.ai-qa/dock-audit-final/`, `.ai-qa/dock-audit-wrap-height/`).
  Revalidarea dock-urilor pe cinci dimensiuni și compilarea noului APK sunt în curs;
  livrarea anterioară `6539a44` nu conține aceste corecții.
- Butoanele care depind de microfon, autentificare, provideri, servicii de generare,
  servere MCP și catalogul public Store necesită separat verificare cu dispozitivul
  sau serviciul real. Fixture-urile nu confirmă un cont sau serviciu live.
