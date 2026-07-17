# assets — sve sirove datoteke (grafika, teksture, fontovi)

| Folder        | Što ide                                                        |
|---------------|----------------------------------------------------------------|
| `models/`     | 3D modeli (`.glb`/`.fbx`) — igrač, lopta, gol, teren.          |
| `animations/` | Mixamo FBX klipovi (`build_player.gd`/`build_variants.gd` u `scripts/tools/` ih pakiraju u `player_anims.res`). |
| `textures/`   | 2D teksture. `textures/numbers/` = brojevi za dresove (`numbers_*.png`), `textures/ui/countries/` = zastave (`country_kits.gd` ih traži tu, ne u `assets/flags/`). |
| `materials/`  | Zajednički `.tres` materijali (teren, mreža…).                 |
| `shaders/`    | `.gdshader` datoteke (glow, mreža na golu, luminance dim…).    |
| `audio/`      | `bus_layout.tres` + `music/`/`sfx/` (prazni dok se ne doda pravi zvuk — `Settings` autoload ih već očekuje). |
| `fonts/`      | Fontovi (npr. za brojeve na dresu / kasnije HUD).              |

Pravilo: **sirovi asseti → `assets/`**, a **scene koje ih koriste → `scenes/`**.
Nikad ne uređuj uvezeni `.glb` direktno; napravi *Inherited Scene* u `scenes/`.
