class_name FxPool
extends Node3D
## Recycles short-lived effect nodes (particle bursts, floating text, rings, slashes,
## lightning) so combat doesn't create and free hundreds of nodes per second.
## One pool lives in each GameWorld (as its "Fx" root) and dies with the level.

const MAX_PER_KIND := 48

var _pools: Dictionary = {}


func take(kind: String, factory: Callable, lifetime: float) -> Node:
	## A node of `kind` that is free (its previous effect finished), reused or created.
	## When the pool is full the oldest effect is recycled early.
	var now := Time.get_ticks_msec()
	var until := now + int(lifetime * 1000.0)
	var list: Array = _pools.get(kind, [])
	var oldest: Node = null
	for n in list:
		var free_at := int(n.get_meta("free_at", 0))
		if free_at <= now:
			_claim(n, until)
			return n
		if oldest == null or free_at < int(oldest.get_meta("free_at", 0)):
			oldest = n
	if list.size() >= MAX_PER_KIND and oldest != null:
		_claim(oldest, until)
		return oldest
	var fresh: Node = factory.call()
	add_child(fresh)
	list.append(fresh)
	_pools[kind] = list
	_claim(fresh, until)
	return fresh


func _claim(n: Node, until: int) -> void:
	if n.has_meta("tween"):
		var old: Variant = n.get_meta("tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	n.set_meta("free_at", until)
	n.set("visible", true)


func pooled_count() -> int:
	var total := 0
	for k in _pools:
		total += (_pools[k] as Array).size()
	return total
