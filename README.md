# Trajectory Works

An Android-first 3D range game about shaping projectiles, testing them, and learning the physics behind each shot.

## Current setup

- **Godot 4.6.3** — game engine and Android exporter.
- **Blender 5.2 LTS** — procedural 3D asset generation and GLB export.
- **GitHub Actions** — generates the cannon asset, validates the Godot project, and builds a signed APK for download.

The first scene is a range preview with the semi-realistic gas cannon, distance lanes, targets, touch camera orbit, and a basic test shot. The projectile designer and shot-analysis flow are the next game systems to build.

## Build and download

1. Add the Android signing secrets listed in [`docs/ANDROID_SETUP.md`](docs/ANDROID_SETUP.md).
2. Open **Actions → Android APK → Run workflow** (or push a commit to `main`).
3. Download `trajectory-works-apk` from the completed run.

The Blender script can be run independently with:

```sh
blender --background --factory-startup --python assets/blender/build_cannon.py
```

See [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md) for the initial game scope and visual direction.