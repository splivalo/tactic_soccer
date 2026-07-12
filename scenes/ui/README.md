# scenes/ui

Tok ekrana (`GameFlow.Screen`, `scripts/game/game_flow.gd`):

1. `splash_screen.tscn` — **korisnikov vlastiti dizajn** (pozadina/logo/font).
   Tap/klik/tipka → glavni izbornik.
2. `main_menu.tscn` — po uzoru na izbornik originala iz 2006: 1 Player game
   (onemogućen, nema AI), 2 Player game, Options, Instructions, Credits
   (obično `flat` gumb, ne ističe se), Quit.
3. `team_select.tscn` — država Domaćeg + Gosta (`CountryKits`), i koju stranu
   igraš. Natrag → izbornik, Dalje → formacija.
4. `formation_setup.tscn` — **trenutno stub** (samo "Počni meč" gumb, koristi
   automatski `Formations.home()/away()`). Ručno postavljanje figura (od
   golmana) je sljedeći veći korak — treba nova faza u `MatchState`, ne samo
   ovaj ekran.
5. `main.tscn` (izvan `ui/`) — sam meč.
6. HUD (na kraju, Faza 7) — skor, kartoni, tko je na potezu, ide preko meča.

`options_screen.tscn`, `instructions_screen.tscn`, `legal_screen.tscn` sve
dijele isti generički `scripts/ui/info_stub.gd` (naslov + tekst + Natrag na
izbornik) — svaka scena samo postavlja `title_text`/`body_text` na svom
root čvoru. Instructions ima pravi sažetak pravila; Legal ima TODO tekst za
autora/impressum/licence koji treba urediti izravno u toj `.tscn` datoteci.

Placeholder scene (`main_menu`, `team_select`, `formation_setup`, i tri
info-stub ekrana) su namjerno gole (`ColorRect` + `Label`/`Button` u
`VBoxContainer`, samo `my_theme_gold.tres` za font) — izgled/pozicije/boje su za
slobodno uređivanje u editoru; skripte u `scripts/ui/` gledaju samo čvorove
označene `unique_name_in_owner` (`%Ime`), ne raspored. `splash_screen.tscn`
je iznimka — nju je korisnik već dizajnirao, ne dirati izgled.
