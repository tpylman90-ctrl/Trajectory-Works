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

The flight solver uses SI units, Godot rigid-body integration at 120 Hz, inverse-square gravity magnitude, and the 1976 U.S. Standard Atmosphere layer equations through the mesosphere. Density comes from pressure and temperature; sound speed comes from the ideal-gas relation, and dynamic pressure is q = ½ρv². Crosswind is steady and repeatable. Projectile visuals/collision meshes are separate from flight properties. Base drag coefficients and the Mach curve are still shape-class estimates, not wind-tunnel measurements; angle-of-attack moments are simplified. The collision-gate penetration result remains an energy-work estimate, not a validated armor-fracture model. CI checks standard-atmosphere reference points, layer continuity, pressure/density consistency, gravity falloff, and dynamic-pressure units. Future calibration should compare complete trajectories against published/reference drag data.
