# Trajectory Works — project brief

## Game promise

Design a projectile, make a prediction, fire it from a striking gas cannon, then use the shot data to understand what changed. The science should emerge through play, with deeper explanations available when the player wants them.

## First playable slice

- A semi-realistic gas cannon on a 2 km outdoor hypervelocity test course.
- A 3D range view with camera orbit, 250 m distance readouts, measurement gates, and target stations.
- Adjustable barrel elevation, muzzle velocity, crosswind, and three projectile designs.
- A ballistic flight model that uses projectile mass, frontal and side area, shape drag, Mach-region drag, standard-atmosphere density falloff, gravity, and crosswind.
- Shot results report impact range and offset, flight time, apex height, projectile mass, and drag coefficient.
- The next development step is the projectile workshop: editable nose, body, fins, and mass distribution, connected directly to these flight properties.

## Visual direction

Use the supplied cannon image as a style reference: readable industrial forms, detailed plumbing and coil hardware, blue enamel and warm metal accents, dramatic but controlled cyan energy effects, and materials that feel semi-real. Keep the shapes bold enough to read on a phone screen.

## Toolchain

- Godot 4.6.3 for the Android-first game and simulation.
- Blender 5.2 LTS for model generation and GLB export.
- GitHub Actions for asset generation, project validation, and signed APK delivery.
- Godot's built-in glTF importer keeps the art handoff simple. No extra Godot plugin is required for this slice.

## Physics boundary

The current solver uses SI units and Godot rigid-body gravity, then applies aerodynamic drag from air-relative velocity each physics step. It approximates the transonic drag rise and air-density change with altitude. Projectile visuals and collision shapes remain separate from the ballistic parameters so workshop edits can change geometry and mass without coupling them to the integrator. Validate against analytic vacuum trajectories and reference drag curves as the model grows; this first model is intentionally explainable rather than a CFD or high-fidelity atmosphere solver.
