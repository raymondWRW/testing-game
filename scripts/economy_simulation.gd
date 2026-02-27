extends Node
class_name EconomySimulation

## Economic simulation manager - port of npc_simulation.py
## Manages monthly ticks, seasons, resource production/consumption, market, and NPC lifecycle

signal month_changed(year: int, month: int, season: String)
signal npc_died(npc: Node)
signal npc_born(npc: Node, parent: Node)
signal simulation_stats_updated(stats: Dictionary)

enum Season { SPRING, SUMMER, FALL, WINTER }
enum Role { FARMER, LUMBERJACK, NOBLE }

## Simulation speed (seconds per in-game month)
@export var seconds_per_month: float = 10.0

## Enable/disable automatic simulation ticks
@export var auto_simulate: bool = true

## Current time
var year: int = 1
var month: int = 1  # 1-12
var total_months: int = 0

## Timer for monthly ticks
var _month_timer: float = 0.0

## All NPCs in the simulation (references to NPC nodes)
var npcs: Array[Node] = []

## Statistics tracking
var monthly_stats: Array[Dictionary] = []

func _ready() -> void:
	print("EconomySimulation ready")

func _process(delta: float) -> void:
	if not auto_simulate:
		return

	_month_timer += delta
	if _month_timer >= seconds_per_month:
		_month_timer -= seconds_per_month
		simulate_month()

## Get the current season based on month
func get_season() -> Season:
	if month in [1, 2, 3]:
		return Season.SPRING
	elif month in [4, 5, 6]:
		return Season.SUMMER
	elif month in [7, 8, 9]:
		return Season.FALL
	else:
		return Season.WINTER

func get_season_name() -> String:
	match get_season():
		Season.SPRING: return "Spring"
		Season.SUMMER: return "Summer"
		Season.FALL: return "Fall"
		Season.WINTER: return "Winter"
	return "Unknown"

## Register an NPC with the simulation
func register_npc(npc: Node) -> void:
	if npc not in npcs:
		npcs.append(npc)
		print("Registered NPC: %s (total: %d)" % [npc.name, npcs.size()])

## Unregister an NPC from the simulation
func unregister_npc(npc: Node) -> void:
	var idx := npcs.find(npc)
	if idx >= 0:
		npcs.remove_at(idx)

## Get all alive NPCs
func get_alive_npcs() -> Array[Node]:
	var alive: Array[Node] = []
	for npc in npcs:
		if is_instance_valid(npc) and npc.has_method("is_alive") and npc.is_alive():
			alive.append(npc)
	return alive

## Get NPCs by role
func get_npcs_by_role(role: Role) -> Array[Node]:
	var result: Array[Node] = []
	for npc in get_alive_npcs():
		if npc.has_method("get_economic_role") and npc.get_economic_role() == role:
			result.append(npc)
	return result

## Get population count by role
func get_population_by_role() -> Dictionary:
	return {
		Role.FARMER: get_npcs_by_role(Role.FARMER).size(),
		Role.LUMBERJACK: get_npcs_by_role(Role.LUMBERJACK).size(),
		Role.NOBLE: get_npcs_by_role(Role.NOBLE).size()
	}

## Run one month of simulation
func simulate_month() -> Dictionary:
	var season := get_season()

	# Track population before
	var pop_before := get_population_by_role()

	# 1. Resource production based on role
	_produce_resources(season)

	# 2. Noble taxation
	_noble_taxation()

	# 3. Resource consumption
	_consume_resources(season)

	# 4. Resource decay (10% per month)
	_apply_decay()

	# 5. Market trading
	_run_market(season)

	# 6. Gold balance (inflation/deflation)
	_balance_gold()

	# 7. Death check (starvation/freezing)
	_check_deaths(season)

	# 8. Replication (birth)
	_check_replication(season)

	# Track population after
	var pop_after := get_population_by_role()

	# Calculate statistics
	var stats := _calculate_stats(pop_before, pop_after, season)
	monthly_stats.append(stats)

	# Emit signal
	month_changed.emit(year, month, get_season_name())
	simulation_stats_updated.emit(stats)

	# Advance time
	total_months += 1
	month += 1
	if month > 12:
		month = 1
		year += 1

	print("Month %d, Year %d (%s) - Population: %d" % [month, year, get_season_name(), get_alive_npcs().size()])

	return stats

## NPCs produce resources based on their role
func _produce_resources(season: Season) -> void:
	for npc in get_alive_npcs():
		if not npc.has_method("get_economic_role"):
			continue

		var role: Role = npc.get_economic_role()

		match role:
			Role.FARMER:
				# Farmers gain 100 food in each fall month
				if season == Season.FALL:
					npc.food += 100
			Role.LUMBERJACK:
				# Lumberjacks gain 10 wood per month
				npc.wood += 10
			Role.NOBLE:
				# Nobles don't produce resources
				pass

## Nobles tax other NPCs
func _noble_taxation() -> void:
	var nobles := get_npcs_by_role(Role.NOBLE)
	var non_nobles: Array[Node] = []
	for npc in get_alive_npcs():
		if npc.has_method("get_economic_role") and npc.get_economic_role() != Role.NOBLE:
			non_nobles.append(npc)

	for noble in nobles:
		for target in non_nobles:
			# Can only take from NPCs with >= 10 food and >= 2 wood
			if target.food >= 10 and target.wood >= 2 and target.gold >= 1:
				target.gold -= 1
				noble.gold += 1

## NPCs consume food and wood
func _consume_resources(season: Season) -> void:
	for npc in get_alive_npcs():
		if not npc.has_method("get_monthly_food_need"):
			continue

		npc.food -= npc.get_monthly_food_need()
		npc.wood -= npc.get_monthly_wood_need(int(season))

## Food and wood decay by 10% each month (round up)
func _apply_decay() -> void:
	for npc in get_alive_npcs():
		var food_decay := ceili(npc.food * 0.1)
		var wood_decay := ceili(npc.wood * 0.1)
		npc.food = maxf(0.0, npc.food - food_decay)
		npc.wood = maxf(0.0, npc.wood - wood_decay)

## Run the market for buying/selling resources
func _run_market(season: Season) -> void:
	var food_buyers: Array = []  # [npc, gold_to_spend]
	var food_sellers: Array = []  # [npc, food_to_sell]
	var wood_buyers: Array = []
	var wood_sellers: Array = []

	for npc in get_alive_npcs():
		if not npc.has_method("get_months_of_food"):
			continue

		var months_food: float = npc.get_months_of_food()
		var months_wood: float = npc.get_months_of_wood(int(season))

		# Buy orders: if less than 3 months supply, spend 50% gold
		if months_food < 3.0 and npc.gold > 0:
			var gold_to_spend: float = npc.gold * 0.5
			if gold_to_spend >= 1.0:
				food_buyers.append([npc, gold_to_spend])

		if months_wood < 3.0 and npc.gold > 0:
			var gold_to_spend: float = npc.gold * 0.5
			if gold_to_spend >= 1.0:
				wood_buyers.append([npc, gold_to_spend])

		# Sell orders: if more than 2 years (24 months) supply, sell extra
		if months_food > 24.0:
			var extra_food: float = npc.food - (24 * npc.get_monthly_food_need())
			if extra_food > 0:
				food_sellers.append([npc, extra_food])

		if months_wood > 24.0:
			var avg_wood_need: float = (1 + 1 + 1 + 5) / 4.0  # Average across seasons
			var extra_wood: float = npc.wood - (24 * avg_wood_need)
			if extra_wood > 0:
				wood_sellers.append([npc, extra_wood])

	# Execute food market
	_execute_market(food_buyers, food_sellers, "food")

	# Execute wood market
	_execute_market(wood_buyers, wood_sellers, "wood")

## Execute market trades using Hamilton apportionment
func _execute_market(buyers: Array, sellers: Array, resource_type: String) -> void:
	if buyers.is_empty() or sellers.is_empty():
		return

	var total_gold: float = 0.0
	for buyer in buyers:
		total_gold += buyer[1]

	var total_resource: float = 0.0
	for seller in sellers:
		total_resource += seller[1]

	if total_gold <= 0 or total_resource <= 0:
		return

	# Hamilton apportionment for resources to buyers
	var resource_allocation: Array = []
	for buyer in buyers:
		var npc: Node = buyer[0]
		var gold: float = buyer[1]
		var quota: float = (gold / total_gold) * total_resource
		resource_allocation.append([npc, gold, int(quota), quota - int(quota)])

	# Distribute integer parts
	var allocated: int = 0
	for alloc in resource_allocation:
		allocated += alloc[2]
	var remaining: int = int(total_resource) - allocated

	# Sort by remainder (largest first) for remaining resources
	resource_allocation.sort_custom(func(a, b): return a[3] > b[3])

	for i in range(resource_allocation.size()):
		var alloc: Array = resource_allocation[i]
		var npc: Node = alloc[0]
		var gold: float = alloc[1]
		var int_part: int = alloc[2]
		var extra: int = 1 if i < remaining else 0
		var resource_received: int = int_part + extra

		if resource_type == "food":
			npc.food += resource_received
		else:
			npc.wood += resource_received

		npc.gold -= gold

	# Hamilton apportionment for gold to sellers
	var gold_allocation: Array = []
	for seller in sellers:
		var npc: Node = seller[0]
		var amount: float = seller[1]
		var quota: float = (amount / total_resource) * total_gold
		gold_allocation.append([npc, amount, int(quota), quota - int(quota)])

	var allocated_gold: int = 0
	for alloc in gold_allocation:
		allocated_gold += alloc[2]
	var remaining_gold: int = int(total_gold) - allocated_gold

	gold_allocation.sort_custom(func(a, b): return a[3] > b[3])

	for i in range(gold_allocation.size()):
		var alloc: Array = gold_allocation[i]
		var npc: Node = alloc[0]
		var amount: float = alloc[1]
		var int_part: int = alloc[2]
		var extra: int = 1 if i < remaining_gold else 0
		var gold_received: int = int_part + extra

		if resource_type == "food":
			npc.food -= amount
		else:
			npc.wood -= amount

		npc.gold += gold_received

## Balance gold in the economy (inflation/deflation)
func _balance_gold() -> void:
	var alive_npcs := get_alive_npcs()
	if alive_npcs.is_empty():
		return

	var population: int = alive_npcs.size()
	var target_gold: float = 100.0 * population
	var total_gold: float = 0.0

	for npc in alive_npcs:
		total_gold += npc.gold

	if total_gold < target_gold:
		# Increase everyone's gold by 10% (round down)
		for npc in alive_npcs:
			npc.gold += int(npc.gold * 0.1)
	elif total_gold > target_gold:
		# Decrease everyone's gold by 10% (round down)
		for npc in alive_npcs:
			npc.gold -= int(npc.gold * 0.1)

## Check for NPC deaths due to starvation/freezing
func _check_deaths(season: Season) -> void:
	for npc in get_alive_npcs():
		if npc.food < 0 or npc.wood < 0:
			npc.set_alive(false)
			npc_died.emit(npc)
			print("NPC died: %s (food: %.1f, wood: %.1f)" % [npc.name, npc.food, npc.wood])

## Check if NPCs can replicate (give birth)
func _check_replication(season: Season) -> void:
	var new_npcs: Array = []

	for npc in get_alive_npcs():
		if not npc.has_method("get_monthly_food_need"):
			continue

		# 2 years of food = 24 months * 5 = 120 food
		# 2 years of wood = average 2 wood/month * 24 = 48 wood
		var food_for_2_years: float = 24 * npc.get_monthly_food_need()
		var wood_for_2_years: float = 24 * 2.0  # Average wood consumption

		if npc.food > food_for_2_years and npc.wood > wood_for_2_years:
			# Create info for new NPC with half resources
			new_npcs.append({
				"parent": npc,
				"role": npc.get_economic_role(),
				"food": npc.food / 2.0,
				"wood": npc.wood / 2.0,
				"gold": npc.gold / 2.0
			})
			# Parent loses half resources
			npc.food /= 2.0
			npc.wood /= 2.0
			npc.gold /= 2.0

	# Emit signals for new NPCs (actual spawning handled by ground.gd)
	for new_npc_data in new_npcs:
		npc_born.emit(new_npc_data, new_npc_data["parent"])

## Calculate statistics for this month
func _calculate_stats(pop_before: Dictionary, pop_after: Dictionary, season: Season) -> Dictionary:
	var stats := {
		"year": year,
		"month": month,
		"season": get_season_name(),
		"total_population": get_alive_npcs().size(),
	}

	for role in [Role.FARMER, Role.LUMBERJACK, Role.NOBLE]:
		var role_npcs := get_npcs_by_role(role)
		var role_name: String
		match role:
			Role.FARMER: role_name = "farmer"
			Role.LUMBERJACK: role_name = "lumberjack"
			Role.NOBLE: role_name = "noble"

		stats[role_name + "_population"] = role_npcs.size()
		stats[role_name + "_pop_change"] = pop_after[role] - pop_before[role]

		if not role_npcs.is_empty():
			var total_food: float = 0.0
			var total_wood: float = 0.0
			var total_gold: float = 0.0
			for npc in role_npcs:
				total_food += npc.food
				total_wood += npc.wood
				total_gold += npc.gold
			stats[role_name + "_avg_food"] = total_food / role_npcs.size()
			stats[role_name + "_avg_wood"] = total_wood / role_npcs.size()
			stats[role_name + "_avg_gold"] = total_gold / role_npcs.size()
		else:
			stats[role_name + "_avg_food"] = 0.0
			stats[role_name + "_avg_wood"] = 0.0
			stats[role_name + "_avg_gold"] = 0.0

	return stats
