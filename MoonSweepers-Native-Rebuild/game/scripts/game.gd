extends Node3D

const AssetLibrary = preload("res://scripts/asset_library.gd")
const DustSurface = preload("res://scripts/dust_surface.gd")
const ReferenceArt = preload("res://scripts/reference_art.gd")
const CapturedWorld = preload("res://scripts/captured_world.gd")
var captured_world
const NORMAL = Color("d8d5ce")
const ORANGE = Color("ff8025")
const WHITE = Color("faf7ee")
var library
var definitions: Array
var settings: Dictionary
var world: Node3D
var menu_stage: Node3D
var player: CharacterBody3D
var view: Camera3D
var home_view: Camera3D
var surface
var holder: Node3D
var held_tool: Node3D
var ui: Control
var home_ui: Control
var game_ui: Control
var modal: PanelContainer
var modal_box: VBoxContainer
var wallet_text: Label
var tool_text: Label
var cargo_text: Label
var notice: Label
var sector: Label
var compass: Control
var fill_ring: Control
var tool_icon: TextureRect
var slot_buttons: Array[Button] = []
var joystick: Control
var move_value := Vector2.ZERO
var move_origin := Vector2.ZERO
var move_id := -1
var look_id := -1
var pitch := -0.55
var sensitivity := 0.003
var is_playing := false
var cleaning := false
var dirty_time := 0.0
var save_time := 0.0
var sound: AudioStreamPlayer
var balance := 0.0
var bag := 0.0
var deposited := 0.0
var selected_tool := 0
var owned: Array = [0]
var current_slot := 1
var placed: Array = []
var hit := Vector3.ZERO
var previous_hit := Vector3.ZERO
var target_valid := false
var stroke_active := false
var elapsed := 0.0
var hand_rest := Vector3.ZERO
var trace := {"touch_move_events": 0, "touch_look_events": 0, "clean_actions": 0, "deposits": 0, "purchases": 0}

func _ready():
	library = AssetLibrary.new()
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tool_definitions.json"))
	settings = library._json("res://assets/world_settings.json")
	_setup_lighting()
	_create_interface()
	_create_home_stage()
	sound = AudioStreamPlayer.new(); sound.volume_db = -14
	sound.stream = load("res://assets/AudioClip/brush-sweep-01.ogg"); add_child(sound)
	_show_home()
	print("MOON_REFERENCE_READY home=true normal_progression=true native_meshes=", library.mesh_map.size())
	if "--smoke-test" in OS.get_cmdline_user_args(): call_deferred("_smoke_test")

func _setup_lighting():
	var environment := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/Texture2D/space_sky_bg_v003.png")
	sky.sky_material = sky_material; e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("d1d7e5"); e.ambient_light_energy = 0.40
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.75
	environment.environment = e; add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-37, -35, 0)
	sun.light_energy = 1.0; sun.light_color = Color("fff7ec"); sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45; add_child(sun)

func _texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

func _font(bold := false) -> Font:
	return load("res://assets/Resources/fonts/Nunito Black.ttf" if bold else "res://assets/Resources/fonts/Nunito ExtraBold.ttf")

func _label(text: String, parent: Node, pos: Vector2, size := 25, bold := false, color := WHITE) -> Label:
	var label := Label.new(); label.text = text; label.position = pos
	label.add_theme_font_override("font", _font(bold)); label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5)); label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(label); return label

func _style(color: Color, border := Color.TRANSPARENT, radius := 9) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = color; style.border_color = border
	style.set_border_width_all(2 if border.a > 0 else 0); style.set_corner_radius_all(radius)
	style.content_margin_left = 15; style.content_margin_right = 15
	style.content_margin_top = 8; style.content_margin_bottom = 8
	return style

func _button(text: String, parent: Node, callback: Callable, pos := Vector2.ZERO, size := Vector2(160, 60), primary := false) -> Button:
	var button := Button.new(); button.text = text; button.position = pos; button.custom_minimum_size = size
	button.size = size; button.add_theme_font_override("font", _font(true)); button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("27232a") if primary else WHITE)
	button.add_theme_stylebox_override("normal", _style(ORANGE if primary else Color(0.13, 0.13, 0.15, 0.87), Color("77747b") if not primary else ORANGE))
	button.add_theme_stylebox_override("hover", _style(Color("49484c"), ORANGE))
	button.add_theme_stylebox_override("pressed", _style(Color("ff9d50"), ORANGE))
	parent.add_child(button); button.pressed.connect(callback); return button

func _picture(path: String, parent: Node, pos: Vector2, size: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = _texture(path); image.position = pos; image.size = size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(image); return image

func _art(mode: String, parent: Node, pos: Vector2, size: Vector2) -> Control:
	var art := ReferenceArt.new(); art.mode = mode; art.position = pos; art.size = size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(art); return art

func _create_home_stage():
	menu_stage = library.instantiate("Scenes/MainMenu.unity"); add_child(menu_stage)
	home_view = Camera3D.new(); home_view.fov = 34; home_view.far = 500
	var camera_data: Dictionary = library.prefabs["Scenes/MainMenu.unity"]["352"].data
	home_view.position = library.vector(camera_data.m_LocalPosition)
	var q: Dictionary = camera_data.m_LocalRotation
	home_view.quaternion = Quaternion(-q.x, -q.y, q.z, q.w).normalized(); menu_stage.add_child(home_view)
	_earth(menu_stage, home_view.position + Vector3(0.2, 0.21, -1).normalized() * 60, 5.5)

func _earth(parent: Node3D, pos: Vector3, radius: float):
	var planet := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = radius; sphere.height = radius * 2
	planet.mesh = sphere; planet.position = pos
	var material := StandardMaterial3D.new(); material.albedo_texture = _texture("res://assets/Texture2D/earth_v002.png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; planet.material_override = material; parent.add_child(planet)

func _create_interface():
	var layer := CanvasLayer.new(); add_child(layer)
	ui = Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(ui)
	home_ui = Control.new(); home_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.add_child(home_ui)
	game_ui = Control.new(); game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(game_ui)
	# The PC HUD has a compass above, sector status at right, tools below and wallet below-right.
	compass = _art("compass", game_ui, Vector2(445, 40), Vector2(710, 22))
	sector = _label("SECTOR\n0.0%\nCLEANED", game_ui, Vector2(1420, 34), 22, true)
	tool_icon = _picture("", game_ui, Vector2(48, 850), Vector2(90, 90))
	fill_ring = _art("ring", game_ui, Vector2(42, 844), Vector2(102, 102))
	tool_text = _label("TOOTHBRUSH", game_ui, Vector2(162, 858), 29, true)
	cargo_text = _label("0.00 / 0.50 kg", game_ui, Vector2(162, 904), 22)
	wallet_text = _label("$0.00", game_ui, Vector2(1310, 895), 41, true, ORANGE)
	_picture("res://assets/Resources/moon/hud/wallet_coin_icon.png", game_ui, Vector2(1490, 894), Vector2(58, 58))
	notice = _label("", game_ui, Vector2(530, 780), 22)
	for i in definitions.size():
		var index := i
		var button := _button("", game_ui, func(): _select_owned(index), Vector2(510 + i * 75, 871), Vector2(68, 68))
		_picture(_icon_path(i), button, Vector2(8, 7), Vector2(52, 52)); slot_buttons.append(button)
	joystick = Control.new(); joystick.position = Vector2(65, 634); joystick.size = Vector2(210, 210)
	joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE; joystick.draw.connect(_draw_stick); game_ui.add_child(joystick)
	var sweep_button := _button("SWEEP", game_ui, func(): pass, Vector2(1385, 650), Vector2(160, 90))
	sweep_button.button_down.connect(func(): cleaning = true); sweep_button.button_up.connect(func(): cleaning = false)
	_button("JUMP", game_ui, _jump, Vector2(1215, 745), Vector2(135, 64))
	_button("INTERACT", game_ui, _interact, Vector2(1385, 755), Vector2(160, 64))
	_button("EQUIPMENT", game_ui, _shop, Vector2(1385, 545), Vector2(160, 57))
	_button("FIELD MANUAL", game_ui, _manual, Vector2(1385, 480), Vector2(160, 48))
	_button("☰", game_ui, _pause_menu, Vector2(48, 40), Vector2(45, 45))
	modal = PanelContainer.new(); modal.position = Vector2(260, 125); modal.size = Vector2(1070, 735)
	modal.add_theme_stylebox_override("panel", _style(Color("202026"), Color("7d7775"), 12)); ui.add_child(modal)
	var scroll := ScrollContainer.new(); modal.add_child(scroll)
	modal_box = VBoxContainer.new(); modal_box.custom_minimum_size.x = 1010; modal_box.add_theme_constant_override("separation", 14); scroll.add_child(modal_box); modal.hide()

func _icon_path(index: int) -> String:
	return "res://assets/Texture2D/" + ["toothbrush-icon.png", "hand_brush_icon.png", "household_broom_icon.png", "wide_broom_icon.png", "extra_wide_broom_icon.png", "building_tool_icon.png", "nailbrush_icon.png"][index]

func _show_home():
	is_playing = false; cleaning = false; move_value = Vector2.ZERO
	if world: world.hide()
	menu_stage.show(); home_view.current = true; game_ui.hide(); home_ui.show(); modal.hide()
	for child in home_ui.get_children(): child.queue_free()
	_art("sidebar", home_ui, Vector2.ZERO, Vector2(550, 1000))
	_picture("res://assets/Texture2D/moon_sweepers_logo_v002_menu.png", home_ui, Vector2(40, 40), Vector2(445, 220))
	for item in [["START GAME", _slots], ["JOIN GAME", _join_info], ["SETTINGS", _settings], ["QUIT GAME", _quit_game]]:
		var index := ["START GAME", "JOIN GAME", "SETTINGS", "QUIT GAME"].find(item[0])
		var button := _button(item[0], home_ui, item[1], Vector2(0, 326 + index * 102), Vector2(520, 84))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.add_theme_font_size_override("font_size", 37)
		button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
		var normal: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		normal.content_margin_left = 54; button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", _style(Color("454344"), Color.TRANSPARENT, 0))
		button.add_theme_constant_override("outline_size", 1)
	_button("YOUR ASTRONAUT", home_ui, _astronaut, Vector2(1010, 865), Vector2(230, 48))
	_label("0.3 · ANDROID", home_ui, Vector2(375, 948), 16, false, Color("99959a"))
	_label("Choose a save to begin", home_ui, Vector2(55, 943), 18, false, NORMAL)

func _slots():
	for child in home_ui.get_children(): child.queue_free()
	_art("sidebar", home_ui, Vector2.ZERO, Vector2(880, 1000))
	_label("START GAME", home_ui, Vector2(54, 57), 48, true)
	for i in range(1, 6):
		var slot := i
		var data := _read_save(slot)
		var description := "New game" if data.is_empty() else "$%.2f  ·  %.2f kg deposited" % [float(data.get("balance", 0)), float(data.get("deposited", 0))]
		_button("SLOT %d       %s" % [slot, description], home_ui, func(): current_slot = slot; _slots(), Vector2(0, 155 + (i - 1) * 83), Vector2(850, 72), slot == current_slot)
	_button("PLAY", home_ui, _start_slot, Vector2(660, 630), Vector2(190, 62), true)
	_button("BACK", home_ui, _show_home, Vector2(55, 914), Vector2(120, 50))
	_label("LOCAL GAME", home_ui, Vector2(55, 626), 19, true, NORMAL)

func _start_slot():
	if world:
		remove_child(world); world.queue_free()
	world = Node3D.new(); add_child(world)
	_build_world(); _build_player()
	balance = 0; bag = 0; deposited = 0; selected_tool = 0; owned = [0]; placed = []
	var data := _read_save(current_slot)
	if not data.is_empty(): _restore(data)
	_equip(selected_tool)
	menu_stage.hide(); home_ui.hide(); game_ui.show(); modal.hide(); world.show(); view.current = true
	is_playing = true; _message("Collect lunar dust. Return to the intake to earn your first dollars.")
	_save()
	print("MOON_SESSION_READY slot=", current_slot, " balance=", balance, " owned=", owned)

func _build_world():
	captured_world = CapturedWorld.new(library); captured_world.build(world)
	surface = DustSurface.new(); surface.terrain_grid = captured_world.data.terrain_grid; world.add_child(surface)
	_earth(world, Vector3(-100, 70, -170), 12)

func _prop(fragment: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var path: String = library.find_prefab(fragment)
	var node: Node3D = library.instantiate(path); world.add_child(node); node.position = pos; node.rotation.y = yaw
	return node

func _build_player():
	player = CharacterBody3D.new(); player.collision_mask = 3; world.add_child(player)
	player.floor_max_angle = deg_to_rad(float(settings.get("slopeLimit", 30))); player.floor_snap_length = 0.62
	player.position = captured_world.spawn(); player.rotation.y = captured_world.data.spawn_yaw
	var collider := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = 0.32; capsule.height = 1.75
	collider.shape = capsule; collider.position.y = 0.9; player.add_child(collider)
	view = Camera3D.new(); player.add_child(view); view.position.y = 1.68; view.fov = 78; view.far = 250
	holder = Node3D.new(); view.add_child(holder)
	pitch = -0.55

func _capacity() -> float:
	return maxf(0.1, float(definitions[selected_tool].containerKg))

func _select_owned(index: int):
	if owned.has(index): _equip(index)
	else: _shop()

func _equip(index: int):
	selected_tool = index
	if is_instance_valid(held_tool): held_tool.queue_free()
	var definition: Dictionary = definitions[index]
	holder.position = library.vector(definition.heldPosition)
	var angle: Dictionary = definition.heldEuler; hand_rest = Vector3(-angle.x, -angle.y, angle.z) * PI / 180
	holder.rotation = hand_rest
	held_tool = library.instantiate(definition.prefabPath); holder.add_child(held_tool); held_tool.scale *= float(definition.visualScale)
	tool_icon.texture = _texture(_icon_path(index))
	tool_text.text = str(definition.displayName).to_upper()
	_save()

func _dialog(title: String):
	for child in modal_box.get_children(): child.queue_free()
	modal.show(); cleaning = false; move_value = Vector2.ZERO; move_id = -1; look_id = -1
	_label(title, modal_box, Vector2.ZERO, 38, true)
	_button("BACK", modal_box, func(): modal.hide(), Vector2.ZERO, Vector2(1000, 52))

func _shop():
	if not is_playing: return
	_dialog("EQUIPMENT")
	_label("BALANCE  $%.2f" % balance, modal_box, Vector2.ZERO, 26, true, ORANGE)
	for i in definitions.size():
		var index := i
		var price := float(definitions[i].purchaseDollars)
		var text: String = definitions[i].displayName
		text += "   EQUIP" if owned.has(i) else "   $%.2f" % price
		var button := _button(text, modal_box, func(): _purchase(index), Vector2.ZERO, Vector2(1000, 62))
		button.disabled = not owned.has(i) and balance + 0.00001 < price

func _purchase(index: int) -> bool:
	if not owned.has(index):
		var price := float(definitions[index].purchaseDollars)
		if balance + 0.00001 < price: return false
		balance = snappedf(balance - price, 0.000001); owned.append(index); trace.purchases += 1
	_equip(index); _shop(); return true

func _interact():
	if Vector2(player.position.x, player.position.z + 10).length() < 6:
		_deposit()
	elif selected_tool == 5: _construction()
	elif player.position.distance_to(captured_world.shop()) < 6: _shop()
	else: _message("Move closer to the intake or equipment kiosk.")

func _deposit():
	if Vector2(player.position.x, player.position.z + 10).length() > 6: return
	if bag <= 0: _message("Your container is empty."); return
	var earned := bag * float(settings.get("dollarsPerKilogram", 1))
	deposited += bag; balance += earned; bag = 0; trace.deposits += 1
	_message("+$%.2f" % earned); _save()

func _construction():
	if not owned.has(5): _shop(); return
	_dialog("BUILD")
	var search := LineEdit.new(); search.placeholder_text = "Search building parts"; search.custom_minimum_size.y = 54; modal_box.add_child(search)
	var entries := VBoxContainer.new(); modal_box.add_child(entries)
	var populate := func(query: String):
		for child in entries.get_children(): child.queue_free()
		var count := 0
		for key in library.prefabs:
			if not key.ends_with(".prefab"): continue
			if not query.is_empty() and not key.to_lower().contains(query.to_lower()): continue
			if count >= 45: break
			var path: String = key
			_button(key.get_file().get_basename(), entries, func(): _place(path), Vector2.ZERO, Vector2(1000, 55)); count += 1
	search.text_changed.connect(populate); populate.call("")

func _place(path: String):
	var pos := player.position - player.basis.z * 5; pos.y = 0
	var node: Node3D = library.instantiate(path); world.add_child(node); node.position = pos; node.rotation.y = player.rotation.y
	placed.append({"path": path, "position": [pos.x, pos.y, pos.z], "yaw": node.rotation.y})
	modal.hide(); _save()

func _pause_menu():
	if not is_playing: return
	_dialog("PAUSED")
	_button("RESUME", modal_box, func(): modal.hide(), Vector2.ZERO, Vector2(1000, 62))
	_button("SETTINGS", modal_box, _settings, Vector2.ZERO, Vector2(1000, 62))
	_button("SAVE AND MAIN MENU", modal_box, func(): _save(); _show_home(), Vector2.ZERO, Vector2(1000, 62))

func _manual():
	_dialog("FIELD MANUAL")
	_label("Collect dust with your brush. Bring a full container to the intake.\nSell the collected material and buy better equipment.\n\nMove: left thumbstick\nLook: drag the right side\nSweep: hold SWEEP while aiming at dust\nInteract: use intake or equipment kiosk\nJump: JUMP\n\nController: left/right sticks, RT sweep, A jump, X interact.\nKeyboard: WASD, right mouse look, left mouse sweep, E interact.", modal_box, Vector2.ZERO, 24)

func _settings():
	_dialog("SETTINGS")
	_label("LOOK SENSITIVITY", modal_box, Vector2.ZERO, 25, true)
	var slider := HSlider.new(); slider.min_value = 0.001; slider.max_value = 0.007; slider.step = 0.0001; slider.value = sensitivity
	slider.custom_minimum_size = Vector2(900, 55); slider.value_changed.connect(func(value): sensitivity = value); modal_box.add_child(slider)
	_label("SOUND VOLUME", modal_box, Vector2.ZERO, 25, true)
	var volume := HSlider.new(); volume.min_value = -40; volume.max_value = 0; volume.value = -14; volume.custom_minimum_size = Vector2(900, 55)
	volume.value_changed.connect(func(value): sound.volume_db = value); modal_box.add_child(volume)

func _astronaut():
	_dialog("YOUR ASTRONAUT")
	_label("Original astronaut model and suit materials are loaded.\nFull appearance editing and original animation retargeting remain unavailable.", modal_box, Vector2.ZERO, 24)

func _join_info():
	_dialog("JOIN GAME")
	_label("Online crew sessions are not available in this Android build.", modal_box, Vector2.ZERO, 25)

func _quit_game():
	_save(); get_tree().quit()

func _draw_stick():
	joystick.draw_circle(Vector2(105, 105), 96, Color(0.1, 0.1, 0.13, 0.2))
	joystick.draw_arc(Vector2(105, 105), 96, 0, TAU, 64, Color(1, 1, 1, 0.3), 2)
	joystick.draw_circle(Vector2(105, 105) + move_value * 56, 29, Color(1, 1, 1, 0.28))

func _message(text: String):
	notice.text = text

func _jump():
	if is_playing and not modal.visible and player.is_on_floor(): player.velocity.y = sqrt(2.0 * float(settings.get("gravity", 1.62)) * float(settings.get("jumpHeight", 2.5)))

func _input(event):
	if not is_playing: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: modal.hide() if modal.visible else _pause_menu()
			KEY_SPACE: _jump()
			KEY_E: _interact()
			KEY_H: _manual()
			KEY_TAB: _shop()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7: _select_owned(event.keycode - KEY_1)
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _jump()
			JOY_BUTTON_X: _interact()
			JOY_BUTTON_START: modal.hide() if modal.visible else _pause_menu()
	if modal.visible: return
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == move_id: move_id = -1; move_value = Vector2.ZERO
			if event.index == look_id: look_id = -1
		elif event.position.x < 300 and event.position.y > 550 and event.position.y < 850:
			move_id = event.index; move_origin = event.position
		elif event.position.x > 600 and event.position.x < 1350 and event.position.y < 820:
			look_id = event.index
	if event is InputEventScreenDrag:
		if event.index == move_id: move_value = ((event.position - move_origin) / 75).limit_length(); trace.touch_move_events += 1
		if event.index == look_id: _look(event.relative); trace.touch_look_events += 1
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): _look(event.relative)

func _look(delta: Vector2):
	player.rotation.y -= delta.x * sensitivity; pitch = clampf(pitch - delta.y * sensitivity, -1.4, 1.2)

func _step_up(motion: Vector3) -> bool:
	if motion.length_squared() < 0.000001 or not player.test_move(player.global_transform, motion): return false
	# MoonWalker defines StepHeight=0.62. Test full capsule clearance before lifting it.
	var raised := player.global_transform
	if player.test_move(raised, Vector3.UP * 0.62): return false
	raised.origin.y += 0.62
	if player.test_move(raised, motion): return false
	raised.origin += motion
	var contact := KinematicCollision3D.new()
	if not player.test_move(raised, Vector3.DOWN * 0.64, contact): return false
	if contact.get_normal().y < cos(player.floor_max_angle): return false
	var next_height := raised.origin.y + contact.get_travel().y + 0.002
	var rise := next_height - player.global_position.y
	if rise <= 0.01 or rise > 0.62: return false
	player.global_position.y = next_height; player.velocity.y = 0
	return true

func _physics_process(delta: float):
	elapsed += delta
	if not is_playing: return
	_update_hud()
	if modal.visible: return
	captured_world.update(delta, player.position)
	var move := move_value + Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var action := cleaning or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().get_mouse_position().y < 830)
	for pad in Input.get_connected_joypads():
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.18: move += stick
		var look := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.18: _look(look * delta * 600)
		action = action or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.25
	move = move.limit_length(); var direction := player.basis * Vector3(move.x, 0, move.y)
	player.velocity.x = direction.x * float(settings.get("runSpeed", 7)); player.velocity.z = direction.z * float(settings.get("runSpeed", 7))
	if not player.is_on_floor(): player.velocity.y -= float(settings.get("gravity", 1.62)) * delta
	if player.is_on_floor() and player.velocity.y <= 0: _step_up(Vector3(player.velocity.x, 0, player.velocity.z) * delta)
	player.move_and_slide(); view.rotation.x = pitch
	if player.position.y < -120: player.position = captured_world.spawn()
	holder.rotation = hand_rest + Vector3(0, sin(elapsed * 13) * 0.11 if action else 0, sin(elapsed * 1.7) * 0.01)
	var ray := -view.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(view.global_position, view.global_position + ray * float(definitions[selected_tool].reach), 3, [player.get_rid()])
	var contact := get_world_3d().direct_space_state.intersect_ray(query)
	target_valid = not contact.is_empty() and contact.collider.collision_layer == 2
	if target_valid:
		hit = contact.position; target_valid = surface.contains(hit)
	if action and target_valid and selected_tool != 5:
		if not stroke_active: previous_hit = hit
		if previous_hit.distance_to(hit) > 1.5: previous_hit = hit
		var definition: Dictionary = definitions[selected_tool]
		var removed: float = surface.sweep(previous_hit, hit, float(definition.cleaningWidth), float(definition.cleaningDepth) * delta / maxf(0.1, float(definition.strokeDuration)), minf(_capacity() - bag, float(definition.removalRate) * delta))
		previous_hit = hit; stroke_active = true
		if removed > 0:
			bag += removed; trace.clean_actions += 1
			if not sound.playing: sound.play()
		if bag >= _capacity() - 0.0001: _message("CONTAINER FULL · Return to the intake")
	else: stroke_active = false
	dirty_time += delta; save_time += delta
	if dirty_time > 0.12: dirty_time = 0; surface.flush()
	if save_time > 5: save_time = 0; _save()
	joystick.queue_redraw()

func _update_hud():
	wallet_text.text = "$%.2f" % balance
	cargo_text.text = "%.2f / %.2f kg" % [bag, _capacity()]
	fill_ring.value = bag / _capacity(); fill_ring.queue_redraw()
	compass.angle = player.rotation.y; compass.queue_redraw()
	sector.text = "SECTOR\n%.1f%%\nCLEANED" % ((1.0 - surface.remaining_mass / maxf(surface.initial_mass, 0.001)) * 100)
	for i in slot_buttons.size():
		slot_buttons[i].modulate = Color.WHITE if owned.has(i) else Color(0.4, 0.4, 0.4, 0.35)
		slot_buttons[i].add_theme_stylebox_override("normal", _style(Color(0.1, 0.1, 0.12, 0.22), ORANGE if selected_tool == i else Color(1, 1, 1, 0.3), 34))

func _path(slot: int) -> String:
	return "user://test_reference_slot_%d.json" % slot if "--smoke-test" in OS.get_cmdline_user_args() else "user://moon_session_v2_slot_%d.json" % slot

func _read_save(slot: int) -> Dictionary:
	if "--smoke-test" in OS.get_cmdline_user_args(): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(_path(slot))) if FileAccess.file_exists(_path(slot)) else null
	return data if data is Dictionary and int(data.get("schema", 0)) == 2 else {}

func _save():
	if not is_playing or not is_instance_valid(player): return
	var state := {"schema": 2, "world_revision": 1, "balance": balance, "bag": bag, "deposited": deposited, "tool": selected_tool, "owned": owned,
		"position": [player.position.x, player.position.y, player.position.z], "yaw": player.rotation.y,
		"surface": surface.serialize(), "placed": placed, "trace": trace}
	var file := FileAccess.open(_path(current_slot), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(state))

func _restore(data: Dictionary):
	balance = maxf(0, data.get("balance", 0)); bag = maxf(0, data.get("bag", 0)); deposited = maxf(0, data.get("deposited", 0))
	# JSON numbers are floats; equipment ownership checks use integer catalog IDs.
	owned = []
	for value in data.get("owned", [0]):
		var id := int(value)
		if id >= 0 and id < definitions.size() and not owned.has(id): owned.append(id)
	if not owned.has(0): owned.append(0)
	selected_tool = data.get("tool", 0); if not owned.has(selected_tool): selected_tool = 0
	var pos: Array = data.get("position", [0, 0.1, 2]); player.position = Vector3(pos[0], pos[1], pos[2]); player.rotation.y = data.get("yaw", 0)
	if int(data.get("world_revision", 0)) < 1:
		# The prototype used a different world layout. Preserve progress and put the player safely outside the original base.
		player.position = captured_world.spawn(); player.rotation.y = captured_world.data.spawn_yaw
	surface.restore(data.get("surface", [])); placed = data.get("placed", [])
	for entry in placed:
		if not library.prefabs.has(entry.path): continue
		var node: Node3D = library.instantiate(entry.path); world.add_child(node); node.position = Vector3(entry.position[0], entry.position[1], entry.position[2]); node.rotation.y = entry.yaw

func _notification(what: int):
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		cleaning = false; move_value = Vector2.ZERO; move_id = -1; look_id = -1; _save()

func _smoke_test():
	var logos := home_ui.get_children().filter(func(child): return child is TextureRect)
	assert(logos.size() == 1 and logos[0].size == Vector2(445, 220))
	_start_slot()
	assert(balance == 0 and owned == [0] and selected_tool == 0)
	assert(not _purchase(1))
	var initial: float = surface.remaining_mass
	assert(captured_world.loaded == 215 and captured_world.collisions > 0)
	assert(captured_world.data.unresolved.is_empty())
	assert(captured_world.doors.size() == 1)
	var door: Dictionary = captured_world.doors[0]
	var center: Vector3 = captured_world._v(door.center) - Vector3(0, 0.9, 0)
	captured_world.update(0.6, center)
	assert(door.amount == 1.0)
	for leaf in door.leaves: assert(leaf.node.position.distance_to(captured_world._v(leaf.open)) < 0.0001)
	captured_world.update(2.0, Vector3(-100, 0, -100))
	assert(door.amount == 0.0)
	for leaf in door.leaves: assert(leaf.node.position.distance_to(captured_world._v(leaf.closed)) < 0.0001)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ground_query := PhysicsRayQueryParameters3D.create(Vector3(-8, 5, -10), Vector3(-8, -5, -10), 2)
	var ground_contact := get_world_3d().direct_space_state.intersect_ray(ground_query)
	print("MOON_TERRAIN_CONTACT ", ground_contact, " visual_height=", surface.ground_height(-8, -10))
	# Original stable-bedrock collision is 0.10 m below the visible surface here.
	assert(not ground_contact.is_empty() and absf(ground_contact.position.y + 0.6) < 0.001)
	is_playing = false
	player.position = Vector3(center.x, 0.15, 1.0)
	await get_tree().physics_frame
	for i in 60: player.move_and_collide(Vector3(0, 0, -0.1))
	assert(player.position.z > center.z, "Closed original door must block the capsule")
	captured_world.update(0.6, center)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in 60:
		var obstruction := player.move_and_collide(Vector3(0, 0, -0.1))
		if obstruction and i == 59: print("MOON_DOOR_OBSTRUCTION player=", player.position, " collider=", obstruction.get_collider().get_path(), " point=", obstruction.get_position())
	assert(player.position.z < center.z - 1.0, "Open original door must allow entry")
	player.position = Vector3(center.x, -0.624, 1.0)
	await get_tree().physics_frame
	for i in 90:
		_step_up(Vector3(0, 0, -0.1)); player.move_and_collide(Vector3(0, 0, -0.1))
	assert(player.position.z < center.z - 1.0 and player.position.y > -0.1, "Capsule must climb the source entrance steps")
	is_playing = true
	var point := Vector3(-8, -0.5, -10)
	for z in range(10):
		point = Vector3(-8, -0.5, -10 + z * 0.2)
		bag += surface.sweep(point, point + Vector3(0.5, 0, 0), 0.6, 0.05, _capacity() - bag)
		if bag > 0: break
	assert(bag > 0 and bag <= _capacity() + 0.00001)
	assert(absf(initial - surface.remaining_mass - bag) < 0.001)
	player.position = Vector3(0, 1, -8); var earned := bag; _deposit()
	assert(bag == 0 and absf(balance - earned) < 0.00001)
	# Deterministic earned funds for the transaction test, only in isolated test data.
	balance = 12; assert(_purchase(1)); assert(balance == 2 and owned.has(1))
	_save(); var saved = JSON.parse_string(FileAccess.get_file_as_string(_path(current_slot)))
	assert(saved.schema == 2 and saved.balance == 2 and not saved.has("currency"))
	_restore(saved)
	assert(balance == 2 and owned == [0, 1] and selected_tool == 1, "Purchased tools must survive a JSON save/reload")
	assert(not game_ui.get_children().any(func(child): return child.name == "TopBar"))
	print("MOON_SMOKE_PASS normal_start=true capacity=true deformation_mass=true earnings=true purchase_debits=true no_money_preset=true save=true")
	print("MOON_WORLD_SMOKE_PASS original_scene=215 unresolved=0 door_open_close=true door_capsule_entry=true entrance_steps=true terrain_raycast=true purchase_reload=true")
	get_tree().quit()
