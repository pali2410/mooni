extends Node3D

const N := 128
const STEP := 0.20
const TILE := 16
const ORIGIN := Vector2(-22.8, -22.8)
const THICKNESS := 0.10
const DENSITY := 1000.0
var heights := PackedFloat32Array()
var initial_mass := 0.0
var remaining_mass := 0.0
var tiles := {}
var dirty := {}
var surface_material: Material
var terrain_grid := {}

func ground_height(x: float, z: float) -> float:
	if terrain_grid.is_empty(): return 0.0
	var o: Array = terrain_grid.origin; var step: float = terrain_grid.step; var n: int = terrain_grid.n
	var fx := clampf((x - o[0]) / step, 0, n - 1.001); var fz := clampf((z - o[1]) / step, 0, n - 1.001)
	var ix := floori(fx); var iz := floori(fz); var h: Array = terrain_grid.heights
	return lerpf(lerpf(h[iz * n + ix], h[iz * n + ix + 1], fx - ix), lerpf(h[(iz + 1) * n + ix], h[(iz + 1) * n + ix + 1], fx - ix), fz - iz)

func contains(point: Vector3) -> bool:
	var p := (Vector2(point.x, point.z) - ORIGIN) / STEP
	return p.x >= 0 and p.y >= 0 and p.x < N and p.y < N

func _ready():
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/regolith.gdshader")
	material.set_shader_parameter("surface_tint", Color(0.48, 0.48, 0.54))
	surface_material = material
	var texture := "res://assets/Texture2D/moon_macro_detail_v003.png"
	if ResourceLoader.exists(texture): material.set_shader_parameter("detail_map", load(texture))
	reset_surface()

func reset_surface():
	heights.resize(N * N)
	var noise := FastNoiseLite.new(); noise.seed = 73129; noise.frequency = 0.15
	initial_mass = 0.0
	for z in N:
		for x in N:
			var point := Vector2(x, z) * STEP + ORIGIN
			var coverage := smoothstep(-0.30, -0.02, noise.get_noise_2d(point.x, point.y))
			# Preserve a clear walkway to the intake, with continuous banks on either side.
			if absf(point.x) < 0.7 and point.y < 0: coverage = 0.0
			heights[z * N + x] = THICKNESS * coverage
			initial_mass += heights[z * N + x] * STEP * STEP * DENSITY
	remaining_mass = initial_mass
	for tz in N / TILE:
		for tx in N / TILE: dirty[Vector2i(tx, tz)] = true
	flush()

func _height(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= N or z >= N: return 0.0
	return heights[z * N + x]

func _corner(x: int, z: int) -> float:
	return (_height(x, z) + _height(x - 1, z) + _height(x, z - 1) + _height(x - 1, z - 1)) * 0.25

func _tile_mesh(tile: Vector2i):
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uvs := PackedVector2Array()
	for z in range(tile.y * TILE, (tile.y + 1) * TILE):
		for x in range(tile.x * TILE, (tile.x + 1) * TILE):
			if _height(x, z) < 0.00002: continue
			var points := [Vector3(x * STEP + ORIGIN.x, _corner(x, z) + 0.002, z * STEP + ORIGIN.y),
				Vector3((x + 1) * STEP + ORIGIN.x, _corner(x + 1, z) + 0.002, z * STEP + ORIGIN.y),
				Vector3(x * STEP + ORIGIN.x, _corner(x, z + 1) + 0.002, (z + 1) * STEP + ORIGIN.y),
				Vector3((x + 1) * STEP + ORIGIN.x, _corner(x + 1, z + 1) + 0.002, (z + 1) * STEP + ORIGIN.y)]
			for i in points.size(): points[i].y = points[i].y + ground_height(points[i].x, points[i].z)
			for index in [0, 1, 2, 1, 3, 2]:
				var p: Vector3 = points[index]
				vertices.append(p); normals.append(Vector3.UP); uvs.append(Vector2(p.x, p.z) / 3.0)
	var node: MeshInstance3D
	if tiles.has(tile): node = tiles[tile]
	else:
		node = MeshInstance3D.new(); node.material_override = surface_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node); tiles[tile] = node
	node.mesh = null
	if vertices.is_empty(): return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh

func sweep(from: Vector3, to: Vector3, width: float, depth: float, max_kg: float) -> float:
	if max_kg <= 0: return 0.0
	var start := Vector2(from.x, from.z); var end := Vector2(to.x, to.z)
	var radius := maxf(width * 0.5, STEP * 0.7)
	var low := (start.min(end) - Vector2.ONE * radius - ORIGIN) / STEP
	var high := (start.max(end) + Vector2.ONE * radius - ORIGIN) / STEP
	var removed := 0.0
	for z in range(maxi(0, floori(low.y)), mini(N - 1, ceili(high.y)) + 1):
		for x in range(maxi(0, floori(low.x)), mini(N - 1, ceili(high.x)) + 1):
			var i := z * N + x
			if heights[i] <= 0: continue
			var point := Vector2(x + 0.5, z + 0.5) * STEP + ORIGIN
			var closest := Geometry2D.get_closest_point_to_segment(point, start, end)
			var distance := point.distance_to(closest)
			if distance > radius: continue
			var falloff := smoothstep(radius, radius * 0.55, distance)
			var delta := minf(heights[i], depth * falloff)
			delta = minf(delta, (max_kg - removed) / (STEP * STEP * DENSITY))
			if delta <= 0: continue
			heights[i] -= delta; removed += delta * STEP * STEP * DENSITY
			var tile := Vector2i(x / TILE, z / TILE)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var adjacent := tile + Vector2i(dx, dz)
					if adjacent.x >= 0 and adjacent.y >= 0 and adjacent.x < N / TILE and adjacent.y < N / TILE: dirty[adjacent] = true
	remaining_mass = maxf(0, remaining_mass - removed)
	return removed

func flush():
	for tile in dirty: _tile_mesh(tile)
	dirty.clear()

func serialize() -> Array:
	return Array(heights)

func restore(values: Array):
	if values.size() != N * N: return
	remaining_mass = 0
	for i in values.size():
		heights[i] = clampf(values[i], 0, THICKNESS)
		remaining_mass += heights[i] * STEP * STEP * DENSITY
	for tz in N / TILE:
		for tx in N / TILE: dirty[Vector2i(tx, tz)] = true
	flush()
