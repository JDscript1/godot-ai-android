# Următoarele îmbunătățiri ale agentului

Actualizat: 23.10.2026. Aceasta este lista de priorități propusă; punctele de mai
jos nu sunt prezentate ca implementate. Starea verificată este în
[PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).

## Prioritate imediată

1. **Validare pe tableta/telefonul real.** Interfață, tastatură, gesturi, mutarea
   dock-ului, accesul la stocare, suspendare/revenire și preview-uri mari. Testele
   randate și APK-ul compilat nu înlocuiesc acest control.
2. **Activarea autentificării GitHub.** Înregistrăm aplicația OAuth proprie,
   activăm Device Flow și configurăm Client ID-ul public. Verificăm login,
   repository privat, anulare și deconectare cu un cont real. Apoi Client ID-ul
   poate deveni implicit în aplicație, eliminând configurarea pentru utilizator.
3. **Un export real per furnizor și format.** Meshy/Tripo → FBX/USDZ/3MF/BLEND,
   texturi și animații unde sunt disponibile, deschidere în aplicațiile țintă și
   import în Godot. Confirmăm costul și consistența fișierelor, nu doar răspunsul API.
4. **Verificare LAN între dispozitive.** Ollama și LM Studio pe calculator,
   conexiune de pe Android, server cu token, rețea izolată și adresă schimbată.
   Rezultatul căutării trebuie să arate și motive utile pentru o conexiune eșuată.

## Următorul set de funcții

5. **GitHub: branch, commit și pull request prin API.** Selectarea fișierelor,
   diff înainte de publicare, mesaj de commit și trimitere explicită. Autentificarea
   singură nu înseamnă că avem deja un client Git complet.
6. **Profiluri de export 3D.** Godot, Blender, Unity/Unreal și imprimare 3D:
   unități, axe, pivot, scară, texturi, rig/animații și buget de poligoane. Ulterior
   LOD/retopologie și verificarea importului. Presetările depind de furnizor/API;
   conversia desktop prin Blender rămâne separată de Android.
7. **Coadă vizuală de generare.** Progres per resursă, cost raportat de furnizor,
   reluare după suspendare, erori recuperabile și anulare remote numai pentru
   sarcina proprie, dacă API-ul permite. Așteptarea oprită local nu anulează factura.
8. **Restaurarea unui task întreg.** Checkpoint cu lista schimbărilor și restaurare
   coerentă pentru mai multe fișiere/scenă, pe lângă recuperarea individuală deja
   existentă. Rezolvarea explicită a conflictelor cu editările utilizatorului.
9. **Conectare LAN prin QR și dispozitive favorite.** Adresă, tip și port, apoi
   verificare; tokenul nu apare în QR/jurnal. Alegerea interfeței/subrețelei și
   descoperire mDNS unde serverul o publică. Introducerea manuală rămâne disponibilă.
10. **Verificarea capabilităților modelelor.** Test mic, explicit, pentru tools,
    imagini și streaming, cu rezultat per model. Numele modelului sau un catalog
    OpenAI-compatible nu garantează că poate folosi corect toate uneltele.
11. **Context de proiect mai eficient.** Index incremental pentru scripturi, scene
    și dependențe, referințe precise în răspuns și afișarea fișierelor efectiv citite.
    Refolosirea rezultatelor valide reduce costul și umplerea contextului.
12. **Validare înainte de finalizare.** Diagnostice GDScript, scene lipsă, resurse
    neimportate și playtest relevant, cu o dovadă clară a ceea ce a fost verificat.
    Salvarea/compilarea nu trebuie prezentate ca rezultat vizual testat.

Ordinea recomandată: punctele 1–4, apoi GitHub complet, profiluri 3D și checkpoint-uri.
Așa avem întâi un flux verificat pe dispozitiv și servicii reale, apoi extindem
funcțiile pe o bază confirmată.
