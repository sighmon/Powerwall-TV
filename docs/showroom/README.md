# Showroom stage

`Powerwall-TV/ShowroomStage.swift` rebuilds the stage the Tesla app puts a car on.
The values come from the Tesla Android app 4.62.5 asset pack, decompiled with GDRE Tools.

![Before, after, and a Tesla app render](comparison.jpg)

The before and after columns are Cycles approximations of the SceneKit scene, made with
`tools/render.py`. They are not simulator captures. The reference is
`assets/img/car_wrap_arcade_placeholder.png` from the app.

## What the Tesla app does

| Part | Tesla source | Value | SceneKit |
| --- | --- | --- | --- |
| Background | `EnvironmentManager.gd` `dark_background_color` | `#161718` | `scene.background`, view background |
| Lighting | `mobile.tscn`, `env/mobile.tres` | No lights. PanoramaSky `New_Studio.png` | `scene.lightingEnvironment` = `ShowroomStudio.png` |
| Sky rotation | `MobileEnvTest.gd`, `Snapshots.gd` PARKED | `(0, -11, 83)`° | Baked into `ShowroomStudio.png` by `tools/bake_env.py` |
| Sky energy | `Snapshots.gd` PARKED | background 6, ambient 2.6 | intensity 2.2, because our paint is lifted to display colours |
| Camera | `Snapshots.gd` PARKED | rotation `(-25, -138, 0)`°, `(-4.13, 3.09, -4.73)`, FOV 30° | `CarShowroomOrbit.restingOffset`, FOV 30° |
| Floor | `reflective_floor.tres`, `.shader` | unshaded, background colour, mirror at 10%, half resolution | `SCNFloor` reflectivity 0.1, `reflectionResolutionScaleFactor` 0.5 |
| Floor fade | `reflective_floor.shader` | `1 - smoothstep(5, 15, distance)` m | fragment shader modifier on alpha |
| Glow | `ReflectiveFloor.gd` `update_glow_plane` | 8.2 × 4.3 m half size, 16.3 m behind `(0, 1, 0)`, faces camera | `ShowroomStage.glowPlacement` |
| Glow colour | `Terrain.gd` `ColorToHighlightMap`, `calculate_highlight_for_paint_color` | paint table, else value × 0.325 × 5, max 0.7 | `ShowroomStage.highlight` |
| Glow opacity | `Terrain.tscn` `night_mode_highlight_fade` | 0.26, gone when looking down 37°–58° | material transparency |
| Contact shadow | each car's `Floor` quad and `Ground_AO*.png` | baked AO | `*_GroundAO.png` on a quad |

## Assets

- `ShowroomStudio.png`: `New_Studio.png` with the sky rotation baked in, 1024 × 512.
- `*_GroundAO.png`: each car's `Ground_AO` texture, rotated so the top is the nose (−Z) and the left is −X.
  Model Y Juniper uses Highland's, because its exported texture is empty. Generic uses Model 3's.

These are Tesla's copyrighted assets. Keep them in this private repository.

## Tuning

- `ShowroomStage.environmentIntensity` sets how bright the studio reflections are.
- If the studio reflections look mirrored left to right, flip `ShowroomStudio.png` horizontally.
  SceneKit's equirectangular convention was not checked on a device.

## Lamps

![Headlights and taillights before and after](headlights.jpg)

In the Tesla app the car is parked with its lamps off, so nothing glows. The lamps look right
because of the lamp housing material. Lights_BC is a texture atlas of chrome reflectors,
projector bowls, LED strips, and red and amber lenses. Lights_MRA packs metallic, roughness, and
occlusion. A thin smoked lens (Glass_Lights) sits over the housing. The mobile environment
(`env/mobile.tres`) has no glow or bloom. No vehicle scene contains an OmniLight or a SpotLight,
and there is no welcome animation.

| Car | Housing (`Light`/`Lights`) albedo × BC, metallic × R, roughness × G, AO = B | Lens (`Glass_Lights`) colour, alpha, roughness |
| --- | --- | --- |
| Model 3 | 0.102, 0.7, 0.0 (mirror) | 0.0118, 0.51, 0.05 |
| Model 3 Highland | 0.137, 1.0, 1.0 | 0.0118, 0.39, 0.05 |
| Model Y | 0.102, 0.7, 0.5 | 0.0118, 0.39, 0.05 |
| Model Y Juniper | `Light_Off` flat 0.0196, roughness 0.45 | 0.0118, 0.39, 0.05 |
| Model S | 0.098, 0.75, 0.5 | 0.0118, 0.43, 0.1 |
| Model X | 0.098, 1.0, 1.0 | 0.0118, 0.51, 0.1 |
| Cybertruck | `Lights1` 0.349, 0, 1.0 | 0, 0.51, 0.01 |

The glowing "lights on" meshes are separate. `Headlights`, `DRL`, `Brake_Lights_*`,
`Reverse_Light`, and the turn signals use `Illumination`, which is additive, unshaded black,
and shows the `Lights_E.png` emission map at energy 0.65–0.8. The `*_Projections` meshes add the
light pools on the ground. All of them are hidden by default. `Vehicle.gd` shows the headlights
only while the car is driving (`set_headlights_on(data.isDriving())`). The Godot glTF export
skips hidden nodes, so these meshes are not in our models.

`tools/build_vehicles_v2.py` now writes the lamp housing as `Lamps`, with `primvars:st`, and the
lens as `LampGlass`. It skips the `*_Global` lamp meshes, which use a different atlas. Before this
change both went into one flat red `Lights` mesh, which `VehicleLights` split into three glowing
lenses. `VehicleLamps` in `HouseLighting.swift` puts `<Model>_Lamps_BC.png` and
`<Model>_Lamps_MRA.png` on the housing, using `textureComponents` red, green, and blue, and makes
the lens the smoked glass.

`tools/headlights.py` makes the close-ups. Run it with `LAMPS=before|after`, `USDZ=`, and
`VIEW=front|rear`. The renders are Cycles approximations, not SceneKit captures.

## Floor reflection

The reflection used to come from `SCNFloor` (reflectivity 0.1, half resolution), with a Metal
fragment shader modifier fading the floor out. It did not show on an older macOS. Now the
reflection is the car again, flipped through the floor (`ShowroomStage.makeMirror`). The copy
shares the car's geometry and materials. A plain `SCNPlane` floor in the background colour covers
it at 90% (`reflection_strength` 0.1). The floor's alpha comes from a generated texture
(`floorImage`) and fades out between 5 m and 15 m, like `reflective_floor.shader`. Nothing depends
on SCNFloor reflections, reflection bit masks, or shader modifiers. The draw order is glow (−20),
mirror (−15), floor (−10), contact shadow (−5), then the car.

## Model Y Juniper glass and B pillars

![Model Y Juniper before and after](juniper.jpg)

Juniper's roof (`Fade`), rear glass (`Trunk_Cover`), and rear door and quarter windows
(`Back_*_window`, `Static_Exterior`) use `glass_skybox` ShaderMaterials (`Glass_Windows_Dark`,
`Glass_Top_Fade`). The glTF export writes no material for these, and the converter had mapped
them to opaque Trim. They now map to Glass, like the windscreen and front windows. No other car
has unnamed exterior surfaces. The B pillars sit on the `Interior` mesh, which is dropped: the
outer cover is on its Trim surface and the inner trim on its `Pillar` surface. The converter keeps
the triangles of those two surfaces between the door windows, as a gloss black `Pillar` material.

## Vehicle info panel and its Fleet call budget

The showroom's left column puts battery and charging on one line (`80% battery · Charging`), then
minutes to full, then a panel of `vehicle_data_cached` rows. Each row has an SF Symbol, uses the same
bold label font at 60% white, and is drawn only when Fleet sent that field:

| Row | Example | SF Symbol | Fleet field |
| --- | --- | --- | --- |
| Range | 402 km range | `gauge.with.dots.needle.67percent` | `charge_state.battery_range` |
| Charge limit | Charge limit 90% | `flag.checkered` | `charge_state.charge_limit_soc` |
| Charge rate (only while charging) | 11 kW · +48 km/h | `ev.charger` | `charger_power`, `charge_rate` |
| Energy added (charging or complete) | 18.4 kWh added | `bolt.fill` | `charge_energy_added` |
| Temperatures | Inside 22°C · Outside 17°C | `thermometer.medium` | `climate_state.inside_temp`, `outside_temp` |
| Climate (only when on) | Climate on | `fan` | `climate_state.is_climate_on` |
| Locks | Locked / Unlocked | `lock.fill` / `lock.open.fill` | `vehicle_state.locked` |
| Sentry (only when on) | Sentry Mode on | `record.circle` | `vehicle_state.sentry_mode` |
| Tyres (all four or none) | Tyres 2.9 · 2.9 · 2.8 · 2.9 bar | `tirepressure` | `tpms_pressure_fl/fr/rl/rr` |
| Odometer | 24,656 km | `road.lanes` | `vehicle_state.odometer` |
| Software | Software 2026.38.4 | `gearshape` | `vehicle_state.car_version` |
| Update | Update available | `arrow.down.circle` | `vehicle_state.software_update.status` |
| Age | Updated 4 min ago | `clock` | newest block `timestamp` |

Distances, temperatures and tyre pressures always show their unit (km or mi, °C or °F, bar, psi or kPa).
`VehicleDisplayUnits` picks each one in this order:

1. The car's own `gui_settings` (`gui_distance_units`, `gui_temperature_units`, `gui_tirepressure_units`),
   so the panel matches the car's screen.
2. For temperature only, the system's own Celsius or Fahrenheit setting (`AppleTemperatureUnit`).
3. The device region: `Locale.measurementSystem` gives miles for the US and UK and °F for the US.
   Tyres use psi in the US, UK, Puerto Rico, Liberia and Myanmar, kPa in Canada and Japan, and bar
   everywhere else, as Tesla does in Australia and Europe.

Fleet sends miles, Celsius and bar, and `Measurement` does the conversions. The unit symbol is written by
the panel rather than `MeasurementFormatter`, because the formatter's spacing changes by locale
("22 °C") and the tyre row puts one unit after four numbers. Numbers use the device locale's separators.
Location and "parked at" are left out on purpose. `vehicle_data_cached` never returns `drive_state` or
location, and getting them would need a live `vehicle_data` call with `location_data`, which costs
more and shows the location-sharing icon in the car.

Demo mode shows the same panel from `DemoHouseTour.exampleInfo`, which uses made-up numbers with no VIN
or location. It sends no `gui_settings`, so its units follow the device region: an Australian device shows
km, °C and bar, and a US one mi, °F and psi. Demo makes no Fleet calls.

### Why `vehicle_data_cached`

Tesla's docs say `vehicle_data` "makes a live call to the vehicle" and regular polling "will be expensive".
`vehicle_data_cached` returns the last data the car reported "without a call to the vehicle", works while it
is asleep or offline, and never wakes it. Its body only has `charge_state`, `climate_state`, `gui_settings`
and `vehicle_state`, which is every field above. The docs do not list an `endpoints` filter for it, so the
panel sends none. The existing live charge call keeps its `endpoints=charge_state;vehicle_config;vehicle_state`
filter and is unchanged. Nothing calls `wake_up`.

The data can be hours old, so the panel's last row says how old it is.

### Throttling (`VehicleInfoRefreshPolicy`)

- Calls only happen while the showroom is open. Its SwiftUI `.task` checks the policy once a minute and is
  cancelled when the showroom closes. Nothing polls in the background, and the catalogue cars never call.
- One call per car at a time. A second check while one is in flight does nothing.
- Results are kept in memory and in `UserDefaults` (`fleetVehicleInfoCache`), together with the throttle
  state, so reopening the showroom or relaunching the app does not reset the clock. Cached info older than a
  day is not shown.
- Parked: at most one call every 10 minutes. While charging: every 5 minutes, because range and kWh added
  move. When the car has not reported anything new since the last call, the wait doubles (20, 40, then 60
  minutes at most).
- 408 asleep/offline: wait 30 minutes. 429: wait for `Retry-After`, and never less than 15 minutes.
  404 (no cached data) or 412 (car does not support it): wait 6 hours. 403: wait a day and show the
  existing re-login message. 401 runs the existing token refresh. Network errors and 5xx back off from
  5 minutes up to an hour.
- A hard cap of 100 calls per car per rolling 24 hours.

### Call budget

Tesla bills Data requests at 500 per $1, so $0.002 per call. Any response under 500 is billed. Each account
gets a $10 monthly discount. The cached-data rate limit is 60 requests per minute, far above anything here.

| Use | Calls per car per day | Cost per day |
| --- | --- | --- |
| Showroom never opened | 0 | $0 |
| Opened about 5 times, briefly | up to 5 | up to $0.01 |
| Left open all day, parked (backs off to hourly) | about 26 | about $0.05 |
| Left open while charging (5 minutes, then the cap) | at most 100 | at most $0.20 |

The worst case, a showroom left open on a charging car every day, is about $6 a month per car, which is
inside the $10 discount. These calls are on top of the app's existing live charge calls, which are unchanged.
