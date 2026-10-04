extends RefCounted
## Original low-poly miniature artwork. Decorative meshes carry no game rules.
## All dimensions are world units. Meshes/materials are shared across instances.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
const STONE = Color("9ba7ad")
const STONE_DARK = Color("596872")
const WOOD = Color("72513b")
const WOOD_LIGHT = Color("a37b50")
const STEEL = Color("c5d6dd")
const SKIN = Color("d5b18e")
const ALLY = Color("279b9a")
const ENEMY = Color("aa557e")
const GOLD = Color("dcba65")


static func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key = color.to_html() + ("u" if unshaded else "s")
	if key not in _materials:
		var value = StandardMaterial3D.new()
		value.albedo_color = color
		value.roughness = 0.93
		if color.a < 1.0:
			value.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			value.cull_mode = BaseMaterial3D.CULL_DISABLED
		if unshaded:
			value.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = value
	return _materials[key]


static func _mesh(shape: String) -> Mesh:
	if shape not in _meshes:
		var value: Mesh
		if shape == "box":
			var box = BoxMesh.new()
			box.size = Vector3.ONE
			value = box
		elif shape == "sphere":
			var sphere = SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 10
			sphere.rings = 5
			value = sphere
		elif shape == "roof":
			value = _solid([
				[Vector3(-1, 0, -1), Vector3(0, 1, -1), Vector3(1, 0, -1)],
				[Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1)],
				[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, -1)],
				[Vector3(1, 0, -1), Vector3(0, 1, -1), Vector3(0, 1, 1), Vector3(1, 0, 1)],
				[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]])
		else:
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.0 if shape == "cone" else 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			cylinder.radial_segments = 10
			cylinder.rings = 1
			value = cylinder
		_meshes[shape] = value
	return _meshes[shape]


static func _solid(faces: Array) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	for face in faces:
		for i in range(1, face.size() - 1):
			var normal: Vector3 = (face[i] - face[0]).cross(face[i + 1] - face[0]).normalized()
			# Godot front faces use clockwise winding; retain the outward face normal.
			vertices.append_array(PackedVector3Array([face[0], face[i + 1], face[i]]))
			normals.append_array(PackedVector3Array([normal, normal, normal]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var value = ArrayMesh.new()
	value.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return value


static func _part(parent: Node3D, name: String, shape: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = name
	node.mesh = _mesh(shape)
	node.material_override = _material(color)
	node.scale = size
	node.position = at
	parent.add_child(node)
	return node


static func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	return _part(parent, name, "box", size, at, color)


static func _round(parent: Node3D, name: String, radius: float, height: float, at: Vector3, color: Color, cone: bool = false) -> MeshInstance3D:
	return _part(parent, name, "cone" if cone else "cylinder", Vector3(radius, height, radius), at, color)


static func _beam(parent: Node3D, name: String, start: Vector3, end: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node = _round(parent, name, radius, start.distance_to(end), (start + end) * 0.5, color)
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return node


static func _faction(team: String) -> Color:
	return ENEMY if team in ["enemy", "Enemy", "raider"] else ALLY


static func terrain() -> Node3D:
	var root = Node3D.new()
	root.name = "OriginalTabletop"
	_box(root, "SolidWalnutTable", Vector3(53, 1.1, 39), Vector3(0, -0.95, 0), Color("3b302b"))
	_box(root, "CarvedEdgeBand", Vector3(53.2, 0.17, 39.2), Vector3(0, -0.46, 0), WOOD_LIGHT)
	# A true sloped frustum gives the board a bevel without expensive mesh details.
	var bevel = MeshInstance3D.new()
	bevel.name = "SlopedTableRim"
	var a = Vector3(-26, -0.10, -19)
	var b = Vector3(26, -0.10, -19)
	var c = Vector3(26, -0.10, 19)
	var d = Vector3(-26, -0.10, 19)
	var e = Vector3(-26.6, -0.44, -19.6)
	var f = Vector3(26.6, -0.44, -19.6)
	var g = Vector3(26.6, -0.44, 19.6)
	var h = Vector3(-26.6, -0.44, 19.6)
	bevel.mesh = _solid([[a, b, f, e], [b, c, g, f], [c, d, h, g], [d, a, e, h]])
	bevel.material_override = _material(Color("88745a"))
	root.add_child(bevel)
	_box(root, "PlayableGround52x38", Vector3(52, 0.12, 38), Vector3(0, -0.06, 0), Color("64775b"))
	var rng = RandomNumberGenerator.new()
	rng.seed = 73041
	for i in range(34):
		var patch = _round(root, "GrassPatch%d" % i, rng.randf_range(0.5, 1.7), 0.014,
			Vector3(rng.randf_range(-24, 24), 0.009, rng.randf_range(-17, 17)), Color("6b805f") if i % 2 == 0 else Color("596f52"))
		patch.scale.z *= rng.randf_range(0.4, 1.0)
	# Surface dressing only: roads do not determine passability, ownership, or placement.
	_box(root, "CrossingRoad", Vector3(34, 0.025, 1.65), Vector3(0, 0.015, 5.5), Color("998e70"))
	_box(root, "BranchRoad", Vector3(1.45, 0.028, 27), Vector3(-8, 0.018, 0), Color("998e70"))
	for i in range(36):
		var side = i % 4
		var at = Vector3.ZERO
		if side < 2:
			at = Vector3(rng.randf_range(-25.5, 25.5), 0, (-1 if side == 0 else 1) * rng.randf_range(19.15, 19.8))
		else:
			at = Vector3((-1 if side == 2 else 1) * rng.randf_range(26.15, 26.8), 0, rng.randf_range(-18.5, 18.5))
		var tree = _pine(rng.randf_range(0.75, 1.3))
		tree.position = at
		root.add_child(tree)
	for i in range(18):
		var rock = _part(root, "BorderRock%d" % i, "sphere", Vector3(0.5, 0.35, 0.4),
			Vector3(rng.randf_range(-25, 25), 0.16, 19.15 if i % 2 == 0 else -19.15), STONE_DARK)
		rock.rotation = Vector3(0.2, rng.randf() * TAU, 0.3)
	return root


static func _pine(size: float) -> Node3D:
	var root = Node3D.new()
	root.name = "BorderPine"
	root.scale = Vector3.ONE * size
	_round(root, "Trunk", 0.12, 1.15, Vector3(0, 0.57, 0), WOOD)
	_round(root, "LowerNeedles", 0.7, 1.15, Vector3(0, 1.0, 0), Color("344f40"), true)
	_round(root, "MiddleNeedles", 0.56, 1.05, Vector3(0, 1.5, 0), Color("406047"), true)
	_round(root, "CrownNeedles", 0.4, 0.9, Vector3(0, 1.94, 0), Color("527354"), true)
	return root


static func selection(radius: float, color: Color) -> Node3D:
	var root = Node3D.new()
	root.name = "SelectionRing"
	var mesh = TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.035)
	mesh.outer_radius = radius + 0.035
	mesh.rings = 24
	mesh.ring_segments = 6
	var node = MeshInstance3D.new()
	node.mesh = mesh
	var translucent = color
	translucent.a = minf(color.a, 0.75)
	node.material_override = _material(translucent, true)
	node.position.y = 0.065
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return root


static func unit(kind: String, team: String) -> Node3D:
	var root = Node3D.new()
	root.name = "Original" + kind.capitalize()
	root.set_meta("kind", kind)
	var rig = Node3D.new()
	rig.name = "Rig"
	root.add_child(rig)
	var cloth = _faction(team)
	var boots = Color("383d40")
	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.name = "LeftLeg" if side == -1 else "RightLeg"
		leg.position = Vector3(side * 0.105, 0.5, 0)
		rig.add_child(leg)
		_box(leg, "Greave", Vector3(0.135, 0.38, 0.14), Vector3(0, -0.2, 0), STONE_DARK)
		_box(leg, "Boot", Vector3(0.17, 0.12, 0.23), Vector3(0, -0.43, 0.035), boots)
	_round(rig, "Torso", 0.20, 0.4, Vector3(0, 0.75, 0), cloth)
	_box(rig, "Belt", Vector3(0.405, 0.07, 0.33), Vector3(0, 0.59, 0), WOOD)
	_box(rig, "Buckle", Vector3(0.08, 0.06, 0.025), Vector3(0, 0.59, 0.18), GOLD)
	_part(rig, "Head", "sphere", Vector3(0.15, 0.17, 0.145), Vector3(0, 1.075, 0.01), SKIN)
	for side in [-1, 1]:
		_part(rig, "Eye", "sphere", Vector3(0.018, 0.017, 0.018), Vector3(side * 0.055, 1.1, 0.144), Color("26343b"))
	var cape = _box(rig, "Cape", Vector3(0.34, 0.48, 0.045), Vector3(0, 0.7, -0.22), cloth.darkened(0.2))
	cape.rotation.x = -0.17
	for side in [-1, 1]:
		_part(rig, "Shoulder", "sphere", Vector3(0.14, 0.105, 0.13), Vector3(side * 0.22, 0.88, 0), STEEL if kind == "footmen" else cloth)
		_beam(rig, "Arm", Vector3(side * 0.23, 0.83, 0), Vector3(side * 0.31, 0.64, 0.12), 0.065, cloth)
		_part(rig, "Hand", "sphere", Vector3.ONE * 0.065, Vector3(side * 0.31, 0.64, 0.12), SKIN)
	var weapon = Node3D.new()
	weapon.name = "Weapon"
	weapon.position = Vector3(0.31, 0.64, 0.12)
	rig.add_child(weapon)
	if kind == "archers":
		_round(rig, "ClothCap", 0.165, 0.12, Vector3(0, 1.2, 0), cloth.darkened(0.25))
		_box(rig, "Quiver", Vector3(0.14, 0.35, 0.14), Vector3(0.19, 0.78, -0.24), WOOD_LIGHT)
		for i in range(3):
			_beam(rig, "QuiverArrow", Vector3(0.13 + i * 0.05, 0.87, -0.24), Vector3(0.13 + i * 0.05, 1.2, -0.24), 0.014, WOOD_LIGHT)
		for i in range(5):
			var start = Vector3(0, -0.29 + i * 0.116, sin(float(i) / 5.0 * PI) * 0.14)
			var end = Vector3(0, -0.29 + (i + 1) * 0.116, sin(float(i + 1) / 5.0 * PI) * 0.14)
			_beam(weapon, "BowSegment", start, end, 0.026, WOOD_LIGHT)
		_beam(weapon, "BowString", Vector3(0, -0.29, 0), Vector3(0, 0.29, 0), 0.006, STEEL)
	elif kind == "raider":
		_part(rig, "LeatherHelmet", "sphere", Vector3(0.18, 0.13, 0.17), Vector3(0, 1.19, 0), WOOD.darkened(0.2))
		for side in [-1, 1]:
			var horn = _round(rig, "Horn", 0.05, 0.19, Vector3(side * 0.19, 1.27, 0), Color("d3c6a6"), true)
			horn.rotation.z = side * -0.65
		_beam(weapon, "MaceHandle", Vector3(0, -0.13, 0), Vector3(0, 0.32, 0), 0.035, WOOD)
		_part(weapon, "MaceHead", "sphere", Vector3.ONE * 0.115, Vector3(0, 0.32, 0), STONE_DARK)
	else:
		_part(rig, "Helmet", "sphere", Vector3(0.18, 0.14, 0.17), Vector3(0, 1.18, 0), STEEL)
		_box(rig, "NoseGuard", Vector3(0.035, 0.16, 0.025), Vector3(0, 1.135, 0.169), STEEL)
		var shield = _round(rig, "Shield", 0.24, 0.05, Vector3(-0.31, 0.65, 0.21), cloth)
		shield.rotation.x = PI / 2.0
		shield.scale.z *= 1.2
		_part(rig, "ShieldBoss", "sphere", Vector3.ONE * 0.07, Vector3(-0.31, 0.65, 0.25), GOLD)
		_box(weapon, "SwordGrip", Vector3(0.045, 0.18, 0.045), Vector3(0, 0, 0), WOOD)
		_box(weapon, "SwordGuard", Vector3(0.2, 0.04, 0.065), Vector3(0, 0.105, 0), GOLD)
		_box(weapon, "SwordBlade", Vector3(0.058, 0.39, 0.025), Vector3(0, 0.31, 0), STEEL)
	var ring = selection(0.42, cloth.lightened(0.25))
	ring.name = "UnitSelection"
	ring.visible = false
	root.add_child(ring)
	return root


static func worker() -> Node3D:
	var root = unit("archers", "ally")
	root.name = "OriginalWorker"
	root.set_meta("kind", "worker")
	var rig = root.get_node("Rig") as Node3D
	var weapon = rig.get_node("Weapon") as Node3D
	for child in weapon.get_children():
		weapon.remove_child(child)
		child.free()
	_beam(weapon, "ToolHandle", Vector3(0, -0.1, 0), Vector3(0, 0.4, 0), 0.027, WOOD_LIGHT)
	_box(weapon, "ToolHead", Vector3(0.24, 0.12, 0.045), Vector3(0.03, 0.32, 0), STEEL)
	_box(rig, "SupplySatchel", Vector3(0.22, 0.25, 0.13), Vector3(-0.23, 0.55, -0.1), WOOD_LIGHT)
	return root


static func animate_unit(node: Node3D, state: String, phase: float, selected: bool) -> void:
	var rig = node.get_node_or_null("Rig") as Node3D
	if rig == null:
		return
	var walking = state in ["walk", "walking", "move", "moving"]
	var attacking = state in ["attack", "attacking"]
	var dead = state in ["death", "dead", "dying"]
	var rhythm = sin(phase * 9.0)
	rig.position.y = absf(rhythm) * 0.055 if walking else sin(phase * 2.0) * 0.016
	rig.rotation = Vector3(0, sin(phase * 10) * 0.09 if attacking else 0, 1.35 if dead else 0)
	if dead:
		rig.position.y = 0.06
	elif state == "hit":
		rig.rotation.x = -0.18 * absf(sin(phase * 12))
	for name in ["LeftLeg", "RightLeg"]:
		var leg = rig.get_node_or_null(name) as Node3D
		if leg != null:
			leg.rotation.x = rhythm * (0.48 if name == "LeftLeg" else -0.48) if walking else 0.0
	var weapon = rig.get_node_or_null("Weapon") as Node3D
	if weapon != null:
		weapon.rotation.x = -1.0 * maxf(0.0, sin(phase * 9.0)) if attacking else rhythm * 0.12 if walking else 0.0
	var ring = node.get_node_or_null("UnitSelection") as Node3D
	if ring != null:
		ring.visible = selected and not dead


static func _window(parent: Node3D, at: Vector3, width: float = 0.35) -> void:
	_box(parent, "WindowShadow", Vector3(width, 0.48, 0.035), at, Color("27383d"))
	_box(parent, "WindowSill", Vector3(width + 0.1, 0.06, 0.08), at + Vector3(0, -0.25, 0.025), WOOD_LIGHT)
	_box(parent, "WindowCross", Vector3(0.035, 0.48, 0.055), at + Vector3(0, 0, 0.023), WOOD_LIGHT)


static func _banner(parent: Node3D, at: Vector3, faction: Color) -> void:
	_round(parent, "BannerPole", 0.035, 1.35, at + Vector3(0, 0.65, 0), WOOD_LIGHT)
	_box(parent, "FactionBanner", Vector3(0.58, 0.48, 0.025), at + Vector3(0.27, 1.03, 0), faction)
	_box(parent, "BannerEmblem", Vector3(0.12, 0.2, 0.035), at + Vector3(0.27, 1.03, 0.021), GOLD)


static func _tower(parent: Node3D, at: Vector3, radius: float, height: float, roof: bool, faction: Color) -> void:
	_round(parent, "StoneTower", radius, height, at + Vector3(0, height * 0.5, 0), STONE)
	_round(parent, "TowerFooting", radius * 1.1, 0.2, at + Vector3(0, 0.1, 0), STONE_DARK)
	_round(parent, "TowerCoping", radius * 1.09, 0.14, at + Vector3(0, height - 0.05, 0), STONE_DARK)
	_window(parent, at + Vector3(0, height * 0.67, radius + 0.03), 0.24)
	if roof:
		_round(parent, "SlateSpire", radius * 1.2, 1.15, at + Vector3(0, height + 0.5, 0), Color("405f70"), true)
		_banner(parent, at + Vector3(0, height + 0.94, 0), faction)
	else:
		for i in range(8):
			var angle = i * TAU / 8.0
			var merlon = _box(parent, "Battlement", Vector3(0.25, 0.3, 0.25), at + Vector3(sin(angle) * radius * 0.86, height + 0.12, cos(angle) * radius * 0.86), STONE)
			merlon.rotation.y = angle


static func building(kind: String, team: String) -> Node3D:
	var root = Node3D.new()
	root.name = "Original" + kind.capitalize()
	var faction = _faction("enemy" if kind == "enemy_keep" else team)
	var roof_color = Color("405f70") if faction == ALLY else Color("784958")
	if kind in ["keep", "enemy_keep"]:
		_box(root, "StoneFoundation", Vector3(4.2, 0.25, 3.55), Vector3(0, 0.125, 0), STONE_DARK)
		_box(root, "GreatHall", Vector3(3.6, 2.25, 2.8), Vector3(0, 1.3, 0), STONE)
		_part(root, "HallRoof", "roof", Vector3(2.05, 1.15, 1.65), Vector3(0, 2.43, 0), roof_color)
		_box(root, "KeepDoor", Vector3(0.8, 1.05, 0.08), Vector3(0, 0.77, 1.43), WOOD)
		_box(root, "DoorLintel", Vector3(1.03, 0.18, 0.17), Vector3(0, 1.39, 1.48), STONE_DARK)
		for x in [-1.18, 1.18]:
			_window(root, Vector3(x, 1.65, 1.44))
			_tower(root, Vector3(x * 1.55, 0, -0.65), 0.56, 3.0, false, faction)
		_banner(root, Vector3(0, 3.48, 0), faction)
	elif kind in ["tower", "outpost"]:
		_tower(root, Vector3.ZERO, 0.73 if kind == "tower" else 0.57, 2.75 if kind == "tower" else 2.0, true, faction)
		_box(root, "TowerDoor", Vector3(0.43, 0.72, 0.04), Vector3(0, 0.36, 0.76 if kind == "tower" else 0.60), WOOD)
	elif kind == "sawmill":
		_timber_house(root, Vector3(2.7, 1.6, 2.3), roof_color, faction)
		for i in range(5):
			var log_node = _round(root, "StackedLog", 0.14, 1.7, Vector3(1.7, 0.17 + (i / 3) * 0.23, -0.7 + (i % 3) * 0.31), WOOD_LIGHT)
			log_node.rotation.z = PI / 2.0
		var wheel = _round(root, "SawWheel", 0.42, 0.09, Vector3(-1.52, 0.65, 0.2), STONE_DARK)
		wheel.rotation.z = PI / 2.0
		for i in range(6):
			var angle = i * TAU / 6.0
			_beam(root, "SawSpoke", Vector3(-1.58, 0.65, 0.2), Vector3(-1.58, 0.65 + cos(angle) * 0.38, 0.2 + sin(angle) * 0.38), 0.03, STEEL)
	else:
		_timber_house(root, Vector3(3.05, 1.8, 2.4), roof_color, faction)
		for x in [-1.25, 1.25]:
			_box(root, "WeaponRackPost", Vector3(0.09, 0.85, 0.09), Vector3(x, 0.43, 1.68), WOOD)
		_box(root, "WeaponRackBar", Vector3(2.6, 0.075, 0.075), Vector3(0, 0.7, 1.68), WOOD)
		for i in range(5):
			_round(root, "TrainingSpear", 0.023, 1.2, Vector3(-0.8 + i * 0.4, 0.6, 1.66), WOOD_LIGHT)
			_round(root, "SpearPoint", 0.065, 0.15, Vector3(-0.8 + i * 0.4, 1.25, 1.66), STEEL, true)
	return root


static func _timber_house(parent: Node3D, dimensions: Vector3, roof: Color, faction: Color) -> void:
	_box(parent, "StonePlinth", dimensions * Vector3(1.07, 0, 1.07) + Vector3(0, 0.25, 0), Vector3(0, 0.125, 0), STONE_DARK)
	_box(parent, "PlasterWalls", dimensions, Vector3(0, dimensions.y * 0.5 + 0.2, 0), Color("c3b696"))
	for x in [-0.48, 0, 0.48]:
		_box(parent, "TimberUpright", Vector3(0.12, dimensions.y, 0.1), Vector3(x * dimensions.x, dimensions.y * 0.5 + 0.2, dimensions.z * 0.5 + 0.025), WOOD)
	_box(parent, "TimberCrossbeam", Vector3(dimensions.x, 0.12, 0.1), Vector3(0, dimensions.y * 0.62, dimensions.z * 0.5 + 0.03), WOOD)
	_part(parent, "GabledRoof", "roof", Vector3(dimensions.x * 0.57, 0.95, dimensions.z * 0.58), Vector3(0, dimensions.y + 0.23, 0), roof)
	_box(parent, "Door", Vector3(0.58, 0.9, 0.065), Vector3(0, 0.65, dimensions.z * 0.5 + 0.095), WOOD_LIGHT)
	_window(parent, Vector3(dimensions.x * 0.32, 1.15, dimensions.z * 0.5 + 0.06), 0.39)
	_box(parent, "Chimney", Vector3(0.35, 0.8, 0.4), Vector3(-dimensions.x * 0.3, dimensions.y + 0.7, -0.3), STONE)
	_banner(parent, Vector3(dimensions.x * 0.35, dimensions.y + 0.53, 0), faction)
