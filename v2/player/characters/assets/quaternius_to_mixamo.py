# Blender script: converts a Quaternius rig (Root > Body > Hips, IK feet, PT pole bones,
# FBX 100x scale) to a Mixamo-style rig. Run from the Scripting tab, then export glTF.
# Safe to re-run: every step skips what's already converted.
import math

import bpy
from mathutils import Vector

# IK sets the head bone's absolute orientation, so match the Mixamo forward lean (clanker)
NECK_LEAN_FORWARD_DEG = 10.0
HEAD_LEAN_FORWARD_DEG = 19.0
# IK snaps the Hips bone to the seat; Mixamo hips sit this far above the leg joints (meters)
HIPS_ABOVE_LEGS = 0.065
# Quaternius feet are ground-level IK controls; Mixamo feet run ankle -> ball of foot
FOOT_FORWARD = 0.1
FOOT_TIP_HEIGHT = 0.02
# Ankle = centroid of the top band of foot-weighted verts, where the foot meets the shin
ANKLE_BAND = 0.03

RENAMES = {
    "Body": "mixamorig:Hips",
    "Abdomen": "mixamorig:Spine",
    "Torso": "mixamorig:Spine1",
    "Chest": "mixamorig:Spine2",
    "Neck": "mixamorig:Neck",
    "Head": "mixamorig:Head",
}
for side, s in (("Left", "L"), ("Right", "R")):
    RENAMES.update({
        f"Shoulder.{s}": f"mixamorig:{side}Shoulder",
        f"UpperArm.{s}": f"mixamorig:{side}Arm",
        f"LowerArm.{s}": f"mixamorig:{side}ForeArm",
        f"Wrist.{s}": f"mixamorig:{side}Hand",
        f"Fist.{s}": f"mixamorig:{side}Hand",  # rig variant with no fingers
        f"UpperLeg.{s}": f"mixamorig:{side}UpLeg",
        f"LowerLeg.{s}": f"mixamorig:{side}Leg",
        f"Foot.{s}": f"mixamorig:{side}Foot",
    })
    for i in range(1, 4):
        RENAMES[f"Thumb{i}.{s}"] = f"mixamorig:{side}HandThumb{i}"
    # Quaternius Index1 is the metacarpal; Mixamo starts counting at the proximal
    for finger in ("Index", "Middle", "Ring", "Pinky"):
        for i in range(2, 5):
            RENAMES[f"{finger}{i}.{s}"] = f"mixamorig:{side}Hand{finger}{i - 1}"

arm = next(ob for ob in bpy.context.scene.objects if ob.type == "ARMATURE")
meshes = [c for c in arm.children if c.type == "MESH"]
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

# Body becomes Hips, so fold the old Hips weights into it before deleting that bone
if "Body" in arm.data.bones:
    for ob in meshes:
        src = ob.vertex_groups.get("Hips")
        if src is None:
            continue
        dst = ob.vertex_groups.get("Body") or ob.vertex_groups.new(name="Body")
        for v in ob.data.vertices:
            for g in v.groups:
                if g.group == src.index:
                    dst.add([v.index], g.weight, "ADD")
        ob.vertex_groups.remove(src)

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
if "Body" in eb:
    eb["Abdomen"].use_connect = False
    eb["Abdomen"].parent = eb["Body"]
    eb["Body"].parent = None
    eb.remove(eb["Hips"])
for s in ("L", "R"):
    if f"Foot.{s}" in eb:
        eb[f"Foot.{s}"].use_connect = False
        eb[f"Foot.{s}"].parent = eb[f"LowerLeg.{s}"]
# IK pole/control bones and unweighted roots (Root, or "Bone" on the PoleTarget variant)
weighted = {ob.vertex_groups[g.group].name for ob in meshes for v in ob.data.vertices for g in v.groups if g.weight > 0}
for name in ("PT.L", "PT.R", "PoleTarget.L", "PoleTarget.R", "Root", "Bone"):
    if name in eb and name not in weighted:
        eb.remove(eb[name])
# Renaming a bone also renames the matching vertex groups
for old, new in RENAMES.items():
    if old in eb:
        eb[old].name = new
bpy.ops.object.mode_set(mode="OBJECT")

# Drop the glTF leaf "_end" empties and the RootNode wrapper
root = arm.parent
if root:
    world = arm.matrix_world.copy()
    arm.parent = None
    arm.matrix_world = world
for ob in list(arm.children):
    if ob.type == "EMPTY":
        bpy.data.objects.remove(ob)
if root and root.type == "EMPTY" and not root.children:
    bpy.data.objects.remove(root)

# Bake the FBX 100x scale / -90 X rotation so mesh data is Y-up meters
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for ob in meshes:
    ob.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# Bone edits below set absolute positions so re-runs don't stack. Blender: Z up, -Y forward
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
hips = eb["mixamorig:Hips"]
for child in hips.children:
    child.use_connect = False
legs_mid = (eb["mixamorig:LeftUpLeg"].head + eb["mixamorig:RightUpLeg"].head) / 2
hips_dir = hips.tail - hips.head
hips.head = legs_mid + Vector((0.0, 0.0, HIPS_ABOVE_LEGS))
hips.tail = hips.head + hips_dir
# Godot aims Hips at Spine on import, so Spine below Hips flips the whole upper body.
# Mixamo spaces Hips -> Spine -> Spine1 evenly
spine = eb["mixamorig:Spine"]
spine.head = (hips.head + eb["mixamorig:Spine1"].head) / 2
spine.tail = eb["mixamorig:Spine1"].head


# Quaternius lower legs are ~4mm stubs, so the ankle has to come from the mesh
def ankle_point(group: str) -> Vector:
    pts = []
    for ob in meshes:
        vg = ob.vertex_groups.get(group)
        if vg is None:
            continue
        for v in ob.data.vertices:
            for g in v.groups:
                if g.group == vg.index and g.weight > 0.5:
                    pts.append(ob.matrix_world @ v.co)
    top = max(p.z for p in pts)
    band = [p for p in pts if p.z > top - ANKLE_BAND]
    return sum(band, Vector()) / len(band)


# Blender: -Y is forward. Feet pivot at the ankle, which is what skinning rotates around
for side in ("Left", "Right"):
    foot = eb[f"mixamorig:{side}Foot"]
    ankle = ankle_point(f"mixamorig:{side}Foot")
    eb[f"mixamorig:{side}Leg"].tail = ankle
    foot.head = ankle
    foot.tail = Vector((ankle.x, ankle.y - FOOT_FORWARD, FOOT_TIP_HEIGHT))

eb["mixamorig:Head"].use_connect = False
for name, lean_deg in (("mixamorig:Neck", NECK_LEAN_FORWARD_DEG), ("mixamorig:Head", HEAD_LEAN_FORWARD_DEG)):
    bone = eb[name]
    lean = math.radians(lean_deg)
    bone.tail = bone.head + Vector((0.0, -math.sin(lean), math.cos(lean))) * bone.length
bpy.ops.object.mode_set(mode="OBJECT")

# Godot anim tracks expect Armature/Skeleton
arm.name = "Armature"
print("quaternius_to_mixamo: done")
