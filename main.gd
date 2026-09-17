extends Node3D
## ============================================================================
##  ЗВЁЗДНЫЕ ВРАТА: ОБОРОНА  —  волновой 3D-шутер для Godot 4.x (один скрипт)
## ----------------------------------------------------------------------------
##  Вы — солдат на базе Звёздных врат (SGC). Врата активируются, оттуда идут
##  волны Джаффа. Держите оборону как можно дольше.
##
##  Всё (база, врата, солдат, враги, оружие, HUD, звуки) строится кодом.
##  В main.tscn нужен только корневой Node3D со этим скриптом.
##
##  Управление:
##    WASD / стрелки   — движение          Мышь        — обзор
##    ЛКМ              — огонь             R           — перезарядка
##    Shift            — бег               Space       — прыжок
##    V                — 1-е / 3-е лицо    Esc         — отпустить мышь
##    R / ЛКМ          — рестарт после смерти
## ============================================================================

# ------------------------------ настройка -----------------------------------
const ROOM_HX := 19.0          # полуширина комнаты (X)
const ROOM_HZ := 27.0          # полу-глубина (Z)
const ROOM_H := 12.0           # высота потолка
const GATE_POS := Vector3(0, 3.6, -25.5)
const GATE_R := 3.4

const PLAYER_SPEED := 6.0
const SPRINT_SPEED := 9.2
const JUMP_V := 6.0
const GRAV := 20.0
const MOUSE_SENS := 0.0022

const MAG_SIZE := 30
const FIRE_RATE := 0.10        # сек между выстрелами (авто)
const RELOAD_TIME := 1.5
const BULLET_DMG := 14.0
const BULLET_RANGE := 120.0

const GRENADE_DMG := 95.0
const GRENADE_R := 5.5
const GRENADE_SPEED := 17.0
const BOSS_EVERY := 5
const STAFF_WINDUP := 0.22   # раскрытие пасти перед выстрелом
const STAFF_CLOSE := 0.28    # закрытие пасти после выстрела
const FEELER_LEN := 3.0      # длина лучей-щупов обхода препятствий
const TURRET_RANGE := 32.0
const TURRET_DMG := 9.0
const TURRET_RATE := 0.45
const CHOICE_TIME := 10.0   # авто-продолжение выбора улучшения
const POWER_PER_WAVE := 0.35  # прирост коэффициента усиления за каждую волну
const POWER_CAP := 4.0        # потолок усиления (насыщение, без взрывного роста)
const TURRET_REPAIR_COST := 150
const TURRET_UPGRADE_COST := 300
const TURRET_INTERACT := 4.5

const COL_CYAN := Color(0.35, 0.95, 1.0)
const COL_ORANGE := Color(1.0, 0.55, 0.15)
const COL_RED := Color(1.0, 0.25, 0.18)
const COL_WHITE := Color(0.95, 0.98, 1.0)

# слои коллизий
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_ALLY := 8

const ALLY_COUNT := 2
const ALLY_RANGE := 26.0
const ALLY_NAMES := ["CARTER", "TEAL'C"]

enum Phase { MENU, PLAY, OVER }

# ------------------------------- состояние ----------------------------------
var phase: int = Phase.MENU
var score := 0
var wave := 0
var kills := 0
var best := 0

var health := 100.0
var max_health := 100.0
var reloading := false
var reload_t := 0.0
var fire_cd := 0.0
var firing := false
var dmg_flash := 0.0

# оружие: два ствола с собственными магазинами и характеристиками
var weapon_state := [
	{"name": "АВТОМАТ", "base_mag": 30, "mag": 30, "base_rate": 0.10, "base_reload": 1.5, "base_dmg": 14.0, "pellets": 1, "spread": 0.006},
	{"name": "ДРОБОВИК", "base_mag": 8, "mag": 8, "base_rate": 0.70, "base_reload": 2.2, "base_dmg": 9.0, "pellets": 8, "spread": 0.06},
]
var cur_weapon := 0

# улучшения / динамические характеристики (общие для обоих стволов)
var dmg_mult := 1.0
var rof_mult := 1.0
var reload_mult := 1.0
var mag_bonus := 0
var speed_mult := 1.0
var lifesteal := 0.0
var grenade_count := 3
var max_grenades := 3
var grenade_cd := 0.0

# выбор апгрейда между волнами
var awaiting_choice := false
var upgrade_choices: Array[String] = []
var choice_t := 0.0
var choice_lines := ""

var enemies_alive := 0
var to_spawn := 0
var spawn_t := 0.0
var wave_break := false
var break_t := 0.0

var yaw := 0.0
var pitch := 0.0
var cam_fps := true
var vel_y := 0.0
var recoil := 0.0
var bob := 0.0
var shake := 0.0

var rng := RandomNumberGenerator.new()
var gen: AudioStreamGeneratorPlayback = null

# ------------------------------- узлы ---------------------------------------
var space: PhysicsDirectSpaceState3D
var player: CharacterBody3D
var soldier: Node3D
var cam_pivot: Node3D
var camera: Camera3D
var weapon_view: Node3D
var muzzle_fps: Marker3D
var muzzle_tps: Marker3D
var shoot_light: OmniLight3D

var gate: Node3D
var horizon_mat: ShaderMaterial
var gate_light: OmniLight3D
var chevrons: Array[StandardMaterial3D] = []

var enemy_root: Node3D
var proj_root: Node3D
var fx_root: Node3D
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var ally_root: Node3D
var allies: Array[Dictionary] = []
var ally_lbls: Array[Label] = []
var ally_bars: Array[ColorRect] = []
var obstacles: Array[Dictionary] = []
var turret_root: Node3D
var turrets: Array[Dictionary] = []
var lbl_turret_hint: Label
var power := 0.0   # плавно растущий коэффициент усиления (враги/союзники/турели)

# радиообмен SG-1
var radio_log: Array[Dictionary] = []
var radio_cd := 0.0
var voice_cd := 0.0
var idle_radio_t := 10.0
var low_warned := false
var radio_lbls: Array[Label] = []

# кат-сцены
var cut_cam: Camera3D
var cutscene_active := false
var cut_t := 0.0
var cut_dur := 0.0
var cut_points: Array = []
var letter_top: ColorRect
var letter_bot: ColorRect
var cut_label: Label
var intro_played := false

var hud_root: Control
var hud_layer: CanvasLayer
var cut_root: Control
var lbl_score: Label
var lbl_wave: Label
var lbl_enemy: Label
var lbl_ammo: Label
var lbl_grenade: Label
var lbl_center: Label
var lbl_sub: Label
var center_tw: Tween = null
var bar_health: ColorRect
var bar_reload: ColorRect
var lbl_health_num: Label
var lbl_boss_num: Label
var ally_nums: Array[Label] = []
var boss_panel: Panel
var bar_boss: ColorRect
var reticle: Control
var vignette_mat: ShaderMaterial
var flash_mat: ShaderMaterial

var snd_amb: AudioStreamPlayer
var snd_sfx: AudioStreamPlayer
var snd_voice: AudioStreamPlayer

# ============================== СТАРТ =======================================
func _ready() -> void:
	rng.randomize()
	best = _load_best()
	space = get_world_3d().direct_space_state

	_build_environment()
	_build_room()
	_build_gate()
	_build_turrets()
	enemy_root = Node3D.new(); enemy_root.name = "Enemies"; add_child(enemy_root)
	ally_root = Node3D.new(); ally_root.name = "Allies"; add_child(ally_root)
	proj_root = Node3D.new(); proj_root.name = "Projectiles"; add_child(proj_root)
	fx_root = Node3D.new(); fx_root.name = "FX"; add_child(fx_root)
	_build_player()
	_build_audio()
	_build_hud()
	_build_cutscene()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_game()
	phase = Phase.MENU
	_set_center("ЗВЁЗДНЫЕ ВРАТА: ОБОРОНА", "ЛКМ — начать   |   WASD — движение, ЛКМ — огонь, R — перезарядка, V — вид")


func _unhandled_input(event: InputEvent) -> void:
	# во время кат-сцены любой ввод её пропускает
	if cutscene_active:
		if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
			_end_cutscene()
		return
	# выбор апгрейда между волнами
	if awaiting_choice and event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
		if idx >= 0 and idx < upgrade_choices.size():
			_apply_upgrade(upgrade_choices[idx])
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				if phase == Phase.PLAY:
					cam_fps = not cam_fps
					_switch_camera()
			KEY_G:
				if phase == Phase.PLAY:
					_throw_grenade()
			KEY_F:
				if phase == Phase.PLAY:
					_repair_turret()
			KEY_T:
				if phase == Phase.PLAY:
					_upgrade_turret()
			KEY_Q:
				if phase == Phase.PLAY:
					_switch_weapon()
			KEY_R:
				if phase == Phase.PLAY:
					_try_reload()
				elif phase == Phase.OVER:
					_reset_game(); phase = Phase.PLAY; _set_center("", ""); _capture(true)
			KEY_ESCAPE:
				if phase == Phase.PLAY:
					_capture(false)

	if phase == Phase.PLAY:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			yaw -= event.relative.x * MOUSE_SENS
			pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				firing = event.pressed
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_throw_grenade()
	elif phase != Phase.PLAY:
		var go := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				go = true
		if go or event.is_action_pressed("ui_accept"):
			_reset_game(); phase = Phase.PLAY; _set_center("", ""); _capture(true)
			if not intro_played:
				intro_played = true
				_play_cutscene("intro")


func _capture(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if cutscene_active:
		return
	if phase == Phase.PLAY:
		_update_player(delta)
		_update_waves(delta)
	_update_enemies(delta)
	_update_allies(delta)
	_update_turrets(delta)
	_update_projectiles(delta)
	_update_grenades(delta)
	_cleanup_allies()
	_update_camera(delta)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	voice_cd = maxf(0.0, voice_cd - delta)
	if cutscene_active:
		_update_cutscene(delta)
	_animate_gate(delta)
	_update_hud(delta)
	_update_audio(delta)

# ============================== ИГРОК =======================================
func _w() -> Dictionary:
	return weapon_state[cur_weapon]


func _w_mag_size() -> int:
	return int(_w().base_mag) + mag_bonus


func _w_rate() -> float:
	return float(_w().base_rate) * rof_mult


func _w_reload() -> float:
	return float(_w().base_reload) * reload_mult


func _w_dmg() -> float:
	return float(_w().base_dmg) * dmg_mult


func _switch_weapon() -> void:
	cur_weapon = 1 - cur_weapon
	reloading = false
	reload_t = 0.0
	fire_cd = 0.25
	_sfx("weapon_switch")
	_set_center(String(_w().name), "Оружие переключено")
	_fade_center(1.0)


func _update_player(delta: float) -> void:
	# --- движение ---
	var ix := Input.get_axis("ui_left", "ui_right")
	var iz := Input.get_axis("ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): ix -= 1.0
	if Input.is_key_pressed(KEY_D): ix += 1.0
	if Input.is_key_pressed(KEY_W): iz -= 1.0
	if Input.is_key_pressed(KEY_S): iz += 1.0
	ix = clampf(ix, -1.0, 1.0)
	iz = clampf(iz, -1.0, 1.0)

	player.rotation.y = yaw
	cam_pivot.rotation.x = pitch

	var sprinting := Input.is_key_pressed(KEY_SHIFT)
	var spd := (SPRINT_SPEED if sprinting else PLAYER_SPEED) * speed_mult
	var basis := player.global_transform.basis
	var wish := (basis * Vector3(ix, 0, iz))
	if wish.length() > 0.01:
		wish = wish.normalized() * spd
	else:
		wish = Vector3.ZERO
	# плавное ускорение по горизонтали
	var hv := player.velocity
	hv.x = move_toward(hv.x, wish.x, 60.0 * delta)
	hv.z = move_toward(hv.z, wish.z, 60.0 * delta)

	# гравитация и прыжок
	vel_y -= GRAV * delta
	if Input.is_key_pressed(KEY_SPACE) and player.is_on_floor():
		vel_y = JUMP_V
	hv.y = vel_y
	player.velocity = hv
	player.move_and_slide()
	if player.is_on_floor() and vel_y < 0.0:
		vel_y = -0.5
	# границы (страховка)
	player.position.x = clampf(player.position.x, -ROOM_HX + 1.0, ROOM_HX - 1.0)
	player.position.z = clampf(player.position.z, -ROOM_HZ + 1.0, ROOM_HZ - 1.0)

	# покачивание при ходьбе
	var speed_planar := Vector2(hv.x, hv.z).length()
	bob += delta * speed_planar * 1.6
	if not player.is_on_floor():
		bob = 0.0

	# --- стрельба ---
	fire_cd = maxf(0.0, fire_cd - delta)
	grenade_cd = maxf(0.0, grenade_cd - delta)
	recoil = maxf(0.0, recoil - delta * 6.0)
	var w := _w()
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			w.mag = _w_mag_size()
			_sfx("reload_end")
	if firing and not reloading and fire_cd <= 0.0:
		if w.mag > 0:
			_shoot()
		else:
			_try_reload()


func _try_reload() -> void:
	var w := _w()
	if reloading or w.mag >= _w_mag_size():
		return
	reloading = true
	reload_t = _w_reload()
	_sfx("reload")


func _shoot() -> void:
	var w := _w()
	w.mag -= 1
	fire_cd = _w_rate()
	recoil = 1.0 if int(w.pellets) == 1 else 1.6
	_sfx("shot" if int(w.pellets) == 1 else "shotgun")
	var from := camera.global_position
	var base_dir := -camera.global_transform.basis.z
	var sp: float = float(w.spread)
	for p in int(w.pellets):
		var dir := base_dir
		dir = dir.rotated(camera.global_transform.basis.x, rng.randf_range(-sp, sp))
		dir = dir.rotated(camera.global_transform.basis.y, rng.randf_range(-sp, sp))
		var to := from + dir * BULLET_RANGE
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_ENEMY, [player.get_rid()])
		var hit := space.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit.position
			var col: Object = hit.collider
			if col != null and col.is_in_group("enemy"):
				_damage_enemy(col, _w_dmg(), dir)
			else:
				_impact(end, hit.get("normal", Vector3.UP), COL_WHITE)
		_tracer(_active_muzzle(), end)
	_muzzle_flash()


func _active_muzzle() -> Vector3:
	return (muzzle_fps if cam_fps else muzzle_tps).global_position


func _damage_player(dmg: float) -> void:
	if phase != Phase.PLAY:
		return
	health -= dmg
	dmg_flash = 1.0
	_sfx("hurt")
	if health > 0.0 and health < 30.0 and not low_warned:
		low_warned = true
		_radio_ally("CARTER", "Командир, у вас критически мало HP!")
	if health <= 0.0:
		health = 0.0
		_game_over()


# ============================== ВРАГИ =======================================
func _spawn_enemy(kind: String = "jaffa") -> void:
	var e := CharacterBody3D.new()
	e.collision_layer = LAYER_ENEMY
	e.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ALLY
	e.add_to_group("enemy")
	var cap := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cap.shape = cs
	e.add_child(cap)

	var body := _make_humanoid(false, kind)
	e.add_child(body)

	var px := GATE_POS.x + rng.randf_range(-1.8, 1.8)
	e.position = Vector3(px, 0.0, GATE_POS.z + 1.2)
	enemy_root.add_child(e)

	# --- характеристики по типу ---
	var hp := 30.0
	var spd := 2.4
	var fire := 2.0
	var keep := 7.0
	var melee := 30.0
	var sc := 1.0
	var pdmg := 8.0
	var pspd := 26.0
	match kind:
		"scout":
			hp = 18.0 + float(wave) * 5.0
			spd = clampf(4.0 + float(wave) * 0.22, 4.0, 7.0)
			fire = 1.5; keep = 2.6; melee = 55.0; sc = 0.9
			pdmg = 5.0; pspd = 30.0
		"heavy":
			hp = 70.0 + float(wave) * 16.0
			spd = clampf(1.7 + float(wave) * 0.05, 1.7, 2.8)
			fire = 2.6; keep = 11.0; melee = 40.0; sc = 1.3
			pdmg = 16.0 + float(wave) * 0.8; pspd = 17.0
		"boss":
			hp = 420.0 + float(wave) * 130.0
			spd = 2.1; fire = 1.5; keep = 13.0; melee = 70.0; sc = 1.9
			pdmg = 12.0 + float(wave) * 0.6; pspd = 22.0
		_:
			hp = 30.0 + float(wave) * 9.0
			spd = clampf(2.4 + float(wave) * 0.16, 2.4, 5.2)
			fire = clampf(2.2 - float(wave) * 0.06, 0.9, 2.2)
			keep = 7.0; melee = 30.0; sc = 1.0
			pdmg = 8.0 + float(wave) * 0.6; pspd = 26.0

	# плавное усиление врагов со временем
	hp *= _enemy_mult()
	pdmg *= _enemy_mult()
	melee *= _enemy_mult()
	spd = clampf(spd * (1.0 + power * 0.02), 1.5, 7.0)

	body.scale = Vector3.ONE * sc
	cs.radius = 0.45 * sc
	cs.height = 1.8 * sc
	cap.position = Vector3(0, 0.9 * sc, 0)

	# энергетический щит босса (пузырь), включается во 2-й фазе
	var shield_node = null
	var shield_mat = null
	if kind == "boss":
		shield_mat = _emissive(Color(0.4, 0.8, 1.0), 1.2)
		shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shield_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var bm := SphereMesh.new()
		bm.radius = 1.0
		bm.height = 2.0
		shield_node = _mesh(bm, shield_mat)
		shield_node.scale = Vector3(1.5 * sc, 2.1 * sc, 1.5 * sc)
		shield_node.position = Vector3(0, 1.0 * sc, 0)
		shield_node.visible = false
		e.add_child(shield_node)

	enemies.append({
		"body": e, "kind": kind, "hp": hp, "max_hp": hp, "speed": spd, "sc": sc,
		"fire_cd": rng.randf_range(0.6, fire), "fire_rate": fire,
		"keep": keep, "melee": melee, "pdmg": pdmg, "pspd": pspd,
		"hitflash": 0.0, "mat": body.get_meta("armor_mat"),
		"head": body.get_meta("staff_head", null),
		"jaw_u": body.get_meta("jaw_u", null),
		"jaw_l": body.get_meta("jaw_l", null),
		"core_mat": body.get_meta("core_mat", null),
		"windup": 0.0, "close_t": 0.0, "open": 0.0,
		"shield_node": shield_node, "shield_mat": shield_mat,
		"bphase": 1, "shield_on": false, "shield_t": 0.0, "summon_t": 0.0,
		"stuck_t": 0.0, "unstick": 0.0, "unstick_side": 1.0, "last_pos": e.position,
	})
	enemies_alive += 1
	_gate_spawn_fx(e.position + Vector3(0, 1.2 * sc, 0))
	_sfx("gate_spawn")
	if kind == "boss":
		_sfx("boss_roar")


func _pick_kind() -> String:
	var r := rng.randf()
	if wave >= 3 and r > 0.86:
		return "heavy"
	if wave >= 2 and r < 0.26:
		return "scout"
	return "jaffa"


func _update_enemies(delta: float) -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var d: Dictionary = enemies[i]
		var body: CharacterBody3D = d.body
		if body == null or not is_instance_valid(body):
			enemies.remove_at(i); i -= 1; continue

		# выбор цели: игрок или ближайший живой союзник
		var tpos := player.global_position + Vector3(0, 1.0, 0)
		var tally: Dictionary = {}
		var ttur: Dictionary = {}
		var best_d := body.global_position.distance_to(tpos)
		for al in allies:
			if al.hp > 0.0 and is_instance_valid(al.body):
				var ap: Vector3 = al.body.global_position + Vector3(0, 1.0, 0)
				var ad := body.global_position.distance_to(ap)
				if ad < best_d:
					best_d = ad
					tpos = ap
					tally = al
		for t in turrets:
			if t.alive and is_instance_valid(t.head):
				var tpv: Vector3 = t.head.global_position
				var td := body.global_position.distance_to(tpv) * 1.25
				if td < best_d:
					best_d = td
					tpos = tpv
					tally = {}
					ttur = t
		var to_p := tpos - body.global_position
		var dist := to_p.length()
		var flat := Vector3(to_p.x, 0, to_p.z)
		var flat_len := flat.length()

		# движение: сближаться до ~7 м, иначе стрейф
		var move := Vector3.ZERO
		if flat_len > 0.05:
			var fwd := flat / flat_len
			if dist > d.keep:
				move = fwd * d.speed
			else:
				var side := Vector3(-fwd.z, 0, fwd.x)
				move = side * d.speed * 0.5 * (1.0 if (kills + i) % 2 == 0 else -1.0)
			# повернуться к цели
			var target := tpos
			target.y = body.global_position.y
			if body.global_position.distance_to(target) > 0.05:
				body.look_at(target, Vector3.UP)

		# расталкивание
		for j in enemies.size():
			if j == i: continue
			var o: Dictionary = enemies[j]
			var ob: CharacterBody3D = o.body
			if ob != null and is_instance_valid(ob):
				var diff: Vector3 = body.global_position - ob.global_position
				diff.y = 0.0
				var dl := diff.length()
				if dl < (0.9 + d.sc * 0.5) and dl > 0.001:
					move += diff / dl * (1.0 - dl) * 3.0

		var vel := body.velocity
		move = _agent_move(body, move, d.speed, delta, d)
		vel.x = move.x
		vel.z = move.z
		vel.y = -GRAV * 0.5 if body.is_on_floor() else vel.y - GRAV * delta
		body.velocity = vel
		body.move_and_slide()

		# вспышка попадания
		if d.hitflash > 0.0:
			d.hitflash = maxf(0.0, d.hitflash - delta * 4.0)
			var m: StandardMaterial3D = d.mat
			m.emission_energy_multiplier = d.hitflash * 4.0

		# стрельба: раскрытие пасти -> выстрел -> закрытие
		if phase == Phase.PLAY:
			d.fire_cd -= delta
			if d.windup > 0.0:
				d.windup -= delta
				d.open = 1.0 - clampf(d.windup / STAFF_WINDUP, 0.0, 1.0)
				if d.windup <= 0.0:
					_enemy_shoot(d, tpos)
					d.close_t = STAFF_CLOSE
			elif d.close_t > 0.0:
				d.close_t -= delta
				d.open = clampf(d.close_t / STAFF_CLOSE, 0.0, 1.0)
			else:
				d.open = 0.0
				if d.fire_cd <= 0.0 and dist < 34.0:
					d.fire_cd = d.fire_rate * rng.randf_range(0.8, 1.2)
					if _enemy_has_los(body.global_position + Vector3(0, 1.3 * d.sc, 0), tpos):
						d.windup = STAFF_WINDUP
						_sfx("staff_charge")
			_apply_staff_open(d, d.open)

		# контактный урон по текущей цели (игрок, союзник или турель)
		if dist < 1.2 * d.sc + 0.5 and phase == Phase.PLAY:
			if not ttur.is_empty():
				_damage_turret(ttur, d.melee * delta)
			elif tally.is_empty():
				_damage_player(d.melee * delta)
			else:
				_damage_ally(tally, d.melee * delta)

		# --- фазы босса: щит и призыв миньонов ---
		if d.kind == "boss" and phase == Phase.PLAY:
			var frac := clampf(d.hp / d.max_hp, 0.0, 1.0)
			if d.bphase == 1 and frac <= 0.66:
				d.bphase = 2
				_boss_phase_fx(d, 2)
			elif d.bphase == 2 and frac <= 0.33:
				d.bphase = 3
				_boss_phase_fx(d, 3)
			# цикл щита (фаза 2+)
			if d.bphase >= 2:
				d.shield_t -= delta
				if d.shield_t <= 0.0:
					d.shield_on = not d.shield_on
					d.shield_t = 4.0 if d.shield_on else 3.0
					_sfx("shield_up" if d.shield_on else "shield_down")
					if d.shield_on:
						_radio_ally("CARTER", "Щит поднят — прекратите огонь!")
					else:
						_radio_ally("CARTER", "Окно! Огонь по Гоа'улду!")
			# призыв миньонов (фаза 3)
			if d.bphase >= 3:
				d.summon_t -= delta
				if d.summon_t <= 0.0:
					d.summon_t = 6.0
					_boss_summon(d)
			# визуал щита
			var sn: Node3D = d.shield_node
			if sn != null and is_instance_valid(sn):
				sn.visible = d.shield_on
				if d.shield_on:
					var pulse := 1.0 + sin(float(Time.get_ticks_msec()) * 0.01) * 0.06
					sn.scale = Vector3(1.5 * d.sc, 2.1 * d.sc, 1.5 * d.sc) * pulse
			var smat: StandardMaterial3D = d.shield_mat
			if smat != null:
				smat.emission_energy_multiplier = 1.2 if d.shield_on else 0.0

		i -= 1


func _enemy_has_los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD, [])
	var hit := space.intersect_ray(q)
	return hit.is_empty()


# Обход препятствий: отталкивание от укрытий + лучи-щупы + анти-застревание.
# Возвращает итоговый горизонтальный вектор скорости для агента.
func _agent_move(body: CharacterBody3D, desired: Vector3, speed: float, delta: float, ag: Dictionary) -> Vector3:
	desired.y = 0.0
	# мягкое отталкивание от укрытий, чтобы обтекать их
	for ob in obstacles:
		var to_b: Vector3 = body.global_position - ob.pos
		to_b.y = 0.0
		var d := to_b.length()
		var rr: float = ob.r + 1.3
		if d < rr and d > 0.001:
			desired += (to_b / d) * (1.0 - d / rr) * 2.0
	if desired.length_squared() < 0.0001:
		return Vector3.ZERO
	desired = desired.normalized()

	# детект застревания: хотим двигаться, но почти не смещаемся
	var disp: Vector3 = body.global_position - ag.last_pos
	disp.y = 0.0
	ag.last_pos = body.global_position
	if disp.length() < speed * delta * 0.25:
		ag.stuck_t += delta
	else:
		ag.stuck_t = maxf(0.0, ag.stuck_t - delta * 2.0)
	if ag.stuck_t > 0.5:
		ag.unstick = 0.8
		ag.stuck_t = 0.0
		ag.unstick_side = -ag.unstick_side
	if ag.unstick > 0.0:
		ag.unstick -= delta
		var side: Vector3 = Vector3(-desired.z, 0, desired.x) * float(ag.unstick_side)
		desired = (desired * 0.4 + side).normalized()

	# лучи-щупы: первое свободное направление (прямо, затем в стороны)
	var origin := body.global_position + Vector3(0, 0.7, 0)
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var d2 := desired.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d2 * FEELER_LEN, LAYER_WORLD, [body.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return d2 * speed
	# всё перекрыто — отступить
	return -desired * speed * 0.4


func _apply_staff_open(d: Dictionary, open: float) -> void:
	var ju: Node3D = d.jaw_u
	var jl: Node3D = d.jaw_l
	if ju != null and is_instance_valid(ju):
		ju.rotation.x = open * 0.85
	if jl != null and is_instance_valid(jl):
		jl.rotation.x = -open * 0.85
	var cm: StandardMaterial3D = d.core_mat
	if cm != null:
		cm.emission_energy_multiplier = 0.6 + open * 7.0


func _boss_phase_fx(d: Dictionary, ph: int) -> void:
	_sfx("boss_roar")
	_flash(0.3)
	shake = 0.7
	if ph == 2:
		_set_center("ФАЗА 2: ЩИТ", "Гоа'улд поднимает энергетический щит — бей, когда он падает!")
	else:
		_set_center("ФАЗА 3: ЯРОСТЬ", "Гоа'улд призывает слуг и ускоряется!")
		d.fire_rate = maxf(0.6, d.fire_rate * 0.7)
		d.speed = d.speed * 1.2
	_fade_center(2.5)
	if ph == 2:
		_radio_ally("CARTER", "Энергетический щит! Огонь бесполезен — ждём окно!")
	else:
		_radio_ally("TEAL'C", "Он призывает слуг! Приготовьтесь!")


func _boss_summon(d: Dictionary) -> void:
	if enemies_alive >= 12:
		return
	_sfx("boss_summon")
	for k in 2:
		_spawn_enemy("jaffa" if rng.randf() < 0.6 else "scout")
	_gate_spawn_fx(GATE_POS + Vector3(0, 1.0, 1.0))


func _shield_hit_fx(d: Dictionary, pos: Vector3) -> void:
	_impact(pos, Vector3.UP, Color(0.4, 0.8, 1.0))
	_sfx("shield_hit")
	var smat: StandardMaterial3D = d.shield_mat
	if smat != null:
		smat.emission_energy_multiplier = 3.0


func _enemy_shoot(d: Dictionary, target: Vector3) -> void:
	var body: CharacterBody3D = d.body
	var sc: float = d.sc
	var hn: Node3D = d.head
	var from: Vector3
	if hn != null and is_instance_valid(hn):
		from = hn.global_position + (-body.global_transform.basis.z) * (0.18 * sc)
	else:
		from = body.global_position + Vector3(0, 1.35 * sc, 0) + (-body.global_transform.basis.z) * (0.6 * sc)
	var base := (target - from).normalized()
	var kind: String = d.kind
	if kind == "boss":
		for s in 5:
			var ang := (float(s) - 2.0) * 0.13 + rng.randf_range(-0.02, 0.02)
			_spawn_projectile(from, base.rotated(Vector3.UP, ang), d.pspd, d.pdmg, Color(0.75, 0.45, 1.0), 0.2)
		_sfx("boss_shot")
	elif kind == "heavy":
		var dir := base.rotated(Vector3.UP, rng.randf_range(-0.03, 0.03))
		_spawn_projectile(from, dir, d.pspd, d.pdmg, Color(1.0, 0.35, 0.12), 0.3)
		_sfx("enemy_shot")
	else:
		var dir := base.rotated(Vector3.UP, rng.randf_range(-0.05, 0.05))
		dir = dir.rotated(body.global_transform.basis.x, rng.randf_range(-0.04, 0.04))
		_spawn_projectile(from, dir, d.pspd, d.pdmg, COL_ORANGE, 0.16)
		_sfx("enemy_shot")


func _damage_enemy(col: Object, dmg: float, dir: Vector3) -> void:
	for k in enemies.size():
		var d: Dictionary = enemies[k]
		if d.body == col:
			if d.kind == "boss" and d.shield_on:
				_shield_hit_fx(d, col.global_position + Vector3(0, 1.4 * d.sc, 0) - dir * 0.5)
				return
			d.hp -= dmg
			d.hitflash = 1.0
			_impact(col.global_position + Vector3(0, 1.2, 0) - dir * 0.3, -dir, COL_RED)
			_sfx("hit_enemy")
			if d.hp <= 0.0:
				_kill_enemy(k)
			return


func _kill_enemy(index: int) -> void:
	var d: Dictionary = enemies[index]
	var body: CharacterBody3D = d.body
	var kind: String = d.kind
	var sc: float = d.sc
	if body != null and is_instance_valid(body):
		_death_fx(body.global_position + Vector3(0, 1.0 * sc, 0))
		body.queue_free()
	enemies.remove_at(index)
	enemies_alive -= 1
	kills += 1
	var pts := 100
	match kind:
		"scout": pts = 75
		"heavy": pts = 200
		"boss": pts = 1500
	score += pts
	if lifesteal > 0.0:
		health = minf(max_health, health + lifesteal)
	if kind == "boss":
		_flash(0.5)
		shake = 0.9
		_sfx("boss_die")
		_set_center("ГОА'УЛД ПОВЕРЖЕН", "+%d очков" % pts)
		_fade_center(2.0)
	else:
		_sfx("enemy_die")


# ============================== СНАРЯДЫ =====================================
func _spawn_projectile(from: Vector3, dir: Vector3, spd: float, dmg: float, col: Color, radius: float = 0.16) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.position = from
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proj_root.add_child(mi)

	projectiles.append({"node": mi, "vel": dir * spd, "dmg": dmg, "life": 3.0, "col": col})


func _update_projectiles(delta: float) -> void:
	var pp := player.global_position + Vector3(0, 1.0, 0)
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		var node: Node3D = p.node
		if node == null or not is_instance_valid(node):
			projectiles.remove_at(i); i -= 1; continue
		var prev: Vector3 = node.position
		node.position += p.vel * delta
		p.life -= delta
		var pos: Vector3 = node.position
		var dead := false
		var hitpos := pos
		var hitnrm := Vector3.UP
		# столкновение с укрытиями / стенами / полом
		var q := PhysicsRayQueryParameters3D.create(prev, pos, LAYER_WORLD, [])
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			dead = true
			hitpos = wh.position
			hitnrm = wh.get("normal", Vector3.UP)
		elif p.life <= 0.0 or absf(pos.x) > ROOM_HX or absf(pos.z) > ROOM_HZ or pos.y < 0.0 or pos.y > ROOM_H:
			dead = true
			hitpos = pos
		elif phase == Phase.PLAY and pos.distance_to(pp) < 1.0:
			_damage_player(p.dmg)
			dead = true
			hitpos = pos
		elif phase == Phase.PLAY:
			var handled := false
			for t in turrets:
				if t.alive and is_instance_valid(t.head) and pos.distance_to(t.head.global_position) < 1.1:
					_damage_turret(t, p.dmg)
					dead = true
					hitpos = pos
					handled = true
					break
			if not handled:
				for al in allies:
					if is_instance_valid(al.body) and pos.distance_to(al.body.global_position + Vector3(0, 1.0, 0)) < 0.9:
						_damage_ally(al, p.dmg)
						dead = true
						hitpos = pos
						break
		if dead:
			_impact(hitpos, hitnrm, p.col)
			node.queue_free()
			projectiles.remove_at(i)
		i -= 1


# ============================== ВОЛНЫ =======================================
func _update_waves(delta: float) -> void:
	# насыщающая кривая: усиление растёт с волной, но плавно выходит на потолок
	var raw := maxf(0.0, float(wave - 1)) * POWER_PER_WAVE
	power = raw / (1.0 + raw / POWER_CAP)
	if wave_break:
		if awaiting_choice:
			choice_t -= delta
			lbl_sub.text = choice_lines + "\nАвто-выбор через %d с" % int(ceil(choice_t))
			if choice_t <= 0.0:
				_auto_pick()
			return
		break_t -= delta
		if break_t <= 0.0:
			wave_break = false
			_start_wave(wave + 1)
		return

	# спавн
	if to_spawn > 0:
		spawn_t -= delta
		if spawn_t <= 0.0 and enemies_alive < 16:
			_spawn_enemy(_pick_kind())
			to_spawn -= 1
			spawn_t = clampf(1.1 - float(wave) * 0.03, 0.35, 1.1)

	# редкий idle-радиообмен во время боя
	idle_radio_t -= delta
	if idle_radio_t <= 0.0:
		idle_radio_t = rng.randf_range(12.0, 18.0)
		if enemies_alive > 0:
			_idle_radio()

	# волна зачищена?
	if to_spawn <= 0 and enemies_alive <= 0:
		_wave_clear()


func _start_wave(n: int) -> void:
	wave = n
	to_spawn = 3 + n * 2
	if to_spawn > 18:
		to_spawn = 18
	spawn_t = 1.5
	# пополнение и лечение отряда SG-1
	while allies.size() < ALLY_COUNT:
		_spawn_ally()
	for al in allies:
		al.hp = minf(al.max_hp, al.hp + 40.0)
	_sfx("gate_open")
	if n % BOSS_EVERY == 0:
		_spawn_enemy("boss")
		_set_center("ВОЛНА %d — БОСС" % n, "Из врат выходит Гоа'улд!")
		_radio_ally("TEAL'C", "Это Гоа'улд. Будьте осторожны, O'Neill.")
		_play_cutscene("boss")
	else:
		_set_center("ВОЛНА %d" % n, "Врата активируются…")
		if n % 2 == 0:
			_radio_ally("CARTER", "Врата активны — движутся Джаффа!")
		else:
			_radio_ally("TEAL'C", "Они идут. Держите строй.")
	_fade_center(2.0)


func _wave_clear() -> void:
	wave_break = true
	break_t = 3.0
	var bonus := 250 + wave * 50
	score += bonus
	_w().mag = _w_mag_size()
	reloading = false
	grenade_count = max_grenades
	health = minf(max_health, health + 15.0)
	low_warned = false
	for t in turrets:
		if t.alive:
			t.hp = minf(t.max_hp, t.hp + 40.0)
	_sfx("wave_clear")
	if wave % 2 == 0:
		_radio_ally("TEAL'C", "Сектор чист. Хорошо поработали.")
	else:
		_radio_ally("CARTER", "Неплохо, командир. Перегруппируемся.")
	_roll_upgrades()


# ============================== УЛУЧШЕНИЯ ===================================
const UPGRADES := {
	"hp": ["БРОНЯ", "+30 к макс. здоровью, полный ремонт"],
	"dmg": ["РАЗРЫВНЫЕ", "+25% урона пуль"],
	"rof": ["СКАТ", "+18% к темпу огня"],
	"mag": ["МАГАЗИН", "+12 патронов в магазине"],
	"reload": ["ЛОВКИЕ РУКИ", "-25% времени перезарядки"],
	"speed": ["СЕРУМ", "+15% к скорости бега"],
	"grenade": ["АРСЕНАЛ", "+2 гранаты и пополнение"],
	"lifesteal": ["РЕГЕНЕРАЦИЯ", "+8 HP за каждое убийство"],
}


func _roll_upgrades() -> void:
	var pool: Array = UPGRADES.keys()
	pool.shuffle()
	upgrade_choices.clear()
	for i in 3:
		if i < pool.size():
			upgrade_choices.append(String(pool[i]))
	awaiting_choice = true
	choice_t = CHOICE_TIME
	var lines := ""
	for i in upgrade_choices.size():
		var u: Array = UPGRADES[upgrade_choices[i]]
		lines += "%d) %s — %s\n" % [i + 1, u[0], u[1]]
	choice_lines = "ВЫБЕРИТЕ УЛУЧШЕНИЕ (клавиши 1–3):\n" + lines
	_set_center("ВОЛНА %d ОТБИТА" % wave, choice_lines)


func _auto_pick() -> void:
	if upgrade_choices.is_empty():
		awaiting_choice = false
		return
	_apply_upgrade(upgrade_choices[rng.randi() % upgrade_choices.size()])


func _apply_upgrade(id: String) -> void:
	match id:
		"hp":
			max_health += 30.0
			health = max_health
		"dmg":
			dmg_mult *= 1.25
		"rof":
			rof_mult = maxf(0.4, rof_mult * 0.82)
		"mag":
			mag_bonus += 12
		"reload":
			reload_mult = maxf(0.4, reload_mult * 0.75)
		"speed":
			speed_mult *= 1.15
		"grenade":
			max_grenades += 2
			grenade_count = max_grenades
		"lifesteal":
			lifesteal += 8.0
	awaiting_choice = false
	upgrade_choices.clear()
	_sfx("upgrade")
	var u: Array = UPGRADES[id]
	_set_center("УЛУЧШЕНИЕ: %s" % u[0], u[1])
	_fade_center(1.6)


# ============================== ГРАНАТЫ =====================================
func _throw_grenade() -> void:
	if phase != Phase.PLAY or grenade_count <= 0 or grenade_cd > 0.0:
		return
	grenade_count -= 1
	grenade_cd = 0.6
	_sfx("throw")
	if rng.randf() < 0.5:
		_radio("ВЫ", "Граната!")
	var fwd := -camera.global_transform.basis.z
	var from := camera.global_position + fwd * 0.6
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	mi.material_override = _mat(Color(0.2, 0.3, 0.15), 0.6, 0.3, Color(0.2, 1.0, 0.3), 1.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = from
	fx_root.add_child(mi)
	grenades.append({"node": mi, "vel": fwd * GRENADE_SPEED + Vector3(0, 4.5, 0), "fuse": 2.2})


func _update_grenades(delta: float) -> void:
	var i := grenades.size() - 1
	while i >= 0:
		var g: Dictionary = grenades[i]
		var node: Node3D = g.node
		if node == null or not is_instance_valid(node):
			grenades.remove_at(i); i -= 1; continue
		g.vel.y -= GRAV * delta
		node.position += g.vel * delta
		node.rotate(Vector3(1, 0, 0), delta * 9.0)
		g.fuse -= delta
		var pos: Vector3 = node.position
		if g.fuse <= 0.0 or pos.y <= 0.2 or pos.y >= ROOM_H - 0.4 or absf(pos.x) >= ROOM_HX - 0.4 or absf(pos.z) >= ROOM_HZ - 0.4:
			_explode(pos)
			node.queue_free()
			grenades.remove_at(i)
		i -= 1


func _explode(pos: Vector3) -> void:
	_sfx("explode")
	_explosion_fx(pos)
	var k := enemies.size() - 1
	while k >= 0:
		var d: Dictionary = enemies[k]
		if is_instance_valid(d.body):
			var c: Vector3 = d.body.global_position + Vector3(0, 1.0 * d.sc, 0)
			var dist := pos.distance_to(c)
			if dist < GRENADE_R:
				if d.kind == "boss" and d.shield_on:
					_shield_hit_fx(d, c)
				else:
					d.hp -= GRENADE_DMG * (1.0 - dist / GRENADE_R)
					d.hitflash = 1.0
					if d.hp <= 0.0:
						_kill_enemy(k)
		k -= 1
	var pd := pos.distance_to(player.global_position)
	if pd < GRENADE_R + 3.0:
		shake = clampf(shake + (1.0 - pd / (GRENADE_R + 3.0)), 0.0, 1.2)


func _explosion_fx(pos: Vector3) -> void:
	if _fx_full():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var mat := _emissive(Color(1.0, 0.6, 0.2), 4.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.6, 0.3)
	lt.light_energy = 9.0
	lt.omni_range = 16.0
	lt.shadow_enabled = false
	mi.add_child(lt)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 11.0, 0.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(lt, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)


func _reset_game() -> void:
	_clear_entities()
	power = 0.0
	_build_turrets()   # восстановить разрушенные турели к новой игре
	score = 0; wave = 0; kills = 0
	max_health = 100.0
	dmg_mult = 1.0; rof_mult = 1.0; reload_mult = 1.0; mag_bonus = 0
	speed_mult = 1.0; lifesteal = 0.0
	cur_weapon = 0
	for ws in weapon_state:
		ws.mag = ws.base_mag
	max_grenades = 3; grenade_count = 3; grenade_cd = 0.0
	awaiting_choice = false; upgrade_choices.clear()
	shake = 0.0
	radio_log.clear(); radio_cd = 0.0; idle_radio_t = 10.0; low_warned = false
	choice_t = 0.0; choice_lines = ""
	health = max_health
	reloading = false; reload_t = 0.0; fire_cd = 0.0
	firing = false; dmg_flash = 0.0
	to_spawn = 0; enemies_alive = 0; spawn_t = 0.0
	wave_break = true; break_t = 2.5   # короткая пауза «приготовиться», затем волна 1
	yaw = 0.0; pitch = 0.0
	player.position = Vector3(0, 0.5, 14.0)
	player.velocity = Vector3.ZERO
	vel_y = 0.0
	cam_fps = true
	_switch_camera()
	# wave = 0 -> _update_waves сам вызовет _start_wave(1) после брейка


func _clear_entities() -> void:
	for d in enemies:
		if is_instance_valid(d.body): d.body.queue_free()
	enemies.clear(); enemies_alive = 0
	for al in allies:
		if is_instance_valid(al.body): al.body.queue_free()
	allies.clear()
	for p in projectiles:
		if is_instance_valid(p.node): p.node.queue_free()
	projectiles.clear()
	for g in grenades:
		if is_instance_valid(g.node): g.node.queue_free()
	grenades.clear()


func _game_over() -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	firing = false
	_capture(false)
	_sfx("gameover")
	dmg_flash = 1.0
	if score > best:
		best = score
		_save_best()
	_set_center("ВЫ ПОГИБЛИ", "Волн: %d    Убийств: %d    Очки: %d    Рекорд: %d\nЛКМ или R — начать заново" % [wave, kills, score, best])


# ============================== КАМЕРА / ВИД ================================
func _switch_camera() -> void:
	soldier.visible = not cam_fps
	weapon_view.visible = cam_fps
	camera.fov = 78.0 if cam_fps else 70.0


func _update_camera(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 2.5)
	var shk := Vector3.ZERO
	if shake > 0.001:
		shk = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake * 0.14
	if cam_fps:
		var b := sin(bob) * 0.03 * (1.0 if player.velocity.length() > 1.0 else 0.0)
		camera.position = Vector3(0, b, 0) + shk
		camera.rotation.z = shk.x * 0.06
		# отдача
		cam_pivot.rotation.x = pitch + recoil * 0.05
		weapon_view.position = Vector3(0.28, -0.26 + b * 0.5, -0.45) + Vector3(0, 0, recoil * 0.06)
		weapon_view.rotation = Vector3(0.0, 0.10, 0.0)
	else:
		cam_pivot.rotation.x = pitch
		var target := Vector3(0, 0.5, 3.2)
		var to_world := cam_pivot.global_transform * target
		var q := PhysicsRayQueryParameters3D.create(cam_pivot.global_position, to_world, LAYER_WORLD, [player.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			camera.position = target
		else:
			var lp: Vector3 = cam_pivot.global_transform.affine_inverse() * hit.position
			camera.position = lp * 0.88
		camera.position += shk
		camera.rotation.z = shk.x * 0.06


# ============================== ЭФФЕКТЫ =====================================
func _muzzle_flash() -> void:
	_muzzle_flash_at(_active_muzzle())


func _muzzle_flash_at(pos: Vector3) -> void:
	shoot_light.global_position = pos
	shoot_light.light_energy = 4.0
	var tw := create_tween()
	tw.tween_property(shoot_light, "light_energy", 0.0, 0.07)
	if _fx_full():
		return

	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14; sm.height = 0.28
	mi.mesh = sm
	var mat := _emissive(Color(1.0, 0.85, 0.4), 5.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	var t2 := create_tween()
	t2.set_parallel(true)
	t2.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.08)
	t2.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	t2.chain().tween_callback(mi.queue_free)


func _fx_full() -> bool:
	return fx_root.get_child_count() > 140


func _tracer(from: Vector3, to: Vector3) -> void:
	if _fx_full():
		return
	var dir := to - from
	var len := dir.length()
	if len < 0.05:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02; cm.bottom_radius = 0.02; cm.height = 1.0
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (from + to) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, dir.normalized())
	mi.scale = Vector3(1, len, 1)
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.06)
	tw.tween_callback(mi.queue_free)


func _impact(pos: Vector3, normal: Vector3, col: Color) -> void:
	if _fx_full():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1; sm.height = 0.2
	mi.mesh = sm
	var mat := _emissive(col, 4.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 3.0, 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(mi.queue_free)


func _death_fx(pos: Vector3) -> void:
	if _fx_full():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0
	mi.mesh = sm
	var mat := _emissive(Color(1.0, 0.5, 0.2), 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 4.0, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


func _gate_spawn_fx(pos: Vector3) -> void:
	if _fx_full():
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7; tm.outer_radius = 1.0; tm.rings = 24; tm.ring_segments = 10
	mi.mesh = tm
	var mat := _emissive(COL_CYAN, 4.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 3.0, 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(mi.queue_free)


# ============================== HUD =========================================
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	hud_layer = hud
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = _vignette_shader()
	vig.material = vignette_mat
	hud_root.add_child(vig)

	# верх слева — очки/волна
	var p1 := _panel(Vector2(16, 14), Vector2(300, 76))
	hud_root.add_child(p1)
	lbl_score = _label(p1, Vector2(14, 8), "ОЧКИ 0", 22, COL_WHITE)
	lbl_wave = _label(p1, Vector2(14, 40), "ВОЛНА 1", 15, COL_CYAN)

	# верх справа — враги
	var p2 := _panel(Vector2.ZERO, Vector2(240, 50))
	hud_root.add_child(p2)
	p2.anchor_left = 1.0; p2.anchor_right = 1.0
	p2.offset_left = -256.0; p2.offset_right = -16.0; p2.offset_top = 14.0; p2.offset_bottom = 64.0
	lbl_enemy = _label(p2, Vector2(14, 12), "ВРАГИ: 0", 18, COL_ORANGE)

	# низ слева — здоровье
	var p3 := _panel(Vector2(16, -96), Vector2(300, 80))
	hud_root.add_child(p3)
	p3.anchor_top = 1.0; p3.anchor_bottom = 1.0
	p3.offset_top = -96.0; p3.offset_bottom = -16.0
	_label(p3, Vector2(14, 8), "ЗДОРОВЬЕ", 11, Color(0.7, 0.85, 0.95))
	lbl_health_num = _label(p3, Vector2(150, 6), "100 / 100", 14, COL_WHITE)
	lbl_health_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_health = _bar(p3, Vector2(14, 26), 272.0, Color(0.3, 1.0, 0.45))

	# низ справа — патроны и гранаты
	var p4 := _panel(Vector2.ZERO, Vector2(280, 104))
	hud_root.add_child(p4)
	p4.anchor_left = 1.0; p4.anchor_right = 1.0; p4.anchor_top = 1.0; p4.anchor_bottom = 1.0
	p4.offset_left = -296.0; p4.offset_right = -16.0; p4.offset_top = -120.0; p4.offset_bottom = -16.0
	lbl_ammo = _label(p4, Vector2(14, 6), "30 / ∞", 26, COL_WHITE)
	lbl_grenade = _label(p4, Vector2(14, 42), "ГРАНАТЫ: 3", 15, Color(0.6, 1.0, 0.6))
	bar_reload = _bar(p4, Vector2(14, 68), 252.0, COL_CYAN)

	# верх по центру — здоровье босса
	boss_panel = _panel(Vector2.ZERO, Vector2(400, 46))
	hud_root.add_child(boss_panel)
	boss_panel.anchor_left = 0.5; boss_panel.anchor_right = 0.5
	boss_panel.offset_left = -200.0; boss_panel.offset_right = 200.0
	boss_panel.offset_top = 14.0; boss_panel.offset_bottom = 60.0
	_label(boss_panel, Vector2(14, 3), "ГОА'УЛД", 12, Color(1.0, 0.85, 0.3))
	lbl_boss_num = _label(boss_panel, Vector2(250, 2), "", 12, Color(1.0, 0.85, 0.3))
	lbl_boss_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_boss = _bar(boss_panel, Vector2(14, 22), 372.0, Color(1.0, 0.3, 0.2))
	boss_panel.visible = false

	# низ по центру — статус отряда SG-1
	var p5 := _panel(Vector2.ZERO, Vector2(300, 64))
	hud_root.add_child(p5)
	p5.anchor_left = 0.5; p5.anchor_right = 0.5; p5.anchor_top = 1.0; p5.anchor_bottom = 1.0
	p5.offset_left = -150.0; p5.offset_right = 150.0; p5.offset_top = -80.0; p5.offset_bottom = -16.0
	for i in 2:
		var ln := _label(p5, Vector2(10, 5 + i * 28), ALLY_NAMES[i], 12, Color(0.7, 0.9, 0.7))
		ln.size = Vector2(64, 16)
		ally_lbls.append(ln)
		ally_bars.append(_bar(p5, Vector2(78, 7 + i * 28), 130.0, Color(0.4, 0.9, 0.5)))
		var num := _label(p5, Vector2(214, 6 + i * 28), "", 11, Color(0.8, 0.95, 0.8))
		num.size = Vector2(80, 14)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ally_nums.append(num)

	# слева выше здоровья — лог радиообмена SG-1
	var rp := _panel(Vector2.ZERO, Vector2(430, 96))
	hud_root.add_child(rp)
	rp.anchor_left = 0.0; rp.anchor_right = 0.0; rp.anchor_top = 1.0; rp.anchor_bottom = 1.0
	rp.offset_left = 16.0; rp.offset_right = 446.0; rp.offset_top = -200.0; rp.offset_bottom = -104.0
	for i in 3:
		var rl := _label(rp, Vector2(10, 6 + i * 30), "", 13, COL_WHITE)
		rl.size = Vector2(410, 26)
		radio_lbls.append(rl)

	# центр
	lbl_center = Label.new()
	lbl_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_center.position = Vector2(-450, 130); lbl_center.size = Vector2(900, 62)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_center.add_theme_font_size_override("font_size", 44)
	lbl_center.add_theme_color_override("font_color", COL_WHITE)
	lbl_center.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl_center.add_theme_constant_override("shadow_offset_y", 3)
	lbl_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(lbl_center)

	lbl_sub = Label.new()
	lbl_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_sub.position = Vector2(-450, 196); lbl_sub.size = Vector2(900, 130)
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sub.add_theme_font_size_override("font_size", 18)
	lbl_sub.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(lbl_sub)

	reticle = _Reticle.new()
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-40, -40); reticle.size = Vector2(80, 80)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(reticle)

	# подсказка взаимодействия с турелью
	lbl_turret_hint = Label.new()
	lbl_turret_hint.anchor_left = 0.0; lbl_turret_hint.anchor_right = 1.0
	lbl_turret_hint.anchor_top = 1.0; lbl_turret_hint.anchor_bottom = 1.0
	lbl_turret_hint.offset_top = -250.0; lbl_turret_hint.offset_bottom = -215.0
	lbl_turret_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_turret_hint.add_theme_font_size_override("font_size", 15)
	lbl_turret_hint.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	lbl_turret_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl_turret_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_turret_hint.visible = false
	hud_root.add_child(lbl_turret_hint)

	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = _flash_shader()
	flash.material = flash_mat
	hud_root.add_child(flash)


func _update_hud(delta: float) -> void:
	lbl_score.text = "ОЧКИ %d   (РЕКОРД %d)" % [score, best]
	lbl_wave.text = "ВОЛНА %d" % wave
	var remaining := enemies_alive + to_spawn
	lbl_enemy.text = "ВРАГИ: %d" % remaining
	var w := _w()
	lbl_ammo.text = ("ПЕРЕЗАРЯДКА" if reloading else "%s  %d / %d   [Q]" % [String(w.name), int(w.mag), _w_mag_size()])
	lbl_ammo.add_theme_color_override("font_color", COL_ORANGE if (reloading or int(w.mag) == 0) else COL_WHITE)
	lbl_grenade.text = "ГРАНАТЫ: %d   [G]" % grenade_count
	lbl_grenade.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if grenade_count > 0 else Color(0.5, 0.4, 0.4))
	bar_health.size.x = 272.0 * clampf(health / max_health, 0.0, 1.0)
	bar_health.color = Color(0.3, 1.0, 0.45).lerp(Color(1.0, 0.2, 0.15), 1.0 - clampf(health / max_health, 0.0, 1.0))
	lbl_health_num.text = "%d / %d" % [int(health), int(max_health)]
	bar_reload.size.x = 252.0 * (1.0 - clampf(reload_t / _w_reload(), 0.0, 1.0)) if reloading else 0.0

	var bossd := _find_boss()
	if bossd.is_empty():
		boss_panel.visible = false
		lbl_boss_num.text = ""
	else:
		boss_panel.visible = true
		bar_boss.size.x = 372.0 * clampf(float(bossd.hp) / float(bossd.max_hp), 0.0, 1.0)
		lbl_boss_num.text = "%d / %d" % [int(bossd.hp), int(bossd.max_hp)]

	for i in 2:
		if i < allies.size():
			var al: Dictionary = allies[i]
			ally_lbls[i].text = al.name
			ally_lbls[i].add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			ally_bars[i].size.x = 130.0 * clampf(float(al.hp) / float(al.max_hp), 0.0, 1.0)
			ally_nums[i].text = "%d/%d" % [int(al.hp), int(al.max_hp)]
		else:
			ally_lbls[i].text = "—"
			ally_lbls[i].add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
			ally_bars[i].size.x = 0.0
			ally_nums[i].text = ""

	# подсказка у ближайшей турели
	var nt := _nearest_turret()
	if phase == Phase.PLAY and not nt.is_empty():
		lbl_turret_hint.visible = true
		var st := "ЦЕЛА" if nt.hp >= nt.max_hp - 0.5 else "ПОВРЕЖДЕНА"
		lbl_turret_hint.text = "ТУРЕЛЬ ур.%d %s %.0f/%.0f   |   [F] ремонт %d   |   [T] апгрейд %d" % [nt.lvl, st, nt.hp, nt.max_hp, TURRET_REPAIR_COST, TURRET_UPGRADE_COST * nt.lvl]
	else:
		lbl_turret_hint.visible = false

	dmg_flash = maxf(0.0, dmg_flash - delta * 2.0)
	vignette_mat.set_shader_parameter("damage", dmg_flash)
	reticle.queue_redraw()

	# радиообмен: затухание и вывод лога
	radio_cd = maxf(0.0, radio_cd - delta)
	var ri := radio_log.size() - 1
	while ri >= 0:
		radio_log[ri].t -= delta
		if radio_log[ri].t <= 0.0:
			radio_log.remove_at(ri)
		ri -= 1
	for i in 3:
		if i < radio_log.size():
			var e: Dictionary = radio_log[i]
			radio_lbls[i].text = "[%s] %s" % [e.sp, e.tx]
			radio_lbls[i].modulate.a = clampf(float(e.t) / 1.0, 0.0, 1.0)
			radio_lbls[i].add_theme_color_override("font_color", _radio_color(e.sp))
		else:
			radio_lbls[i].text = ""


func _radio(speaker: String, text: String) -> void:
	if radio_cd > 0.0:
		return
	radio_cd = 1.4
	radio_log.append({"sp": speaker, "tx": text, "t": 6.0})
	while radio_log.size() > 3:
		radio_log.remove_at(0)
	_sfx("radio")
	if voice_cd <= 0.0:
		voice_cd = 2.5
		_voice(speaker, text)


# Реплику союзника озвучивает только ЖИВОЙ: если указанный погиб —
# эфир берёт выживший напарник, а если никого не осталось — сам игрок.
func _radio_ally(speaker: String, text: String) -> void:
	if _ally_alive(speaker):
		_radio(speaker, text)
		return
	for al in allies:
		if al.hp > 0.0:
			_radio(al.name, text)
			return
	_radio("ВЫ", text)


func _ally_alive(nm: String) -> bool:
	for al in allies:
		if al.name == nm and al.hp > 0.0:
			return true
	return false


# Процедурная "речь" (вокoder-подобный синтез): слогы с формантами под гласные,
# шум согласных, индивидуальная высота тона у каждого персонажа.
func _voice(sp: String, text: String) -> void:
	var rate := 10000
	var f0 := 150.0
	match sp:
		"CARTER": f0 = 205.0
		"TEAL'C": f0 = 100.0
		"ВЫ": f0 = 145.0
	var syl := clampi(int(text.length() / 6), 3, 10)
	var total := float(syl) * 0.19 + 0.15
	var n := int(rate * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	var idx := 0
	var phase := 0.0
	for s in syl:
		var dur := rng.randf_range(0.11, 0.17)
		var gap := rng.randf_range(0.02, 0.05)
		var ff := f0 * rng.randf_range(0.9, 1.15)
		var f1 := rng.randf_range(300.0, 850.0)
		var f2 := rng.randf_range(900.0, 2300.0)
		var g0 := 1.0 + 1.6 * exp(-pow((ff - f1) / 300.0, 2)) + 1.1 * exp(-pow((ff - f2) / 400.0, 2))
		var g1 := 0.5 + 1.6 * exp(-pow((ff * 2 - f1) / 300.0, 2)) + 1.1 * exp(-pow((ff * 2 - f2) / 400.0, 2))
		var g2 := 0.33 + 1.6 * exp(-pow((ff * 3 - f1) / 300.0, 2)) + 1.1 * exp(-pow((ff * 3 - f2) / 400.0, 2))
		var ns := int(rate * dur)
		for i in ns:
			var x := float(i) / float(ns)
			var env := sin(x * PI)
			phase += TAU * ff / rate
			var v := (g0 * sin(phase) + g1 * sin(phase * 2.0) + g2 * sin(phase * 3.0)) * env * 0.12
			if x < 0.15:
				v += (rng.randf() * 2.0 - 1.0) * 0.06 * (1.0 - x / 0.15)
			if idx < n:
				data.encode_s16(idx * 2, int(clampf(v, -1.0, 1.0) * 32767))
				idx += 1
		var ng := int(rate * gap)
		for i in ng:
			if idx < n:
				data.encode_s16(idx * 2, 0)
				idx += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	snd_voice.stream = wav
	snd_voice.play()


func _radio_color(sp: String) -> Color:
	match sp:
		"CARTER": return Color(0.5, 0.8, 1.0)
		"TEAL'C": return Color(1.0, 0.85, 0.4)
	return Color(0.8, 1.0, 0.8)


const IDLE_LINES := [
	["CARTER", "Держу прицел на фланге."],
	["TEAL'C", "Джаффа не пройдут."],
	["CARTER", "Боезапас в норме, командир."],
	["TEAL'C", "Слышу движение у врат."],
	["CARTER", "Прикройте левый фланг."],
	["TEAL'C", "O'Neill, за мной."],
]


func _idle_radio() -> void:
	var l: Array = IDLE_LINES[rng.randi() % IDLE_LINES.size()]
	_radio_ally(String(l[0]), String(l[1]))


# ============================== КАТ-СЦЕНЫ ===================================
func _build_cutscene() -> void:
	cut_cam = Camera3D.new()
	cut_cam.name = "CutCamera"
	cut_cam.fov = 70.0
	cut_cam.near = 0.05
	cut_cam.far = 400.0
	add_child(cut_cam)
	cut_cam.current = false

	# отдельный слой поверх HUD: letterbox и подпись видны, когда сам HUD скрыт
	cut_root = Control.new()
	cut_root.name = "CutRoot"
	cut_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	cut_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(cut_root)

	letter_top = ColorRect.new()
	letter_top.color = Color(0, 0, 0, 1)
	letter_top.anchor_left = 0.0; letter_top.anchor_right = 1.0
	letter_top.anchor_top = 0.0; letter_top.anchor_bottom = 0.0
	letter_top.offset_top = 0.0; letter_top.offset_bottom = 90.0
	letter_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cut_root.add_child(letter_top)
	letter_bot = ColorRect.new()
	letter_bot.color = Color(0, 0, 0, 1)
	letter_bot.anchor_left = 0.0; letter_bot.anchor_right = 1.0
	letter_bot.anchor_top = 1.0; letter_bot.anchor_bottom = 1.0
	letter_bot.offset_top = -90.0; letter_bot.offset_bottom = 0.0
	letter_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cut_root.add_child(letter_bot)
	cut_label = Label.new()
	cut_label.anchor_left = 0.0; cut_label.anchor_right = 1.0
	cut_label.anchor_top = 1.0; cut_label.anchor_bottom = 1.0
	cut_label.offset_top = -150.0; cut_label.offset_bottom = -100.0
	cut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cut_label.add_theme_font_size_override("font_size", 20)
	cut_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	cut_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	cut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cut_root.add_child(cut_label)
	letter_top.visible = false
	letter_bot.visible = false
	cut_label.visible = false


func _play_cutscene(kind: String) -> void:
	cutscene_active = true
	cut_t = 0.0
	cut_points.clear()
	if kind == "intro":
		cut_dur = 4.5
		cut_points.append({"pos": Vector3(0, 7, 22), "look": Vector3(0, 3, -25)})
		cut_points.append({"pos": Vector3(0, 3.2, 6), "look": Vector3(0, 3.6, -25)})
		cut_label.text = "SGC, горный комплекс Шайенн. Звёздные врата активированы."
	else:
		cut_dur = 3.5
		cut_points.append({"pos": Vector3(7, 3.4, -14), "look": GATE_POS})
		cut_points.append({"pos": Vector3(-6, 2.6, -12), "look": GATE_POS})
		cut_label.text = "Из врат выходит Гоа'улд. Приготовьтесь."
	cut_cam.current = true
	camera.current = false
	hud_root.visible = false
	letter_top.visible = true
	letter_bot.visible = true
	cut_label.visible = true
	_sfx("gate_open")


func _update_cutscene(delta: float) -> void:
	cut_t += delta
	var n := cut_points.size()
	if n >= 2:
		var f := clampf(cut_t / cut_dur, 0.0, 1.0)
		var x := f * (n - 1)
		var i := int(floor(x))
		if i > n - 2:
			i = n - 2
		var u := x - float(i)
		u = u * u * (3.0 - 2.0 * u)
		var p0: Vector3 = cut_points[i].pos
		var p1: Vector3 = cut_points[i + 1].pos
		var l0: Vector3 = cut_points[i].look
		var l1: Vector3 = cut_points[i + 1].look
		cut_cam.position = p0.lerp(p1, u)
		var lk := l0.lerp(l1, u)
		if cut_cam.global_position.distance_to(lk) > 0.05:
			cut_cam.look_at(lk, Vector3.UP)
	if cut_t >= cut_dur:
		_end_cutscene()


func _end_cutscene() -> void:
	cutscene_active = false
	cut_cam.current = false
	camera.current = true
	hud_root.visible = true
	letter_top.visible = false
	letter_bot.visible = false
	cut_label.visible = false


func _find_boss() -> Dictionary:
	for d in enemies:
		if d.kind == "boss" and is_instance_valid(d.body):
			return d
	return {}


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.10, 0.6)
	sb.border_color = Color(0.3, 0.8, 1.0, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(parent: Control, pos: Vector2, text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(parent.size.x - pos.x - 8, float(fsize) + 12)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, w: float, col: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.1)
	bg.position = pos
	bg.size = Vector2(w, 12)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = pos
	fill.size = Vector2(w, 12)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)
	return fill


func _set_center(t: String, s: String) -> void:
	if center_tw != null and center_tw.is_valid():
		center_tw.kill()
	lbl_center.text = t
	lbl_sub.text = s
	lbl_center.modulate.a = 1.0
	lbl_sub.modulate.a = 1.0


func _fade_center(dur: float) -> void:
	if center_tw != null and center_tw.is_valid():
		center_tw.kill()
	center_tw = create_tween()
	center_tw.set_parallel(true)
	center_tw.tween_property(lbl_center, "modulate:a", 0.0, dur)
	center_tw.tween_property(lbl_sub, "modulate:a", 0.0, dur)


func _flash(power: float) -> void:
	flash_mat.set_shader_parameter("amount", 0.0)
	var tw := create_tween()
	tw.tween_property(flash_mat, "shader_parameter/amount", power, 0.06)
	tw.tween_property(flash_mat, "shader_parameter/amount", 0.0, 0.5).set_trans(Tween.TRANS_EXPO)


# ============================== ЗВУК ========================================
func _build_audio() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = 22050.0
	g.buffer_length = 0.2
	snd_amb = AudioStreamPlayer.new()
	snd_amb.stream = g
	snd_amb.volume_db = -30.0
	add_child(snd_amb)
	snd_amb.play()
	gen = snd_amb.get_stream_playback()

	snd_sfx = AudioStreamPlayer.new()
	snd_sfx.volume_db = -4.0
	add_child(snd_sfx)
	sfx_players.append(snd_sfx)
	for i in 2:
		var sp := AudioStreamPlayer.new()
		sp.volume_db = -4.0
		add_child(sp)
		sfx_players.append(sp)

	snd_voice = AudioStreamPlayer.new()
	snd_voice.volume_db = -6.0
	add_child(snd_voice)


func _update_audio(delta: float) -> void:
	if gen == null:
		return
	var frames := int(22050.0 * delta) + 1
	var t := float(Time.get_ticks_msec()) * 0.001
	var active := 1.0 if phase == Phase.PLAY else 0.5
	for i in frames:
		var s := sin(t * 40.0 + float(i) * 0.01) * 0.25 * active
		s += sin(t * 81.0) * 0.08 * active
		s += (rng.randf() - 0.5) * 0.02
		gen.push_frame(Vector2(s, s))


var sfx_bank := {}
var sfx_last := {}
var sfx_players := []
var sfx_pi := 0
const SFX_MIN_MS := {
	"shot": 45, "turret_shot": 70, "ally_shot": 90, "enemy_shot": 70,
	"hit_enemy": 45, "shield_hit": 60, "explode": 60, "staff_charge": 80,
}


func _sfx(kind: String) -> void:
	var now := Time.get_ticks_msec()
	var min_ms: int = int(SFX_MIN_MS.get(kind, 0))
	var last: int = int(sfx_last.get(kind, 0))
	if now - last < min_ms:
		return
	sfx_last[kind] = now
	if not sfx_bank.has(kind):
		sfx_bank[kind] = [_gen_sfx(kind), _gen_sfx(kind)]
	var arr: Array = sfx_bank[kind]
	var wav: AudioStreamWAV = arr[rng.randi() % arr.size()]
	sfx_pi = (sfx_pi + 1) % sfx_players.size()
	var p: AudioStreamPlayer = sfx_players[sfx_pi]
	p.stream = wav
	p.play()


func _gen_sfx(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.2
	var vol := 0.5
	match kind:
		"shot": dur = 0.12; vol = 0.45
		"enemy_shot": dur = 0.18; vol = 0.35
		"hit_enemy": dur = 0.08; vol = 0.3
		"enemy_die": dur = 0.35; vol = 0.55
		"hurt": dur = 0.2; vol = 0.6
		"reload": dur = 0.12; vol = 0.3
		"reload_end": dur = 0.14; vol = 0.35
		"gate_open", "gate_spawn": dur = 0.6; vol = 0.5
		"wave_clear": dur = 0.5; vol = 0.5
		"gameover": dur = 1.0; vol = 0.8
		"boss_roar": dur = 0.9; vol = 0.7
		"boss_shot": dur = 0.3; vol = 0.5
		"boss_die": dur = 1.2; vol = 0.85
		"upgrade": dur = 0.35; vol = 0.45
		"throw": dur = 0.12; vol = 0.3
		"explode": dur = 0.6; vol = 0.85
		"staff_charge": dur = 0.25; vol = 0.4
		"shield_up": dur = 0.4; vol = 0.5
		"shield_down": dur = 0.3; vol = 0.45
		"shield_hit": dur = 0.1; vol = 0.3
		"boss_summon": dur = 0.7; vol = 0.6
		"ally_shot": dur = 0.1; vol = 0.25
		"ally_down": dur = 0.5; vol = 0.5
		"radio": dur = 0.16; vol = 0.3
		"turret_shot": dur = 0.09; vol = 0.3
		"shotgun": dur = 0.25; vol = 0.6
		"weapon_switch": dur = 0.15; vol = 0.4
		"deny": dur = 0.18; vol = 0.4
		"repair": dur = 0.3; vol = 0.45

	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var x := float(i) / float(n)
		var env := pow(1.0 - x, 2.0)
		var s := 0.0
		match kind:
			"shot":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 6.0) * 0.9 + sin(x * 120.0) * env * 0.3
			"enemy_shot":
				s = sin(x * (300.0 - x * 200.0) * TAU) * env * 0.5 + (rng.randf() * 2.0 - 1.0) * env * 0.2
			"hit_enemy":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 8.0) * 0.7
			"enemy_die":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 2.0) * 0.8 + sin(x * 60.0) * env * 0.4
			"hurt":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 3.0) * 0.8 + sin(x * 50.0) * env * 0.5
			"reload":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 10.0) * 0.5
			"reload_end":
				s = sin(x * 400.0 * TAU) * pow(1.0 - x, 6.0) * 0.4
			"gate_open", "gate_spawn":
				s = sin(x * 70.0 * (1.0 + x) * TAU) * env * 0.5 + (rng.randf() * 2.0 - 1.0) * env * 0.3
			"wave_clear":
				s = sin(x * 500.0 * TAU) * env * 0.3 + sin(x * 750.0 * TAU) * env * 0.2
			"gameover":
				s = sin(x * (200.0 - x * 150.0) * TAU) * env * 0.6 + (rng.randf() * 2.0 - 1.0) * env * 0.3
			"boss_roar":
				s = sin(x * (70.0 - x * 30.0) * TAU) * env * 0.6 + (rng.randf() * 2.0 - 1.0) * env * 0.3
			"boss_shot":
				s = sin(x * (420.0 - x * 260.0) * TAU) * env * 0.5 + (rng.randf() * 2.0 - 1.0) * env * 0.2
			"boss_die":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 1.5) * 0.9 + sin(x * (150.0 - x * 100.0) * TAU) * env * 0.6
			"upgrade":
				s = sin(x * 600.0 * TAU) * env * 0.3 + sin(x * 900.0 * TAU) * env * 0.25
			"throw":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 8.0) * 0.5
			"explode":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 1.8) * 0.95 + sin(x * 30.0) * env * 0.7
			"staff_charge":
				s = sin(x * (200.0 + x * 500.0) * TAU) * env * 0.4 + (rng.randf() * 2.0 - 1.0) * env * 0.15
			"shield_up":
				s = sin(x * (300.0 + x * 400.0) * TAU) * env * 0.4 + sin(x * 60.0) * env * 0.3
			"shield_down":
				s = sin(x * (500.0 - x * 300.0) * TAU) * env * 0.4
			"shield_hit":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 6.0) * 0.5 + sin(x * 800.0) * env * 0.2
			"boss_summon":
				s = sin(x * (90.0 + x * 60.0) * TAU) * env * 0.5 + (rng.randf() * 2.0 - 1.0) * env * 0.25
			"ally_shot":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 7.0) * 0.6 + sin(x * 140.0) * env * 0.2
			"ally_down":
				s = sin(x * (250.0 - x * 180.0) * TAU) * env * 0.5 + (rng.randf() * 2.0 - 1.0) * env * 0.3
			"radio":
				s = sin(x * 900.0 * TAU) * pow(1.0 - x, 4.0) * 0.3 + (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 2.0) * 0.15
			"turret_shot":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 9.0) * 0.7 + sin(x * 180.0) * env * 0.25
			"shotgun":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 4.0) * 0.9 + sin(x * 90.0) * env * 0.4
			"weapon_switch":
				s = (rng.randf() * 2.0 - 1.0) * pow(1.0 - x, 12.0) * 0.5 + sin(x * 300.0 * TAU) * pow(1.0 - x, 6.0) * 0.3
			"deny":
				s = sin(x * 120.0 * TAU) * pow(1.0 - x, 3.0) * 0.4 * (1.0 if fmod(x * 30.0, 1.0) < 0.5 else 0.2)
			"repair":
				s = sin(x * (400.0 + x * 500.0) * TAU) * env * 0.35 + (rng.randf() * 2.0 - 1.0) * env * 0.1
		var v := int(clampf(s * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 4, v)
		data.encode_s16(i * 4 + 2, v)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	wav.data = data
	return wav


# ============================== ПОСТРОЕНИЕ МИРА =============================
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.32, 0.45)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.12)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# основной свет сверху
	var top := DirectionalLight3D.new()
	top.rotation_degrees = Vector3(-70, 20, 0)
	top.light_color = Color(0.8, 0.85, 1.0)
	top.light_energy = 0.5
	top.shadow_enabled = true
	add_child(top)

	# лампы потолка
	for x in [-10.0, 0.0, 10.0]:
		for z in [-14.0, 0.0, 14.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, ROOM_H - 1.0, z)
			l.light_color = Color(0.75, 0.85, 1.0)
			l.light_energy = 1.1
			l.omni_range = 20.0
			l.shadow_enabled = false
			add_child(l)

	# вспышка выстрела (следует за дулом)
	shoot_light = OmniLight3D.new()
	shoot_light.light_color = Color(1.0, 0.85, 0.5)
	shoot_light.light_energy = 0.0
	shoot_light.omni_range = 8.0
	shoot_light.shadow_enabled = false
	add_child(shoot_light)


func _build_room() -> void:
	var world := StaticBody3D.new()
	world.collision_layer = LAYER_WORLD
	world.collision_mask = 0
	add_child(world)

	var floor_mat := _mat(Color(0.18, 0.20, 0.24), 0.9, 0.1)
	var wall_mat := _mat(Color(0.16, 0.19, 0.25), 0.85, 0.15)
	var crate_mat := _mat(Color(0.28, 0.26, 0.2), 0.8, 0.1)

	# пол
	_slab(world, Vector3(0, -0.5, 0), Vector3(ROOM_HX * 2, 1.0, ROOM_HZ * 2), floor_mat)
	# потолок
	_slab(world, Vector3(0, ROOM_H + 0.5, 0), Vector3(ROOM_HX * 2, 1.0, ROOM_HZ * 2), wall_mat)
	# стены
	_slab(world, Vector3(-ROOM_HX - 0.5, ROOM_H * 0.5, 0), Vector3(1.0, ROOM_H, ROOM_HZ * 2), wall_mat)
	_slab(world, Vector3(ROOM_HX + 0.5, ROOM_H * 0.5, 0), Vector3(1.0, ROOM_H, ROOM_HZ * 2), wall_mat)
	_slab(world, Vector3(0, ROOM_H * 0.5, -ROOM_HZ - 0.5), Vector3(ROOM_HX * 2, ROOM_H, 1.0), wall_mat)
	_slab(world, Vector3(0, ROOM_H * 0.5, ROOM_HZ + 0.5), Vector3(ROOM_HX * 2, ROOM_H, 1.0), wall_mat)

	# светящиеся полосы на стенах (декор)
	var strip := _emissive(Color(0.4, 0.7, 1.0), 2.0)
	for z in [-18.0, -6.0, 6.0, 18.0]:
		var s := _mesh(BoxMesh.new(), strip)
		s.scale = Vector3(0.2, 0.3, 4.0)
		s.position = Vector3(-ROOM_HX + 0.15, 3.0, z)
		add_child(s)
		var s2 := _mesh(BoxMesh.new(), strip)
		s2.scale = Vector3(0.2, 0.3, 4.0)
		s2.position = Vector3(ROOM_HX - 0.15, 3.0, z)
		add_child(s2)

	# ящики-укрытия
	var crates := [
		Vector3(-8, 0, 4), Vector3(8, 0, 4), Vector3(-6, 0, -6),
		Vector3(7, 0, -8), Vector3(0, 0, 6), Vector3(-12, 0, -2),
		Vector3(12, 0, -2), Vector3(3, 0, -14), Vector3(-4, 0, -16),
	]
	for c in crates:
		var sz := Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(1.4, 2.2), rng.randf_range(1.6, 2.6))
		_slab(world, c + Vector3(0, sz.y * 0.5, 0), sz, crate_mat)
		obstacles.append({"pos": c, "r": maxf(sz.x, sz.z) * 0.5})

	# декоративный постамент под вратами (БЕЗ коллизии — чтобы враги свободно выходили)
	var dais := _mesh(CylinderMesh.new(), _mat(Color(0.2, 0.23, 0.3), 0.7, 0.35, Color(0.05, 0.12, 0.18), 0.6))
	dais.scale = Vector3(9.0, 0.12, 9.0)
	dais.position = Vector3(0, 0.06, GATE_POS.z + 0.6)
	add_child(dais)


func _slab(parent: StaticBody3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	col.position = pos
	parent.add_child(col)
	var mi := _mesh(BoxMesh.new(), mat)
	mi.scale = size
	mi.position = pos
	add_child(mi)


func _build_gate() -> void:
	gate = Node3D.new()
	gate.name = "Stargate"
	gate.position = GATE_POS
	add_child(gate)

	var tm := TorusMesh.new()
	tm.inner_radius = GATE_R - 0.5
	tm.outer_radius = GATE_R
	tm.rings = 48
	tm.ring_segments = 18
	var ring := _mesh(tm, _mat(Color(0.42, 0.45, 0.52), 0.35, 0.9, Color(0.06, 0.12, 0.16), 0.8))
	ring.rotation_degrees = Vector3(90, 0, 0)
	gate.add_child(ring)

	var pm := PlaneMesh.new()
	pm.size = Vector2(GATE_R * 1.9, GATE_R * 1.9)
	var disc := MeshInstance3D.new()
	disc.mesh = pm
	horizon_mat = ShaderMaterial.new()
	horizon_mat.shader = _horizon_shader()
	horizon_mat.set_shader_parameter("time", 0.0)
	horizon_mat.set_shader_parameter("open", 0.6)
	horizon_mat.set_shader_parameter("speed", 1.0)
	disc.material_override = horizon_mat
	disc.rotation_degrees = Vector3(90, 0, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(disc)

	for i in 7:
		var ang := float(i) / 7.0 * TAU
		var cm := _emissive(Color(1.0, 0.45, 0.1), 2.2)
		var ch := _mesh(BoxMesh.new(), cm)
		ch.scale = Vector3(0.5, 0.5, 0.4)
		ch.position = Vector3(cos(ang) * (GATE_R + 0.15), sin(ang) * (GATE_R + 0.15), 0)
		ch.rotation = Vector3(0, 0, ang)
		gate.add_child(ch)
		chevrons.append(cm)

	gate_light = OmniLight3D.new()
	gate_light.light_color = COL_CYAN
	gate_light.light_energy = 3.0
	gate_light.omni_range = 22.0
	gate_light.shadow_enabled = false
	gate.add_child(gate_light)


var gate_open := 0.6
func _animate_gate(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var active := 1.0 if (phase == Phase.PLAY and not wave_break) else 0.35
	gate_open = lerpf(gate_open, active, delta * 3.0)
	horizon_mat.set_shader_parameter("time", t)
	horizon_mat.set_shader_parameter("open", gate_open)
	horizon_mat.set_shader_parameter("speed", 0.6 + active)
	gate_light.light_energy = lerpf(gate_light.light_energy, 1.5 + active * 3.0, delta * 3.0)
	for i in chevrons.size():
		chevrons[i].emission_energy_multiplier = 1.4 + sin(t * 3.0 + float(i)) * 0.8 * active + active


# ============================== СОЮЗНИКИ SG-1 ===============================
func _spawn_ally(_idx: int = 0) -> void:
	# первое свободное имя (чтобы не дублировать погибших)
	var used := []
	for al in allies:
		used.append(al.name)
	var name := ALLY_NAMES[0]
	var ni := 0
	for k in ALLY_NAMES.size():
		if not used.has(ALLY_NAMES[k]):
			name = ALLY_NAMES[k]
			ni = k
			break
	var a := CharacterBody3D.new()
	a.collision_layer = LAYER_ALLY
	a.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	var cap := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.42
	cs.height = 1.8
	cap.shape = cs
	cap.position = Vector3(0, 0.9, 0)
	a.add_child(cap)
	var variant := "carter" if ni == 0 else "tealc"
	var body := _make_humanoid(true, "jaffa", false, variant)
	a.add_child(body)
	body.scale = Vector3.ONE * (0.96 if ni == 0 else 1.08)   # Картер ниже, Тил'к крупнее
	var side := -1.0 if ni == 0 else 1.0
	a.position = player.position + Vector3(side * 2.0, 0, 1.5)
	ally_root.add_child(a)
	var base_hp: float = 120.0 if ni == 0 else 180.0
	var max_hp: float = base_hp * _ally_mult()
	allies.append({
		"body": a, "name": name, "ni": ni,
		"hp": max_hp, "max_hp": max_hp, "base_max_hp": base_hp,
		"fire_cd": rng.randf_range(0.2, 0.6), "fire_rate": 0.32, "dmg": 11.0,
		"stuck_t": 0.0, "unstick": 0.0, "unstick_side": 1.0, "last_pos": a.position,
		"warned": false,
	})


func _update_allies(delta: float) -> void:
	var ppos := player.global_position
	for ai in allies.size():
		var a: Dictionary = allies[ai]
		var body: CharacterBody3D = a.body
		if body == null or not is_instance_valid(body) or a.hp <= 0.0:
			continue
		# плавный рост макс. HP союзника
		var nm: float = a.base_max_hp * _ally_mult()
		if nm > a.max_hp:
			a.hp += nm - a.max_hp
			a.max_hp = nm
		# ближайший враг
		var tgt: Node3D = null
		var bd := 1e9
		for d in enemies:
			if is_instance_valid(d.body):
				var dd: float = body.global_position.distance_to(d.body.global_position)
				if dd < bd:
					bd = dd; tgt = d.body
		var move := Vector3.ZERO
		if tgt != null and phase == Phase.PLAY:
			var to_e := tgt.global_position - body.global_position
			var fl := Vector3(to_e.x, 0, to_e.z)
			var flen := fl.length()
			var lk := tgt.global_position
			lk.y = body.global_position.y
			if body.global_position.distance_to(lk) > 0.05:
				body.look_at(lk, Vector3.UP)
			if flen > ALLY_RANGE:
				move = (fl / flen) * 4.0
			elif flen < 6.0:
				move = -(fl / flen) * 2.0
			a.fire_cd -= delta
			if a.fire_cd <= 0.0 and flen < ALLY_RANGE and _enemy_has_los(body.global_position + Vector3(0, 1.4, 0), tgt.global_position + Vector3(0, 1.0, 0)):
				a.fire_cd = a.fire_rate / _ally_mult()
				_ally_shoot(a, tgt)
		else:
			# держать строй рядом с игроком
			var off := player.global_transform.basis * Vector3(-2.2 if a.ni == 0 else 2.2, 0, 1.6)
			var to_f := (ppos + off) - body.global_position
			to_f.y = 0
			if to_f.length() > 1.2:
				move = to_f.normalized() * 4.5
			body.rotation.y = player.rotation.y
		# расталкивание с игроком и другими союзниками
		var push := body.global_position - ppos
		push.y = 0
		if push.length() < 1.2 and push.length() > 0.001:
			move += push.normalized() * (1.2 - push.length()) * 3.0
		for o in allies:
			if o.body == body: continue
			if is_instance_valid(o.body):
				var df: Vector3 = body.global_position - o.body.global_position
				df.y = 0
				if df.length() < 1.0 and df.length() > 0.001:
					move += df.normalized() * (1.0 - df.length()) * 3.0
		var vel := body.velocity
		move = _agent_move(body, move, 4.5, delta, a)
		vel.x = move.x
		vel.z = move.z
		vel.y = -GRAV * 0.5 if body.is_on_floor() else vel.y - GRAV * delta
		body.velocity = vel
		body.move_and_slide()


func _ally_shoot(a: Dictionary, tgt: Node3D) -> void:
	var abody: Node3D = a.body
	var from: Vector3 = abody.global_position + Vector3(0, 1.45, 0)
	var to: Vector3 = tgt.global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = (to - from).normalized()
	dir = dir.rotated(Vector3.UP, rng.randf_range(-0.02, 0.02))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, LAYER_WORLD | LAYER_ENEMY, [abody.get_rid()])
	var hit := space.intersect_ray(q)
	var end: Vector3 = from + dir * 60.0
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col != null and col.is_in_group("enemy"):
			_damage_enemy(col, a.dmg * _ally_mult(), dir)
	_tracer(from + dir * 0.5, end)
	_muzzle_flash_at(from + dir * 0.6)
	_sfx("ally_shot")


func _damage_ally(a: Dictionary, dmg: float) -> void:
	a.hp -= dmg
	if a.hp > 0.0 and a.hp < a.max_hp * 0.35 and not a.warned:
		a.warned = true
		_radio(a.name, "Меня задело... нужна передышка!")
	if a.hp <= 0.0:
		a.hp = 0.0


func _kill_ally(index: int) -> void:
	var a: Dictionary = allies[index]
	var body: CharacterBody3D = a.body
	if body != null and is_instance_valid(body):
		_death_fx(body.global_position + Vector3(0, 1.0, 0))
		body.queue_free()
	allies.remove_at(index)
	_sfx("ally_down")
	# погибший НЕ передаёт сообщения; о потере докладывает выживший напарник или игрок
	var other := ""
	for al in allies:
		if al.hp > 0.0:
			other = al.name
			break
	if other != "":
		_radio(other, "%s down! Держимся!" % a.name)
	else:
		_radio("ВЫ", "%s down... держусь один." % a.name)


func _cleanup_allies() -> void:
	var i := allies.size() - 1
	while i >= 0:
		if allies[i].hp <= 0.0:
			_kill_ally(i)
		i -= 1


# ============================== ТУРНЕЛИ =====================================
func _enemy_mult() -> float:
	return 1.0 + power * 0.15


func _ally_mult() -> float:
	return 1.0 + power * 0.12


func _turret_mult() -> float:
	return 1.0 + power * 0.12


func _build_turrets() -> void:
	if turret_root != null and is_instance_valid(turret_root):
		for c in turret_root.get_children():
			c.queue_free()
		turrets.clear()
	else:
		turret_root = Node3D.new()
		turret_root.name = "Turrets"
		add_child(turret_root)
	var base_mat := _mat(Color(0.2, 0.22, 0.26), 0.5, 0.6)
	var gun_mat := _mat(Color(0.14, 0.15, 0.18), 0.4, 0.7)
	var spots := [Vector3(-8, 0, -20), Vector3(8, 0, -20), Vector3(-13, 0, 2), Vector3(13, 0, 2)]
	for sp in spots:
		var base := _mesh(CylinderMesh.new(), base_mat)
		base.scale = Vector3(0.9, 0.5, 0.9)
		base.position = sp + Vector3(0, 0.25, 0)
		turret_root.add_child(base)
		var head := Node3D.new()
		head.position = sp + Vector3(0, 0.75, 0)
		turret_root.add_child(head)
		var hb := _mesh(BoxMesh.new(), gun_mat)
		hb.scale = Vector3(0.5, 0.35, 0.6)
		hb.position = Vector3(0, 0, 0)
		head.add_child(hb)
		var barrel := _mesh(CylinderMesh.new(), gun_mat)
		barrel.scale = Vector3(0.08, 0.5, 0.08)
		barrel.rotation_degrees = Vector3(90, 0, 0)
		barrel.position = Vector3(0, 0.05, -0.5)
		head.add_child(barrel)
		var sensor_mat := _emissive(Color(0.3, 0.9, 1.0), 2.0)
		var sensor := _mesh(SphereMesh.new(), sensor_mat)
		sensor.scale = Vector3(0.08, 0.08, 0.08)
		sensor.position = Vector3(0, 0.2, -0.2)
		head.add_child(sensor)
		turrets.append({
			"head": head, "base": base, "sensor_mat": sensor_mat,
			"fire_cd": rng.randf_range(0.0, 0.5),
			"hp": 150.0, "max_hp": 150.0, "base_max_hp": 150.0, "alive": true, "lvl": 1,
		})


func _update_turrets(delta: float) -> void:
	if phase != Phase.PLAY:
		return
	for t in turrets:
		if not t.alive:
			continue
		var head: Node3D = t.head
		if head == null or not is_instance_valid(head):
			continue
		var smat: StandardMaterial3D = t.sensor_mat
		if smat != null:
			var fr := clampf(float(t.hp) / float(t.max_hp), 0.0, 1.0)
			smat.emission = Color(1.0, 0.2, 0.15).lerp(Color(0.3, 0.9, 1.0), fr)
		# плавный рост макс. HP турели (от волны) + бонус уровня
		var lm: float = 1.0 + 0.3 * float(t.lvl - 1)
		var tm: float = t.base_max_hp * _turret_mult() * lm
		if tm > t.max_hp:
			t.hp += tm - t.max_hp
			t.max_hp = tm
		t.fire_cd -= delta
		var tgt: Node3D = null
		var bd := TURRET_RANGE
		var aim := Vector3.ZERO
		for d in enemies:
			if is_instance_valid(d.body):
				var c: Vector3 = d.body.global_position + Vector3(0, 1.0 * d.sc, 0)
				var dd := head.global_position.distance_to(c)
				if dd < bd and _enemy_has_los(head.global_position, c):
					bd = dd
					tgt = d.body
					aim = c
		if tgt != null:
			head.look_at(aim, Vector3.UP)
			if t.fire_cd <= 0.0:
				t.fire_cd = TURRET_RATE / (_turret_mult() * lm)
				_turret_fire(t, head, aim)


func _turret_fire(t: Dictionary, head: Node3D, aim: Vector3) -> void:
	var lm: float = 1.0 + 0.3 * float(t.lvl - 1)
	var mz: Vector3 = head.global_position + (-head.global_transform.basis.z) * 0.6
	var dir: Vector3 = (aim - mz).normalized()
	var q := PhysicsRayQueryParameters3D.create(mz, mz + dir * TURRET_RANGE, LAYER_WORLD | LAYER_ENEMY, [])
	var hit := space.intersect_ray(q)
	var end := mz + dir * TURRET_RANGE
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col != null and col.is_in_group("enemy"):
			_damage_enemy(col, TURRET_DMG * _turret_mult() * lm, dir)
	_tracer(mz, end)
	_muzzle_flash_at(mz)
	_sfx("turret_shot")


func _damage_turret(t: Dictionary, dmg: float) -> void:
	if not t.alive:
		return
	t.hp -= dmg
	if is_instance_valid(t.head):
		_impact(t.head.global_position + Vector3(0, 0.2, 0), Vector3.UP, COL_ORANGE)
	if t.hp <= 0.0:
		_destroy_turret(t)


func _destroy_turret(t: Dictionary) -> void:
	t.alive = false
	if is_instance_valid(t.head):
		_explosion_fx(t.head.global_position)
		t.head.queue_free()
	if is_instance_valid(t.base):
		t.base.queue_free()
	shake = maxf(shake, 0.4)
	_sfx("explode")
	_radio_ally("CARTER", "Турель уничтожена!")


func _nearest_turret() -> Dictionary:
	var best: Dictionary = {}
	var bd := TURRET_INTERACT
	for t in turrets:
		if t.alive and is_instance_valid(t.head):
			var d := player.global_position.distance_to(t.head.global_position)
			if d < bd:
				bd = d
				best = t
	return best


func _repair_turret() -> void:
	var t := _nearest_turret()
	if t.is_empty():
		return
	if t.hp >= t.max_hp - 0.5:
		_sfx("deny")
		return
	if score < TURRET_REPAIR_COST:
		_sfx("deny")
		_set_center("НЕДОСТАТОЧНО ОЧКОВ", "Ремонт турели стоит %d очков" % TURRET_REPAIR_COST)
		_fade_center(1.2)
		return
	score -= TURRET_REPAIR_COST
	t.hp = t.max_hp
	_impact(t.head.global_position + Vector3(0, 0.3, 0), Vector3.UP, Color(0.3, 1.0, 0.5))
	_sfx("repair")
	_set_center("ТУРЕЛЬ ОТРЕМОНТИРОВАНА", "-%d очков" % TURRET_REPAIR_COST)
	_fade_center(1.2)


func _upgrade_turret() -> void:
	var t := _nearest_turret()
	if t.is_empty():
		return
	var cost: int = TURRET_UPGRADE_COST * int(t.lvl)
	if score < cost:
		_sfx("deny")
		_set_center("НЕДОСТАТОЧНО ОЧКОВ", "Улучшение турели стоит %d очков" % cost)
		_fade_center(1.2)
		return
	score -= cost
	t.lvl += 1
	_impact(t.head.global_position + Vector3(0, 0.3, 0), Vector3.UP, Color(0.4, 0.8, 1.0))
	_sfx("upgrade")
	_set_center("ТУРЕЛЬ УЛУЧШЕНА ДО УР. %d" % t.lvl, "-%d очков   |   урон, темп и запас прочности выше" % cost)
	_fade_center(1.6)


# ============================== СОЛДАТ / ВРАГ ===============================
func _make_humanoid(is_player: bool, kind: String = "jaffa", assign_muzzle: bool = true, variant: String = "") -> Node3D:
	var root := Node3D.new()
	var armor_col := Color(0.32, 0.36, 0.28)
	var accent_col := Color(0.2, 0.22, 0.18)
	var eye_col := COL_RED
	var skin := Color(0.76, 0.6, 0.48)
	var torso_w := 0.72
	var shoulder_s := 0.24
	if is_player and variant != "":
		match variant:
			"carter":   # светлокожая женщина
				skin = Color(0.88, 0.74, 0.64)
				armor_col = Color(0.33, 0.37, 0.3)
				accent_col = Color(0.22, 0.24, 0.2)
				torso_w = 0.6
				shoulder_s = 0.19
			"tealc":    # темнокожий мужчина
				skin = Color(0.33, 0.21, 0.14)
				armor_col = Color(0.24, 0.21, 0.18)
				accent_col = Color(0.5, 0.4, 0.2)
				torso_w = 0.84
				shoulder_s = 0.3
	elif not is_player:
		match kind:
			"scout":
				armor_col = Color(0.36, 0.24, 0.18); accent_col = Color(0.5, 0.3, 0.18)
				eye_col = Color(1.0, 0.6, 0.2)
			"heavy":
				armor_col = Color(0.24, 0.25, 0.3); accent_col = Color(0.5, 0.42, 0.22)
				eye_col = Color(1.0, 0.3, 0.15)
			"boss":
				armor_col = Color(0.45, 0.38, 0.14); accent_col = Color(0.72, 0.56, 0.2)
				eye_col = Color(1.0, 0.9, 0.3); skin = Color(0.7, 0.62, 0.5)
			_:
				armor_col = Color(0.22, 0.24, 0.28); accent_col = Color(0.55, 0.45, 0.25)

	var armor_mat := _mat(armor_col, 0.7, 0.2)
	armor_mat.emission_enabled = true
	armor_mat.emission = Color(1, 1, 1)
	armor_mat.emission_energy_multiplier = 0.0
	root.set_meta("armor_mat", armor_mat)

	# ноги
	for side in [-1.0, 1.0]:
		var leg := _mesh(BoxMesh.new(), _mat(accent_col, 0.8, 0.1))
		leg.scale = Vector3(0.28, 0.85, 0.3)
		leg.position = Vector3(side * 0.18, 0.45, 0)
		root.add_child(leg)
	# торс
	var torso := _mesh(BoxMesh.new(), armor_mat)
	torso.scale = Vector3(torso_w, 0.78, 0.4)
	torso.position = Vector3(0, 1.25, 0)
	root.add_child(torso)
	# наплечники
	for side in [-1.0, 1.0]:
		var sh := _mesh(BoxMesh.new(), _mat(accent_col, 0.6, 0.4))
		sh.scale = Vector3(shoulder_s, shoulder_s, 0.42)
		sh.position = Vector3(side * (torso_w * 0.5 + 0.06), 1.5, 0)
		root.add_child(sh)
	# руки вперёд
	for side in [-1.0, 1.0]:
		var arm := _mesh(BoxMesh.new(), armor_mat)
		arm.scale = Vector3(0.2, 0.2, 0.55)
		arm.position = Vector3(side * 0.28, 1.25, -0.35)
		root.add_child(arm)
	# голова
	var head := _mesh(SphereMesh.new(), _mat(skin, 0.8, 0.0))
	head.scale = Vector3(0.34, 0.36, 0.34)
	head.position = Vector3(0, 1.82, 0)
	root.add_child(head)
	# голова/шлем по варианту
	if variant == "carter":
		# волосы + хвост
		var hair := _mesh(SphereMesh.new(), _mat(Color(0.78, 0.62, 0.35), 0.85, 0.0))
		hair.scale = Vector3(0.36, 0.3, 0.36)
		hair.position = Vector3(0, 1.9, 0.04)
		root.add_child(hair)
		var pony := _mesh(BoxMesh.new(), _mat(Color(0.78, 0.62, 0.35), 0.85, 0.0))
		pony.scale = Vector3(0.1, 0.36, 0.1)
		pony.position = Vector3(0, 1.7, 0.3)
		root.add_child(pony)
	elif variant == "tealc":
		# лысый + золотой символ на лбу
		var emblem := _mesh(BoxMesh.new(), _emissive(Color(0.9, 0.75, 0.3), 1.2))
		emblem.scale = Vector3(0.1, 0.12, 0.04)
		emblem.position = Vector3(0, 1.88, -0.3)
		root.add_child(emblem)
	else:
		var helm := _mesh(SphereMesh.new(), _mat(accent_col, 0.5, 0.5))
		helm.scale = Vector3(0.38, 0.3, 0.4)
		helm.position = Vector3(0, 1.92, 0.02)
		root.add_child(helm)

	if is_player:
		var gun := _mesh(BoxMesh.new(), _mat(Color(0.12, 0.12, 0.14), 0.5, 0.6))
		gun.scale = Vector3(0.12, 0.16, 0.7)
		gun.position = Vector3(0.18, 1.25, -0.55)
		root.add_child(gun)
		var muzzle := Marker3D.new()
		muzzle.position = Vector3(0.18, 1.25, -0.95)
		root.add_child(muzzle)
		if assign_muzzle:
			muzzle_tps = muzzle
	else:
		# копьё-посох Джаффа: тонкое древко + конический наконечник
		var pole := _mesh(CylinderMesh.new(), _mat(Color(0.34, 0.29, 0.2), 0.5, 0.6))
		pole.scale = Vector3(0.07, 1.15, 0.07)      # радиус ~0.035, длина ~2.3
		pole.rotation_degrees = Vector3(90, 0, 0)  # ось вдоль Z (вперёд)
		pole.position = Vector3(0.24, 1.18, -0.5)
		root.add_child(pole)
		# металлическая втулка у рук
		var collar := _mesh(CylinderMesh.new(), _mat(Color(0.55, 0.48, 0.28), 0.4, 0.8))
		collar.scale = Vector3(0.12, 0.12, 0.12)
		collar.rotation_degrees = Vector3(90, 0, 0)
		collar.position = Vector3(0.24, 1.18, -0.15)
		root.add_child(collar)
		# каноничный наконечник-«пасть»: голова с раскрывающимися створками и ядром
		var head_node := Node3D.new()
		head_node.position = Vector3(0.24, 1.18, -1.7)
		root.add_child(head_node)
		var bronze := _mat(Color(0.55, 0.45, 0.22), 0.4, 0.85)
		# череп-основание головы
		var skull := _mesh(SphereMesh.new(), bronze)
		skull.scale = Vector3(0.09, 0.1, 0.16)
		skull.position = Vector3(0, 0, 0.02)
		head_node.add_child(skull)
		# верхняя створка-челюсть (конус остриём вперёд)
		var jaw_u_p := Node3D.new()
		head_node.add_child(jaw_u_p)
		var ju_m := CylinderMesh.new()
		ju_m.top_radius = 0.0; ju_m.bottom_radius = 0.06; ju_m.height = 0.3
		var jaw_u := _mesh(ju_m, bronze)
		jaw_u.scale = Vector3(0.8, 1.0, 0.8)
		jaw_u.rotation_degrees = Vector3(-90, 0, 0)
		jaw_u.position = Vector3(0, 0.035, -0.14)
		jaw_u_p.add_child(jaw_u)
		# нижняя створка-челюсть
		var jaw_l_p := Node3D.new()
		head_node.add_child(jaw_l_p)
		var jl_m := CylinderMesh.new()
		jl_m.top_radius = 0.0; jl_m.bottom_radius = 0.06; jl_m.height = 0.26
		var jaw_l := _mesh(jl_m, bronze)
		jaw_l.scale = Vector3(0.8, 1.0, 0.8)
		jaw_l.rotation_degrees = Vector3(-90, 0, 0)
		jaw_l.position = Vector3(0, -0.035, -0.12)
		jaw_l_p.add_child(jaw_l)
		# плазменное ядро в пасти (разгорается при раскрытии)
		var core_mat := _emissive(eye_col, 0.6)
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var core := _mesh(SphereMesh.new(), core_mat)
		core.scale = Vector3(0.06, 0.06, 0.06)
		core.position = Vector3(0, 0, -0.05)
		head_node.add_child(core)
		root.set_meta("staff_head", head_node)
		root.set_meta("jaw_u", jaw_u_p)
		root.set_meta("jaw_l", jaw_l_p)
		root.set_meta("core_mat", core_mat)
		# светящийся глаз
		var eye := _mesh(SphereMesh.new(), _emissive(eye_col, 3.0))
		eye.scale = Vector3(0.1, 0.08, 0.08)
		eye.position = Vector3(0, 1.84, -0.16)
		root.add_child(eye)
		if kind == "boss":
			# корона Гоа'улда
			var crown := _mesh(CylinderMesh.new(), _emissive(Color(0.9, 0.75, 0.25), 1.5))
			crown.scale = Vector3(0.42, 0.24, 0.42)
			crown.position = Vector3(0, 2.06, 0)
			root.add_child(crown)
			# плащ
			var cape := _mesh(BoxMesh.new(), _mat(Color(0.5, 0.1, 0.12), 0.8, 0.1))
			cape.scale = Vector3(0.85, 1.5, 0.12)
			cape.position = Vector3(0, 1.2, 0.28)
			root.add_child(cape)
			# светящаяся ладонь-устройство
			var hand := _mesh(SphereMesh.new(), _emissive(Color(0.8, 0.5, 1.0), 4.0))
			hand.scale = Vector3(0.22, 0.22, 0.22)
			hand.position = Vector3(-0.3, 1.25, -0.6)
			root.add_child(hand)
	return root


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = LAYER_PLAYER
	player.collision_mask = LAYER_WORLD | LAYER_ENEMY | LAYER_ALLY
	add_child(player)

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.42
	cs.height = 1.8
	col.shape = cs
	col.position = Vector3(0, 0.9, 0)
	player.add_child(col)

	soldier = _make_humanoid(true)
	player.add_child(soldier)

	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 1.6, 0)
	player.add_child(cam_pivot)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 300.0
	cam_pivot.add_child(camera)
	camera.current = true

	# оружие от 1-го лица (компактное, справа-снизу; тонкий ствол не перекрывает обзор)
	weapon_view = Node3D.new()
	camera.add_child(weapon_view)
	var gmat := _mat(Color(0.13, 0.14, 0.16), 0.45, 0.6)
	var gun_body := _mesh(BoxMesh.new(), gmat)
	gun_body.scale = Vector3(0.09, 0.12, 0.40)
	gun_body.position = Vector3(0, 0, -0.10)
	weapon_view.add_child(gun_body)
	var barrel := _mesh(CylinderMesh.new(), _mat(Color(0.08, 0.08, 0.09), 0.4, 0.7))
	barrel.scale = Vector3(0.05, 0.32, 0.05)   # тонкий ствол: торец почти не виден
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.02, -0.44)
	weapon_view.add_child(barrel)
	var sight := _mesh(BoxMesh.new(), gmat)
	sight.scale = Vector3(0.03, 0.06, 0.14)
	sight.position = Vector3(0, 0.09, -0.16)
	weapon_view.add_child(sight)
	var magb := _mesh(BoxMesh.new(), _mat(Color(0.1, 0.1, 0.12), 0.6, 0.3))
	magb.scale = Vector3(0.06, 0.16, 0.09)
	magb.position = Vector3(0, -0.12, -0.08)
	magb.rotation_degrees = Vector3(12, 0, 0)
	weapon_view.add_child(magb)
	var grip := _mesh(BoxMesh.new(), _mat(Color(0.1, 0.1, 0.12), 0.6, 0.3))
	grip.scale = Vector3(0.06, 0.16, 0.08)
	grip.position = Vector3(0, -0.13, 0.06)
	grip.rotation_degrees = Vector3(18, 0, 0)
	weapon_view.add_child(grip)
	muzzle_fps = Marker3D.new()
	muzzle_fps.position = Vector3(0, 0.02, -0.62)
	weapon_view.add_child(muzzle_fps)

	_switch_camera()


# ============================== ШЕЙДЕРЫ =====================================
func _horizon_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque;
uniform float time = 0.0;
uniform float open = 0.6;
uniform float speed = 1.0;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float a = atan(p.y, p.x);
	float t = time * speed;
	float ripple = sin(r * 22.0 - t * 4.0) * 0.5 + 0.5;
	float swirl = noise(vec2(a * 2.6 + t * 0.4, r * 6.0 - t * 1.2));
	float m = ripple * 0.55 + swirl * 0.75;
	vec3 col = mix(vec3(0.015, 0.07, 0.12), vec3(0.06, 0.55, 0.85), clamp(m, 0.0, 1.0));
	col = mix(col, vec3(0.8, 1.0, 1.0), pow(clamp(m - 0.55, 0.0, 1.0) * 2.2, 2.0));
	float rim = smoothstep(1.0, 0.86, r);
	ALBEDO = vec3(0.0);
	EMISSION = col * (1.1 + m * 1.6) * open;
	ALPHA = clamp((0.34 + m * 0.66) * rim * open, 0.0, 1.0);
}
"""
	return sh


func _vignette_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float damage = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float vig = smoothstep(0.45, 1.2, d);
	vec3 c = vec3(0.0, 0.0, 0.02) * vig * 0.85;
	c += vec3(0.7, 0.02, 0.0) * damage * (0.2 + vig * 0.5);
	COLOR = vec4(c, clamp(vig * 0.85 + damage * 0.5, 0.0, 1.0));
}
"""
	return sh


func _flash_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float rad = length(p);
	vec3 c = mix(vec3(0.65, 0.95, 1.0), vec3(1.0), amount);
	COLOR = vec4(c, clamp(amount * (1.0 - rad * 0.45), 0.0, 1.0));
}
"""
	return sh


# ============================== ХЕЛПЕРЫ =====================================
func _mat(albedo: Color, rough: float, metal: float, emis: Color = Color.BLACK, emis_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m


func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _mesh(m, mat) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _load_best() -> int:
	if not FileAccess.file_exists("user://stargate_best.cfg"):
		return 0
	var f := FileAccess.open("user://stargate_best.cfg", FileAccess.READ)
	if f == null:
		return 0
	var v: Variant = f.get_var()
	f.close()
	return int(v)


func _save_best() -> void:
	var f := FileAccess.open("user://stargate_best.cfg", FileAccess.WRITE)
	if f == null:
		return
	f.store_var(best)
	f.close()


# ============================== ПРИЦЕЛ ======================================
class _Reticle:
	extends Control
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.55, 0.95, 1.0, 0.85)
		draw_arc(c, 8.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.5), 1.5, true)
		draw_line(c + Vector2(-16, 0), c + Vector2(-6, 0), col, 2.0)
		draw_line(c + Vector2(16, 0), c + Vector2(6, 0), col, 2.0)
		draw_line(c + Vector2(0, -16), c + Vector2(0, -6), col, 2.0)
		draw_line(c + Vector2(0, 16), c + Vector2(0, 6), col, 2.0)
		draw_circle(c, 1.4, col)
