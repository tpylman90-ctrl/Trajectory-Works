# Trajectory Works — project brief

## Game promise

Design a projectile, make a prediction, fire it from a striking gas cannon, then use the shot data to understand what changed. The science should emerge through play, with deeper explanations available when the player wants them.

## First playable slice

- One semi-realistic gas cannon in a polished outdoor test lane.
- A 3D range view with camera orbit, marked distances, and target boards.
- A firing interaction and a basic projectile flight test.
- The next development step is the projectile workshop: nose, body, fins, and mass distribution.
- After that, add shot replay and an analysis panel for distance, flight time, impact point, and stability.

## Visual direction

Use the supplied cannon image as a style reference: readable industrial forms, detailed plumbing and coil hardware, blue enamel and warm metal accents, dramatic but controlled cyan energy effects, and materials that feel semi-real. Keep the shapes bold enough to read on a phone screen.

## Toolchain

- Godot 4.6.3 for the Android-first game and simulation.
- Blender 5.2 LTS for model generation and GLB export.
- GitHub Actions for asset generation, project validation, and signed APK delivery.
- Godot's built-in glTF importer keeps the art handoff simple. No extra Godot plugin is required for this slice.

## Physics boundary

The first shot is a controlled teaching simulation. Keep the visible projectile model and its collision shape separate so shape experimentation can grow without destabilizing collision behavior. Calibrate the model against clear, explainable variables before adding advanced aerodynamics.
