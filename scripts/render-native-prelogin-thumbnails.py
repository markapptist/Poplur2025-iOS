"""Render the already-static pre-login artwork once, outside the mobile apps.

blender --background --threads 2 --python scripts/render-native-prelogin-thumbnails.py -- MODELS_DIR
Inputs are prepared by prepare-native-prelogin-models.mjs. Outputs retain the
original mesh, materials and full texture resolution with transparent margins.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

directory = Path(sys.argv[sys.argv.index('--') + 1])
for model in json.loads((directory / 'models.json').read_text()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=model['prepared'])
    scene.frame_set(0)
    imported = list(scene.objects)
    for obj in imported:
        if obj.type in {'CAMERA', 'LIGHT'}:
            bpy.data.objects.remove(obj, do_unlink=True)
    roots = [obj for obj in scene.objects if obj.parent is None]
    bounds = []
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type == 'MESH':
            evaluated = obj.evaluated_get(graph)
            bounds.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not bounds:
        raise RuntimeError(f"No geometry in {model['name']}")
    low = Vector(tuple(min(v[i] for v in bounds) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in bounds) for i in range(3)))
    center = (low + high) * 0.5
    scale = 1.55 / max(high - low)
    pivot = bpy.data.objects.new('Thumbnail angle', None)
    normalization = bpy.data.objects.new('Centered artwork', None)
    scene.collection.objects.link(pivot)
    scene.collection.objects.link(normalization)
    normalization.parent = pivot
    for obj in roots:
        matrix = obj.matrix_world.copy()
        obj.parent = normalization
        obj.matrix_world = matrix
    normalization.scale = (scale, scale, scale)
    normalization.location = -center * scale
    # glTF's Y-up axis becomes Blender's Z-up axis on import.
    pivot.rotation_euler = (-0.12, 0, model['rotationY'])
    camera_data = bpy.data.cameras.new('Thumbnail camera')
    camera = bpy.data.objects.new('Thumbnail camera', camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0, -3.2, 0)
    camera.rotation_euler = (-camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.angle = math.radians(35)
    scene.camera = camera
    world = bpy.data.worlds.new('Soft ambient')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (1, 1, 1, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.5
    scene.world = world
    for name, location, energy, size in [('Key', (2, -3, 4), 280, 4), ('Fill', (-3, -2, 1), 150, 4), ('Rim', (1, 2, 3), 220, 3)]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.shape = 'DISK'
        data.size = size
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (-light.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.render.resolution_x = 360
    scene.render.resolution_y = 360
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = str(directory / (model['name'] + '.png'))
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {model['name']}", flush=True)
