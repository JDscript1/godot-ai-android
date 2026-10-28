# Chat, capturi și ciclul playtestului — AG-55

Implementat în surse la 28.10.2026. APK-ul instalat și cel din Download nu au fost schimbate în această etapă.

## Jocul pornit pentru verificare

`godot_run` refolosește aceeași scenă deja pornită. `restart=true` cere explicit o repornire, de exemplu pentru încărcarea codului modificat. O altă scenă deja deschisă este raportată înainte de înlocuire. Pornirea singură nu confirmă rularea sau interacțiunea.

Sesiunile temporare pornite de agent sunt închise la finalizarea cererii, la Stop și la ieșirea panoului. Subagentul Playtest închide sesiunea pe care a pornit-o și dacă verificarea inițială eșuează. O sesiune existentă este împrumutată, fără preluarea dreptului de închidere. Semnalele reale ale EditorRunBar detectează inclusiv oprirea și repornirea manuală a aceleiași scene.

`keep_open=true` se folosește când utilizatorul cere să rămână jocul deschis. Instrucțiunile agentului cer viewportul editorului pentru compoziție statică, test runtime pentru comportament, refolosirea sesiunii și capturi la momente relevante. Aceste instrucțiuni nu garantează că orice model alege întotdeauna numărul optim de verificări. Închiderile automate apar în jurnal ca `playtest_cleanup`.

## Capturile automate

Anterior, capturile puteau exista ca fișiere originale, copii cu hash, miniaturi și cadre separate în `qa_runs`. Nu exista o politică generală de expirare pentru acestea.

Capturile noi ale editorului și jocului sunt în stocarea privată a aplicației, în `ai_assistant/projects/<proiect>/files/captures/`, cu un singur PNG și o miniatură per conținut. Un cadru identic refolosește aceleași fișiere. Nu sunt salvate în galeria Android sau în proiect.

Capturile automate nefixate sunt curățate după maximum 24 ore, la depășirea a 64 capturi sau a 64 MiB, incluzând miniaturile. Curățarea rulează la încărcare, după capturi, la finalizare și periodic cât panoul există. Metadatele rămân pentru ca istoricul să poată afișa „Captură expirată”. Miniaturile vizibile expirate sunt eliberate și din UI. Fixarea într-o conversație protejează captura; capturile fixate sunt în afara bugetului automat.

Datele PNG ale instrumentelor nu se dublează în atașamentele permanente ale conversației. Buffer-ele sunt scoase din istoricul activ la salvare și încărcate din cache numai în bugetul vizual al contextului. În caz de eșec la scrierea cache-ului, pixelii temporari nu sunt salvați într-o copie permanentă alternativă.

Politica se aplică noilor capturi automate. Nu șterge retroactiv directoarele vechi `qa_runs`, fișierele utilizatorului, capturile manuale găsite în stocare, asseturile generate sau imaginile cache ale previzualizării unui asset 3D.

## Derulare și tastatură

Derularea manuală în sus suspendă urmărirea mesajelor noi. Săgeata în jos apare în colțul conversației; apăsarea duce la ultimul mesaj și reactivează urmărirea. Modificarea înălțimii mesajelor și streamingul nu schimbă singure această alegere. O conversație nouă pornește cu urmărirea activă.

Pe Android, înălțimea tastaturii raportată de Godot este transformată în coordonatele viewportului și redusă cu spațiul liber de sub chat. Un spacer restrânge zona conversației astfel încât composerul să rămână deasupra tastaturii. Mesajele lungi se derulează în propriul câmp, cu cursorul adus în vedere; închiderea tastaturii restaurează spațiul.

## Dovezi și limite

Probe în editor upstream izolat, fără chei sau generări plătite: gesturi touch, rotiță, streaming, revenire la final, tastatură simulată, retenție/pin/deduplicare/bugete, sesiuni reale pornite și oprite prin EditorInterface și eșec timpuriu al subagentului. Dovezile sunt în `.ai-qa/chat-lifecycle-20261028/`.

Tastatura reală, focusul dintre activitățile Android și comportamentul complet al modelului prin API necesită noul APK și acceptare fizică. Randarea prin Xvfb/PRoot emite avertismente de mediu legate de XServer și `--shm-helper`; acestea sunt păstrate în loguri, separat de rezultatele verificărilor.

Rezultate finale: **749 aserțiuni runtime**, **68 verificări focalizate narrow**, **68 phone_compact**, toate fără eșecuri; **35 surse încorporate identice**. Regresia extinsă **744/0** precede ajustările finale de etichetă pin și separarea imaginilor externe; acestea sunt acoperite de probele finale focalizate.
