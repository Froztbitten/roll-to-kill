extends SubViewportContainer
class_name Die3DRenderer

signal roll_finished(result_value: int)

@onready var sub_viewport = $SubViewport
@onready var world_node = $SubViewport/World3D

var rigid_body: RigidBody3D
var die_mesh_instance: MeshInstance3D
var die_edges_instance: MeshInstance3D
var die_collision: CollisionShape3D
var labels_root: Node3D

var _target_value: int = 1
var _sides: int = 6
var _is_rolling: bool = false
var _settling: bool = false
var _face_data = [] # Array of {normal: Vector3, value: int}
var _camera: Camera3D

func _ready():
	sub_viewport.transparent_bg = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_environment()

func _setup_environment():
	# Clear existing children of World3D to ensure clean state
	for child in world_node.get_children():
		child.queue_free()
		
	# Camera - Top down view
	_camera = Camera3D.new()
	# Position camera high enough to see the whole box
	_camera.transform.origin = Vector3(0, 25, 0)
	_camera.rotation_degrees = Vector3(-90, 0, 0) # Ensure perfect top-down
	_camera.fov = 35
	world_node.add_child(_camera)
	
	# Floor (Invisible)
	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var floor_box = BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.transform.origin = Vector3(0, -2, 0)
	world_node.add_child(floor_body)
	
	# Invisible Walls Cage
	# Box area is roughly -3 to 3 in X and Z
	var wall_dist = 6.0
	var wall_height = 20.0
	var walls = [
		Vector3(wall_dist, 0, 0), Vector3(-wall_dist, 0, 0),
		Vector3(0, 0, wall_dist), Vector3(0, 0, -wall_dist)
	]
	for pos in walls:
		var wall_body = StaticBody3D.new()
		var wall_shape = CollisionShape3D.new()
		var wall_box = BoxShape3D.new()
		if pos.x != 0: wall_box.size = Vector3(1, wall_height, 20)
		else: wall_box.size = Vector3(20, wall_height, 1)
		wall_shape.shape = wall_box
		wall_body.add_child(wall_shape)
		wall_body.transform.origin = pos
		world_node.add_child(wall_body)

	# RigidBody Die
	rigid_body = RigidBody3D.new()
	rigid_body.mass = 1.5
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.2
	mat.friction = 1.0
	rigid_body.physics_material_override = mat
	rigid_body.gravity_scale = 5.0
	rigid_body.angular_damp = 2.0
	rigid_body.continuous_cd = true # Prevent tunneling
	world_node.add_child(rigid_body)
	
	die_mesh_instance = MeshInstance3D.new()
	var face_mat = StandardMaterial3D.new()
	face_mat.albedo_color = Color.WHITE
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	die_mesh_instance.material_override = face_mat
	rigid_body.add_child(die_mesh_instance)
	
	die_edges_instance = MeshInstance3D.new()
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color.BLACK
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	die_edges_instance.material_override = edge_mat
	rigid_body.add_child(die_edges_instance)
	
	die_collision = CollisionShape3D.new()
	rigid_body.add_child(die_collision)
	
	labels_root = Node3D.new()
	rigid_body.add_child(labels_root)
	
	# Default to D6
	configure(6)

func configure(sides: int):
	_sides = sides
	_generate_die_mesh(sides)

func _generate_die_mesh(sides: int):
	for child in labels_root.get_children():
		child.queue_free()
	_face_data.clear()
	
	var faces = [] # Array of Arrays of Vector3
	var d4_vertex_values = {}
	
	if sides == 4:
		var s = 1.5
		var v0 = Vector3(1, 1, 1).normalized() * s
		var v1 = Vector3(1, -1, -1).normalized() * s
		var v2 = Vector3(-1, 1, -1).normalized() * s
		var v3 = Vector3(-1, -1, 1).normalized() * s
		# Correct winding order for outward normals
		faces = [[v0, v1, v2], [v0, v3, v1], [v0, v2, v3], [v1, v3, v2]]
		
		d4_vertex_values[v0] = 1
		d4_vertex_values[v1] = 2
		d4_vertex_values[v2] = 3
		d4_vertex_values[v3] = 4
		
		_face_data.append({"normal": v0.normalized(), "value": 1})
		_face_data.append({"normal": v1.normalized(), "value": 2})
		_face_data.append({"normal": v2.normalized(), "value": 3})
		_face_data.append({"normal": v3.normalized(), "value": 4})
	elif sides == 8:
		var s = 1.3
		var v = [Vector3(0, s, 0), Vector3(0, -s, 0), Vector3(s, 0, 0), Vector3(-s, 0, 0), Vector3(0, 0, s), Vector3(0, 0, -s)]
		faces = [[v[0], v[4], v[2]], [v[0], v[2], v[5]], [v[0], v[5], v[3]], [v[0], v[3], v[4]], [v[1], v[2], v[4]], [v[1], v[5], v[2]], [v[1], v[3], v[5]], [v[1], v[4], v[3]]]
	elif sides == 10:
		var s = 1.3
		var k = 1.0 * s # Tip height
		# Calculate h to ensure planarity for a regular pentagonal trapezohedron
		var cos36 = cos(deg_to_rad(36))
		var h = k * (1.0 - cos36) / (1.0 + cos36)
		var r = 0.9 * s # Radius
		
		var top = Vector3(0, k, 0)
		var bottom = Vector3(0, -k, 0)
		var r1 = []
		var r2 = []
		
		for i in range(5):
			var angle = deg_to_rad(72 * i)
			r1.append(Vector3(r * cos(angle), h, r * sin(angle)))
			angle = deg_to_rad(72 * i + 36)
			r2.append(Vector3(r * cos(angle), -h, r * sin(angle)))
			
		for i in range(5):
			# Ensure CCW winding for outward normals
			faces.append([top, r1[(i+1)%5], r2[i], r1[i]])
			faces.append([bottom, r2[i], r1[(i+1)%5], r2[(i+1)%5]])
	elif sides == 12:
		var s = 1.0
		var t = (1.0 + sqrt(5.0)) / 2.0
		var one_t = 1.0 / t
		
		var verts = []
		for x in [-1, 1]:
			for y in [-1, 1]:
				for z in [-1, 1]:
					verts.append(Vector3(x, y, z).normalized() * s)
		for y in [-t, t]:
			for z in [-one_t, one_t]:
				verts.append(Vector3(0, y, z).normalized() * s)
		for x in [-one_t, one_t]:
			for z in [-t, t]:
				verts.append(Vector3(x, 0, z).normalized() * s)
		for x in [-t, t]:
			for y in [-one_t, one_t]:
				verts.append(Vector3(x, y, 0).normalized() * s)
		
		# Generate faces by finding 5 closest vertices to each of the 12 icosahedron vertices (face centers)
		var face_centers = [Vector3(0, 1, t), Vector3(0, 1, -t), Vector3(0, -1, t), Vector3(0, -1, -t), Vector3(1, t, 0), Vector3(1, -t, 0), Vector3(-1, t, 0), Vector3(-1, -t, 0), Vector3(t, 0, 1), Vector3(t, 0, -1), Vector3(-t, 0, 1), Vector3(-t, 0, -1)]
		
		for center in face_centers:
			var normal = center.normalized()
			var face_verts = []
			var sorted_verts = []
			for v in verts:
				sorted_verts.append({"v": v, "dot": v.dot(normal)})
			sorted_verts.sort_custom(func(a, b): return a.dot > b.dot)
			for i in range(5): face_verts.append(sorted_verts[i].v)
			
			var tangent = Vector3.UP.cross(normal).normalized()
			if tangent.length() < 0.01: tangent = Vector3.RIGHT.cross(normal).normalized()
			var bitangent = normal.cross(tangent).normalized()
			face_verts.sort_custom(func(a, b): return atan2(a.dot(bitangent), a.dot(tangent)) < atan2(b.dot(bitangent), b.dot(tangent)))
			faces.append(face_verts)
	elif sides == 20:
		var s = 1.2
		var t = (1.0 + sqrt(5.0)) / 2.0
		var v = [Vector3(-1, t, 0).normalized()*s, Vector3(1, t, 0).normalized()*s, Vector3(-1, -t, 0).normalized()*s, Vector3(1, -t, 0).normalized()*s,
				 Vector3(0, -1, t).normalized()*s, Vector3(0, 1, t).normalized()*s, Vector3(0, -1, -t).normalized()*s, Vector3(0, 1, -t).normalized()*s,
				 Vector3(t, 0, -1).normalized()*s, Vector3(t, 0, 1).normalized()*s, Vector3(-t, 0, -1).normalized()*s, Vector3(-t, 0, 1).normalized()*s]
		
		var indices = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
					   [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
					   [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
					   [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
		
		for idx in indices:
			faces.append([v[idx[0]], v[idx[1]], v[idx[2]]])
	else: # Default D6
		var s = 1.0
		var v = [Vector3(-s, s, s), Vector3(s, s, s), Vector3(s, -s, s), Vector3(-s, -s, s), Vector3(-s, s, -s), Vector3(s, s, -s), Vector3(s, -s, -s), Vector3(-s, -s, -s)]
		faces = [[v[0], v[1], v[2], v[3]], [v[1], v[5], v[6], v[2]], [v[5], v[4], v[7], v[6]], [v[4], v[0], v[3], v[7]], [v[4], v[5], v[1], v[0]], [v[3], v[2], v[6], v[7]]]

	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var edge_tool = SurfaceTool.new()
	edge_tool.begin(Mesh.PRIMITIVE_LINES)
	
	for i in range(faces.size()):
		var face_verts = faces[i]
		var center = Vector3.ZERO
		for v in face_verts: center += v
		center /= face_verts.size()
		var normal = center.normalized()
		
		if sides == 4:
			for v in face_verts:
				var val = d4_vertex_values[v]
				var label = Label3D.new()
				label.text = str(val)
				label.font_size = 96
				label.modulate = Color.BLACK
				label.double_sided = false
				
				var label_pos = center.lerp(v, 0.65) + normal * 0.002
				label.look_at_from_position(label_pos, label_pos - normal, (v - center).normalized())
				labels_root.add_child(label)
		else:
			_face_data.append({"normal": normal, "value": i + 1})
			
			var label = Label3D.new()
			label.text = str(i + 1)
			label.font_size = 128
			label.modulate = Color.BLACK
			label.double_sided = false
			var label_pos = center + normal * 0.002
			# Orient label to face outward
			var up_vector = ((face_verts[0] + face_verts[1]) / 2.0 - center).normalized()
			label.look_at_from_position(label_pos, center - normal, up_vector)
			labels_root.add_child(label)
		
		for j in range(1, face_verts.size() - 1):
			surface_tool.set_normal(normal)
			surface_tool.set_uv(Vector2(0, 0))
			surface_tool.add_vertex(face_verts[0])
			surface_tool.set_uv(Vector2(1, 0))
			surface_tool.add_vertex(face_verts[j])
			surface_tool.set_uv(Vector2(0, 1))
			surface_tool.add_vertex(face_verts[j+1])
			
		for j in range(face_verts.size()):
			edge_tool.add_vertex(face_verts[j] * 1.005)
			edge_tool.add_vertex(face_verts[(j + 1) % face_verts.size()] * 1.005)

	surface_tool.index()
	die_mesh_instance.mesh = surface_tool.commit()
	die_collision.shape = die_mesh_instance.mesh.create_convex_shape()
	
	die_edges_instance.mesh = edge_tool.commit()

func roll(value: int, _duration: float = 1.0):
	_target_value = value
	_is_rolling = true
	_settling = false
	
	rigid_body.freeze = false
	rigid_body.sleeping = false
	
	# Spawn high up, slightly offset from center
	var spawn_offset = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	rigid_body.transform.origin = Vector3(0, 8, 0) + spawn_offset
	
	rigid_body.linear_velocity = Vector3.ZERO
	rigid_body.angular_velocity = Vector3.ZERO
	rigid_body.rotation = Vector3(randf()*TAU, randf()*TAU, randf()*TAU)
	
	# Throw towards the center (opposite of offset)
	var throw_dir = -spawn_offset.normalized()
	# Add some randomness to throw
	throw_dir = (throw_dir + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))).normalized()
	
	# Impulse: Down and Across
	var force = randf_range(5.0, 25.0) * rigid_body.mass
	var down_force = randf_range(-5.0, -20.0) * rigid_body.mass
	rigid_body.apply_impulse(throw_dir * force + Vector3(0, down_force, 0))
	
	# Spin
	var spin_speed = randf_range(20.0, 50.0)
	var spin_dir = Vector3([-1, 1].pick_random(), [-1, 1].pick_random(), [-1, 1].pick_random()).normalized()
	rigid_body.angular_velocity = spin_dir * spin_speed
	
	set_process(true)

func _process(_delta):
	if _is_rolling and not _settling:
		# Failsafe: If die falls through floor OR flies out of bounds, snap to result immediately
		var pos = rigid_body.transform.origin
		if pos.y < -5.0 or abs(pos.x) > 15.0 or abs(pos.z) > 15.0:
			_settling = true
			_snap_to_result()
			return

		# Check if settled
		if rigid_body.linear_velocity.length() < 0.1 and rigid_body.angular_velocity.length() < 0.5:
			# Ensure it's near the floor (y approx -1 to -2 depending on size)
			if rigid_body.transform.origin.y < 0: 
				_settling = true
				_snap_to_result()

func skip_animation():
	if _is_rolling:
		if _settling: return
		_snap_to_result()

func _snap_to_result():
	_is_rolling = false
	rigid_body.freeze = true
	
	# Determine result from orientation
	var max_dot = -2.0
	var best_face = null
	
	for f in _face_data:
		var global_normal = rigid_body.transform.basis * f.normal
		var dot = global_normal.dot(Vector3.UP)
		if dot > max_dot:
			max_dot = dot
			best_face = f
			
	if best_face:
		_target_value = best_face.value
		var target_normal = best_face.normal
		
		var current_basis = rigid_body.transform.basis
		var global_normal = current_basis * target_normal
		var axis = global_normal.cross(Vector3.UP).normalized()
		var angle = global_normal.angle_to(Vector3.UP)
		
		# If angle is significant, tween it. Otherwise just finish.
		if angle > 0.001 and axis.is_normalized():
			var tween = create_tween()
			var end_basis = current_basis.rotated(axis, angle).orthonormalized()
			tween.tween_method(func(b): rigid_body.transform.basis = b.orthonormalized(), current_basis, end_basis, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func(): emit_signal("roll_finished", _target_value))
		else:
			emit_signal("roll_finished", _target_value)

func _gui_input(event):
	if _is_rolling and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			skip_animation()
			accept_event()

func get_die_screen_position() -> Vector2:
	if not _camera or not rigid_body:
		return global_position + size / 2.0
	var pos_3d = rigid_body.global_position
	var pos_2d = _camera.unproject_position(pos_3d)
	return global_position + pos_2d
