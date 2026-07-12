# assets/animations — Mixamo animacije (kasnije)

Ovdje idu Mixamo klipovi (idle, pass/shoot kombinacija, gol slavlje…).

## Workflow (kad dobiješ Mixamo)
1. Skini iz Mixamo kao **FBX Binary**, "Without Skin" za dodatne klipove (skeleton mora odgovarati modelu igrača).
2. Ubaci ovdje → u **Import** tabu postavi *Animation → Save to File* ili koristi
   **AnimationLibrary** da ih spojiš na model iz `assets/models/players`.
3. U player sceni (`scenes/player/`) dodaj **AnimationPlayer**/**AnimationTree**
   i mapiraj klipove. Kombinacija (pass→shoot) okida animaciju, gol okida slavlje + spuštanje kamere.

Trenutni `main.gd` već ima `_autoplay_animations()` koji vrti "idle" klip — to je
polazna točka; kasnije ide u zaseban `scripts/game/` kontroler.
