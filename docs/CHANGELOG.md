# TACTIC SOCCER — Changelog / Session Log

> Kronološki dnevnik što je rađeno i zašto. Za trenutno stanje pravila/arhitekture
> vidi [`GAME_DESIGN.md`](GAME_DESIGN.md); za otvorene zadatke [`TODO.md`](TODO.md).

## 2026-07-07 — Setup, uvoz grafike, osnovna mehanika

**Struktura projekta.** Posložen plosnat raspored: `scenes/`, `scripts/game/`
(čista logika), `scripts/data/` (kitovi, izgled igrača), `scripts/visuals/`,
`assets/{models,animations,audio,textures,flags,materials,fonts}/`, `docs/`.

**Uvoz 3D grafike.** Korisnik uvezao `stadium.glb` (arena+golovi+teren+linije
kao odvojeni imenovani node-ovi: `field`, `field_lines`, `arena`, `fence`,
`banner`, `seats`, `goal1_frame/net`, `goal2_frame/net`, `reflectors`),
`ball.glb`, `player.glb`. `main.gd` prepravljen da **koristi** `stadium` node
koji je korisnik ručno postavio u `main.tscn` (ne stvara ga više iz koda).

**Mreža 7×10 (`scripts/game/board.gd`).** `grid_to_world`/`world_to_grid`,
`TILE_SIZE=1.0`, `SURFACE_Y=0.2322`. Potvrđeno headless testom da se `field`
mesh (7.0×10.0, top Y 0.2322) poklapa s logičkom mrežom.

**Dres i brojevi.** `player_appearance.gd`: boja dresa (`primary`/`secondary`/
`hair` materijali) iz `country_kits.gd`; broj na dresu pečen kao **neprozirna
ploča** (boja dresa + utisnut broj) preko `number_front`/`number_back`
materijala — riješen problem "rupe" oko broja (alfa kanal transparentan).
Golmani dobili **poseban GK dres** (crno/žuto doma, zeleno/bijelo gost),
nikad boje reprezentacije.

**Banner fix.** `stadium_logo` tekstura ima tekst samo u alpha kanalu (crn RGB)
na OPAQUE materijalu → renderao se kao puna crna ploha. `_fix_banner()` peče
novu neprozirnu teksturu (žuta pozadina + tekst iz alpha maske).

**Kamera auto-fit.** Korisnik i dalje ručno štima kut/FOV u editoru; kod
(`_fit_camera`) samo klizi kameru po **toj istoj osi** tako da cijeli teren
uvijek stane, na bilo kojem omjeru ekrana. `window/stretch/aspect="expand"`
da nema crnih traka.

**Pravila igre (`scripts/game/match_state.gd`, čista logika, bez čvorova).**
Nakon što sam pravila prvo pogrešno implementirao (previše radnji po potezu,
lopta na figurici, golman izlazi iz gola…), korisnik je ispravio i model je
sad: lopta **uvijek na praznom polju**; posjed = figurica na 1 od 8 polja oko
lopte; potez = **točno 2 radnje** — (1) COMBO: lanac vlastitih figurica pa
ispucavanje na prazno polje, (2) MOVE: pomak jedne figurice za 1 polje;
golman samo u svoja 3 gol-polja (stupci 2,3,4), ostali ne smiju u gol; gol =
ispucavanje u protivnički gol s protivničke polovice → rezultat + reset
(primatelj izvodi). Refaktorirano iz `main.gd` u `MatchState` + headless
unit test `scripts/tests/test_match.gd` (svi prolaze) — `main.gd` ostaje
tanki vizualni sloj.

**Vizualni feedback (`scripts/visuals/board_fx.gd`).** Umjesto krugova/točaka:
sve oznake (dostupna polja za pomak/ispucavanje, dodirljive figurice, odabrani
lanac, odabrani "mover") su **isti zaobljeni kvadrat**, samo druge boje — jedan
vizualni jezik. Energetski trag kroz lanac dodavanja prebačen s teksture na
**shader** (dash ili dot uzorak, biraš iz Inspectora) jer je scroll animacija
preko teksture ovisila o nezajamčenom "repeat" wrapu i nije pouzdano radila.
Popravljen bug gdje su "dot" oznake bile izdužene (elipsa umjesto kruga) —
shader sad oba smjera računa u stvarnim metrima. Boje i tuning parametri
(`color_*`, `fx_*` na `Main` nodeu) su `@export` — mijenjaš uživo preko
Remote scene tree dok igra radi (Scene dock → Remote tab).

**Sitni ispravci mehanike na korisnikov zahtjev:**
- Ne može se ispucati na polje na kojem lopta trenutno stoji.
- Promjena mišljenja pri odabiru primatelja (klik na drugog dostupnog igrača
  umjesto prvog) — čak i ako bi to inače bilo dodavanje.
- Maknut stari `SelectionIndicator` (prstenovi/strelice) — zamijenjen
  jednostavnijim `BoardFx` sustavom.

## 2026-07-08 — Kratki eksperiment: PC / landscape (odbačeno)

Korisnik je htio probati platformu za **PC, landscape**, s izometrijski
iskošenom kamerom (umjesto ravno-odozgo-portret). Napravljeno:
- `project.godot`: viewport 1920×1080, orijentacija landscape.
- Nova Camera3D transformacija u `main.tscn`: kut ~38° zaokreta + ~34° nagiba,
  izračunat preko `Transform3D().looking_at()` da gleda u središte terena.

**Bug i pouka (važno, zapisano u trajnu memoriju):** ručno upisana
`Transform3D(...)` matrica u `.tscn` je bila **kriva** — Godot u `.tscn`
zapisuje 9 brojeva bazisa **transponirano** (red po red: sve X komponente,
pa sve Y, pa sve Z), a ne kao `basis.x, basis.y, basis.z` jedno za drugim
kako sam pretpostavio. Rezultat je bio validan ortonormalan bazis (ništa nije
puklo), ali kamera je gledala u posve krivom smjeru (odletjela "u nebo").
Uzrok potvrđen eksperimentom: node s poznatim bazisom spremljen kao pravi
`.tscn` i pročitan sirovi zapis — to je otkrilo pravi redoslijed. Popravljeno.

**Odluka korisnika (2026-07-08):** vratiti se na **mobilnu, portret** verziju
— brojevi na dresovima i UI se bolje vide u portretu na ovoj kompoziciji.
PC/landscape ideja nije zaboravljena, samo odgođena; kod (logika, `MatchState`,
`BoardFx`, klik/tap koji već podržava i miš i touch) je platformski neovisan,
pa je povratak na landscape kasnije samo pitanje ponovnog štimanja kamere i
project-settingsa, ne prepravke igre.

**Vraćeno:** `project.godot` na portret 1080×1920; `main.tscn` Camera3D na
raniju, provjereno ispravnu portret transformaciju (ravno iza jednog gola,
nagnuta prema dolje) — vidi git/datotečnu povijest ili trenutne vrijednosti
u `main.tscn` za točan transform.

## 2026-07-09 — Rewind lanca + Tap-vs-Drag sustav dodavanja

**Rewind.** Klik na figuricu koja je već u lancu dodavanja (bilo gdje u nizu,
ne samo prvu) skraćuje lanac do nje umjesto da dopusti petlju (npr. 1→2→3→2
je sad nemoguće). `MatchState.rewind(cell)`, čista logika + test.

**Problem koji je uslijedio:** kad su dvije (ili tri) figurice do lopte
**ujedno i međusobno u ravnoj liniji** (čest slučaj kod formacije), klik na
drugu se sudarao s dva različita, jednako legitimna očekivanja — "promijeni
primatelja" (potpuno novi početak) ili "dodaj od prve do druge" (pravi pas) —
isti gest, dva moguća značenja, nemoguće razlikovati bez dodatnog signala.
Isprobane i odbačene ideje: tap na loptu za reset (loša meta na mobitelu,
nema vizualni signal), dugi pritisak (neintuitivno), fiksni reset-gumb
(korisnik ne želi UI element za to).

**Riješeno: TAP i DRAG rade dvije različite, dosljedne stvari.**
- **TAP** na figuricu → **uvijek** (re)pokreće lanac ispočetka s njom (ili
  rewind ako je već u lancu) — nikad ne ovisi o geometriji/liniji.
- **DRAG** (stvarno povlačenje prsta/miša) od zadnje figurice u lancu prema
  drugoj → **jedini** način za pravo dodavanje. Isto za ispucavanje (drag
  prema zelenom polju), iako tap na već prikazano zeleno polje i dalje radi
  izravno (nema dvosmislenosti ondje).
- **Snap (hvatanje):** dok povlačiš, sustav gleda koja je od već prikazanih
  meta (dodavanje/ispucavanje/figure u lancu za rewind) **najbliža prstu**
  (`Board.nearest_cell`, čista/testirana funkcija) i "zakvači" liniju na nju —
  ne treba pratiti pravac piksel-precizno. Ako ništa nije dovoljno blizu pri
  puštanju, gest se otkaže bez posljedica (stanje nepromijenjeno).
- Isti model kao original iz 2006. (dashed linija + istaknuti cilj), samo
  gest zamijenjen (drag+snap umjesto tap-na-cilj).

**Implementacija:** `Board.nearest_cell()` u `board.gd` (čisto, testirano —
3 nova testa). `main.gd`: `_unhandled_input` prerađen u `_on_press` /
`_on_motion` / `_on_release`, razlikuje tap od draga po pomaku prsta
(`DRAG_TAP_THRESHOLD_PX`), `_draw_combo(preview)` sad crta i "uživo" segment
traga prema trenutno uhvaćenoj meti. MOVE faza (pomicanje figurice) ostaje
nepromijenjena (tap-only, nema tu dvosmislenosti).

**⚠️ Nije headless testirano** (nema pravog dodira/miša u headless okruženju)
— logika hvatanja (`Board.nearest_cell`) jest testirana, ali sam gest treba
provjeriti uživo u editoru/na mobitelu.

## 2026-07-09 — Dekompilacija originala: potvrda pravila kartona + veličina ploče

**Zašto.** Karton/stalling pravilo je prošlo kroz tri pogrešna pokušaja
(tekst datoteka → doslovno "isti nogometaš ne smije pucati dva puta zaredom"
→ moj kompromis "ista figurica NA ISTO polje"), a korisnik je svaki put našao
konkretan protuprimjer koji je ruši (npr. figura 1 puca, kasnije puca opet ali
na sasvim drugo mjesto — to NIJE prekršaj po duhu pravila; obrnuto, dvije
figure koje se naizmjenično vrte oko istog mjesta bi trebale biti prekršaj,
a stara verzija to ne bi uhvatila). Korisnik je onda dao pristup pravim
`.jar` fajlovima originalne igre (Football Mania, Samsung E810 build) pa smo
prešli sa nagađanja na dekompilaciju stvarnog bytecode-a.

**Proces.** Dekompilirano preko JD-Core (`a.java`, ~4700 linija, obfuscirani
jednoslovni identifikatori). Ključni koraci:
- String-tablica (`EN.dat` i sl.): binarni format, 2-bajtni header = broj
  unosa, pa niz `[2-bajtna dužina][UTF-8]`. Prvi pokušaj parsiranja je
  preskakao ne-ASCII unose bez inkrementiranja indeksa pa su svi kasniji
  indeksi bili pomaknuti — ispravljeno parsiranjem striktno sekvencijalno.
  Točni indeksi: 46=Off-side!, 47=Yellow card, 48=Red card,
  49=Remove a character.
- Osi ploče: bounds-check funkcija otkrila da je `an[team]` RED (row), a
  `ao[team]` STUPAC (col) — obrnuto od prve pretpostavke — bitno za točno
  čitanje offside/stalling provjera.

**Nalaz 1 — veličina ploče: original je 7×8, mi smo 7×10.** Odlučeno:
**zadržavamo 7×10** kao svjesnu vlastitu varijaciju (duži teren = više
taktičkog prostora), ne kao grešku koju treba ispraviti. Kod (`board.gd`)
NIJE mijenjan.

**Nalaz 2 — zaleđe: naša implementacija se poklapa s originalom**
(golman isključen iz provjere, isti princip "svi terenski protivnici strogo
iza napadača"). Nema promjena.

**Nalaz 3 — konačno, izvorom-potvrđeno pravilo kartona/zadržavanja.**
Original NE gleda "ista figurica" ni "isto polje" doslovno — gleda je li
novi šut sletio unutar 1 polja (Chebyshev, `max(|dx|,|dy|)<=1`) od pozicije
figurice koja je tom timu odigrala **posljednji čisti (neprekršajni) šut**,
bez obzira koja figurica sad puca. Ako se ta referentna figurica u
međuvremenu pomakne, provjera ne vrijedi (jer se referenca briše kad se
ta konkretna figura pomakne — `do_move()`). Ovo istovremeno rješava oba
korisnikova protuprimjera: ista figura na drugo mjesto = sigurno (jer
"drugo mjesto" nije blizu reference); dvije figure koje se naizmjenično
vrte oko istog mjesta = prekršaj (jer nova pozicija je blizu stare
reference, bez obzira koja je figura puca). 1. prekršaj = žuti, 2. = crveni,
3. = obavezno uklanjanje figurice (`Phase.REMOVE`).

**Implementacija (`match_state.gd`):** `last_shooter_id`/`last_shot_cell`
zamijenjeni s `stall_ref_id`/`stall_ref_cell` (po timu) + novi
`foul_count` (po timu, broji do 3). `execute_combo()`: provjera je sad
Chebyshev-udaljenost umjesto usporedbe identiteta/polja. `do_move()`: ako
se pomakne baš figura koja je trenutna referenca, referenca se briše.
`setup()`/`reset()` prošireni da resetiraju nova polja.

**Testovi (`test_match.gd`):** cijeli blok kartona prepisan — dvije figure
(`fig_a`, `fig_b`), redom provjerava: prvi šut postavlja referencu; ista
figura na daleko polje = sigurno; DRUGA figura blizu nepomaknute reference
= prekršaj (žuti); referenca se briše nakon prekršaja; svjež šut postavlja
novu referencu; 2. prekršaj = crveni; 3. prekršaj = `must_remove` +
`Phase.REMOVE`; `remove_figure()` mehanika (prazno polje/vlastita
figura/čisti `pending_removal`/predaja poteza); pomicanje referentne
figure briše `stall_ref_id`. Ukupno 54 checka, sve `TEST_MATCH: ALL PASSED`
(headless scan + unit test + scene load, sve čisto).

**`main.gd` nije trebao izmjene** — čita `res["card"]`/`res["must_remove"]`
generički po stringu, isti Dictionary ključevi/vrijednosti kao prije.

**Dokumentacija.** `GAME_DESIGN.md` §2 i §3 ažurirani (veličina ploče,
konačno pravilo kartona). `TODO.md`: stara stavka kartona označena kao
zamijenjena, dodane tri nove HUD stavke (prikaz kartona po timu, naznaka
blizine kartona, tooltip/pravila ekran) za Fazu 7 — trenutno nema HUD-a,
ovo je samo priprema; kad HUD dođe na red, poruke se već ispisuju u
`_after_combo()` (`main.gd`) pa se lako mogu preusmjeriti na UI umjesto
konzole.

## 2026-07-09 — Tok ekrana: splash → odabir momčadi → formacija (stub) → meč

**Zašto.** Korisnik je nabrojao što još nedostaje: splash, odabir strane i
države, postavljanje formacije (od golmana), HUD, animacije. Dosad je
`main.tscn` bio izravno `run/main_scene` — nije postojao nikakav meni ni
prijelaz između ekrana. Dogovoreno da krenemo od "skeletona" toka jer sve
ostalo (formacija, HUD) visi na tome da postoji način prijelaza iz ekrana u
ekran i mjesto gdje se odabir države/strane sprema prije nego meč krene.

**Novo: `GameFlow` autoload (`scripts/game/game_flow.gd`).** Čuva
`player_side`, `home_country`, `away_country` (prazan string = nepostavljeno)
i `goto(Screen)` koji radi `get_tree().call_deferred("change_scene_to_file", ...)`.
Registriran u `project.godot` `[autoload]`. `run/main_scene` promijenjen s
`main.tscn` na `scenes/ui/splash_screen.tscn`.

**Tri nova ekrana u `scenes/ui/` (+ `scripts/ui/`, nova mapa za kontrolere
ekrana, paralelno s `scripts/game/`):**
- `splash_screen.tscn` — bilo koji tap/klik/tipka → odabir momčadi.
- `team_select.tscn` — `OptionButton` za državu Domaćeg i Gosta (popunjeno iz
  `CountryKits.KITS.keys()`), prekidač "Ja igram kao: Domaći/Gost", "Dalje"
  sprema izbor na `GameFlow` i ide na formaciju.
- `formation_setup.tscn` — **namjerno samo stub** (tekst + "Počni meč"):
  pravo ručno postavljanje figura (redom od golmana, na svoju polovicu) je
  zaseban, veći komad logike (nova faza u `MatchState`, ne samo UI) i
  ostavljen je za sljedeći korak. Ovaj stub postoji samo da cijeli lanac
  splash→odabir→formacija→meč radi i da se može klikati kroz njega već sad.

**`main.gd`** na početku `_ready()` sad čita `GameFlow.home_country`/
`away_country` i njima prepiše svoje `@export` defaultove SAMO ako nisu
prazni — tako `main.tscn` i dalje radi identično kad se pokrene samostalno u
editoru (F6), a kad dođe iz toka ekrana, koristi ono što je igrač odabrao.

**Podjela dizajn/kod (po dogovoru).** Sve tri nove scene su namjerno gole
placeholder scene (`ColorRect` pozadina + `Label`/`Button` u `VBoxContainer`,
bez stiliziranja) — struktura/logika/nazivi čvorova (`unique_name_in_owner`)
su fiksni jer ih skripta čita, ali izgled/pozicije/boje/fontovi su
korisnikovi za urediti u editoru, isti princip kao i kamera (`_fit_camera`).

**Verifikacija.** Sve četiri nove/izmijenjene scene (`splash_screen`,
`team_select`, `formation_setup`, `main`) headless-učitane bez grešaka;
usput uhvaćena i popravljena greška tipa u `splash_screen.gd`
(`is_continue := (...) or (...)` nije mogao inferirati tip kroz `or` lanac
preko različitih `InputEvent` podtipova — riješeno eksplicitnim
`if/elif` umjesto jednog izraza). `test_match.gd` i dalje 54/54.

**Sljedeći korak (nije ovdje rađeno):** zamijeniti `formation_setup.tscn`
stub pravom logikom ručnog postavljanja figura — nova faza u `MatchState`
(igrač tapka svoju polovicu, postavlja figure jednu po jednu počevši od
golmana, umjesto da `Formations.home()/away()` sve automatski poreda).

## 2026-07-10 — Glavni izbornik (po uzoru na original iz 2006)

**Zašto.** Korisnik je sam dizajnirao `splash_screen.tscn` u editoru
(pozadinska slika, logo, `my_theme.tres`/BebasNeue font, glow environment) i
tražio da se ostavi netaknut. Poslao je screenshot izbornika iz originalne
igre iz 2006. (1 Player game / 2 Player game / Options / Instructions /
Credits / Quit) i zatražio isti raspored, s tim da Credits ne bude istaknut
kao ostali gumbi nego običan tekstualni gumb koji vodi na legal/credits
stranicu. Dosad je splash vodio izravno na odabir momčadi — sad se ubacuje
pravi glavni izbornik između njih.

**`GameFlow.Screen` proširen s 4 na 8 ekrana:** dodani `MAIN_MENU`,
`OPTIONS`, `INSTRUCTIONS`, `LEGAL` (uz postojeće `SPLASH`, `TEAM_SELECT`,
`FORMATION_SETUP`, `MATCH`). `splash_screen.gd` sad vodi na `MAIN_MENU`
umjesto izravno na `TEAM_SELECT` — jedina izmjena te scene je ta linija
koda, izgled nije diran.

**`scenes/ui/main_menu.tscn` + `main_menu.gd`.** 6 gumba u `VBoxContainer`
(placeholder raspored, `my_theme.tres` za font — za redizajn u editoru):
"1 Player game" je `disabled` (nema AI protivnika, vidi backlog), "2 Player
game" vodi na `TEAM_SELECT`, "Options"/"Instructions" na svoje ekrane,
"Credits" je `flat = true` gumb (bez pozadinske "pilule" kao ostali,
namjerno manje istaknut) koji vodi na `LEGAL`, "Quit" zove
`get_tree().quit()`.

**`scripts/ui/info_stub.gd` — jedan generički ekran za tri scene.** Umjesto
tri gotovo identične skripte, jedan skript s `@export var title_text` /
`@export var body_text` (postavljeno po instanci u `.tscn`-u) + gumb
"Natrag" na izbornik. Koriste ga `options_screen.tscn` ("uskoro"),
`instructions_screen.tscn` (pravi sažetak pravila — poteza, gola, zaleđa,
kartona, na hrvatskom) i `legal_screen.tscn` (jasno označen TODO placeholder
tekst koji korisnik treba sam urediti u `LegalScreen.body_text` — autor,
impressum, licence fontova/zvuka).

**`team_select.tscn`** dobio "Natrag" gumb (uz postojeći "Dalje") da se
može vratiti na glavni izbornik bez restarta aplikacije.

**Pitanje o Firebaseu (odgovoreno u razgovoru, ne u kodu):** korisnik je
pitao treba li registrirati igrače ako igra ide preko Firebasea. Odgovor:
ne — Firebase Anonymous Auth daje stabilan UID po instalaciji bez ikakve
prijave; ako kasnije zatreba spremanje preko više uređaja, anonimni račun
se opcionalno može "linkati" na Google/Apple. Trenutno u projektu nema
nikakve online/Firebase integracije — samo za kasnije.

**Verifikacija.** Svih 7 `scenes/ui/*.tscn` + `main.tscn` headless-učitano
bez grešaka (uklj. provjeru da su multiline `body_text` stringovi u
`.tscn`-u ispravno parsirani), `--headless --editor` scan čist,
`test_match.gd` i dalje 54/54 (ova sesija nije dirala `match_state.gd`).

**Popravak veličine sadržaja (isti dan).** Korisnik je primijetio da su
gumbi/tekst premali u odnosu na canvas (1080×1920, `stretch/mode=canvas_items`
+ `aspect=expand` iz `project.godot` — sve veličine se dakle crtaju u tim
"stvarnim" pikselima, ne u nekoj maloj apstraktnoj jedinici, pa treba
razmišljati u toj skali). Uzrok: `my_theme.tres` je imao
`default_font_size = 0` (Godot default ~16px) i `Button` font 30px, gumbi
`custom_minimum_size` 320×64 — sitno na 1080px širokom platnu. **Dodatno,
`team_select.tscn` i `formation_setup.tscn` uopće nisu imali `theme =` na
root čvoru** (previd iz prošle sesije) pa nisu ni koristili `my_theme.tres`.
Popravljeno: `my_theme.tres` → `default_font_size=42`, `Button` font 48;
teme dodane na `team_select`/`formation_setup`; svi glavni gumbi
`custom_minimum_size` podignut na ~340×130 (naslovni na main menu 820×150,
"Credits" namjerno ostaje manji, 300×90, jer je `flat` i ne treba se
isticati); naslovi na 84px; duži tekstovi (Instructions/Legal body) dobili
eksplicitni manji font (36px) i širi wrap (880px) da dugi pasusi ne budu
neproporcionalno veliki. Sve headless provjereno ponovno, čisto.

**Safe-area margina, dosljedno na svih 7 ekrana (isti dan).** Splash je
imao `Center` = `MarginContainer` s `margin_left/right = 80` (korisnikov
dizajn) — ostalih 6 ekrana (`main_menu`, `team_select`, `formation_setup`,
`options/instructions/legal_screen`) nisu imali tu marginu, samo
`CenterContainer` izravno na rootu, pa im je sadržaj mogao dosegnuti sam
rub platna. Dodan identičan `SafeArea` (`MarginContainer`, 80px lijevo/
desno) između pozadine i postojećeg `Center`/`VBox` na svih 6 — čvorovi i
`unique_name_in_owner` reference nisu dirane, samo je `Center` sad dijete
`SafeArea` umjesto root Controla. Provjereno da širine sadržaja (880px kod
Instructions/Legal body, 820px main menu gumbi) i dalje stanu unutar
preostalih ~920px. Headless load na svih 7 scena + `main.tscn` čist.

**Gumbi: pravi gradient umjesto flat boje (isti dan).** Korisnik je poslao
referentni screenshot (zaobljeni zlatni gumbi, gradient, deblji donji rub,
smeđi bold font) i tražio isto, obavezno s pravim gradientom. `StyleBoxFlat`
fizički nema gradient (samo flat `bg_color`) — zato je zamijenjen
`StyleBoxTexture` pristupom: `scripts/tools/gen_button_textures.gd` (novi,
jednokratni generator) peče 4 PNG-a (normal/hover/pressed/disabled) u
`assets/textures/ui/button_*.png`, piksel-po-piksel, koristeći rounded-box
SDF formulu (Inigo Quilez) za glatko antialiasirane zaobljene kutove +
vertikalni lerp gradient boje + solid boju samo u zadnjih ~15px (donji
border, korisnikovo ranije podešavanje na `StyleBoxFlat` prije ovoga).
Teme referenciraju te texture kao `StyleBoxTexture` s `texture_margin=40`
(9-slice, sredina se rasteže bez kvarenja kutova). Provjereno da je i sama
generirana slika ispravna (učitana i vizualno pregledana, ne samo da
property "postoji") prije nego se krivnja tražila drugdje.

**Duh u mašini: Godot editor je 3× zaredom vratio `my_theme.tres` na staru
flat verziju**, čak i nakon punog gašenja i ponovnog pokretanja editora s
"Discard" na eventualni save-prompt — dakle ne obična "otvoren resurs u
editoru drži staru verziju u memoriji" priča, nego nešto upornije
(moguće project-restore/crash-recovery koji vraća zadnje poznato stanje
resursa, ili neki drugi keš izvan dosega jednostavnog reloada). Umjesto
daljnjeg nagađanja, **riješeno zaobilaženjem**: kreiran potpuno nov fajl
`my_theme_gold.tres` (nov naziv, nov UID, ništa što bi se moglo pomiješati
sa starim kešom) sa istim `StyleBoxTexture` sadržajem, i svih 7 UI scena
(`splash_screen` uklj.) prebačeno da ga referenciraju umjesto
`res://my_theme.tres`. Stari `my_theme.tres` ostavljen netaknut na disku
(ništa ga više ne koristi) za slučaj da nešto drugo još visi na njega.
Verificirano headless da stvarni Button node unutar `main_menu.tscn`
(ne samo izolirani Theme resurs) rješava `normal` stil u `StyleBoxTexture`
s ispravnom teksturom. Ako se ista "vraća se sama" pojava ikad ponovi na
BILO KOJEM resursu, ovo je dokazani recept: presnimi na nov fajl/UID umjesto
daljnjeg pokušavanja da se "uvjeri" postojeći.

**Jači gradient + font emboss (isti dan, nastavak).** Korisnik je javio da
je vidljiv gumb, ali gradient djeluje kao da ga nema. Uzrok: `gen_button_textures.gd`
je pekao teksturu 128px visoku s `texture_margin=40` — 9-slice sredina se
rasteže iz uskog, niskokontrastnog dijela gradijenta (t=0.31 do 0.69), pa na
stvarno visokom gumbu ta rastegnuta sredina vizualno dominira i djeluje
skoro flat. Popravljeno: tekstura sad 100px (manje "rezerve" za rastegnutu
sredinu → fiksni rubovi nose većinu vizualnog raspona boje), veći kontrast
boja (blijedo krem vrh → bogata amber-smeđa baza), plus nov tanki rub
(`RIM_WIDTH=4`) oko CIJELOG gumba (ne samo dna) uz postojeći deblji donji
border — bliže referentnoj slici.

**Font emboss.** Provjereno (`ThemeDB.get_default_theme().get_color_list("Button")`)
da `Button` u Godotu 4 NEMA `shadow_color`/`shadow_offset` kao theme stavku
(samo `Label` ima) — samo `font_outline_color`/`outline_size`. Pravi emboss
stoga nije moguć kroz `my_theme_gold.tres` samog. Riješeno kroz
`scripts/ui/styled_button.gd` (`class_name StyledButton extends Button`):
sakrije vlastiti tekst gumba (sve `font_*_color` postavljene na providno
preko `add_theme_color_override`), pa preko njega doda cjeloekranski
(`PRESET_FULL_RECT`) `Label` s `mouse_filter=IGNORE` (klikovi prolaze kroz
njega do gumba ispod) i pravim `LabelSettings`: boja/veličina/outline
pročitani JEDNOM iz teme prije nego se sakriju (da se ne "kontaminiraju"
vlastitim providnim overrideom), plus `shadow_color` svijetla topla nijansa
POMAKNUTA GORE (`shadow_offset=(0,-3)`) umjesto dolje — trik za "ispupčeni
rub" jer svijetla sjena iznad + tamni outline oko slova zajedno čitaju kao
blagi emboss. Skripta se ponaša kao normalan Button (toggle_mode,
button_group, `.text`, signali, min-size) — samo su nacrtani glyph-ovi
zamijenjeni. Primijenjeno na svih 15 pravih Button node-ova kroz 6 scena
(namjerno preskočeno na `OptionButton` nodeove u team_select jer taj tip
nema javni `.text` na isti način). Verificirano headless na STVARNO
instanciranom gumbu iz `main_menu.tscn`: native `font_color` providan,
overlay Label postoji s ispravnim tekstom, `LabelSettings` ima točan
font_size/color/outline/shadow. `test_match.gd` i dalje 54/54.
