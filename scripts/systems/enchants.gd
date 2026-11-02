class_name Enchants
extends RefCounted
## Enchantment effect handlers. Each enchantment in enchantments.json names a
## 'hook' (when it fires) and an 'effect' (which handler below runs).
## A new enchantment that reuses an effect needs only JSON; a brand new effect
## needs one more `match` branch in _apply().


static func run(hook: String, player, ctx: Dictionary) -> void:
	for e in player.active_enchants:
		if str(e.hook) == hook:
			_apply(str(e.effect), e.params, player, ctx, e)


static func _apply(effect: String, p: Dictionary, player, ctx: Dictionary, e: Dictionary) -> void:
	var target = ctx.get("target")
	var col: Color = e.color
	match effect:
		"bonus_vs_low_hp":
			if target != null and target.hp / target.max_hp < float(p.get("threshold", 0.3)):
				ctx.mult = float(ctx.mult) * (1.0 + float(p.get("bonus", 0.5)))
				Fx.text(target.global_position + Vector3(0, 2.2, 0), "EXECUTE", col, 0.8)
		"heal_on_hit":
			player.heal(float(ctx.final) * float(p.get("pct", 0.05)), false)
		"dot_on_hit":
			if target != null and not ctx.killed and randf() < float(p.get("chance", 1.0)):
				var dur := float(p.get("duration", 3.0))
				target.add_dot(float(ctx.final) * float(p.get("pct", 0.5)) / dur, dur, col)
		"chain_on_hit":
			if target != null and randf() < float(p.get("chance", 0.2)):
				var from: Vector3 = target.global_position
				var hit: Array = [target]
				for i in int(p.get("jumps", 1)):
					var next = _nearest(from, float(p.get("radius", 6.0)), hit)
					if next == null:
						break
					Fx.lightning(from + Vector3(0, 1, 0), next.global_position + Vector3(0, 1, 0), col)
					Audio.play("zap", -4.0)
					hit.append(next)
					from = next.global_position
					Combat.player_strike(player, next, float(p.get("mult", 0.6)), {"proc": true, "knockback_mult": 0.3})
		"teleport_on_hit":
			if target != null and not ctx.killed and randf() < float(p.get("chance", 0.1)):
				player.glitch_behind(target)
				player.force_next_crit = true
		"stun_on_hit":
			if target != null and not ctx.killed and randf() < float(p.get("chance", 0.1)):
				target.stun(float(p.get("duration", 1.0)))
		"buff_on_crit":
			player.add_buff("overload", float(p.get("bonus", 0.2)), float(p.get("duration", 3.0)))
			Fx.burst(player.global_position + Vector3(0, 1.2, 0), col, 8, 3.0, 0.1, 0.4, 0.0)
		"explode_on_kill":
			if target != null:
				var pos: Vector3 = target.global_position
				var radius := float(p.get("radius", 3.0))
				Fx.burst(pos + Vector3(0, 0.8, 0), col, 30, 9.0, 0.16, 0.6, -4.0)
				Fx.ring(pos, radius, col, 0.35)
				Audio.play("explosion", -8.0)
				for other in Combat.enemies_in_radius(pos, radius, target):
					Combat.player_strike(player, other, float(p.get("mult", 1.0)), {"proc": true, "knockback_mult": 1.5})
		"heal_on_kill":
			player.heal(float(p.get("value", 5)), true)
		"gold_on_kill":
			if target != null and randf() < float(p.get("chance", 0.3)):
				GameState.world.spawn_gold(target.global_position, int(p.get("value", 5)))
		"wave_on_swing":
			var dir: Vector3 = ctx.get("dir", Vector3.FORWARD)
			GameState.world.spawn_player_wave(player.global_position + dir * 0.8, dir, float(p.get("mult", 0.5)), float(p.get("speed", 16)), float(p.get("range", 9)), col)
		"stat_bonus", "shield_periodic":
			pass  # passive: handled by StatCalc / Player
		_:
			push_warning("[Enchants] Unknown effect '%s'" % effect)


static func _nearest(from: Vector3, radius: float, exclude: Array):
	var best = null
	var best_d := radius
	for en in GameState.world.get_tree().get_nodes_in_group("enemies"):
		if en.dead or en in exclude:
			continue
		var d: float = from.distance_to(en.global_position)
		if d < best_d:
			best_d = d
			best = en
	return best
