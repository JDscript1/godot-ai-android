# Evaluarea comportamentului agentului

Actualizat: 23.10.2026. Modificările acestei etape sunt în surse, după APK-ul
livrat `36457dd`. Starea livrării este în [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).

## Reproduceri și corecții

Primele cinci scenarii noi au produs patru eșecuri pe implementarea inițială.
Același set a trecut după modificarea harness-ului. Verificările includ ulterior:

| Scenariu | Rezultat cerut |
| --- | --- |
| Același prompt, alt ID de apel | O singură trimitere de generare în același turn |
| Reluare după întrerupere | Refolosirea rezultatelor și a ID-ului sarcinii |
| O variantă suplimentară cerută explicit | O cerere distinctă, diferențiată prin `variant` |
| Cerere nouă a utilizatorului | Poate solicita explicit încă o generare |
| Lipsă plan, apoi plan corect | Operația poate continua inclusiv cu ID-ul inițial |
| Refuzul unei permisiuni | Același apel nu mai cere aprobarea în acel turn |
| Răspunsuri fără progres | Oprire după trei încercări consecutive |
| Erori identice sau batch blocat | Oprire și închiderea tuturor apelurilor restante |
| Mesaj nou în timpul lucrului | Întreruperea cererii depășite, apoi executarea mesajului nou |
| Reluare din chat | Fără mesaj artificial și fără pierderea ciornei |
| Sarcină deja încheiată | Butonul de reluare nu execută din nou operațiile |
| Răspuns pierdut după POST | Sarcină persistentă cu trimitere neconfirmată |
| Stocare indisponibilă înainte de POST | Nicio cerere de generare trimisă |

Protecția pe semnătură compară argumentele exacte. Nu stabilește dacă două
prompturi reformulate descriu același obiect. Planificarea, selecția operațiilor
și calitatea codului depind în continuare de model. Instrucțiunile cer inspectarea
rezultatelor existente și interzic regenerarea în timpul unei cereri de curățare;
aceste instrucțiuni nu sunt prezentate drept dovadă că orice model le respectă.

## Verificări automate

- **396 aserțiuni runtime**, fără eșecuri, prin Godot 4.7.2 ARM64 în proot,
  inclusiv arhiva oficială Terrain3D și testele HTTP izolate.
- **329 verificări în editor în fiecare dintre cinci configurații**, fără
  eșecuri: desktop, îngust, lat, telefon landscape și compact.
- Testele editorului folosesc furnizori determinați de fixturi, scene temporare,
  Undo real și aceeași interfață/harness ca aplicația. Ele verifică controlul
  execuției; nu măsoară calitatea unui model real.
- Testele de conectare acoperă IP simplu, porturi implicite, catalog LM Studio,
  modelele încărcate, contextul activ, catalog Ollama, autentificare, streaming
  lent, expirare la inactivitate și Stop. Nu folosesc un model real.
- Capturile cu planul compact și bara chatului au fost inspectate vizual.

Dovezi locale: `.ai-qa/behavior-before.log`, `.ai-qa/behavior-harness.log`,
`.ai-qa/behavior-verified-runtime.log`, `.ai-qa/behavior-verified-render/`,
`.ai-qa/local-connections-runtime.log`, `.ai-qa/local-connections-render-final/`.

Comenzi rulate din rădăcina repository-ului:

```sh
GODOT_AI_TERRAIN3D_ZIP="$PWD/.ai-qa/Terrain3D_v1.0.2-stable.zip" python modules/ai_assistant/tests/run.py --godot /data/data/com.termux/files/home/godot-engine/Godot_v4.7.2-stable_linux.arm64 --proot
python modules/ai_assistant/tests/render.py --godot /data/data/com.termux/files/home/godot-engine/Godot_v4.7.2-stable_linux.arm64 --proot --output .ai-qa/local-connections-render-final
```

## Conexiune reală și inferență

Probele API DeepSeek efectuate ulterior sunt documentate separat în
[Evaluarea agentului cu API real](AI_API_EVALUATION.md). Ele folosesc panoul și
tool-urile reale într-un proiect izolat, nu driverul LM Studio în memorie.

Conectarea LM Studio a fost verificată prin Wi-Fi, după identificarea adresei
IPv4 a adaptorului activ. Calculatorul și dispozitivul Android sunt conectate
la hotspotul unui telefon. Adaptorul nativ Godot a trecut **10 citiri consecutive**
ale catalogului: minimum 95 ms, mediană 164 ms, maximum 368 ms. `/v1/models` și
`/api/v0/models` au confirmat modelul încărcat `prism-ml/bonsai-27b`, cu un context
activ de 4.096 tokeni. Modelul de embeddings este exclus din selectorul chatului.
După repornirea Wi-Fi, aceeași adresă a răspuns din nou în 0,24 secunde.

Aceste rezultate confirmă accesul la catalog în timpul probelor, nu o garanție
de stabilitate pe termen lung sau o sesiune de inferență reușită în APK.
Ollama nu a răspuns pe portul 11434 al calculatorului; testarea sa live rămâne
de făcut când serverul este pornit și accesibil. Adresa calculatorului poate
să se schimbe după reconectarea la hotspot.

Driverul local `.ai-qa/live_behavior.gd` folosește adaptorul HTTP și harness-ul
din sursele curente, cu patru scenarii: identitate compactă, citire fără modificări,
editare urmată de recitire și curățare fără generare. Tool-urile de fișiere sunt
simulate în memorie; nu ating proiectele utilizatorului și nu apelează furnizori
de generare. Testul măsoară comportamentul modelului cu acest contract, nu este
o probă completă a APK-ului Android. Prima cerere către modelul mare nu s-a
încheiat în timpul probei; clientul nostru de test a fost oprit. O cerere HTTP
scurtă separată a expirat după 25 de secunde. Nu există o rundă finalizată din
care să putem evalua calitatea răspunsurilor sau tool use-ul modelului.
Prioritatea acestei etape a devenit conectarea simplă și separarea timpului de
conectare de timpul de inferență. Nu am modificat configurația serverului sau
modelul încărcat și nu am trimis cereri de generare cu cost.

Dovezi: `.ai-qa/live-lmstudio-connection.json`,
`.ai-qa/lmstudio-after-wifi-restart.json`, `.ai-qa/lmstudio-plain-chat.json`,
`.ai-qa/live-bonsai-behavior.log`. Adresele LAN exacte rămân în dovezile locale.

## Alternativă open source

[Deep Agents](https://github.com/langchain-ai/deepagents) este un candidat cu
licență MIT, planificare, persistență și tool use, disponibil ca bibliotecă Python
și JavaScript/TypeScript. Nu este un modul nativ Godot/Android gata de introdus
în APK. Pentru sistemul nostru ar necesita un runtime încorporat sau un serviciu
opțional pe calculator și un adaptor pentru tool-urile editorului; compatibilitatea
Android nu a fost testată. Licența harness-ului nu include costul modelelor cloud.

Decizia pentru această etapă: păstrăm harness-ul nativ și măsurăm corecțiile.
O înlocuire se justifică prin comparația pe aceleași scenarii și același model,
nu doar prin numărul de funcții al altei biblioteci. Nicio dependență externă
nouă nu a fost adăugată aplicației.
