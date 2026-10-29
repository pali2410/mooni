extends RefCounted

var prefabs: Dictionary
var mesh_map: Dictionary
var materials: Dictionary
var guids: Dictionary
var mesh_cache := {}
var material_cache := {}
var loaded_parts := 0
var unresolved := []
var skin_data := {}

func _init():
	prefabs = _json("res://assets/prefabs.json")
	mesh_map = _json("res://assets/mesh_map.json")
	materials = _json("res://assets/materials.json")
	guids = _json("res://assets/guid_map.json")
	skin_data = _json("res://assets/character_skin.json")

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func find_prefab(fragment: String) -> String:
	for key in prefabs:
		if key.get_file().get_basename().to_lower() == fragment.to_lower():
			return key
	return ""

func vector(data: Dictionary, fallback := Vector3.ZERO) -> Vector3:
	return Vector3(data.get("x", fallback.x), data.get("y", fallback.y), -data.get("z", -fallback.z))

func mesh(path: String) -> ArrayMesh:
	if mesh_cache.has(path):
		return mesh_cache[path]
	var record: Dictionary = mesh_map.get(path, {})
	if record.is_empty():
		return null
	var file := FileAccess.open(record.file, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != "MSW1":
		return null
	var count := file.get_32()
	var surfaces := file.get_32()
	var positions := file.get_buffer(count * 12).to_float32_array()
	var normals := file.get_buffer(count * 12).to_float32_array()
	var uvs := file.get_buffer(count * 8).to_float32_array()
	var vertices := PackedVector3Array()
	var normal_array := PackedVector3Array()
	var uv_array := PackedVector2Array()
	vertices.resize(count); normal_array.resize(count); uv_array.resize(count)
	for i in count:
		vertices[i] = Vector3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		normal_array[i] = Vector3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2])
		uv_array[i] = Vector2(uvs[i * 2], 1.0 - uvs[i * 2 + 1])
	var result := ArrayMesh.new()
	for surface in surfaces:
		var indices := file.get_buffer(file.get_32() * 4).to_int32_array()
		if indices.is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normal_array
		arrays[Mesh.ARRAY_TEX_UV] = uv_array
		arrays[Mesh.ARRAY_INDEX] = indices
		if skin_data.has(path):
			arrays[Mesh.ARRAY_BONES] = PackedInt32Array(skin_data[path].bones)
			arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(skin_data[path].weights)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_cache[path] = result
	return result

func material(path: String) -> Material:
	if material_cache.has(path): return material_cache[path]
	if path == "Material/Astronaut visor eyes.mat":
		var eyes := ShaderMaterial.new(); eyes.shader = load("res://shaders/visor_eyes.gdshader")
		eyes.set_shader_parameter("eye_sheet", load("res://assets/Texture2D/astronaut_eyes_sheet.png"))
		material_cache[path] = eyes
		return eyes
	if path == "Material/MenuGround.mat":
		var ground := ShaderMaterial.new(); ground.shader = load("res://shaders/regolith.gdshader")
		ground.set_shader_parameter("detail_map", load("res://assets/Texture2D/moon_macro_detail_v003.png"))
		ground.set_shader_parameter("tile_scale", 75.0)
		ground.set_shader_parameter("surface_tint", Color(0.64, 0.64, 0.69))
		material_cache[path] = ground
		return ground
	var result := StandardMaterial3D.new()
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.roughness = 0.8
	var properties: Dictionary = materials.get(path, {}).get("m_SavedProperties", {})
	var colors: Dictionary = properties.get("m_Colors", {})
	var color: Dictionary = colors.get("_BaseColor", colors.get("_Color", {}))
	if not color.is_empty():
		result.albedo_color = Color(color.get("r", 0.7), color.get("g", 0.7), color.get("b", 0.7), color.get("a", 1.0))
	var floats: Dictionary = properties.get("m_Floats", {})
	result.metallic = clampf(floats.get("_Metallic", 0.0), 0.0, 1.0)
	result.roughness = clampf(1.0 - floats.get("_Smoothness", 0.2), 0.18, 1.0)
	var envs: Dictionary = properties.get("m_TexEnvs", {})
	var texture: Dictionary = envs.get("_BaseMap", envs.get("_MainTex", {})).get("m_Texture", {})
	var texture_path: String = guids.get(texture.get("guid", ""), "")
	if not texture_path.is_empty() and ResourceLoader.exists("res://assets/" + texture_path):
		result.albedo_texture = load("res://assets/" + texture_path)
	var base_env: Dictionary = envs.get("_BaseMap", envs.get("_MainTex", {}))
	var tiling: Dictionary = base_env.get("m_Scale", {})
	result.uv1_scale = Vector3(tiling.get("x", 1.0), tiling.get("y", 1.0), 1.0)
	var normal_ref: Dictionary = envs.get("_BumpMap", {}).get("m_Texture", {})
	var normal_path: String = guids.get(normal_ref.get("guid", ""), "")
	if not normal_path.is_empty() and ResourceLoader.exists("res://assets/" + normal_path):
		result.normal_enabled = true
		result.normal_texture = load("res://assets/" + normal_path)
		result.normal_scale = float(floats.get("_BumpScale", 1.0))
	var emission: Dictionary = colors.get("_EmissionColor", {})
	if maxf(emission.get("r", 0), maxf(emission.get("g", 0), emission.get("b", 0))) > 0.01:
		result.emission_enabled = true
		result.emission = Color(emission.get("r", 0), emission.get("g", 0), emission.get("b", 0))
	material_cache[path] = result
	return result

func instantiate(path: String) -> Node3D:
	var root := Node3D.new()
	root.name = path.get_file().get_basename().validate_node_name()
	var docs: Dictionary = prefabs.get(path, {})
	var nodes := {}
	var transforms := {}
	var renderers := {}
	for id in docs:
		var doc: Dictionary = docs[id]
		var data: Dictionary = doc.data
		if int(doc.kind) in [4, 224]:
			var node := Node3D.new()
			var game_id := str(data.get("m_GameObject", {}).get("fileID", 0))
			node.name = str(docs.get(game_id, {}).get("data", {}).get("m_Name", id)).validate_node_name()
			node.position = vector(data.get("m_LocalPosition", {}))
			var r: Dictionary = data.get("m_LocalRotation", {})
			var q := Quaternion(-r.get("x", 0.0), -r.get("y", 0.0), r.get("z", 0.0), r.get("w", 1.0))
			if q.length_squared() > 0.01: node.quaternion = q.normalized()
			var scale_data: Dictionary = data.get("m_LocalScale", {})
			node.scale = Vector3(scale_data.get("x", 1.0), scale_data.get("y", 1.0), scale_data.get("z", 1.0))
			node.visible = bool(docs.get(game_id, {}).get("data", {}).get("m_IsActive", 1))
			nodes[game_id] = node
			transforms[id] = {"node": node, "parent": str(data.get("m_Father", {}).get("fileID", 0))}
		elif int(doc.kind) in [23, 137]:
			renderers[str(data.get("m_GameObject", {}).get("fileID", 0))] = data
	for id in transforms:
		var entry: Dictionary = transforms[id]
		if transforms.has(entry.parent): transforms[entry.parent].node.add_child(entry.node)
		else: root.add_child(entry.node)
	for id in docs:
		var doc: Dictionary = docs[id]
		if int(doc.kind) not in [33, 137]: continue
		var data: Dictionary = doc.data
		var ref: Dictionary = data.get("m_Mesh", {})
		var mesh_path: String = guids.get(ref.get("guid", ""), "")
		if mesh_path.is_empty(): continue
		var model := mesh(mesh_path)
		if model == null:
			unresolved.append(mesh_path)
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = model
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var game_id := str(data.get("m_GameObject", {}).get("fileID", 0))
		var renderer: Dictionary = renderers.get(game_id, {})
		var refs: Array = renderer.get("m_Materials", [])
		for i in model.get_surface_count():
			if i < refs.size(): instance.set_surface_override_material(i, material(guids.get(refs[i].get("guid", ""), "")))
		if nodes.has(game_id) and int(doc.kind) == 137 and skin_data.has(mesh_path):
			_bind_skin(instance, nodes[game_id], data, transforms, root, mesh_path)
		elif nodes.has(game_id): nodes[game_id].add_child(instance)
		else: root.add_child(instance)
		loaded_parts += 1
	return root

func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != root and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

func _bind_skin(instance: MeshInstance3D, holder: Node3D, data: Dictionary, transforms: Dictionary, root: Node3D, mesh_path: String):
	var skeleton := Skeleton3D.new(); skeleton.name = "RecoveredSkeleton"
	holder.add_child(skeleton)
	var bone_refs: Array = data.get("m_Bones", [])
	var bone_ids := {}
	for i in bone_refs.size():
		var id := str(bone_refs[i].fileID)
		bone_ids[id] = i
		skeleton.add_bone(transforms[id].node.name if transforms.has(id) else "Bone%d" % i)
	var inv_holder := _relative_transform(holder, root).affine_inverse()
	var globals := []
	for ref in bone_refs:
		globals.append(inv_holder * _relative_transform(transforms[str(ref.fileID)].node, root))
	for i in bone_refs.size():
		var id := str(bone_refs[i].fileID)
		var parent_id: String = transforms[id].parent
		while transforms.has(parent_id) and not bone_ids.has(parent_id): parent_id = transforms[parent_id].parent
		var rest: Transform3D = globals[i]
		if bone_ids.has(parent_id):
			var parent_index: int = bone_ids[parent_id]
			skeleton.set_bone_parent(i, parent_index)
			rest = globals[parent_index].affine_inverse() * rest
		skeleton.set_bone_rest(i, rest)
	skeleton.reset_bone_poses()
	var skin := Skin.new()
	for i in skin_data[mesh_path].binds.size():
		var m: Array = skin_data[mesh_path].binds[i]
		var basis := Basis(Vector3(m[0], m[4], -m[8]), Vector3(m[1], m[5], -m[9]), Vector3(-m[2], -m[6], m[10]))
		skin.add_bind(i, Transform3D(basis, Vector3(m[3], m[7], -m[11])))
	skeleton.add_child(instance); instance.skin = skin; instance.skeleton = NodePath("..")
