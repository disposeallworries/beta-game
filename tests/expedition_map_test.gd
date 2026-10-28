extends SceneTree
const MapScript = preload("res://scripts/expedition_map.gd")
const PlayerScript = preload("res://scripts/player.gd")
var checks: int = 0
var failures: int = 0
var world: Node3D

func _initialize()->void:
	call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("Expedition map: "+message)
func run()->void:
	world=MapScript.new()
	root.add_child(world)
	world.setup()
	check(world.boxes.size()>=50,"Large map includes at least50 collision pieces")
	var footprint:AABB=world.boxes[0]
	for bounds:AABB in world.boxes:
		footprint=footprint.merge(bounds)
	check(footprint.size.x>=145 and footprint.size.z>=150,"Four branches cover a large two-axis map")
	check(world.pools.size()==7,"Seven finite mana sites exist")
	check(world.swords.size()==2,"Two physical sword pickups exist")
	check(world.safe_points.size()==7,"Hub and all remote pools have recovery pads")
	check(world.POOL_ROUTES.size()==7,"Every mana site has a documented approach route")
	var total:float=0
	for pool:Dictionary in world.pools:
		total+=pool["remaining"]
		check(pool["remaining"]==pool["capacity"] and float(pool["capacity"])>=90,"Pool starts with its real finite reserve")
	check(is_equal_approx(total,810),"Total reserve is810mana, requiring route choices at the600corecap")
	var narrow:bool=false
	var tall:bool=false
	for bounds:AABB in world.boxes:
		narrow=narrow or minf(bounds.size.x,bounds.size.z)<2.0
		tall=tall or bounds.size.y>4.0
	check(narrow and tall,"Narrow beams and a tall wall-jump shaft add physical challenge")
	for point:Dictionary in world.safe_points:
		var p:ParkourPlayer=PlayerScript.new()
		root.add_child(p)
		p.boxes=world.boxes
		p.respawn(point["position"])
		for tick in 12:p.simulate(1.0/120,{})
		check(p.grounded and p.position.is_equal_approx(point["position"]),"Recovery pad is clear and stable: "+point["name"])
		p.free()
	for id in world.POOL_ROUTES:
		var route:Array=world.POOL_ROUTES[id]
		check(not route.is_empty() and int(route[0])==0,"Pool route starts at the sanctuary")
		for index:int in route:check(index>=0 and index<world.boxes.size(),"Approach references an actual collision platform")
		for i in range(route.size()-1):
			var a:AABB=world.boxes[route[i]]
			var b:AABB=world.boxes[route[i+1]]
			var gap_x:float=maxf(0,maxf(b.position.x-a.end.x,a.position.x-b.end.x))
			var gap_z:float=maxf(0,maxf(b.position.z-a.end.z,a.position.z-b.end.z))
			check(Vector2(gap_x,gap_z).length()<=3.25,"Route gap fits the current sprint jump envelope")
			check(b.end.y-a.end.y<=2.25 or int(route[i+1])==int(world.shaft["top"]),"Large vertical steps occur only in the wall-jump shaft")
	_test_harvest()
	_test_pickups()
	_test_portal_and_reset()
	world.free()
	print("Expedition map: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
func _test_harvest()->void:
	var at:Vector3=world.pools[0]["position"]
	check(world.harvest(at,false,0,.5,600).is_empty(),"Airborne player cannot channel")
	check(world.harvest(at,true,.6,.5,600).is_empty(),"Moving player cannot channel")
	check(world.harvest(at+Vector3(2,0,0),true,0,.5,600).is_empty(),"Channeling requires standing inside the pool")
	check(world.harvest(at+Vector3(0,.5,0),true,0,.5,600).is_empty(),"Channeling requires correct vertical standing height")
	check(world.harvest(at,true,0,.5,0).is_empty(),"A full core does not consume a pool")
	check(world.harvest(at,true,0,-.5,600).is_empty(),"Negative time cannot create resources")
	var drawn:Dictionary=world.harvest(at,true,0,.5,600)
	check(is_equal_approx(drawn["amount"],12) and drawn["pool_id"]==0,"Standing channels24mana per second from the named pool")
	check(is_equal_approx(world.pools[0]["remaining"],78),"Harvest subtracts only the actual amount")
	drawn=world.harvest(at,true,0,1,3.5)
	check(is_equal_approx(drawn["amount"],3.5) and is_equal_approx(world.pools[0]["remaining"],74.5),"Near-full core capacity bounds the transfer without wasting reserve")
	drawn=world.harvest(at,true,0,20,600)
	check(is_equal_approx(drawn["amount"],74.5) and is_zero_approx(world.pools[0]["remaining"]),"A depleted pool cannot overdraw")
	drawn=world.harvest(at,true,0,10,600)
	check(is_zero_approx(drawn["amount"]),"Staying in an empty pool does not generate infinite mana")
	var visuals:Dictionary=world._pool_visuals[0]
	check(not visuals["crystal"].visible and visuals["label"].text.contains("EMPTY"),"Depleted pool changes its beacon and label")
	check(world.get_hint(at).contains("Nearest pool"),"Hint points to a remaining site after depletion")
func _test_pickups()->void:
	var at:Vector3=world.swords[0]["position"]
	check(world.take_sword(at+Vector3(0,2,0))==0,"Sword pickup checks vertical proximity")
	check(world.take_sword(at)==1,"Garden blade grants level one")
	check(world.take_sword(at)==0 and world.swords[0]["taken"],"Collected blade cannot be duplicated")
	check(not world._sword_visuals[0].visible,"Collected blade disappears from the map")
	check(world.take_sword(world.swords[1]["position"])==2,"Harder Crown route grants the stronger sword")
func _test_portal_and_reset()->void:
	check(world.portal_in_range(world.portal_position),"Portal accepts player in its entrance radius")
	check(not world.portal_in_range(world.portal_position+Vector3(3,0,0)),"Distant portal cannot be activated")
	check(not world.portal_in_range(world.portal_position+Vector3(0,3,0)),"Portal checks vertical position")
	world.set_portal_ready(true)
	check(world.portal_ready and world._portal_material.emission_enabled,"Ready rift lights up")
	world.tick(.5)
	check(is_finite(world._pool_visuals[0]["crystal"].position.y),"Resource and portal animation stays finite")
	world.reset_resources()
	check(not world.portal_ready,"Restart closes early portal activation")
	for pool:Dictionary in world.pools:check(pool["remaining"]==pool["capacity"],"Restart restores finite reserves")
	for i in world.swords.size():check(not world.swords[i]["taken"] and world._sword_visuals[i].visible,"Restart restores both sword pickups")
