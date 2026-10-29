extends RefCounted

var data: Dictionary
var library
var material_cache := {}
var loaded := 0
var collisions := 0
var doors := []

func _v(p: Array) -> Vector3: return Vector3(p[0], p[1], p[2])

func _transform(m: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))

func _door_body(path: String) -> AnimatableBody3D:
	for door in doors:
		for leaf in door.leaves:
			if ("/" + str(leaf.key)) in path: return leaf.node
	return null

func _init(asset_library):
	library = asset_library
	data = library._json("res://assets/pc_world/world.json")
	for key in data.get("meshes", {}): library.mesh_map[key] = data.meshes[key]

func _material(id: String, ground: bool) -> Material:
	if ground: return library.material("Material/MenuGround.mat")
	if material_cache.has(id): return material_cache[id]
	var record: Dictionary = data.materials.get(id, {})
	var paths: Array = record.get("source_paths", [])
	var result: StandardMaterial3D
	if paths.size() == 1:
		var original: Material = library.material(paths[0])
		result = original.duplicate() as StandardMaterial3D
	if result == null: result = StandardMaterial3D.new()
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	var colors: Dictionary = record.get("colors", {})
	var color: Array = colors.get("_BaseColor", colors.get("_Color", []))
	if color.size() == 4: result.albedo_color = Color(color[0], color[1], color[2], color[3])
	var floats: Dictionary = record.get("floats", {})
	result.metallic = clampf(floats.get("_Metallic", 0), 0, 1)
	result.roughness = clampf(1.0 - float(floats.get("_Smoothness", 0.2)), 0.15, 1)
	var textures: Dictionary = record.get("textures", {})
	var base: Dictionary = textures.get("_BaseMap", textures.get("_MainTex", {}))
	if not str(base.get("file", "")).is_empty(): result.albedo_texture = load(base.file)
	var emission: Array = colors.get("_EmissionColor", [])
	if emission.size() == 4 and maxf(emission[0], maxf(emission[1], emission[2])) > 0.01:
		result.emission_enabled = true; result.emission = Color(emission[0], emission[1], emission[2])
	if result.albedo_color.a < 0.99: result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_cache[id] = result
	return result

func build(parent: Node3D):
	for source in data.get("doors", []):
		var door: Dictionary = source.duplicate(true); door.amount = 0.0; door.presence = -100.0
		for leaf in door.leaves:
			var body := AnimatableBody3D.new(); body.sync_to_physics = false
			parent.add_child(body); body.position = _v(leaf.current); leaf.node = body
		doors.append(door)
	for entry in data.get("instances", []):
		var mesh: ArrayMesh = library.mesh(entry.mesh)
		if mesh == null: continue
		var node := MeshInstance3D.new(); node.name = str(entry.path).get_file().validate_node_name()
		node.mesh = mesh
		node.transform = _transform(entry.matrix)
		for i in mesh.get_surface_count():
			var mid: String = entry.materials[mini(i, entry.materials.size() - 1)] if not entry.materials.is_empty() else ""
			node.set_surface_override_material(i, _material(mid, entry.ground))
		var door_body := _door_body(entry.path)
		if door_body:
			node.position -= door_body.position; door_body.add_child(node)
		else: parent.add_child(node)
		loaded += 1
	for entry in data.get("colliders", []):
		var shape := CollisionShape3D.new(); var transform := _transform(entry.matrix)
		if entry.type == "MeshCollider":
			var collision_mesh: ArrayMesh = library.mesh(entry.mesh)
			shape.shape = collision_mesh.create_trimesh_shape()
		elif entry.type == "BoxCollider":
			var box := BoxShape3D.new(); box.size = _v(entry.size).abs(); shape.shape = box
		elif entry.type == "SphereCollider":
			var sphere := SphereShape3D.new(); sphere.radius = entry.radius; shape.shape = sphere
		elif entry.type == "CapsuleCollider":
			var capsule := CapsuleShape3D.new(); capsule.radius = entry.radius; capsule.height = entry.height; shape.shape = capsule
			if entry.direction == 0: shape.rotation.z = PI / 2
			elif entry.direction == 2: shape.rotation.x = PI / 2
		if entry.has("center"): transform.origin += transform.basis * _v(entry.center)
		var leaf_body := _door_body(entry.path)
		if leaf_body:
			transform.origin -= leaf_body.position; shape.transform = transform; leaf_body.add_child(shape)
		else:
			var body := StaticBody3D.new(); body.collision_layer = 2 if entry.ground else 1
			body.transform = transform; body.add_child(shape); parent.add_child(body)
		collisions += 1
	print("MOON_CAPTURED_WORLD_READY meshes=", loaded, " collisions=", collisions, " unresolved=", data.get("unresolved", []).size())

func update(delta: float, point: Vector3):
	for door in doors:
		var difference: Vector3 = (point + Vector3(0, 0.9, 0) - _v(door.center)).abs()
		var extent := _v(door.extents)
		if difference.x < extent.x + 0.32 and difference.y < extent.y + 0.9 and difference.z < extent.z + 0.32: door.presence = 1.25
		else: door.presence -= delta
		door.amount = move_toward(door.amount, 1.0 if door.presence > 0 else 0.0, delta / maxf(0.1, door.seconds))
		var eased := smoothstep(0.0, 1.0, door.amount)
		for leaf in door.leaves: leaf.node.position = _v(leaf.closed).lerp(_v(leaf.open), eased)

func spawn() -> Vector3:
	var p: Array = data.spawn
	return Vector3(p[0], p[1], p[2])

func shop() -> Vector3:
	var p: Array = data.shop
	return Vector3(p[0], p[1], p[2])
