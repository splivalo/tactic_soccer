# assets — sve sirove datoteke (grafika, teksture, fontovi)

| Folder        | Što ide                                                        |
|---------------|----------------------------------------------------------------|
| `models/`     | 3D modeli (`.glb`/`.fbx`) — igrač, lopta, gol, teren.          |
| `animations/` | Mixamo animacijski klipovi (kasnije).                          |
| `textures/`   | 2D teksture. `textures/numbers/` = brojevi za dresove (`numbers_*.png`). |
| `flags/`      | Zastave država — **`country_kits.gd` ih traži na `res://assets/flags/<drzava>.png`** (npr. `croatia.png`). |
| `materials/`  | Zajednički `.tres` materijali (teren, mreža…).                 |
| `fonts/`      | Fontovi (npr. za brojeve na dresu / kasnije HUD).              |

Pravilo: **sirovi asseti → `assets/`**, a **scene koje ih koriste → `scenes/`**.
Nikad ne uređuj uvezeni `.glb` direktno; napravi *Inherited Scene* u `scenes/`.
