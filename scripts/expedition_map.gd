extends "res://scripts/course.gd"
class_name ExpeditionMap
## A resource expedition: four routes fan out from the core's portal sanctuary.
const HARVEST_RATE: float = 24.0
const HARVEST_RADIUS: float = 1.3
const HARVEST_SPEED: float = 0.6
var spawn_point := Vector3(0, 0, 5)
var portal_position := Vector3(0, 0, -5)
var safe_points: Array[Dictionary] = []
var pools: Array[Dictionary] = []
var swords: Array[Dictionary] = []
var POOL_ROUTES: Dictionary = {}
var CONNECTOR_ROUTES: Array[Array] = []
var shaft: Dictionary = {}
var portal_ready: bool = false
var _pool_visuals: Dictionary = {}
var _sword_visuals: Array[Node3D] = []
var _portal: Node3D
var _portal_surface: MeshInstance3D
var _portal_material: StandardMaterial3D
var _islands: Array[int] = []
var _clock: float = 0.0

func setup() -> void:
	_environment()
	scenery = Node3D.new()
	scenery.name = "ExpeditionScenery"
	add_child(scenery)
	_island(Vector3.ZERO, Vector2(24, 24), SAND, 2.5) # 0, sanctuary
	safe_points.append({"position": spawn_point, "name": "Core sanctuary"})
	POOL_ROUTES[0] = [0]
	var north: Array[int] = [0]
	for point in [Vector3(0,.4,-16), Vector3(-2,.8,-22), Vector3(1,1.2,-28), Vector3(-2,1.6,-34), Vector3(-7,2.2,-39)]:
		north.append(_island(point, Vector2(4.5,4), MINT))
	north.append(_island(Vector3(-8,3,-45), Vector2(10,8), SAND, 2))
	POOL_ROUTES[1] = north.duplicate()
	north.append(_island(Vector3(-1,3.6,-50), Vector2(4,4), PALE))
	north.append(_island(Vector3(4,4.2,-55), Vector2(3.5,3.5), MINT))
	north.append(_island(Vector3(4,6.4,-60), Vector2(6,5), CORAL, 3))
	var court: int = _island(Vector3(0,6.4,-66), Vector2(10,9), SAND, 2)
	north.append(court)
	var left: int = boxes.size()
	box(Vector3(-4,6.4,-70),Vector3(-1.5,11.2,-62),INK)
	var right: int = boxes.size()
	box(Vector3(1.5,6.4,-70),Vector3(4,11.2,-62),INK)
	var back: int = boxes.size()
	box(Vector3(-4,6.4,-72),Vector3(4,11.2,-70),SLATE)
	north.append(left)
	var crown: int = _island(Vector3(0,11.2,-76), Vector2(12,8), CORAL, 2.5)
	north.append(crown)
	POOL_ROUTES[2] = north.duplicate()
	shaft = {"court":court,"left":left,"right":right,"back":back,"top":left,"center":Vector3(0,6.4,-66),"exit":crown}

	var east: Array[int] = [0]
	for point in [Vector3(16,.3,0),Vector3(22,.8,2),Vector3(28,1.2,-1)]:
		east.append(_island(point,Vector2(4,4.5),PALE))
	east.append(_island(Vector3(34,1.7,-2),Vector2(6,1.7),INK))
	east.append(_island(Vector3(41,2.2,-2),Vector2(4,4),MINT))
	east.append(_island(Vector3(47,4.4,1),Vector2(5,5),CORAL,3))
	east.append(_island(Vector3(55,4.4,0),Vector2(10,10),SAND,2))
	POOL_ROUTES[3] = east.duplicate()
	for point in [Vector3(62,5,-7),Vector3(68,5.5,-12),Vector3(73,6,-18)]:
		east.append(_island(point,Vector2(4,4),PALE))
	east.append(_island(Vector3(76,8.2,-24),Vector2(6,4),CORAL,3))
	east.append(_island(Vector3(76,8.8,-30),Vector2(10,8),MINT,2))
	POOL_ROUTES[4] = east.duplicate()

	var west: Array[int] = [0]
	for point in [Vector3(-16,.2,0),Vector3(-22,.6,-3),Vector3(-28,1,-6)]:
		west.append(_island(point,Vector2(4,4.5),PALE))
	west.append(_island(Vector3(-34,1.6,-9),Vector2(6,1.8),INK))
	west.append(_island(Vector3(-41,2.2,-10),Vector2(4,4),MINT))
	west.append(_island(Vector3(-47,2.8,-14),Vector2(4,4),PALE))
	west.append(_island(Vector3(-53,5,-19),Vector2(5,5),CORAL,3))
	west.append(_island(Vector3(-58,5.6,-24),Vector2(4,4),PALE))
	west.append(_island(Vector3(-64,6.2,-30),Vector2(10,8),MINT,2))
	POOL_ROUTES[5] = west.duplicate()

	var south: Array[int] = [0]
	for point in [Vector3(0,.2,16),Vector3(-2,.6,22),Vector3(2,1,28)]:
		south.append(_island(point,Vector2(4,4),PALE))
	south.append(_island(Vector3(0,1.6,34),Vector2(1.8,6),INK))
	south.append(_island(Vector3(-4,2.2,41),Vector2(4,4),MINT))
	south.append(_island(Vector3(0,2.8,47),Vector2(4,4),PALE))
	south.append(_island(Vector3(5,5,53),Vector2(5,5),CORAL,3))
	south.append(_island(Vector3(4,5.6,59),Vector2(4,4),PALE))
	south.append(_island(Vector3(0,6.2,65),Vector2(4,4),MINT))
	south.append(_island(Vector3(0,8.4,72),Vector2(10,10),CORAL,3))
	POOL_ROUTES[6] = south.duplicate()
	# A deliberately narrow optional shortcut links two resource branches.
	var connector: Array[int] = [north[6]]
	for point in [Vector3(-17,3.2,-44),Vector3(-24,3.7,-41),Vector3(-31,4.2,-38),Vector3(-38,4.8,-35),Vector3(-45,5.4,-32),Vector3(-52,5.8,-29),Vector3(-58,6.2,-29)]:
		connector.append(_island(point,Vector2(4,3.2),STONE))
	connector.append(west[-1])
	CONNECTOR_ROUTES.append(connector)

	_add_pool(0,Vector3(-7,0,-4),90,"Sanctuary spring",false)
	_add_pool(1,Vector3(-8,3,-45),90,"Moss reservoir")
	_add_pool(2,Vector3(0,11.2,-76),110,"Crown cistern")
	_add_pool(3,Vector3(55,4.4,0),110,"Ember fountain")
	_add_pool(4,Vector3(76,8.8,-30),130,"High ember well")
	_add_pool(5,Vector3(-64,6.2,-30),130,"Mist reservoir")
	_add_pool(6,Vector3(0,8.4,72),150,"Moon sanctuary")
	_add_sword(Vector3(-41,2.2,-10),1,"Garden blade")
	_add_sword(Vector3(3,11.2,-76),2,"Crown greatsword")
	_make_portal()
	_build_expedition_scenery()
	_waymarks(north)
	_waymarks(east)
	_waymarks(west)
	_waymarks(south)
	_label(Vector3(0,3.4,9),"CORE SANCTUARY",34,PALE)
	_label(Vector3(0,2.3,-13),"MOSS RIDGE  /  CROWN CISTERN",25,PALE)
	_label(Vector3(13,2,0),"EMBER RIDGE  →",25,PALE)
	_label(Vector3(-13,2,0),"←  MIST RESERVOIR + BLADE",25,PALE)
	_label(Vector3(0,2,13),"MOON SANCTUARY",25,PALE)
	_label(Vector3(0,9.3,-61),"ALTERNATE WALL JUMPS",25,PALE)

func _island(at:Vector3,size:Vector2,color:Color,thickness:float=1.5)->int:
	var index: int = boxes.size()
	platform(at.x,at.y,at.z,size.x,size.y,color,thickness)
	_islands.append(index)
	return index

func _waymarks(route:Array[int])->void:
	for i in range(route.size()-1):
		var bounds: AABB = boxes[route[i]]
		var at := Vector3(bounds.get_center().x,bounds.end.y+.008,bounds.get_center().z)
		if route[i] == 0:
			var next: Vector3 = boxes[route[i+1]].get_center()
			var direction := Vector3(next.x,0,next.z).normalized()
			at = direction*10 + Vector3.UP*.008
		_arrow(at,boxes[route[i+1]].get_center())

func _add_pool(id:int,at:Vector3,capacity:float,title:String,safe:bool=true)->void:
	pools.append({"id":id,"position":at,"capacity":capacity,"remaining":capacity,"name":title})
	if safe:
		safe_points.append({"position":at+Vector3(2,0,0),"name":title})
	var holder := Node3D.new()
	holder.name = "ManaPool%d"%id
	holder.position = at
	scenery.add_child(holder)
	var basin := CylinderMesh.new()
	basin.top_radius=1.55
	basin.bottom_radius=1.55
	basin.height=.06
	basin.radial_segments=40
	_mesh(holder,basin,Vector3.UP*.005,INK)
	var water := CylinderMesh.new()
	water.top_radius=1.36
	water.bottom_radius=1.36
	water.height=.024
	water.radial_segments=40
	var surface := _mesh(holder,water,Vector3.UP*.048,Color("4cb6ce"))
	var water_material := StandardMaterial3D.new()
	water_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.albedo_color=Color("63d8dc")
	water_material.emission_enabled=true
	water_material.emission=Color("2a7c8e")
	water_material.emission_energy_multiplier=.3
	surface.material_override=water_material
	var rim := TorusMesh.new()
	rim.inner_radius=1.36
	rim.outer_radius=1.51
	rim.rings=40
	rim.ring_segments=8
	_mesh(holder,rim,Vector3.UP*.05,Color("a7dbd5"))
	var crystal := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size=Vector3(.32,.65,.32)
	crystal.mesh=prism
	crystal.material_override=water_material
	crystal.position=Vector3(0,1.15,0)
	holder.add_child(crystal)
	var beam := CylinderMesh.new()
	beam.top_radius=.035
	beam.bottom_radius=.035
	beam.height=7
	beam.radial_segments=6
	var beacon := _mesh(holder,beam,Vector3.UP*3.6,Color("59d1dd"))
	beacon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.material_override=water_material
	var label := Label3D.new()
	label.text=title+"\n%d mana"%int(capacity)
	label.font_size=28
	label.pixel_size=.008
	label.position=Vector3(0,2.05,0)
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate=Color("b7efee")
	label.outline_modulate=INK
	label.outline_size=5
	holder.add_child(label)
	_pool_visuals[id]={"holder":holder,"surface":surface,"material":water_material,"crystal":crystal,"beacon":beacon,"label":label}

func _add_sword(at:Vector3,level:int,title:String)->void:
	swords.append({"position":at,"level":level,"taken":false,"name":title})
	var holder := Node3D.new()
	holder.name="SwordPickup%d"%level
	holder.position=at+Vector3.UP*.9
	scenery.add_child(holder)
	_mesh_box(holder,Vector3(0,.45,0),Vector3(.12,.9,.045),PALE if level==1 else Color("c3dde1"))
	_mesh_box(holder,Vector3(0,-.03,0),Vector3(.56,.09,.12),GOLD)
	_mesh_box(holder,Vector3(0,-.2,0),Vector3(.1,.3,.1),INK)
	var tip := PrismMesh.new()
	tip.size=Vector3(.12,.2,.045)
	_mesh(holder,tip,Vector3(0,1,0),PALE)
	var label := Label3D.new()
	label.text=title+"\nWalk close to collect"
	label.position=Vector3(0,1.4,0)
	label.font_size=27
	label.pixel_size=.007
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size=5
	holder.add_child(label)
	_sword_visuals.append(holder)

func _make_portal()->void:
	_portal=Node3D.new()
	_portal.name="ReturnPortal"
	_portal.position=portal_position
	scenery.add_child(_portal)
	var arch := TorusMesh.new()
	arch.inner_radius=1.25
	arch.outer_radius=1.52
	arch.rings=48
	arch.ring_segments=12
	var ring := _mesh(_portal,arch,Vector3.UP*1.8,Color("7352b0"))
	ring.rotation.x=PI/2
	var field := CylinderMesh.new()
	field.top_radius=1.25
	field.bottom_radius=1.25
	field.height=.025
	field.radial_segments=48
	_portal_surface=_mesh(_portal,field,Vector3.UP*1.8,Color("805dd0"))
	_portal_surface.rotation.x=PI/2
	_portal_material=StandardMaterial3D.new()
	_portal_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_portal_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_portal_surface.material_override=_portal_material
	_mesh_box(_portal,Vector3(0,.02,0),Vector3(3.5,.06,1.1),INK)
	_label(portal_position+Vector3(0,3.8,0),"CORE RIFT\n60 mana to cross early  •  E",27,PALE)
	set_portal_ready(false)

func _build_expedition_scenery()->void:
	for offset in [Vector3(-9,0,8),Vector3(9,0,8),Vector3(-9,0,-9),Vector3(9,0,-9)]:
		_tree(offset)
	for id in range(1,pools.size()):
		var at:Vector3=pools[id]["position"]
		_tree(at+Vector3(-3.7,0,-2.5),.7)
		_lantern(at+Vector3(3.4,0,-2.3))
		_lantern(at+Vector3(-3.4,0,2.3))
	for index in _islands:
		var bounds:AABB=boxes[index]
		var rock:=CylinderMesh.new()
		rock.top_radius=minf(bounds.size.x,bounds.size.z)*.32
		rock.bottom_radius=rock.top_radius*.2
		rock.height=1.7 if bounds.size.x<8 else 3.5
		rock.radial_segments=5
		_mesh(scenery,rock,bounds.get_center()-Vector3.UP*(bounds.size.y/2+rock.height/2),SLATE.darkened(.18))
	for info in [Vector4(-96,-5,12,8),Vector4(105,-2,-47,7),Vector4(10,-6,-108,9),Vector4(-45,-3,95,8),Vector4(88,2,75,7)]:
		_distant_island(Vector3(info.x,info.y,info.z),info.w)
	for info in [Vector4(-30,-8,-35,8),Vector4(38,-7,-27,9),Vector4(40,-4,45,9),Vector4(-45,-5,25,8)]:
		_cloud(Vector3(info.x,info.y,info.z),info.w)

func tick(dt:float)->void:
	_clock+=dt
	for pool in pools:
		var visual:Dictionary=_pool_visuals[pool["id"]]
		var crystal:MeshInstance3D=visual["crystal"]
		crystal.rotation.y+=dt*.7
		crystal.position.y=1.15+sin(_clock*1.6+float(pool["id"])*.7)*.08
		_refresh_pool(pool)
	for i in swords.size():
		var holder:Node3D=_sword_visuals[i]
		holder.rotation.y+=dt*.6
		holder.position.y=swords[i]["position"].y+.9+sin(_clock*2+i)*.06
	if is_instance_valid(_portal_surface):
		_portal_surface.scale=Vector3.ONE*(1.0+sin(_clock*1.4)*.025)

func harvest(at:Vector3,grounded:bool,horizontal_speed:float,dt:float,capacity:float)->Dictionary:
	if not grounded or horizontal_speed>=HARVEST_SPEED or dt<=0.0 or capacity<=0.0:
		return {}
	for pool in pools:
		var center:Vector3=pool["position"]
		if Vector2(at.x-center.x,at.z-center.z).length()>HARVEST_RADIUS or absf(at.y-center.y)>.4:
			continue
		var amount:float=minf(HARVEST_RATE*dt,minf(float(pool["remaining"]),capacity))
		pool["remaining"]=maxf(0.0,float(pool["remaining"])-amount)
		_refresh_pool(pool)
		return {"amount":amount,"pool_id":pool["id"],"pool_name":pool["name"],"remaining":pool["remaining"]}
	return {}

func take_sword(at:Vector3)->int:
	for i in swords.size():
		var sword:Dictionary=swords[i]
		var center:Vector3=sword["position"]
		if not sword["taken"] and Vector2(at.x-center.x,at.z-center.z).length()<1.15 and absf(at.y-center.y)<.65:
			sword["taken"]=true
			_sword_visuals[i].hide()
			return sword["level"]
	return 0

func set_portal_ready(ready:bool)->void:
	portal_ready=ready
	if not is_instance_valid(_portal_material):
		return
	_portal_material.albedo_color=Color(.55,.28,.95,.68) if ready else Color(.22,.15,.35,.42)
	_portal_material.emission_enabled=ready
	_portal_material.emission=Color("7440bd")
	_portal_material.emission_energy_multiplier=.5

func portal_in_range(at:Vector3)->bool:
	return Vector2(at.x-portal_position.x,at.z-portal_position.z).length()<2.1 and absf(at.y-portal_position.y)<1.2

func reset_resources()->void:
	_clock=0.0
	for pool in pools:
		pool["remaining"]=pool["capacity"]
		_refresh_pool(pool)
	for i in swords.size():
		swords[i]["taken"]=false
		_sword_visuals[i].show()
	set_portal_ready(false)

func get_hint(at:Vector3)->String:
	var nearest:Dictionary={}
	var distance:float=INF
	for pool in pools:
		if float(pool["remaining"])<=.01:
			continue
		var gap:float=at.distance_to(pool["position"])
		if gap<distance:
			distance=gap
			nearest=pool
	if nearest.is_empty():
		return "All pools drained. Return to the purple core rift."
	if distance<2.0:
		return "%s: %d mana left. Stand still inside the circle."%[nearest["name"],ceili(nearest["remaining"])]
	return "Nearest pool: %s  ·  %d m"%[nearest["name"],roundi(distance)]

func _refresh_pool(pool:Dictionary)->void:
	var visual:Dictionary=_pool_visuals[pool["id"]]
	var ratio:float=float(pool["remaining"])/float(pool["capacity"])
	var mat:StandardMaterial3D=visual["material"]
	mat.albedo_color=Color("63d8dc").lerp(Color("203947"),1.0-ratio)
	visual["crystal"].visible=ratio>0.0
	visual["beacon"].visible=ratio>0.0
	visual["label"].text="%s\n%d / %d mana"%[pool["name"],ceili(pool["remaining"]),int(pool["capacity"])] if ratio>0.0 else pool["name"]+"\nEMPTY"
