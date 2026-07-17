# scenes/ui

Tok ekrana (`GameFlow.Screen`, `scripts/game/game_flow.gd`):

1. `splash_screen.tscn` — **korisnikov vlastiti dizajn** (pozadina/logo/font).
   Tap/klik/tipka → glavni izbornik.
2. `main_menu.tscn` — po uzoru na izbornik originala iz 2006: 1 Player game
   (onemogućen, nema AI), 2 Player game (Online), Options (modal, ne zaseban
   ekran — glasnoća/vibracija preko `Settings` autoloada), Instructions,
   Credits (obično `flat` gumb, ne ističe se), Quit.
3. `team_select.tscn` — dva prolaza (hotseat): Player 1 bira svoju državu
   (uvijek Home — dolje na terenu, lijevi grb u HUD-u), Player 2 svoju
   (uvijek Away). Nema više biranja "koju stranu igraš" — koja je strana čija
   je fiksno, jer u online-u svako igra samo sebe na svom uređaju.
4. `main.tscn` (izvan `ui/`) — sam meč. Rana faza te iste scene je i
   postavljanje formacije (golman pa redom ostali, samo IGRAČEVA strana —
   vidi `main.gd::_start_placement`) prije nego prava utakmica krene. Nema
   zasebnog "formation setup" ekrana — namjerno, da se ponovno iskoristi već
   učitana kamera/teren/HUD umjesto dupliciranja te logike u drugoj sceni.
5. HUD (`hud.tscn`) — grbovi, skor, kartoni, timer, footer (čiji je red /
   uputa za placement) — CanvasLayer preko meča, ne zaseban ekran.
6. `win_screen.tscn` / `lose_screen.tscn` — nakon što netko dosegne
   `goals_to_win`, ruta ovisi o `GameFlow.player_side` naspram pobjednika
   (svatko vidi "YOU WIN"/"YOU LOSE" sa svoje perspektive).

`options_screen.tscn` i dalje koristi generički `scripts/ui/info_stub.gd`
(naslov + tekst + Natrag) kao placeholder dok Options modal na glavnom
izborniku ne pokrije sve što treba. `instructions_screen.tscn` i
`legal_screen.tscn` imaju SVOJE dedicated skripte (`instructions_screen.gd`
— carousel/paging, `legal_screen.gd`), ne dijele info_stub više.

Placeholder scene (`main_menu`, `team_select`, `options_screen`) su namjerno
gole (`ColorRect` + `Label`/`Button` u `VBoxContainer`, samo
`my_theme_gold.tres`/`my_theme.tres` za font) — izgled/pozicije/boje su za
slobodno uređivanje u editoru; skripte u `scripts/ui/` gledaju samo čvorove
označene `unique_name_in_owner` (`%Ime`), ne raspored. `splash_screen.tscn`
je iznimka — nju je korisnik već dizajnirao, ne dirati izgled.
