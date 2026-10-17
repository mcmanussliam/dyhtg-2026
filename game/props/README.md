# Reusable office furniture

Instance `office_desk.tscn`, `office_cabinet.tscn`, `office_sofa.tscn`,
`office_bookshelf.tscn`, `office_plant.tscn`, `office_task_chair.tscn`,
`office_desk_divider.tscn`, `office_copier.tscn` or `office_coffee_table.tscn` beneath a stage and set its 2D
position/rotation. These scenes contain the gameplay footprint and reference an
authored 3D visual/collision scene. Both use the shared 43-pixels-per-metre scale.

During stage presentation, call each OfficeProp's `create_presentation(world,
units_per_pixel)`. It maps the prop's full global transform into the native 3D
world. A Floor in the Crack demonstrates this with its Furniture node. Independent
UI scenes can instantiate the 3D scene directly; the home screen reuses the desk.

Adjust a prop's footprint and corresponding 3D colliders together. Environment
layer 1 blocks live chairs and extinguisher rays. Props do not change floor
support: a desk is an obstacle, rather than another rule for elimination.

## Furniture cut at the stage edge

A Floor in the Crack uses three map-specific, capped ArrayMesh resources in
`game/stage/art/`. Rebuild these with Godot:

```sh
godot --headless --path . --script tools/bake_office_cut.gd
```

The bake presets contain the source prop poses and stage circle. Update them and
rebake when changing those cut pieces or the radius. Assign the result through
`baked_visual_mesh`; the stage calls `clip_to_circle()` for props tagged
`cut_at_edge`. This clips both live 2D footprints and each compound 3D collider,
preserving their individual heights. Ordinary props retain their reusable models.
CSG runs only during this offline bake, never during gameplay.

`OfficeAccessories` adds small mugs, document folders and archive boxes directly
to existing furniture models. These decorative details have no independent floor
footprint, keeping routes and chair collisions unchanged.
