# Blender în Integrări, prin Termux

Inclus în APK-ul Android ARM64 `2287ae5`, livrat la 24 octombrie 2026.
Clasele Android, permisiunea, intrarea JNI, cele 27 scripturi și worker-ul inclus
au fost verificate în pachet. Harness-ul AI rulează în Godot; Termux și Python
sunt dependențe numai ale integrării opționale Blender. Legătura Android prin
Intent și configurarea inițială trebuie verificate din aplicația instalată
înainte ca funcția să fie declarată validată pe dispozitiv.

## Configurare

În **Setări → Integrări → Blender**:

1. **Instalează Termux** deschide distribuția oficială. Instalarea aplicației
   și prima ei deschidere sunt operații ale utilizatorului.
2. **Acordă permisiunea** solicită `com.termux.permission.RUN_COMMAND`.
   **Setări Android** deschide pagina aplicației pentru dispozitivele care
   cer activarea manuală sau au refuzat definitiv permisiunea.
3. **Copiază comanda** și **Deschide Termux** ajută la activarea, o singură
   dată, a `allow-external-apps=true`. Comanda păstrează celelalte proprietăți.
4. **Conectează** pregătește procesul auxiliar și verifică instalările existente.
   Dacă Python lipsește, acesta se instalează numai la această acțiune explicită.
5. Dacă Blender lipsește, **Instalează Blender** pregătește PRoot-Distro și
   containerul dedicat `godot-ai-blender`, din `debian:13-slim`, apoi Blender
   prin catalogul oficial Debian. Instalarea nouă cere PRoot-Distro 5.x și
   minimum 2 GB liberi. O versiune veche existentă nu este migrată automat.
6. **Disponibil** apare după generarea unui GLB real, transfer, verificarea
   hash-ului și importul în Godot. Randarea CPU este verificată separat.
7. **Permite agentului să utilizeze Blender** activează tool-ul pentru proiect.

Termux este detectat din nou la revenirea în panou. Versiunea, conexiunea și
verificarea sunt comune dispozitivului; activarea și sarcinile de recuperat
sunt asociate proiectului. Instalările Blender funcționale sunt reutilizate.
Detectarea verifică atât PATH, cât și containerele PRoot în structura actuală
și cea veche.

Protocolul de pornire urmează [RUN_COMMAND Intent](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent).
Gestionarea mediului folosește [PRoot-Distro](https://github.com/termux/proot-distro),
iar profilul nou utilizează [Blender Debian ARM64](https://packages.debian.org/trixie/arm64/blender).

## Jurnal și diagnostic

APK-ul `2287ae5` înregistrează și pașii anteriori pornirii
unei sarcini: detectare Termux, permisiune, configurare inițială, pornire și
reconectare. **Activat** pentru agent și **Disponibil** sunt stări separate.
Agentul primește motivul indisponibilității și următoarea acțiune.

Jurnalul Blender este salvat în configurația privată a editorului, limitat la
100 evenimente și ultima parte a ieșirii worker-ului. Tokenul conexiunii și
cheile recunoscute sunt redactate înainte de salvare. Verificările periodice
identice nu produc intrări noi. Evenimentele apar și în **Jurnalul** general.
După o conectare eșuată, jurnalul se deschide și derulează la ultima eroare;
butonul de copiere permite partajarea diagnosticului. Închiderea editorului nu
șterge istoricul diagnosticelor.

## Rulare și fișiere

`blender_run` păstrează `script`, `blend` și `seconds`. Pe Android oferă și:

- `inputs`: fișiere suplimentare din proiect, copiate cu aceeași cale relativă;
- `output_directory`: directorul din proiect pentru rezultate, implicit
  `res://ai_assets/blender`;
- `seconds`: 120 implicit, între 1 și 600, pentru execuția Blender.

Scriptul primește `GODOT_AI_PROJECT_DIR` și `GODOT_AI_OUTPUT_DIR`.
Exemplu de script salvat în proiect:

```python
import os
import bpy

out = os.environ["GODOT_AI_OUTPUT_DIR"]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add()
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cutie.glb"), export_format="GLB")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "cutie.blend"))
```

Fiecare sarcină are propriul spațiu de lucru. Rezultatele sunt transferate prin
streaming, verificate și importate într-un folder precum
`res://ai_assets/blender/create_box_<id>/`. Numele fișierelor sunt cele alese
de script pentru obiectul produs. Fișierele existente nu sunt suprascrise.

GLB, glTF și imaginile pot folosi preview-ul din chat. FBX, BLEND și celelalte
formate apar ca fișiere; agentul este instruit să producă și un GLB pentru
previzualizare. Fișierele `.blend` sunt păstrate cu `importer="keep"`, deoarece
importerul Android standard nu poate lansa executabilul din Termux.

Tool-ul apare numai după verificare și activare. Folosește aceleași reguli de
planificare și permisiuni ca celelalte operații externe: Plan nu execută,
iar YOLO dezactivat cere confirmarea operației. Agentul primește versiunea și
capacitățile detectate; nu primește tokenul conexiunii locale.

## Recuperare și limite

- Proces auxiliar inclus în APK, bibliotecă standard Python, conexiune limitată
  la `127.0.0.1`, token aleator de 256 biți păstrat în seiful Android.
- ID-uri persistente și manifest verificat: același ID nu execută comanda
  de două ori. La pierderea conexiunii, **Recuperează** consultă sarcina existentă.
- O singură sarcină activă, două fire Blender, timeout, anularea grupului de
  procese propriu și limitarea logului. PRoot nu este un sandbox de securitate.
- Instalarea se oprește după încheierea tranzacției curente, inclusiv pregătirea
  imaginii Debian. Nu se șterg lock-uri și nu se execută actualizări generale.
- După o oprire forțată în timpul extragerii, **Repară instalarea** poate recrea
  exclusiv imaginea incompletă marcată ca aparținând aplicației. Mediile existente
  fără acest marcaj sunt refuzate, nu resetate.
- După confirmarea importului, copiile de lucru sunt eliberate; metadatele
  sarcinii rămân pentru prevenirea reexecutării. Rezultatele nerecuperate sunt
  păstrate. Procesul auxiliar se închide după zece minute fără activitate.
- O instalare deja verificată se poate reconecta automat, fără instalări de
  pachete sau repetarea probei. Schimbarea runtime-ului invalidează verificarea.
- Android poate opri procesele. O sarcină rămasă activă după dispariția procesului
  este raportată ca întreruptă; nu este prezentată drept finalizată.

## Verificare

```sh
python modules/ai_assistant/tests/test_termux_blender.py
python modules/ai_assistant/tests/run_termux_blender.py --godot /cale/catre/Godot_linux.arm64
python modules/ai_assistant/tests/render.py --godot /cale/catre/Godot_linux.arm64 --proot --scenario blender --output .ai-qa/blender-ui
```

Probele backend/HTTP folosesc directoare izolate. Testul real reutilizează Blender
existent din Termux, trece prin clientul Godot și verifică exporturi GLB, glTF cu
dependențe, FBX, BLEND, randare CPU, anulare și recuperarea unui transfer pierdut.
Înlocuiește numai frontiera Intent cu un adaptor de test, explicit marcat în raport.

Compilarea Kotlin cu SDK-ul Android, compilarea obiectului C++ și randarea
panoului nu dovedesc pornirea din APK. Instalarea pe Termux gol, fluxurile Android
de permisiuni și proba completă din APK rămân verificări fizice distincte.
