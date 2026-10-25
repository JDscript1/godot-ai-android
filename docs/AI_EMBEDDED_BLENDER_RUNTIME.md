# Runtime Blender în aplicația Android

Ținta este un Blender CLI utilizabil de agent fără instalarea aplicației Termux și fără comenzi lipite de utilizator. Harness-ul AI rămâne în Godot; serviciul nativ este doar backend-ul opțional pentru modelare, export și randare.

## Etapa 1: proba de executare

Editorul construiește un executabil PIE ARM64 foarte mic (`ai_runtime_probe.c`) cu NDK și îl include în APK sub `lib/arm64-v8a/libai_runtime_probe.so`. Android îl extrage în directorul bibliotecilor native. Serviciul neexportat `AIEmbeddedRuntimeService` rulează în procesul aplicației `:ai_runtime`, pornește numai acel fișier cunoscut, așteaptă cel mult opt secunde și întoarce rezultatul printr-un receiver neexportat. Puntea Godot acceptă intern `embedded_probe` și `embedded_status` pentru diagnostic. Aceasta verifică mecanismul de proces, izolare și executare; **nu instalează și nu pornește încă PRoot sau Blender**.

Proba nu cere acces la Termux, stocare partajată sau rețea. Modulul nu primește o comandă arbitrară de la model. CI a compilat un APK cu proba, dar pornirea ei din procesul separat din acel APK nu a fost încă verificată fizic. APK-ul existent din Downloads rămâne pe implementarea Termux până la o probă Android a noii căi.

[Workflow-ul `40185968028`](https://github.com/JDscript1/godot-ai-android/actions/runs/40185968028) a trecut toate cele trei joburi. Artefactul `db550ea` conține proba ELF AArch64/PIE de 4.800 bytes; manifestul compilat declară `android:extractNativeLibs=true`, serviciul `:ai_runtime` și receiver-ul, ambele neexportate. APK-ul are aceeași semnătură de dezvoltare ca versiunea din Downloads. Binarul extras din artefact a fost executat separat în Termux pe dispozitiv, dar aceasta **nu** demonstrează încă executarea lui din directorul aplicației Godot.

## Următorii pași pentru un backend funcțional

1. Construim PRoot pentru ID-ul acestei aplicații și verificăm explicit că nu are `RUNPATH` sau prefix `com.termux`. Nu copiem binarul Termux: cel inspectat are `RUNPATH=/data/data/com.termux/files/usr/lib`.
2. Pregătim un rootfs ARM64 reproducibil cu Blender CLI și dependențele sale, cu manifest de versiuni, hash-uri și licențe. PRoot-Distro poate ajuta la pregătirea imaginii, dar nu trebuie să fie un manager de pachete activ în fiecare pornire.
3. Împărțim pachetul în componente verificabile la instalare. Executabilul native rămâne în zona permisă pentru execuție; datele rootfs și proiectele stau în stocarea privată a aplicației. Verificăm spațiul necesar înainte de instalare și nu descărcăm sau extragem pachete în tăcere.
4. Pornim Blender din serviciul separat, cu joburi limitate, anulare, jurnal, import GLB în Godot și verificarea unui mesh real. Abia după o probă fizică în APK mutăm butonul **Instalează Blender** la noul backend și eliminăm fluxul Termux.

Licențele PRoot/PRoot-Distro și Blender, sursele corespunzătoare și notele de distribuție trebuie incluse/verificate înainte de livrarea unui APK care le conține. Dimensiunea finală a pachetului și compatibilitatea Blender pe Android rămân de măsurat.
