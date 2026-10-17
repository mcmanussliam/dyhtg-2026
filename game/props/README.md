# Reusable office furniture

Instance `office_desk.tscn` or `office_cabinet.tscn` beneath a stage and set its 2D
position/rotation. These scenes contain the gameplay footprint and reference an
authored 3D visual/collision scene. Both use the shared 43-pixels-per-metre scale.

During stage presentation, call each OfficeProp's `create_presentation(world,
units_per_pixel)`. It maps the prop's full global transform into the native 3D
world. A Floor in the Crack demonstrates this with its Furniture node. Independent
UI scenes can instantiate the 3D scene directly; the home screen reuses the desk.

Adjust a prop's footprint and corresponding 3D colliders together. Environment
layer 1 blocks live chairs and extinguisher rays. Props do not change floor
support: a desk is an obstacle, rather than another rule for elimination.
