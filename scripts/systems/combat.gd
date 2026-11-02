class_name Combat
extends RefCounted
## Player-to-enemy damage pipeline: crits, enchantment hooks, kills.


static func player_strike(player, enemy, mult: float, tags: Dictionary = {}) -> bool:
	## Returns true if the hit killed the enemy.
	if player == null or enemy == null or not is_instance_valid(enemy) or enemy.dead:
		return false
	var w: Dictionary = player.stats.get("weapon", StatCalc.FISTS)
	var crit_chance := float(w.get("crit_chance", 0.05)) + float(player.stats.get("crit_chance", 0.0))
	var crit: bool = tags.get("force_crit", false) or randf() < crit_chance
	if player.force_next_crit and not tags.get("proc", false):
		crit = true
		player.force_next_crit = false
	var ctx := {"player": player, "target": enemy, "damage": float(w.get("damage", 4.0)) * mult, "crit": crit,
		"mult": 1.0, "tags": tags, "killed": false, "final": 0.0}
	Enchants.run("pre_hit", player, ctx)
	if crit:
		ctx.mult *= float(w.get("crit_mult", 1.5)) + float(player.stats.get("crit_mult_bonus", 0.0))
	ctx.mult *= player.damage_multiplier()
	if tags.get("proc", false):
		# chains, explosions and other effect damage: the "elemental damage" passive
		ctx.mult *= 1.0 + float(player.stats.get("proc_damage_pct", 0.0))
	var final := float(ctx.damage) * float(ctx.mult)
	var kb := float(w.get("knockback", 3.0)) * float(tags.get("knockback_mult", 1.0))
	var killed: bool = enemy.take_hit(final, crit, player.global_position, kb)
	ctx.final = final
	ctx.killed = killed
	if not tags.get("proc", false):
		if not killed and randf() < float(w.get("stun_chance", 0.0)):
			enemy.stun(1.0)
		Enchants.run("post_hit", player, ctx)
		if crit:
			Enchants.run("on_crit", player, ctx)
	if killed:
		Enchants.run("on_kill", player, ctx)
	player.on_hit_landed(crit)
	return killed


static func enemies_in_arc(origin: Vector3, dir: Vector3, reach: float, arc_deg: float) -> Array:
	var out: Array = []
	var half := deg_to_rad(arc_deg) * 0.5
	for e in GameState.world.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - origin
		to.y = 0
		var dist := to.length()
		if dist > reach + float(e.radius):
			continue
		if dist > 0.6 and arc_deg < 359.0 and absf(dir.angle_to(to.normalized())) > half:
			continue
		out.append(e)
	return out


static func enemies_in_radius(origin: Vector3, radius: float, exclude = null) -> Array:
	var out: Array = []
	for e in GameState.world.get_tree().get_nodes_in_group("enemies"):
		if e == exclude or e.dead:
			continue
		var to: Vector3 = e.global_position - origin
		to.y = 0
		if to.length() <= radius + float(e.radius):
			out.append(e)
	return out
