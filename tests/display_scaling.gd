extends SceneTree
## Regression coverage for native window drawing and scaled logical hit targets.
var failures: Array[String] = []
var game: Node2D

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in 5: await process_frame

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.player.set_physics_process(false)
	game.room.active = false
	var hud: Control = game.hud
	var start_rect: Rect2 = hud.start_rect
	var cards: Array = hud.card_rects.duplicate()
	for window_size in [Vector2i(1280, 800), Vector2i(1600, 1000), Vector2i(2560, 1600), Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(1280, 800)]:
		root.size = window_size
		await settle()
		verify(hud.cache_layer.get_viewport() == root, "Text draws at native window resolution at %s" % window_size)
		verify(hud.cache_layer.get_parent() == hud, "HUD draw commands stay on the root canvas")
		for child in hud.get_children():
			verify(not (child is SubViewport or child is TextureRect), "HUD has no intermediate bitmap")
		verify(hud.start_rect == start_rect and hud.card_rects == cards, "Start and reward hit targets retain their logical coordinates")
		var physical_point: Vector2 = hud.get_viewport_transform() * start_rect.get_center()
		var input := InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = true
		input.position = physical_point
		game.mode = "paused"
		root.push_input(input)
		await settle()
		verify(game.mode == "playing", "Scaled start/resume target responds to physical pointer coordinates at %s" % window_size)
		input.pressed = false
		root.push_input(input)
		game.mode = "title"
		await settle()
		var builds: int = hud.cache_builds
		await settle()
		verify(hud.cache_builds == builds, "Idle window does not continuously rebuild the HUD")
		verify(root.is_using_font_oversampling(), "Fonts follow the root window's display scale")
		verify(hud.font.oversampling == 0.0 and hud.font.fallbacks[0].oversampling == 0.0, "Font resources preserve automatic oversampling")
		print("DISPLAY window=", window_size, " direct text; minimum font=", hud.MIN_FONT_SIZE)
	game.queue_free()
	await settle()
	if failures.is_empty():
		print("PASS: native window text, fractional scaling, logical input, font sampling and retained draw stability")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
