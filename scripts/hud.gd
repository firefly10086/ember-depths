extends Control
## Retain drawing commands and render text directly into the native window.

const DESIGN_SIZE := Vector2i(1280, 800)
const MIN_FONT_SIZE := 13

const INK := Color("d9e1d7")
const MUTED := Color("9eafb4")
const GOLD := Color("dfb879")
const TEAL := Color("8ec8b7")
const PANEL := Color("0d1921")
const EDGE := Color("293d43")

var game: Node2D
var font: SystemFont
var display_font: SystemFont
var hover := -1
var styles: Dictionary = {}
var cache_layer: CachedLayer
var painter: Node2D
var dirty := true
var cache_builds := 0
var displayed_elapsed := 0.0
var time_accumulator := 0.0
var portal_near := false
var button_hot := false
var last_mode := ""
const ROOM_NAMES := {"entrance": "入口", "combat": "战斗", "treasure": "宝箱", "cursed": "诅咒", "shop": "商店", "boss": "守门者"}

class CachedLayer extends Node2D:
	var hud: Control
	func _draw() -> void:
		hud.painter = self
		hud._draw_cached()

func invalidate() -> void:
	dirty = true

func _setup_cache() -> void:
	# CanvasItem retains draw commands between invalidations. Text stays on the
	# window canvas, avoiding a bitmap size limit and a second filtering pass.
	cache_layer = CachedLayer.new()
	cache_layer.hud = self
	cache_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(cache_layer)
	var feedback := preload("res://scripts/hud_feedback.gd").new()
	feedback.hud = self
	add_child(feedback)
	var cursor := preload("res://scripts/hud_cursor.gd").new()
	cursor.hud = self
	add_child(cursor)
	get_viewport().size_changed.connect(invalidate)

var card_rects: Array[Rect2] = [Rect2(174, 294, 294, 282), Rect2(493, 294, 294, 282), Rect2(812, 294, 294, 282)]
var start_rect := Rect2(500, 537, 280, 60)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	font.hinting = TextServer.HINTING_NORMAL
	font.fallbacks = [preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")]
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	_setup_cache()
	game.hud_changed.connect(invalidate)
	game.player.stats_changed.connect(invalidate)
	# Warm all finite combinations; draw callbacks only look up reusable resources.
	for pair in [[PANEL, EDGE], [Color("15252c"), EDGE], [Color(0.03, 0.08, 0.10, 0.9), GOLD], [Color("10242b"), TEAL], [Color("e2bc7a"), Color("f0cf95")], [Color("cfa66a"), Color("f0cf95")], [Color("101e27"), Color("3a4c50")]]:
		_style(pair[0], pair[1])
	for upgrade in game.UPGRADES:
		_style(Color("1a2c32"), upgrade.color)

func _process(delta: float) -> void:
	if last_mode != game.mode:
		last_mode = game.mode
		displayed_elapsed = game.elapsed
		time_accumulator = 0
	var mouse := get_global_mouse_position()
	var next_hover := -1
	if game.mode == "reward":
		for i in card_rects.size():
			if card_rects[i].has_point(mouse): next_hover = i
	if next_hover != hover:
		hover = next_hover
		invalidate()
	var next_hot := start_rect.has_point(mouse)
	if next_hot != button_hot:
		button_hot = next_hot
		if game.mode in ["title", "dead", "paused", "victory"]: invalidate()
	var feature: bool = game.room.show_exit or game.rooms[game.room_index].get("kind", "combat") in ["treasure", "shop"]
	var next_near: bool = feature and game.player.position.distance_to(DungeonRoom.CENTER) < 76
	if portal_near != next_near:
		portal_near = next_near
		invalidate()
	time_accumulator += delta
	if time_accumulator >= 0.5:
		time_accumulator = fmod(time_accumulator, 0.5)
		if int(displayed_elapsed) != int(game.elapsed): invalidate()
		displayed_elapsed = game.elapsed
	if dirty:
		dirty = false
		cache_builds += 1
		cache_layer.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_event := make_input_local(event) as InputEventMouseButton
		var p := local_event.position
		if game.mode == "reward":
			if game.in_shop():
				if Rect2(1060, 184, 178, 46).has_point(p):
					game.leave_shop()
					get_viewport().set_input_as_handled()
					return
				for page in 3:
					if Rect2(250 + page * 260, 263, 250, 36).has_point(p):
						game.set_shop_page(page)
						get_viewport().set_input_as_handled()
						return
				for slot in 2:
					if Rect2(430 + slot * 210, 660, 200, 38).has_point(p):
						game.shop_slot = slot
						game.hud_changed.emit()
						return
				if game.shop_page != 0:
					var count := 4 if game.shop_page == 1 else 3
					for row in count:
						if Rect2(260, 315 + row * 76, 760, 66).has_point(p):
							if game.shop_page == 1 and p.x > 900:
								game.actives.equip(ActiveSkills.TYPES[row].id, game.shop_slot)
							else: game.shop_buy(row)
							get_viewport().set_input_as_handled()
							return
					return
			for i in card_rects.size():
				if card_rects[i].has_point(p):
					if game.in_shop(): game.shop_buy(i)
					else: game.choose_reward(i)
					get_viewport().set_input_as_handled()
					return
		elif game.mode in ["title", "dead", "paused", "victory"] and start_rect.has_point(p):
			if game.mode == "paused": game.mode = "playing"
			else: game.new_run()
			get_viewport().set_input_as_handled()

func label(at: Vector2, value: String, size: int = 16, color: Color = INK, width: float = -1, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	painter.draw_string(font, at, value, align, width, maxi(size, MIN_FONT_SIZE), color)

func center(at: Vector2, value: String, size: int = 16, color: Color = INK, width: float = 1280) -> void:
	label(Vector2(0, at.y), value, size, color, width, HORIZONTAL_ALIGNMENT_CENTER)

func panel(rect: Rect2, color: Color = PANEL, edge: Color = EDGE) -> void:
	painter.draw_style_box(_style(color, edge), rect)

func _style(color: Color, edge: Color) -> StyleBoxFlat:
	var key := Vector2i(color.to_rgba32(), edge.to_rgba32())
	if styles.has(key): return styles[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	styles[key] = style
	return style

func _draw_cached() -> void:
	if not is_instance_valid(game.player): return
	# Header and the quiet editorial frame around the game.
	painter.draw_rect(Rect2(0, 0, 1280, 108), Color("0a131b"))
	painter.draw_line(Vector2(42, 108), Vector2(1238, 108), EDGE)
	_draw_ember(Vector2(57, 47), GOLD, 0.65)
	painter.draw_string(display_font, Vector2(83, 52), "EMBER DEPTHS", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, INK)
	label(Vector2(85, 78), "余 烬 地 牢   /   一 次 深 入 黑 暗 的 旅 行", 12, MUTED)
	label(Vector2(844, 44), "最终目标 · 击败 20 层终焉王", 11, MUTED)
	var floor_label := "%02d / 20 · BOSS" % game.floor_number if game.floor_number % 5 == 0 else "地下 %02d / 20" % game.floor_number
	label(Vector2(844, 76), floor_label, 25, Color("ef9875") if game.floor_number % 5 == 0 else GOLD)
	label(Vector2(1113, 43), "本局时间", 11, MUTED)
	label(Vector2(1113, 74), "%02d:%02d" % [int(displayed_elapsed) / 60, int(displayed_elapsed) % 60], 23)
	_draw_sidebar()
	# Room caption, sitting above the lower frame.
	var room_name: String = "静谧的入口" if game.room_index == 0 else game.room.layout.name
	room_name += " · " + ROOM_NAMES.get(game.rooms[game.room_index].get("kind", "combat"), "战斗")
	label(Vector2(46, 122), "%s · %s / %02d" % [game.room.theme.name, room_name, game.room_index + 1], 11, MUTED)
	var status := "清空敌人，领取祝福" if game.room.locked else "穿过亮起的门，继续探索"
	if game.floor_number % 5 == 0 and game.room.locked: status = "Boss 层 · 击败守门者"
	if game.room.show_exit: status = "传送门已开启 · 靠近中心按 E 下潜"
	var kind: String = game.rooms[game.room_index].get("kind", "combat")
	if kind == "cursed" and game.room.locked: status = "诅咒 · 敌人强化 · 奖励两份祝福"
	if kind in ["treasure", "shop"]:
		status = "靠近中心按 E 开启宝箱" if kind == "treasure" else "中心按 E 交易 · 被动 %d 余烬" % game.shop_price(game.SHOP_COST)
		if game.rooms[game.room_index].rewarded and kind != "shop": status = "已经领取 · 继续探索"
	label(Vector2(470, 122), status, 11, TEAL, 465, HORIZONTAL_ALIGNMENT_RIGHT)
	if game.mode == "clearing":
		panel(Rect2(330, 374, 320, 72), Color(0.03, 0.08, 0.10, 0.9), GOLD)
		label(Vector2(330, 418), "房 间 已 净 化", 23, GOLD, 320, HORIZONTAL_ALIGNMENT_CENTER)
	if game.room.show_exit and game.mode == "playing" and game.player.position.distance_to(DungeonRoom.CENTER) < 76:
		panel(Rect2(350, 482, 280, 38), Color("10242b"), TEAL)
		label(Vector2(350, 508), "[ E ] 进入下一层 · 恢复 20 生命", 13, INK, 280, HORIZONTAL_ALIGNMENT_CENTER)
	if game.mode == "playing" and kind in ["treasure", "shop"] and portal_near and (kind == "shop" or not game.rooms[game.room_index].rewarded):
		panel(Rect2(350, 482, 280, 38), Color("10242b"), TEAL)
		label(Vector2(350, 508), "[ E ] 开启宝箱" if kind == "treasure" else "[ E ] 商店 · 祝福 / 主动 / 消耗品", 13, INK, 280, HORIZONTAL_ALIGNMENT_CENTER)
	for enemy in game.enemies:
		if enemy.is_boss and not enemy.dead:
			label(Vector2(298, 166), BossModule.title(enemy), 14, GOLD, 390, HORIZONTAL_ALIGNMENT_CENTER)
			painter.draw_rect(Rect2(298, 175, 390, 7), Color("233037"))
			painter.draw_rect(Rect2(298, 175, 390 * maxf(0, float(enemy.hp) / enemy.max_hp), 7), BossModule.COLORS[enemy.boss_theme])
			label(Vector2(698, 182), "减伤 %d%%" % roundi((1 - BossModule.incoming_multiplier(enemy)) * 100), 11, TEAL)
	_draw_footer()
	if game.mode == "reward": _draw_reward()
	elif game.mode == "title": _draw_title()
	elif game.mode == "dead": _draw_end(false)
	elif game.mode == "paused": _draw_end(true)
	elif game.mode == "victory": _draw_victory()
func _draw_sidebar() -> void:
	panel(Rect2(966, 132, 272, 576))
	label(Vector2(987, 162), "旅 人", 12, GOLD)
	label(Vector2(987, 190), "最后的守火者", 19)
	label(Vector2(987, 217), "生命", 11, MUTED)
	label(Vector2(1110, 217), "%d / %d" % [game.player.hp, game.player.max_hp], 12, INK, 104, HORIZONTAL_ALIGNMENT_RIGHT)
	painter.draw_rect(Rect2(987, 229, 228, 10), Color("233037"))
	painter.draw_rect(Rect2(987, 229, 228 * float(game.player.hp) / game.player.max_hp, 10), Color("bd7463"))
	painter.draw_rect(Rect2(987, 229, 228 * float(game.player.hp) / game.player.max_hp, 2), Color("e7a28b"))
	label(Vector2(987, 264), "攻击  %d" % game.player.effective_damage(), 12, MUTED)
	label(Vector2(1110, 264), "攻速  %.2f/s" % (1 / game.player.effective_attack_cooldown()), 12, MUTED)
	label(Vector2(987, 287), "移速  %d" % int(game.player.speed), 12, MUTED)
	label(Vector2(1110, 287), "剑距  %d" % int(game.player.attack_range), 12, MUTED)
	label(Vector2(987, 302), "余烬 %d  /  碎片 %d" % [game.currency, game.permanent_shards], 10, Color("c9a56f"))
	label(Vector2(987, 316), "本层清场祝福 %d / %d · 宝箱诅咒另计" % [game.floor_rewards, game.REWARDS_PER_FLOOR], 10, MUTED)
	painter.draw_line(Vector2(987, 322), Vector2(1215, 322), EDGE)
	label(Vector2(987, 348), "探 索 地 图", 12, GOLD)
	_draw_minimap(Rect2(987, 363, 228, 135))
	var cleared := 0
	for room in game.rooms:
		if room.cleared: cleared += 1
	label(Vector2(987, 520), "房间 %d / %d" % [cleared, game.rooms.size()], 12, MUTED)
	label(Vector2(1120, 520), "击败 %d" % game.kills, 12, MUTED)
	painter.draw_line(Vector2(987, 538), Vector2(1215, 538), EDGE)
	label(Vector2(987, 564), "已 获 祝 福", 12, GOLD)
	if game.collected.is_empty():
		label(Vector2(987, 592), "清空石室，拾取第一缕余烬。", 11, MUTED)
	else:
		var counts: Dictionary = {}
		for upgrade in game.collected:
			counts[upgrade.id] = counts.get(upgrade.id, 0) + 1
		var index := 0
		for upgrade in game.UPGRADES:
			if not counts.has(upgrade.id): continue
			var x := 1000.0 + (index % 4) * 55
			var row := floori(float(index) / 4.0)
			var y := 580.0 + row * 21
			panel(Rect2(x - 22, y - 10, 46, 20), Color("15252c"), EDGE)
			_draw_upgrade_icon(Vector2(x - 5, y - 2), upgrade.id, upgrade.color, 0.22)
			label(Vector2(x + 5, y + 7), "×%d" % counts[upgrade.id], 9, MUTED, 18, HORIZONTAL_ALIGNMENT_CENTER)
			index += 1
	_draw_active_slots()

func _draw_active_slots() -> void:
	for slot in 2:
		var rect := Rect2(987 + slot * 116, 655, 110, 43)
		panel(rect)
		var id: String = game.actives.slots[slot]
		var key := "Q" if slot == 0 else "R"
		if id.is_empty():
			label(rect.position + Vector2(8, 26), key + " · 未解锁", 11, MUTED)
			continue
		var item: Dictionary = game.actives.data_for(id)
		var left: float = game.actives.cooldowns[slot]
		_draw_active_icon(rect.position + Vector2(17, 19), id, item.color)
		if left > 0:
			painter.draw_rect(Rect2(rect.position, Vector2(rect.size.x * left / float(item.cooldown), rect.size.y)), Color(0, 0, 0, 0.65))
		label(rect.position + Vector2(34, 16), "%s · Lv%d" % [key, game.actives.levels[id]], 10, item.color)
		label(rect.position + Vector2(34, 32), "%.1fs" % left if left > 0 else "就绪", 10)

func _draw_active_icon(at: Vector2, id: String, tint: Color) -> void:
	match id:
		"shock":
			painter.draw_line(at + Vector2(-9, 10), at + Vector2(9, -10), tint, 4)
			painter.draw_line(at + Vector2(-6, -4), at + Vector2(7, 5), tint, 2)
		"ring":
			painter.draw_arc(at, 11, 0, TAU, 20, tint, 3)
			painter.draw_circle(at, 4, GOLD)
		"stasis":
			painter.draw_arc(at, 11, 0, TAU, 20, tint, 2)
			painter.draw_line(at, at + Vector2(0, -8), tint, 2)
			painter.draw_line(at, at + Vector2(6, 3), tint, 2)
		"rekindle":
			painter.draw_line(at + Vector2(-10, 0), at + Vector2(10, 0), tint, 5)
			painter.draw_line(at + Vector2(0, -10), at + Vector2(0, 10), tint, 5)

func _draw_minimap(rect: Rect2) -> void:
	var min_cell := Vector2i(999, 999)
	var max_cell := Vector2i(-999, -999)
	for room in game.rooms:
		min_cell.x = mini(min_cell.x, room.cell.x)
		min_cell.y = mini(min_cell.y, room.cell.y)
		max_cell.x = maxi(max_cell.x, room.cell.x)
		max_cell.y = maxi(max_cell.y, room.cell.y)
	var step := minf(43, minf((rect.size.x - 40) / maxf(1, max_cell.x - min_cell.x), (rect.size.y - 40) / maxf(1, max_cell.y - min_cell.y)))
	var mid := (Vector2(min_cell) + Vector2(max_cell)) / 2
	var origin := rect.get_center() - mid * step
	for room in game.rooms:
		var p: Vector2 = origin + Vector2(room.cell) * step
		for direction in room.doors:
			painter.draw_line(p, p + Vector2(direction) * step, Color("3a5154"), 2)
	for i in game.rooms.size():
		var room: Dictionary = game.rooms[i]
		var p: Vector2 = origin + Vector2(room.cell) * step
		var color := Color("172a33")
		if room.visited: color = Color("38564f") if room.cleared else Color("694d42")
		if i == game.room_index: color = GOLD
		painter.draw_rect(Rect2(p - Vector2(10, 8), Vector2(20, 16)), color)
		painter.draw_rect(Rect2(p - Vector2(10, 8), Vector2(20, 16)), Color("4b6265") if i != game.room_index else Color("f6dc9f"), false)
		if room.exit:
			var exit_color := Color("ef806d") if game.floor_number % 5 == 0 else TEAL
			painter.draw_circle(p, 3, exit_color if i != game.room_index else PANEL)
		elif i == game.room_index: painter.draw_circle(p, 2, PANEL)
		var kind: String = room.get("kind", "combat")
		if kind in ["treasure", "cursed", "shop"]:
			var symbols := {"treasure": "宝", "cursed": "咒", "shop": "商"}
			label(p + Vector2(-7, 4), symbols[kind], 11, GOLD if kind == "treasure" else (Color("c18bb8") if kind == "cursed" else TEAL))

func _draw_footer() -> void:
	painter.draw_line(Vector2(42, 731), Vector2(1238, 731), EDGE)
	var controls := [["WASD", "移动"], ["鼠标左键", "挥剑"], ["SPACE", "闪避"], ["Q / R", "主动技能"], ["E", "交互"], ["ESC", "暂停"]]
	var x := 46.0
	for pair in controls:
		label(Vector2(x, 766), pair[0], 12, INK)
		var length: float = font.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT_SIZE).x
		label(Vector2(x + length + 10, 766), pair[1], 11, MUTED)
		x += length + font.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT_SIZE).x + 43
	label(Vector2(1092, 766), "M  声音：%s" % ("关闭" if game.muted else "开启"), 11, MUTED, 144, HORIZONTAL_ALIGNMENT_RIGHT)

func _overlay() -> void:
	painter.draw_rect(Rect2(0, 0, 1280, 800), Color(0.015, 0.035, 0.05, 0.88))
	for i in range(7, 0, -1):
		painter.draw_circle(Vector2(640, 300), i * 55, Color(0.6, 0.4, 0.16, 0.012))

func _draw_title() -> void:
	_overlay()
	_draw_ember(Vector2(640, 188), GOLD, 1.1)
	center(Vector2(0, 258), "一 束 余 烬 ， 一 场 新 生", 13, GOLD)
	painter.draw_string(display_font, Vector2(0, 334), "EMBER DEPTHS", HORIZONTAL_ALIGNMENT_CENTER, 1280, 64, INK)
	center(Vector2(0, 378), "余 烬 地 牢", 27)
	painter.draw_line(Vector2(555, 405), Vector2(725, 405), Color("68583f"))
	center(Vector2(0, 445), "深入 20 层，击败终焉王，将余烬带回地面。", 16, MUTED)
	center(Vector2(0, 477), "每层两次清场祝福 · 宝箱与诅咒额外奖励", 14, TEAL)
	_button("点燃余烬，开始探索", "ENTER")
	center(Vector2(0, 647), "WASD 移动   /   鼠标左键挥剑   /   空格闪避", 13, MUTED)
	center(Vector2(0, 680), "死亡后重新开始。每一次深入，都是新的构筑。", 12, MUTED)
	center(Vector2(0, 758), "A SMALL ROGUELITE  ·  ORIGINAL PIXEL ART  ·  GODOT 4", 10, Color("536b70"))

func _button(value: String, key: String) -> void:
	var hot := start_rect.has_point(get_global_mouse_position())
	panel(start_rect, Color("e2bc7a") if hot else Color("cfa66a"), Color("f0cf95"))
	label(start_rect.position + Vector2(0, 37), value, 17, Color("17252a"), start_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	label(Vector2(0, start_rect.end.y + 23), key, 10, MUTED, 1280, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_reward() -> void:
	if game.in_shop() and game.shop_page != 0:
		_draw_shop_page()
		return
	_overlay()
	center(Vector2(0, 165), "R O O M   C L E A R E D", 12, GOLD)
	center(Vector2(0, 220), "余烬商店" if game.reward_source == "shop" else "选择一缕余烬", 34)
	var subtitle := "三选一 · 本局持续生效 · 留意契约的代价"
	if game.reward_source == "shop": subtitle = "每份 %d 余烬 · 持有 %d · TAB 切页 · ESC 离开" % [game.shop_price(game.SHOP_COST), game.currency]
	elif game.reward_source == "cursed": subtitle = "诅咒馈赠 · 剩余 %d 次选择" % game.pending_rewards
	elif game.reward_source == "treasure": subtitle = "宝箱馈赠 · 额外一份三选一祝福"
	center(Vector2(0, 255), subtitle, 14, MUTED)
	if game.in_shop(): _draw_shop_tabs()
	for i in mini(3, game.choices.size()):
		var upgrade: Dictionary = game.choices[i]
		var rect := card_rects[i]
		var hot := hover == i
		var color: Color = upgrade.color
		panel(rect, Color("1a2c32") if hot else Color("101e27"), color if hot else Color("3a4c50"))
		painter.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
		label(rect.position + Vector2(21, 30), "0%d  /  %s" % [i + 1, upgrade.tag], 11, color)
		_draw_upgrade_icon(rect.position + Vector2(147, 87), upgrade.id, color, 1.05)
		label(rect.position + Vector2(0, 155), upgrade.name, 23, INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		label(rect.position + Vector2(0, 193), upgrade.desc, 14, color, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		label(rect.position + Vector2(0, 226), upgrade.detail, 11, MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		label(rect.position + Vector2(0, 261), "点击选择   /   按 %d" % [i + 1], 11, INK if hot else MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	center(Vector2(0, 630), ("本房被动已售罄 · 主动和消耗品仍可购买" if game.rooms[game.room_index].rewarded else "点击购买被动祝福 · 每个商店限一份") if game.in_shop() else "门已在等待。让这次选择，改变接下来的旅程。", 13, MUTED)

func _draw_shop_tabs() -> void:
	var exit_rect := Rect2(1060, 184, 178, 46)
	panel(exit_rect, Color("10242b"), TEAL)
	label(exit_rect.position + Vector2(0, 29), "退出商店 · Esc", 16, INK, exit_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	label(Vector2(1060, 250), "无需购买，随时离开", 12, MUTED, 178, HORIZONTAL_ALIGNMENT_CENTER)
	for page in 3:
		var rect := Rect2(250 + page * 260, 263, 250, 36)
		panel(rect, PANEL, GOLD if game.shop_page == page else EDGE)
		label(rect.position + Vector2(0, 24), ["被动祝福", "主动技能", "消耗品"][page], 14, GOLD if game.shop_page == page else MUTED, 250, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_shop_page() -> void:
	_overlay()
	center(Vector2(0, 205), "余烬商店", 32)
	center(Vector2(0, 245), "持有 %d 余烬 · 楼层价格 ×%.2f · TAB 切页 · ESC 离开" % [game.currency, 1.0 + 0.25 * floori(float(game.floor_number - 1) / 5)], 14, GOLD)
	_draw_shop_tabs()
	var count := 4 if game.shop_page == 1 else 3
	for i in count:
		var rect := Rect2(260, 315 + i * 76, 760, 66)
		panel(rect)
		if game.shop_page == 1:
			var item: Dictionary = ActiveSkills.TYPES[i]
			var level: int = game.actives.levels.get(item.id, 0)
			_draw_active_icon(rect.position + Vector2(28, 30), item.id, item.color)
			label(rect.position + Vector2(55, 24), "%s  Lv%d/3" % [item.name, level], 17, item.color)
			label(rect.position + Vector2(55, 48), item.desc + " · 冷却 %ds" % item.cooldown, 12, MUTED)
			label(rect.position + Vector2(420, 28), "已满级" if level >= 3 else "%s %d 余烬" % ["解锁" if level == 0 else "升级", game.actives.price(i)], 14, GOLD)
			var equipped: int = game.actives.slots.find(item.id)
			label(rect.position + Vector2(420, 49), "已装备 %s" % ("Q" if equipped == 0 else "R") if equipped >= 0 else "点击左侧购买", 11, MUTED)
			panel(Rect2(rect.position + Vector2(645, 8), Vector2(105, 50)), PANEL, item.color)
			label(rect.position + Vector2(645, 39), "装备到 " + ("Q" if game.shop_slot == 0 else "R") if level > 0 else "未解锁", 12, INK, 105, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var item: Dictionary = ActiveSkills.CONSUMABLES[i]
			label(rect.position + Vector2(22, 25), item.name, 18, GOLD)
			label(rect.position + Vector2(22, 49), item.desc, 13, MUTED)
			label(rect.position + Vector2(490, 39), "%d 余烬 · 点击购买" % game.shop_price(item.price), 14)
	if game.shop_page == 1:
		for slot in 2:
			var rect := Rect2(430 + slot * 210, 660, 200, 38)
			panel(rect, PANEL, GOLD if slot == game.shop_slot else EDGE)
			label(rect.position + Vector2(0, 26), "目标槽 " + ("Q" if slot == 0 else "R"), 14, INK, 200, HORIZONTAL_ALIGNMENT_CENTER)
	else: center(Vector2(0, 630), "满血不扣疗伤费用 · 药剂和护符不可重复囤叠", 13, MUTED)

func _draw_end(paused: bool) -> void:
	_overlay()
	_draw_ember(Vector2(640, 213), TEAL if paused else GOLD, 1)
	center(Vector2(0, 302), "歇一歇，再出发" if paused else "余烬尚未熄灭", 36)
	center(Vector2(0, 347), "旅程已暂停，黑暗也会等候。" if paused else "这一次倒下，是下一次深入的起点。", 15, MUTED)
	center(Vector2(0, 420), "深入 %d 层     击败 %d 只怪物     收集 %d 份祝福" % [game.floor_number, game.kills, game.collected.size()], 17, GOLD)
	center(Vector2(0, 465), "本局用时  %02d:%02d" % [int(displayed_elapsed) / 60, int(displayed_elapsed) % 60], 14, MUTED)
	_button("继续探索" if paused else "重新点燃余烬", "ESC / ENTER" if paused else "ENTER")

func _draw_victory() -> void:
	_overlay()
	_draw_ember(Vector2(640, 202), GOLD, 1.3)
	center(Vector2(0, 304), "余烬重燃 · 旅程完成", 36, GOLD)
	center(Vector2(0, 351), "你击败了第 20 层终焉王，将火种带回地面。", 16, INK)
	center(Vector2(0, 420), "击败 %d 只敌人 · 收集 %d 份祝福" % [game.kills, game.collected.size()], 17, TEAL)
	center(Vector2(0, 464), "用时 %02d:%02d · 余烬碎片 %d" % [int(displayed_elapsed) / 60, int(displayed_elapsed) % 60, game.permanent_shards], 14, MUTED)
	_button("再次深入 · 新的构筑", "ENTER")

func _draw_ember(p: Vector2, color: Color, scale_value: float) -> void:
	var points := PackedVector2Array([Vector2(0, -27), Vector2(13, -7), Vector2(19, 6), Vector2(12, 22), Vector2(0, 29), Vector2(-16, 18), Vector2(-19, 0), Vector2(-8, 8), Vector2(-9, -10)])
	for i in points.size(): points[i] = p + points[i] * scale_value
	painter.draw_colored_polygon(points, color)
	painter.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -1) * scale_value, p + Vector2(8, 14) * scale_value, p + Vector2(0, 23) * scale_value, p + Vector2(-8, 13) * scale_value]), Color("f7e5b9"))

func _draw_upgrade_icon(p: Vector2, id: String, color: Color, scale_value: float) -> void:
	for i in range(4, 0, -1): painter.draw_circle(p, (12 + i * 9) * scale_value, Color(color, 0.025))
	match id:
		"damage":
			painter.draw_line(p + Vector2(-14, 15) * scale_value, p + Vector2(16, -18) * scale_value, color, 7 * scale_value)
			painter.draw_line(p + Vector2(-18, 4) * scale_value, p + Vector2(-4, 17) * scale_value, GOLD, 4 * scale_value)
		"haste":
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(5, -23) * scale_value, p + Vector2(-15, 4) * scale_value, p + Vector2(-1, 4) * scale_value, p + Vector2(-5, 23) * scale_value, p + Vector2(17, -6) * scale_value, p + Vector2(3, -6) * scale_value]), color)
		"speed":
			painter.draw_rect(Rect2(p + Vector2(-8, -19) * scale_value, Vector2(14, 28) * scale_value), color)
			painter.draw_rect(Rect2(p + Vector2(-8, 5) * scale_value, Vector2(28, 12) * scale_value), color)
			painter.draw_line(p + Vector2(-24, 0) * scale_value, p + Vector2(-13, 0) * scale_value, color, 3 * scale_value)
		"health":
			painter.draw_circle(p + Vector2(-9, -7) * scale_value, 12 * scale_value, color)
			painter.draw_circle(p + Vector2(9, -7) * scale_value, 12 * scale_value, color)
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(-20, -3) * scale_value, p + Vector2(20, -3) * scale_value, p + Vector2(0, 24) * scale_value]), color)
		"reach":
			painter.draw_arc(p, 23 * scale_value, -1.7, 1.5, 24, color, 6 * scale_value)
			painter.draw_arc(p + Vector2(-8, 0) * scale_value, 18 * scale_value, -1.4, 1.4, 24, color, 2 * scale_value)
		"force":
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(-24, 18) * scale_value, p + Vector2(-7, -17) * scale_value, p + Vector2(2, 0) * scale_value, p + Vector2(13, -24) * scale_value, p + Vector2(27, 18) * scale_value]), color)
		"sword_wave":
			painter.draw_arc(p + Vector2(-4, 4) * scale_value, 18 * scale_value, -1.3, 1.3, 20, color, 5 * scale_value)
			painter.draw_line(p + Vector2(-18, 15) * scale_value, p + Vector2(16, -15) * scale_value, Color("d8f4ee"), 3 * scale_value)
		"dash_trail":
			painter.draw_line(p + Vector2(-20, 10) * scale_value, p + Vector2(17, -10) * scale_value, color, 6 * scale_value)
			painter.draw_line(p + Vector2(-11, 16) * scale_value, p + Vector2(23, -1) * scale_value, Color("ffd098"), 2 * scale_value)
		"lifesteal":
			painter.draw_circle(p + Vector2(-8, -7) * scale_value, 10 * scale_value, color)
			painter.draw_circle(p + Vector2(8, -7) * scale_value, 10 * scale_value, color)
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(-17, -2) * scale_value, p + Vector2(17, -2) * scale_value, p + Vector2(0, 20) * scale_value]), color)
			painter.draw_line(p + Vector2(0, 5) * scale_value, p + Vector2(0, 16) * scale_value, Color("ffe8c4"), 2 * scale_value)
		"berserk":
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -23) * scale_value, p + Vector2(7, -5) * scale_value, p + Vector2(22, -2) * scale_value, p + Vector2(9, 7) * scale_value, p + Vector2(14, 23) * scale_value, p + Vector2(0, 13) * scale_value, p + Vector2(-14, 23) * scale_value, p + Vector2(-9, 7) * scale_value, p + Vector2(-22, -2) * scale_value, p + Vector2(-7, -5) * scale_value]), color)
			painter.draw_circle(p, 5 * scale_value, Color("fff0b0"))
		"hazardproof":
			painter.draw_circle(p, 20 * scale_value, Color(color, 0.15))
			painter.draw_polyline(PackedVector2Array([p + Vector2(-17, 0) * scale_value, p + Vector2(-9, 11) * scale_value, p + Vector2(0, 16) * scale_value, p + Vector2(9, 11) * scale_value, p + Vector2(17, 0) * scale_value]), color, 4 * scale_value)
			painter.draw_line(p + Vector2(-12, -13) * scale_value, p + Vector2(12, 13) * scale_value, Color("ffe6a9"), 2 * scale_value)
		"ward":
			painter.draw_circle(p, 19 * scale_value, Color(color, 0.12))
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -19) * scale_value, p + Vector2(15, -8) * scale_value, p + Vector2(11, 13) * scale_value, p + Vector2(0, 20) * scale_value, p + Vector2(-11, 13) * scale_value, p + Vector2(-15, -8) * scale_value]), color)
			painter.draw_line(p + Vector2(-6, 1) * scale_value, p + Vector2(-1, 6) * scale_value, Color("fff2c6"), 2 * scale_value)
			painter.draw_line(p + Vector2(-1, 6) * scale_value, p + Vector2(8, -5) * scale_value, Color("fff2c6"), 2 * scale_value)
		"glass", "oath", "blood":
			painter.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -24) * scale_value, p + Vector2(18, 0) * scale_value, p + Vector2(0, 24) * scale_value, p + Vector2(-18, 0) * scale_value]), color)
			painter.draw_line(p + Vector2(-10, -12) * scale_value, p + Vector2(9, 12) * scale_value, Color("352934"), 4 * scale_value)
			if id == "blood": painter.draw_circle(p + Vector2(0, 6) * scale_value, 5 * scale_value, Color("ffdfc0"))
