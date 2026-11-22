# Sky Duel — 2.5D Airplane Combat (Godot 4.7)

A side-view airplane dogfight for Android, iOS and desktop. Two cartoon fighter
planes wait on a grass strip at opposite ends of a wide landscape, each facing the
middle of the map. Press **Up** and the plane rolls along the surface, lifts its
nose and climbs away — then turn and shoot the other pilot out of the sky, while
infantry on the ground take slow pot shots at both of you.

Built with Godot 4.7.2, GDScript and the **Mobile** renderer. The game is **2.5D**:
the world, physics, hitboxes, projectiles and the whole interface are flat 2D,
but each airplane is a real low-poly **3D model** (`PlaneModel3D`) rendered inside
a `SubViewport` by an orthographic camera that sits on the aircraft's side and
never moves. The 2D `Airplane` node rotates and mirrors that render exactly as it
used to rotate a sprite, so the fighter is always shown in profile while keeping
the volume, panel shading and spinning 3D propeller of a model. Each pilot's
model is built from their own livery colours (player olive and yellow, opponent
crimson and cream), so the two aircraft are told apart at a glance. The cloud,
fireball sheets are animated vector sprite sheets drawn for this project by
`tools/build_art.py`, and the ground infantry is a low-poly 3D figure rendered
the same way as the planes.

Four modes are playable: **vs AI** (Easy / Normal / Hard), **Survival** (AI
fighters that keep coming, scored by how many you shoot down), **two players on
one screen**, and **two devices over the local network** (LAN). Bluetooth still has a
transport architecture and an honest, non-functional stub; see
[docs/BLUETOOTH_INTEGRATION.md](docs/BLUETOOTH_INTEGRATION.md).

---

## Run it

Requires **Godot 4.7.x** (the project targets the mobile renderer, which also runs
fine on desktop).

```bash
# from this folder
godot --path .            # or open project.godot in the editor and press F5
```

macOS with the standard install:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

### Building an Android APK

The project ships an Android export preset (`export_presets.cfg`, package
`com.skyduel.game`, label *Sky Duel*). With the Godot 4.7.x export templates
installed and the Android SDK / Java 17 paths set in the editor settings:

```bash
# from this folder: build the current state, install it and launch the game
./tools/build_apk.sh

./tools/build_apk.sh --build-only     # just build, no adb needed
./tools/build_apk.sh /tmp/duel.apk    # build to another path, then install it

# by hand:
godot --headless --path . --export-debug "Android" build/sky_duel.apk
adb install -r build/sky_duel.apk
```

`tools/build_apk.sh` exports headlessly, only replaces the previous APK once the
new one is written, then installs it on the single phone or emulator that `adb`
can see and starts the game on it. With no device attached it says so, exits
non-zero and keeps the APK. Several devices at once: pick one with
`ADB_SERIAL=<serial>`. An emulator that is still booting is waited for instead of
being rejected. Overrides: `GODOT=/path/to/godot`, `ADB=/path/to/adb`; by default
it uses Godot's macOS install and the `adb` on your `PATH` (or in the Homebrew
Android SDK).

The APK is signed with the Godot debug keystore, so it installs straight onto a
phone with "install unknown apps" allowed; it is not a Play Store build. The
preset grants the **INTERNET** permission (`permissions/internet=true`) — without
it Android gives the app no sockets at all and LAN hosting fails with
`Could not host on port 27777 (error 20)`, which is Godot's `ERR_CANT_CREATE`. Two
settings make it export: textures are imported for **ETC2/ASTC**
(`rendering/textures/vram_compression/import_etc2_astc`), and Android uses the
**OpenGL compatibility** renderer (`rendering/renderer/rendering_method.mobile`),
which runs on the widest range of devices and on emulators with software Vulkan.
Desktop still uses the mobile (Metal/Vulkan) renderer.

---

## Controls

### Desktop

| Action | Player 1 | Player 2 (same-screen mode) |
| --- | --- | --- |
| Turn left | `A` or `←` | `←` |
| Turn right | `D` or `→` | `→` |
| **Take off** | `W` or `↑` | `↑` |
| Gear up (one gear per tap) | `W` or `↑` | `↑` |
| Gear down | `S` or `↓` | `↓` |
| Fire | `Space` | `Enter` |
| Drop a bomb | `B` | `/` |
| Jet boost (hold) | `Shift` | `Ctrl` |
| Flares | `F` | `.` |
| Shield | `G` | `,` |
| Pause / resume | `Esc` | |
| Restart match | `R` | |
| Toggle touch pad (testing) | `F1` | |

In single player, Player 1 answers to **both** the A/D/W/S/Space set and the
arrow keys.

### Mobile

Large on-screen controls appear automatically on touch devices (and with `F1` on
desktop):

- bottom-left: **◀** and **▶** turn buttons (hold them)
- bottom-right: a runway-and-chevron **take-off** button, which turns into a
  wheel-and-chevron **gear-up** button once the wheels leave the ground, a
  wheel-and-chevron **gear-down** button, and the **fire** button, drawn as a
  gunsight
- above the fire button: a **bomb** button, drawn as a falling bomb (with a
  ring that fills while the rack reloads), a **boost** button, drawn as a bolt, a
  **flare** button, drawn as a spitting star, and a **shield** button, drawn as a
  shield

The glyphs are drawn in `TouchButton` (no textures), so they stay crisp at any
size. The buttons track touches by index, so several fingers can be held at once, and
they are laid out in design units (1280×720 with `canvas_items` stretch), so they
scale to any phone or tablet in landscape. To always show them, set
`input_settings/touch/force_virtual_controls` to `true` in Project Settings.

---

## How the game plays

- **Ten fighters to pick from.** The FIGHTER strip on the title screen walks a
  roster that runs from the valley's piston fighters to the modern jets and ends
  on a fighter that never flew: Kestrel Mk I, Corsair FB, Spitfire IX, Mustang
  P-51, Lightning P-38, Sabre F-86, Mirage Delta, Eagle F-15, Raptor F-22 and
  Aurora X. Each one is a different 3D airframe — gull wing, elliptical wing,
  twin boom, nose intake, delta, twin canted tails, a faceted stealth shape and
  finally forward-swept wings with a spinning energy intake — with its own paint
  and its own numbers for top speed, turn rate, rate of fire and armour — the
  picker draws all four as bars with the values beside them. Speed, turn and fire
  rate climb from the props towards the jets (152 px/s and 2.8 rounds/s for the
  Kestrel, 208 px/s and 5.0 rounds/s for the Aurora), while armour is spread the
  other way, from the 168-health twin-boom down to the 139-health experimental.
  Every airframe still goes down to five normal hits, so the choice changes how
  you fly, not how long you last. Whatever you pick, an AI opponent rolls out a different
  fighter (drawn from the session key), and in a duel both pilots fly the same
  airframe so neither side gets the faster plane.
- **Take-off ends in level flight, not a vertical climb.** Both airplanes start
  parked on the flat field, engines idling, nose pointing along the runway toward
  the middle of the map. Pressing Up starts a roll that accelerates to flight
  speed over ~190 px, kicking up dust behind the wheels. It never stops during the
  manoeuvre: the nose rotates up to a 30° climb-out angle (62°/s) while the plane
  keeps rolling, the tyres leave the strip, it climbs out for just over a second,
  and then it levels off again and settles into **horizontal** flight across the
  field. The airframe stays just high enough that neither the belly nor the
  rising tail cuts into the grass. Nothing (turning, guns) happens before that:
  the plane is still on the ground. The AI rolls out a moment later depending on
  difficulty.
- **Four throttle gears.** Up is also the throttle: tap it in the air to shift up
  a gear, `S` / `↓` (or the on-screen **▼**) to shift down. A press changes the
  gear once — holding the button never ratchets through them. The gears are
  0.55× / 1.0× / 1.45× / 2.0× of the plane's base speed (88 / 160 / 232 / 320
  px/s at the default tuning), so gear 1 crawls, gear 2 is the old cruise and
  gear 4 nearly doubles it. Each shift plays a short engine blip that jumps up a
  step, or sweeps back down when you drop a gear, on top of the continuous engine
  drone that climbs in pitch as you go up the box, and the engaged gear is shown
  under each pilot card. Planes launch in gear 2, and the AI works its own
  throttle to close a gap or settle onto your tail.
- **You never hover.** The plane always moves forward along its nose, so turning
  is how you close distance. The nose is not limited: turn until the plane points
  down, keep turning and you fly a full loop. `max_rotation` is 360° by default
  (set it below 180 if you want the old "climbing only" feel).
- **The airframe never flies upside down.** A side view of a loop would leave the
  plane on its back once it passes the vertical, so at that moment the model rolls
  half a turn about its own fuselage axis: 0.34 s in which a wing swings up
  through the profile, the airframe turns over, and it comes out showing its
  other side, belly down. That is a real roll of the 3D aircraft, not a mirrored
  picture, so the plane never appears to fly backwards and the nose keeps
  pointing where the plane is going the whole time.
- **The map wraps.** Fly off the left edge and you come back in on the right at
  the same height and heading — and the other way round. The camera snaps across
  with you instead of sweeping over the whole map. Bullets do not wrap; they stop
  at the map edge.
- **The world is much bigger than the screen** (3200 × 18280 design px). The
  opponent starts far outside your camera's view; the camera never zooms out to
  reveal them. It does sit fairly wide (`camera_zoom = 0.82`), so there is always
  air visible around the plane. The flat surface is **solid**: fly into it and
  the plane explodes where it hits and the round goes to the other pilot, so a
  dive is a real risk, not a free escape.
- **Shooting.** Projectiles spawn at the muzzle, travel at 5× plane speed
  (800 px/s at cruise, configurable), live 3 s, and are removed when they leave
  the world. They can never damage their owner. The infantry's shells are a lot
  slower — 420 px/s — so ground fire is easy to see coming and easy to outrun.
- **Bombs.** Every plane rolls out with **two** bombs in its rack. `B` (or the
  on-screen bomb button) releases one from under the belly: it inherits a third of
  the plane's speed, falls under gravity, and bursts either on the field or
  against the other airframe. The blast is radial — full damage (70) at the
  centre, a third of it at the rim, roughly two-thirds of a fighter's health for
  a direct hit — and the pilot who dropped it is never caught in it. Bombs are
  best dropped from above and close: from high up they are easy to see and easy
  to fly out from under.

  **The rack reloads itself.** Drop the second bomb and the ground crew start
  winching two fresh ones up: **15 seconds**, during which the bomb button is dead
  and shows the wait as a ring filling round it (the HUD's bomb line reads
  `RELOAD 9s`). No more scrounging bombs out of crates — the limit is the wait,
  not the supply.
- **Jet boost.** The plane carries a boost tank that burns while you hold
  `Shift` (or the on-screen bolt) and refills once you let go. Lit, the engine
  puts out 1.75× the engaged gear's speed for up to three seconds, at the cost of
  a tank that takes about thirteen seconds to fill; the strip under each health
  bar shows how full it is. Drain it and you fly on the engine alone until it
  charges again — so it is for closing a gap, breaking off, or catching a crate
  before the other pilot does, not for permanent speed.
- **Shield.** A crate can hand over a **shield charge**, and `G` (or the
  on-screen shield button) spends it on a bubble of light around the airframe that
  **stops everything the enemy has for fifteen seconds** — bullets, heavy shells,
  bomb blasts, the lot — with a bright ripple each time it swallows a hit. It does
  not help with the ground: flying into the field still ends the run. The HUD
  counts it down under each pilot card (`SHIELD 12s`), and the AI buys one too,
  once its health is under half and it still has a charge in hand.
- **Flares.** Every plane carries a dispenser of **three** (crates carry two
  more). `F` throws a burst of five burning decoys out behind the tail. They are
  a hard counter to the one thing you cannot out-fly: a homing round within
  320 px abandons the aircraft and chases the nearest flare instead, and spends
  itself on it. They also light the fuse of any bomb that drifts close, so a bomb
  dropped on you from above can be set off in the air well short of the blast.
  The burst has a half-second cooldown and each one costs a charge, so the
  dispenser is a decision: spend them on the round that is already coming, or
  keep one in reserve. In a LAN duel the burst is mirrored, because it is the
  other device's homing rounds that have to be fooled.
  Health is 150 and a bullet does 34, so a plane takes five hits. The planes are
  deliberately thin: the hitbox is a small capsule (8.6 px radius) inside the
  artwork, so a shot that only clips a wing or the spinner passes by instead of
  counting.
- **Damage stages.** The first hit leaves scorch marks and a rougher engine. The
  second adds a permanent smoke trail. The fifth knocks the plane out of the sky:
  smoke pouring, it spins and falls under gravity, and the explosion that ends the
  round happens where it hits the surface — not in mid-air.
- **The courier run.** Now and then a small cargo plane crosses the sky behind
  the fighters and lets one load go over the fields. It wears the badge of what it
  is carrying on its fuselage — green for repair gear, red for the instant round,
  blue for the homing one, amber for bombs, pale gold for flares — so you know
  what is worth chasing before anything drops. The load hangs from a
  parachute and drifts down, swinging side to side; if it reaches the ground it is
  lost, so the only way to get one is to break off and go and catch it — early,
  or in a dive once it is already low. Either pilot can take any drop, and only
  one pass and one load are ever in the air at a time.
  - **Repair coin** — a gold coin with a green cross, on a slow chute. Caught, it
    patches the plane up: full health, no scorch marks, no smoke, hit count reset,
    so the damage stages start over.
  - **Supply crate** — a wooden crate stamped with what it holds, coming down a
    little faster. The red and blue ones hold exactly **one special round**, and
    the next shot fires it instead of a normal bullet (the loaded round is named
    under the pilot's card):
    - **Instant round** — a heavy red shell at 760 px/s. One hit ends the fight
      outright, however fresh the target is.
    - **Homing round** — a blue shell that chases the enemy for three seconds at
      330 px/s, turning at up to 130°/s. Full throttle (320 px/s) can just outrun
      it and a hard turn can out-turn it, so it is a problem to fly out of rather
      than a death sentence. Flares will shake it off entirely.
    - **Flare crate** (pale gold, stamped with a spitting star) — two more
      flares in the dispenser.
    - **Shield crate** (violet, stamped with a shield) — one charge of the
      bubble that stops enemy fire.
  The courier comes 2.5 s after take-off and then every 24–36 s. Its route, its
  load and its drop point are all drawn from a key rolled fresh for each session,
  so the sequence is different every time you play — and in a LAN duel the host
  hands its key to the other device, so both screens still drop the same load in
  the same place.
- **Infantry on the ground.** A squad of small 3D infantrymen stands along the
  flat surface, rifles swinging round to follow whichever plane is closest
  overhead. Now and then one of them fires a single slow tracer along his rifle
  (±8° spread) — 9–15 s apart on Normal, 6–10 s on Hard, deliberately sparse so
  the duel stays between the aircraft. Their rounds do 8 damage, so they cannot
  decide a duel on their own, but they chip away at both pilots and they can hit
  anyone. **Easy fields none**, Normal three, Hard four.
- **Survival.** The same fight against the AI pilot, but endless: every enemy
  you shoot down counts as a kill and, a second and a half later, another fighter
  rolls onto the strip somewhere down the map and takes off by itself. The tally
  sits under the mode line (`ENEMIES DOWN n · BEST m`), the best run is saved on
  the device, and the first kill that beats it earns a **NEW RECORD** banner.
  **Every kill patches the pilot up**: 45 health back (a third of the bar), so a
  long run is survivable by flying well instead of only by finding a repair coin.
  Going down yourself ends the run, and the result screen shows how many fighters
  you shot down against your best. The best score is also printed on the Survival
  button on the title screen.
- **Day and night.** A match starts at a **random point in the day** — dawn,
  noon, dusk or the middle of the night — and then runs on through a full cycle:
  the sun tracks an arc across the sky, the light turns golden and low at dusk, then night falls under a moon
  and a field of stars. Twilight takes a couple of minutes, not a switch. After
  dark the whole world is tinted moonlit blue — still readable — and each plane
  turns on a landing lamp that throws a soft cone of light ahead of its nose.
- **Weather.** The title screen has a **WEATHER** row: **Auto** (the default),
  **Clear**, **Cloudy**, **Rain** and **Snow**. Auto rolls a fresh opening sky for
  every session — usually clear or overcast, sometimes a storm — so two matches
  never start alike; picking one of the others pins it for the whole match. Cloudy greys the sky out, thickens and dulls the clouds
  and hides most of the sun; rain does the same, darker, and adds a downpour of
  streaks across the screen; snow keeps the light bright but pale and drifts
  flakes instead. All three dim the world tint, and they combine with the day
  cycle, so a rainy night is the darkest the game gets — the landing lamps earn
  their keep. A survival run ignores nothing: it starts with the weather you
  picked and then rolls its own every minute or so (mostly clear, sometimes
  overcast, now and then a rainstorm), fading one kind into the next over a few
  seconds. A LAN duel is always clear, since the two pilots never picked a sky
  together.
- **Result.** The crash hands the round to the other pilot, with Rematch / Main
  menu.

---

## How it looks

The game is staged as a warm, golden-hour diorama. Every layer is painted from
primitives or generated SVG, so there are no large bitmap backgrounds anywhere:

- **Sky.** A four-stop gradient from deep azure to a warm horizon, a soft sun
  with a smooth radial halo, and haze that thickens toward the ground. In a match
  the gradient, the sun, the moon and the stars all move with the day night cycle
  (`DayCycle`): the sun crosses an arc, sets into a warm horizon, and gives way to
  a moon on the opposite side while stars come out. Weather pulls all of that
  toward an overcast palette and drops the sun behind the cloud, while
  `WeatherLayer` adds the rain or snow on its own canvas in front of the world. A
  screen-space vignette pulls the eye to the middle of the frame.
- **Distance.** Three rolling hill ridges, each lighter and hazier than the one in
  front of it, plus a layer of drifting far clouds. World clouds churn through
  their own six-frame sheet and wander on their own instead of scrolling in
  lockstep.
- **Ground.** Staged as a 2.5D surface rather than a flat band. The furrows of
  every field fan in toward a vanishing point above the horizon, so the rows open
  out toward the viewer; each hedge throws a shadow into the field beside it, a
  haze band dissolves the far edge into the air, and the distant ridges behind
  the fields stay lighter and cooler than the near ones. Between the road and the
  bottom of the world sit two more layers of their own, and each one carries real
  objects rather than texture, so you can see it move:
  - the **near verge**, at **1.38×** the world's rate: straw bales left in the
    grass, low bushes, saplings, boulders with a lit edge, tall grass clumps,
    flowers, a fence line with its wire sagging between posts, and a worn farm
    track cutting through
  - the **foreground bank**, at **2.15×**: an undulating dark lip with oversized
    grass blades, fern fans and quarried boulders silhouetted almost black

  Because they travel at different rates, everything near the bottom of the frame
  sweeps past while the fields behind barely creep: the near bush overtakes the
  bale, the bale overtakes the fence post, the fence post overtakes the hedge. That
  relative motion — not the drawing — is what makes the strip of country read as
  ground the camera is flying over. Nothing the game touches moves: the surface,
  the runway, the soldiers and the shadows all stay exactly where they were.
- **Wet airframes.** In rain, water sits on the plane: beads on the spine, the
  near wing and the tailplane swell as they land and creep back along the
  airframe in the airstream, the paint picks up a wet sheen, and spray whips off
  the nose while it flies. It fades in and out with the weather, so a shower
  either side of clear sky leaves the plane dry again.
- **Ground squads.** The infantry work pintle-mounted heavy cannon — a fat barrel
  in a jacket, a muzzle brake, an ammunition drum and a recoil spring — that swing
  on their mount to follow a plane, instead of the rifles they used to carry. The
  fire rate and the shell speed are exactly what they were: the guns only look
  like they mean it.
- **Bombs and boost.** A bomb is a fat olive teardrop with crossed tail fins, a
  yellow band and a blinking fuse, nosing over with its fall and trailing vapour.
  The jet boost draws a flickering cone of blue-white fire off the tail, with a
  particle plume behind it, and the boost tank sits under the health bar as a
  cyan strip that drains and refills.
- **Planes.** Each fighter is a rendered 3D model seen from the side: a tapering
  fuselage, bubble canopy, tapered wing with dihedral and painted tips, tail fin
  and the exhausts and radiator that give the profile its detail. It stands on
  retractable landing gear — main wheels under the wing root and a tail wheel —
  sized so the tyres meet the strip: they roll at the actual ground speed through
  the take-off run, and once the tyres leave the grass the legs swing up about
  their hinges into the wheel bays while the assembly shrinks and sinks out of
  sight — a slow, deliberate wind-up rather than a pop, and the gear only
  disappears when it is inside the wing. It casts a soft shadow on the field that spreads and
  fades as it climbs, spins a 3D two-blade propeller with a motion-blur disc,
  kicks back and flashes at the nose when it fires, and whips white for a moment
  when hit. A kill ends in a fireball with an expanding shockwave, sparks and a camera
  kick.
- **Interface.** Glass pilot cards over the sky: a soft shadow, a lit rim, a
  sheen across the top, an accent rail down the outer edge and a badge holding the
  aircraft's nose — gold for you, warm amber for the other pilot, both cooling to
  ember red as that plane runs out of health. The health bars are drawn by hand
  rather than styled: a dark glass capsule, a glossy fill that drains smoothly,
  a warm ghost that hangs on for a beat after each hit so you can see how much it
  cost, a groove per hit it takes to go down, and a pulsing warning ring under
  twenty-five percent. The number sits in the header opposite the name. A title
  screen built on the game's own valley with a fighter cruising past, and a result
  card that pops in over the dimmed field.
- **Radar.** A dial under the player card with your airplane in the middle pointing
  along its nose and the enemy placed at its real offset from you — the horizontal
  one taken the shorter way round the wrapping map — so you can tell whether he is
  above, behind, or two screens away. Past the dial's range he sits on the rim with
  a hollow ring. The courier shows as a pale diamond and a falling load as a dot in
  its own colour (green repair, red instant, blue homing, amber bombs, pale gold
  flares), so a drop can be found
  after it goes off screen; both are pinned to the rim when out of range too. The
  dial is hidden in local versus, where both planes share the screen.

---

## LAN multiplayer (two devices)

Both devices must be on the same Wi-Fi/network. The game uses **UDP port 27777**
(ENet).

1. On device A: **Host LAN**. The menu shows `Waiting for the other pilot...` and
the host's own IP address.
2. On device B: just press **Join**. The menu broadcasts on the local network
   (`LAN discovery`), the host answers, and its address is filled into the **Host
   IP** field (`Found a host at 192.168.x.y - press Join`). Typing an address
   still works and is the fallback on networks that block broadcast traffic or
   isolate clients from each other.
3. As soon as the two connect, the match starts on both screens. The host flies
the left airplane, the joining device flies the right one, and each device's
camera follows its own airplane.

On both devices you fly your own plane with the player-1 keys (`A`/`D` or
`←`/`→` to turn, `W` to take off and to shift up a gear, `S` to shift down,
`Space` to fire) or the touch pad.

How it works: both devices run the identical simulation (same planes, same
spawns, same deterministic combat) and the **input** of each device's own airplane
travels over the network, reliably, once per physics tick. A state heartbeat every
0.25 s spots a divergence and nudges the remote airplane's position back.
The courier's pass and its drop point come from a fixed seed, so both screens
get the same load in the same place and both sides see the same pilot take it
(the test script compares the planned drop and the released load across the two
processes as well as the planes).

**A duel never ends.** Every crash is a round for the other pilot: both fighters
roll back onto their strips a couple of seconds later and the match keeps going,
round after round, for as long as you both stay. The line under the mode label
reads `ROUND 3  ·  YOU 2 — 1 THEM` from each device's point of view. There is no
result screen because there is no final score. Both devices also fly the same
airframe — the host's pick — so the two simulations share one set of stats; each
pilot keeps their own paint on it.

**Hits are decided once.** Both devices simulate both airplanes, but only the
device that fires a shot decides that it landed: it applies the damage to its own
copy immediately and sends the hit reliably to the other device, whose copy
applies exactly the same amount to the airplane it owns. Both screens therefore
lose the same health, and a pilot cannot be dead on one screen and alive on the
other. While a hit is still in flight the heartbeat is ignored for that airplane,
so a stale, pre-hit number can never spring the bar back up — the heartbeat only
heals real drift. Ground fire is applied only by the airplane's own device, and
so is a repair pickup, which is why neither bounces.
Nothing is server-hosted, so latency on a home network is a single tick. If the
other pilot disconnects mid-match you are returned to the menu.

**Rematch needs both pilots.** Pressing Rematch asks the other device; the round
restarts as soon as both have asked. If the other pilot asks first the result
screen says so and your Rematch button becomes the accept button.

**Connection quality** is shown in the HUD mode label in LAN matches (`LAN match
· host · 18 ms`). The ping is a real round trip every 0.5 s, and the `% loss`
reading appears only when heartbeats are actually going missing — on a healthy
home network it stays hidden.

Testing it without a second device:

```bash
tools/run_lan_test.sh    # starts two headless instances over real UDP on localhost
```

The script plays a scripted match on both processes and fails unless the remote
airplane launches and turns from the network input, the ping works, a rematch
asked for by both sides starts a fresh round, and both simulations agree within
25 px.

### LAN troubleshooting

- **"Waiting for the other pilot..." never ends.** The two devices are not
  reaching each other. Check that the typed address matches the IP the host shows,
  that both devices are on the same Wi-Fi (guest networks and some routers block
  device-to-device traffic), and that the host is still on the menu.
- **"Could not host on port 27777".** Something already owns that UDP port — most
  likely another copy of the game still running or waiting in the background.
  Quit it and host again.
- **The first host or join triggers a firewall prompt.** Allow it; on Windows also
  allow the game on *private* networks. Blocking it keeps the two devices from
  finding each other even on the same Wi-Fi.
- **Planes feel laggy.** Watch the ms/loss readout in the HUD. Under ~60 ms the
  duel plays like local two-player; heavy loss shows up as the other airplane
  hopping back into place.

---

## Project layout

```
scenes/
  main/main.tscn            app flow: menu -> match -> result
  game/game.tscn            world, camera, HUD, touch pad, audio
  airplane/airplane.tscn    body sprite, muzzle flash, damage, smoke, dust, health
  projectile/projectile.tscn
  (bombs are drawn in code - scripts/projectile/bomb.gd)
  effects/explosion.tscn    animated fireball + shockwave + sparks
  environment/              landscape, cloud, soldier, house, farm, tree
  ui/                       hud, main_menu, game_over, mobile_controls
scripts/
  main/main.gd
  managers/                 input_manager (autoload), game_manager, audio_manager,
                            survival_record (best run on this device)
  airplane/                 airplane, airplane_health, airplane_controller,
                            player_plane_controller, plane_input, ground_shadow,
                            plane_model_3d (the rendered 3D airframe)
  projectile/              projectile, bomb
  ai/ai_controller.gd
  camera/camera_controller.gd
  environment/              landscape, ground_depth (the parallax verge and
                            foreground), hills, cloud_controller, cloud_field,
                            far_clouds, sky, day_cycle (sun, moon, twilight),
                            weather (clear/cloudy/rain/snow), weather_layer
                            (rain and snow), vignette, scenery_prop,
                            scenery_shadow, soldier, soldier_field,
                            soldier_model_3d (the rendered 3D figure)
  effects/                 explosion, flare (burning decoys), sheet_frames
                            (strip -> SpriteFrames)
  multiplayer/              lan_transport (ENet), multiplayer_transport,
                            local_transport, bluetooth_transport,
                            remote_plane_controller
  ui/                       hud, main_menu, game_over, mobile_controls,
                            touch_button, ui_style, pilot_card, health_bar,
                            boost_gauge, radar_dial
resources/configurations/   plane_config, projectile_config, ai_config,
                            game_config (+ .tres presets)
assets/                     planes (attribution note; the airframe is modelled in
                            code), environment and effects (animated SVG sheets +
                            SVG props), icon (rendered launcher art)
tools/                      smoke_test, visual_check, lan_test, plane_preview (dev
                            harnesses), icon_builder (renders the app icon),
                            run_lan_test.sh, build_art.py (regenerates the sheets)
docs/BLUETOOTH_INTEGRATION.md
```

### Architecture notes

- **Input abstraction.** `InputManager` (autoload) registers actions and stores
  virtual presses from the touch pad. `Airplane` never reads `Input`: it pulls a
  `PlaneInput { turn, fire, launch, throttle, bomb, boost, flare, shield }` from its
  `AirplaneController` once per physics tick. `PlayerPlaneController`, `AIController` and
  `RemotePlaneController` are interchangeable at runtime, which is what makes AI,
  local and network players use identical movement/combat rules.
- **Network model.** `LanTransport` (the `Lan` autoload) owns the ENet peer,
  exposes `host()` / `join()` and streams one `PlaneInput` per device per tick
  through RPCs. Both devices run the very same deterministic simulation, so no
  positions are trusted from the wire — only intent — plus a small state
  heartbeat for drift correction and health.
	- **Orientation.** The airframe is modelled nose-right, and `rotation == 0` means
  "nose up" for every plane. A `Visual` node carries the ±90° offset that turns
  the horizontal art into a climbing aircraft: `-90°` for player 1, `+90°` for the
  Y-mirrored opponent (`visual_flip_h` in `PlaneConfig`). Flight math therefore
  never needs a per-player sign flip — a left input always swings the nose to the
  left of the screen — and the muzzle and collision capsule ride along with the
  airframe. Same-screen two-player mode uses one shared camera, so both players
  see the whole board; player 2's airframe is simply the mirrored render.
- **Sprite sheets.** `SheetFrames` turns a strip (or grid) sheet into `SpriteFrames`
  by wrapping each cell in an `AtlasTexture`, so one texture backs several
  animations. Clouds use 6 morphing frames and the fireball 10 (7 burning, 3
  smoke); the soldier is no longer a sheet: he is a rendered 3D figure, see below.
  mixes two uniforms. The airplane is the exception: it is not a sheet at all but
  a 3D model rendered live into a texture (see below), and only the muzzle flash
  stays a separate 2D sprite. Frame sizes are constants in the scripts that slice
  them.
- **2.5D airplanes.** `PlaneModel3D` builds a low-poly fighter from primitives at
  "art scale" (1 unit = 1 pixel, nose toward +X), lights it with a key, a fill and
  a camera light, and renders it with an orthographic camera that looks down 13°
  onto the model's side — enough to show the wing planform, never enough to lose
  the profile. Each airplane owns one viewport, coloured by the `livery_*` fields
  of its `PlaneConfig`. The rendered texture is 2x the art size and the `Body`
  sprite is scaled by `PlaneModel3D.sprite_scale()`, and the `Visual` node then
  applies `Airplane.MODEL_SCALE` (0.72), so the airframe flies at ~137 px long:
  small enough to leave real room to manoeuvre. The nose, muzzle, capsule hitbox,
  cast shadow and ground-clearance maths all scale with it, so the tuned
  190 px geometry stays the single source of truth.
- **Data-driven balance.** Flight speed, rotation speed, max rotation, health,
  fire cooldown, take-off roll distance/acceleration, climb-out angle and rates,
  projectile speed multiplier/lifetime/damage, AI difficulty and the world/camera
  bounds are all `Resource` fields. The four throttle gears live in
  `PlaneConfig.GEAR_FACTORS`.
- **Collision.** Airplanes are on physics layer 1; projectiles do a swept raycast
  per tick, so fast bullets cannot tunnel through a plane on a slow frame.
- **Performance.** Projectiles come from a preallocated pool of 28, clouds are
  recycled around the camera instead of being spawned/freed, and the landscape is
  painted with one `_draw()` call plus a handful of sprites.

### Key configuration files

| File | What it controls |
| --- | --- |
| `resources/configurations/plane_player.tres` | P1 speed, rotation, health, cooldown, take-off roll and climb-out, livery colours |
| `resources/configurations/plane_opponent.tres` | P2 / AI values, plus `visual_flip_h` for the mirrored render |
| `scripts/multiplayer/lan_transport.gd` | LAN port (default 27777), host/join, input + state packets |
| `resources/configurations/projectile_*.tres` | speed multiplier, lifetime, damage, radius, tint |
| `resources/configurations/ai_config.gd` | the three difficulty presets, including squad size and firing rate |
| `resources/configurations/projectile_soldier.tres` | the slow 8-damage tracer the infantry fire |
| `tools/build_art.py` | regenerates the cloud and fireball sheets and the muzzle flash |
| `resources/configurations/game_default.tres` | world size, ground line, spawn points, camera zoom |

AI difficulty presets (`AIConfig.preset`):

| | reaction | aim error | fire cooldown ×| attack range | fire cone | take-off delay | soldiers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 0.90 s | ±15° | 1.9 | 950 px | 17° | 1.7 s | none |
| Normal | 0.40 s | ±6° | 1.15 | 1350 px | 10° | 0.9 s | 3, every 3.5–7 s |
| Hard | 0.18 s | ±2.5° | 0.72 | 1650 px | 7° | 0.5 s | 5, every 2.2–4 s |

Versus and LAN matches use the Normal squad; its placement and firing are seeded,
so a LAN match fields the same infantry on both devices.

The AI flies with the same controller contract as a human, leads its shots with an
iterative intercept solution, holds a turn direction for a minimum interval so it
does not flap, and avoids hugging the side walls.

---

## Tests

Headless gameplay test — drives real matches through the real input path
(60 assertions: the two liveries and the thin hitbox, parked and mirrored airframes, ground
roll before take-off, 360° rotation, map wrapping, projectile pooling, owner damage
rules, the three damage stages and the crash, camera limits, animated and wandering
clouds, the ground squad and its tracers, AI take-off and hits, match end, rematch,
local 2P, virtual touch):

```bash
godot --headless --fixed-fps 60 --path . res://tools/smoke_test.tscn
# exit code 0 = all checks passed
```

Two-device network test (real UDP on localhost, host + client processes):

```bash
tools/run_lan_test.sh
# prints PASS/FAIL per process and compares both simulations
```

Visual capture harness — plays a scripted match and writes PNGs to
`tools/shots/` (menu, two players, parked, taxiing, nose-up, flight, firing, touch
pad, pause, altitude, looping, the three damage stages, crash, result):

```bash
godot --path . --resolution 1280x720 res://tools/visual_check.tscn
```

Project load check:

```bash
godot --headless --path . --quit-after 120
```

---

## Export

### Android

1. Editor → **Editor Settings → Export → Android**: set the Android SDK path and
   a debug keystore.
2. **Project → Install Android Build Template** (needed for plugins, and useful for
   the landscape lock).
3. **Project → Export → Add → Android**. The game is landscape-only
   (`display/window/handheld/orientation = 4`), uses the Mobile renderer, and
   targets 60 FPS.
4. Recommended: enable *ARM64-V8A* and *Armeabi-v7a*, keep *Gradle build* on for
   release, and sign with your keystore.
5. Export APK/AAB and install on a device. Touch controls appear automatically.

### iOS

1. **Project → Install iOS Build Template** (requires a Mac with Xcode).
2. **Project → Export → Add → iOS**, set the bundle identifier and team.
3. Export the Xcode project, open it, set signing, run on a device.
4. Landscape orientation and touch controls are already configured.

### Desktop

Add a Linux/Windows/macOS preset and export. Keyboard controls are used; press
`F1` to try the touch overlay.

---

## Implemented features

- Ten selectable fighters built from the same primitive toolkit: five piston
  fighters (including a gull-wing and a twin-boom), four jets (swept wing, delta,
  twin-tail and faceted stealth) and a sci-fi experimental, each with its own
  livery and its own split of speed, agility, armour and rate of fire. The title
  screen previews the pick in a strip and in the sky flypast.
- Endless multiplayer duels on one screen and over LAN: a crash is a round for the
  other pilot, both fighters roll out again, and the HUD keeps the running score.
- Side-view 2D dogfight with a constantly playable 2D world (X = across the
  wrapping map, Y = altitude); gameplay coordinates are identical for both
  players, and only the airplane artwork is oriented differently.
- Parked start on a flat field for both planes, standing on their wheels. The
  round begins on the take-off input: the plane accelerates down the strip, holds
  its nose level with the tyres on the grass, then rotates up — it only lifts off
  once the nose is eight degrees up, easing onto its climb instead of popping into
  the air — and retracts its gear as it climbs away.
- Continuous forward flight with smooth 100°/s rotation and full 360° freedom:
  dives, loops and all the way around, configurable per airplane.
- A horizontally wrapping map: leaving one side re-enters on the other with the
  same height and heading, with the camera snapping across.
- Three-stage damage: scorch marks after the first hit, a smoke trail after the
  second, and a death spiral on the third: the wreck noses over toward the ground,
  keeps some of its forward momentum, tumbles with an easing spin and explodes
  where it hits.
- A 2.5D fighter: a low-poly 3D airframe rendered live behind a side camera, so
  it is always seen in profile but keeps real volume and shading. It spins a 3D
  two-blade propeller with a motion-blur disc, kicks back with a short recoil and
  flashes at the nose when it fires, and takes damage as scorch decals, a smoke
  trail and a spinning fall. The opponent flies the same model in a crimson
  livery, mirrored on the Y axis, so the two pilots are told apart at a glance and
  no second set of geometry has to be kept in sync.
- Pooled projectiles with swept collision, configurable speed/lifetime/damage,
  owner immunity, world-bounds cleanup, trail and glow.
- Large procedurally generated landscape: fields with hedgerows, road with
  markings, river, lake, fence line, villages, farms, windmill, trees — all drawn
  behind the flat surface, so scenery sits behind the ground plane.
- Gradient sky, distant hill layers, and clouds on a 6-frame animated sheet at
  two depths (screen-space and world-space). Every cloud wanders: it picks a
  random point nearby, drifts there at its own speed, then picks another, so the
  sky never moves as one block.
- Smooth camera with world limits at a wide 0.9 zoom, plus a two-plane framing
  mode for same-screen multiplayer (the only mode that zooms out further, and only
  because it is explicit).
- Animated fireball explosion (a 10-frame sheet: 7 frames of burning ball, 3 of
  cooling smoke) plus a spark burst where the wreck hits the surface.
- Ground infantry: 3D soldiers with volume and shading, two uniform colours and
  a pintle-mounted heavy cannon that tracks the nearest plane. Each man has his
  own idle stance, his own breathing sway and a small rock now and then; firing
  flashes the muzzle and kicks the gun back, the torso with it, in a damped
  wobble. They put slow, weak shells up at both planes; squad size and firing
  rate scale with the difficulty, and Easy has none.
- Bombs: two per plane, topped up by supply crates. A bomb inherits a third of
  the plane's speed, falls under gravity, and bursts on the field or against the
  other airframe with radial damage and falloff, never hurting the pilot who
  dropped it. In a LAN duel the drop is mirrored to the other device so both
  pilots watch it fall, and only the device that dropped it decides who the blast
  hurts.
- Jet boost: a tank that burns while held (1.75× the engaged gear's speed for
  three seconds) and refills over thirteen once let go, drawn as a cyan strip
  under each health bar and a flickering flame at the tail.
- Flare dispenser: three bursts per plane, refilled by crates. A burst throws
  five burning decoys off the tail; a homing round within 320 px chases the
  nearest flare instead of the aircraft and is spent on it, and a bomb passing
  close is set off early.
- Bomb rack with a 15-second self-reload: the bomb button dims and fills a ring
  while the crew works, and the HUD line counts the wait down.
- Shield charges from crates: fifteen seconds of complete immunity to enemy
  fire, drawn as a lit bubble round the airframe that ripples where it is hit,
  with the charge and the countdown under the pilot card. Flying into the ground
  is still fatal.
- Survival kills heal 45 health each, and repair coins are the most common load
  the courier carries (better than one drop in two).
- Weather that reaches the airframes: rain beads up on the 3D model, slides back
  along the fuselage and whips spray off the nose, and dries when the shower does.
- A 2.5D ground: perspective field furrows, hedge shadows and a haze band under
  the horizon, plus two near layers — a verge and a foreground grass band — that
  travel at 1.22× and 1.55× the world so the surface reads as depth. Purely
  visual: the surface, runway, soldiers and shadows never move.
- HUD: two glass pilot cards with hand-drawn capsule health bars (drain, damage
  ghost, hit grooves, low-health warning), mode label, take-off prompt, pause
  button and pause overlay (Resume / Restart / Main menu), result screen with
  Rematch.
- Three AI difficulties using the shared movement/projectile/damage systems, with
  lead prediction, reaction delay, aim error, fire cone and wall avoidance.
- Local two-player on one screen with its own key set.
- LAN two-device multiplayer over UDP/ENet, host/join lobby in the menu, lockstep
  input streaming, a state heartbeat, a ping/loss readout, a two-sided rematch and
  clean disconnects.
- Touch controls: multi-touch, holdable, four buttons (left, right, take-off,
  fire) that drive the same input abstraction as the keyboard.
- Synthesized sound effects (shoot, hit, explosion, take-off, throttle shifts,
  UI) generated at runtime — no audio files to license. Under them runs a
  continuous engine drone: a seamless looping note that idles on the strip,
  deepens as the plane rolls, and steps up in pitch and volume with each
  throttle gear.
- Bluetooth transport interface, loopback transport, framing helpers and a
  platform integration plan.

## Known limitations

- **LAN is LAN only.** There is no NAT traversal, relay server, matchmaking or
  reconnect: both devices must share a network and reach each other's UDP port
  27777. Playing over the internet needs port forwarding or a relay.
- **Bluetooth is not functional.** Only the architecture and stub exist; a native
  Android (RFCOMM) plugin and an iOS MultipeerConnectivity plugin are required.
  See `docs/BLUETOOTH_INTEGRATION.md`.
- **Very long matches hit the ceiling.** The sky is 18000 px tall; after that
  planes slide along the top boundary. In practice rounds end far sooner.
- **The surface is solid, not deadly.** Flying into the ground levels the plane
  out along it; only losing all health causes a crash. Adding terrain crashes
  would need a damage rule for ground contact.
- **The AI does not use the wrap deliberately:** it aims and chases across the
  shortest wrapped distance, but its dogfighting is still the simple
  turn-and-shoot of a 2D side-view duel.
- **Game over, not respawn.** A destroyed plane ends the round after 1.5 s; there
  is no lives/respawn system.
- **Infantry are scenery that shoots back.** Soldiers cannot be hit, do not move or
  take cover, and never lead their shots; a soldier round that finishes a plane is
  credited to the other pilot. They are meant as difficulty flavour, not as a
  second AI.
- **The two planes share one silhouette.** The opponent is the same airframe in a
  different livery, not a different aircraft model.
- **Same-screen two-player shares one camera.** Each player watches the same
  window instead of their own half of the screen, so player 2's airplane is the
  mirrored copy and sits on the right. Splitting the view so both players see
  themselves on the left as the unmirrored plane is a camera/viewport feature; the
  flight math already needs no per-player conversion for it.
- **No persistent settings or high scores**, and no audio volume slider.
- **AI is a single-mode dogfighter** — it does not dodge or use terrain.
- Physics-rendered visuals were verified with the capture harness on macOS at
  1280×720; other aspects/grades and real phone/tablet behaviour still need
  manual testing on device.
