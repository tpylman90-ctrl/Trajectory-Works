# Blender asset pipeline

`build_cannon.py` generates a semi-realistic, game-ready cannon preview as a GLB. The Blender scene is deliberately built from reusable parts and materials so we can iterate on the housing, pressure vessels, coil assembly, barrel, supports, and trim without replacing the whole model.

Run it from a Blender installation:

```sh
blender --background --python assets/blender/build_cannon.py
```

The output is `assets/generated/trajectory_cannon.glb`. Godot imports GLB natively; no third-party import add-on is required. The range scene includes a procedural fallback so it still opens before the first asset-generation run.
