# Trajectory Works

An Android-first 3D range game about shaping projectiles, testing them, and learning the physics behind each shot.

## Current setup

- **Godot 4.6.3** — game engine and Android exporter.
- **Blender 5.2 LTS** — procedural 3D asset generation and GLB export.
- **GitHub Actions** — generates the cannon asset, validates the Godot project, and builds a signed APK for download.

The first scene is a 22 km hypervelocity test course with a tilting gas cannon, weather instrumentation, target stations, distance readouts, and touch camera orbit. Players can compare projectile shapes, tune muzzle velocity and barrel elevation, and set surface crosswind plus a deterministic altitude wind-shear profile. The cannon has a brief recoil cycle and compressed-gas muzzle plume. Shots use a 120 Hz rigid-body flight model with inverse-square gravity, the 1976 U.S. Standard Atmosphere layer equations for temperature, pressure, density, viscosity, and sound speed, and aerodynamic drag based on q = ½ρv², projectile reference area, mass, orientation, and a Mach-dependent shape estimate. Flight time, apex, impact speed, spin, dynamic pressure, and range are reported. Headless atmosphere, force-law, and wind-profile checks run in CI; see `tests/physics_validation.gd`.

## Build and download

1. Add the Android signing secrets listed in [`docs/ANDROID_SETUP.md`](docs/ANDROID_SETUP.md).
2. Open **Actions → Android APK → Run workflow** (or push a commit to `main`).
3. Download `trajectory-works-apk` from the completed run.

The Blender script can be run independently with:

```sh
blender --background --factory-startup --python assets/blender/build_cannon.py
```

See [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md) for the initial game scope and visual direction.
