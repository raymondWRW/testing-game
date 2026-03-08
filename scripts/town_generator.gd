class_name TownGenerator
extends RefCounted

## Procedurally generates TownData resources for the world

const TOWN_NAMES: Array[String] = [
	"Greenhollow", "Millbrook", "Stonehaven", "Riverdale",
	"Oakvale", "Pinecrest", "Meadowbrook", "Thornwood",
	"Clearwater", "Ironforge", "Silverlake", "Goldfield",
	"Redmont", "Bluehaven", "Whitepeak", "Blackrock",
	"Sunvalley", "Moonhaven", "Starfall", "Dawnbreak",
	"Duskwood", "Frostholm", "Flamecrest", "Windmere",
	"Ashford", "Willowdale", "Briarwood", "Stormwatch",
	"Copperhill", "Emeraldvale", "Crystalford", "Shadowmere"
]

const TOWN_PREFIXES: Array[String] = [
	"North", "South", "East", "West", "Upper", "Lower",
	"Old", "New", "Greater", "Lesser", "Fort", "Port"
]

const TOWN_SUFFIXES: Array[String] = [
	"shire", "ton", "ville", "burg", "ford", "dale",
	"wood", "field", "haven", "brook", "lake", "ridge"
]

## Generate a world of towns
## Returns Array[TownData] and a VoronoiWorld with positions
static func generate_world(num_towns: int, world_seed: int, world_size: Vector2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var towns: Array[TownData] = []
	var positions: Array[Vector2] = []

	# Generate town positions with minimum spacing
	var min_spacing := world_size.x / (sqrt(num_towns) * 1.5)
	positions = _generate_spaced_positions(rng, num_towns, world_size, min_spacing)

	# Generate town data for each position
	for i in range(positions.size()):
		var town := _generate_town(rng, i, positions[i])
		towns.append(town)

	# Create Voronoi world
	var voronoi := VoronoiWorld.new()
	voronoi.world_size = world_size
	for town in towns:
		voronoi.add_site(town.id, town.world_position)
	voronoi.compute_voronoi()

	return {
		"towns": towns,
		"voronoi": voronoi
	}

## Generate positions with minimum spacing using Poisson disk sampling
static func _generate_spaced_positions(rng: RandomNumberGenerator, count: int, bounds: Vector2, min_dist: float) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var max_attempts := 100

	# Start with a random position
	positions.append(Vector2(
		rng.randf() * bounds.x,
		rng.randf() * bounds.y
	))

	while positions.size() < count:
		var found := false

		for _attempt in range(max_attempts):
			# Pick a random position
			var candidate := Vector2(
				rng.randf() * bounds.x,
				rng.randf() * bounds.y
			)

			# Check distance to all existing positions
			var valid := true
			for existing in positions:
				if candidate.distance_to(existing) < min_dist:
					valid = false
					break

			if valid:
				positions.append(candidate)
				found = true
				break

		# If we couldn't find a valid position, reduce spacing requirement
		if not found:
			min_dist *= 0.9
			if min_dist < bounds.x / 20:
				# Give up and just place randomly
				positions.append(Vector2(
					rng.randf() * bounds.x,
					rng.randf() * bounds.y
				))

	return positions

## Generate a single town's data
static func _generate_town(rng: RandomNumberGenerator, index: int, position: Vector2) -> TownData:
	var town := TownData.new()

	# ID
	town.id = StringName("town_%d" % index)

	# Name
	town.town_name = _generate_town_name(rng, index)

	# Seed for deterministic generation
	town.town_seed = rng.randi()

	# Size (varying sizes for variety)
	var size_roll := rng.randf()
	if size_roll < 0.3:
		# Small town
		town.width = rng.randi_range(100, 130)
		town.height = rng.randi_range(70, 90)
		town.num_houses = rng.randi_range(3, 5)
		town.num_farms = rng.randi_range(1, 3)
	elif size_roll < 0.7:
		# Medium town
		town.width = rng.randi_range(140, 180)
		town.height = rng.randi_range(90, 120)
		town.num_houses = rng.randi_range(5, 8)
		town.num_farms = rng.randi_range(3, 5)
	else:
		# Large town
		town.width = rng.randi_range(180, 220)
		town.height = rng.randi_range(110, 150)
		town.num_houses = rng.randi_range(8, 12)
		town.num_farms = rng.randi_range(4, 7)

	# Layout tuning
	town.plot_margin = 2
	town.road_width = 2

	# World position
	town.world_position = position

	# Metadata
	town.metadata["num_nobles"] = rng.randi_range(1, 3)
	town.metadata["town_type"] = _get_town_type(rng)

	return town

## Generate a town name
static func _generate_town_name(rng: RandomNumberGenerator, index: int) -> String:
	# Use predefined names first
	if index < TOWN_NAMES.size():
		return TOWN_NAMES[index]

	# Generate procedural names
	var style := rng.randi_range(0, 2)
	match style:
		0:
			# Prefix + Name
			var prefix: String = TOWN_PREFIXES[rng.randi() % TOWN_PREFIXES.size()]
			var name: String = TOWN_NAMES[rng.randi() % TOWN_NAMES.size()]
			return prefix + " " + name
		1:
			# Name + Suffix
			var base := ["Oak", "River", "Stone", "Green", "Black", "White", "Red", "Blue"]
			return base[rng.randi() % base.size()] + TOWN_SUFFIXES[rng.randi() % TOWN_SUFFIXES.size()]
		_:
			# Random combination
			return "Town of " + TOWN_NAMES[rng.randi() % TOWN_NAMES.size()]

## Get a town type for flavor
static func _get_town_type(rng: RandomNumberGenerator) -> String:
	var types := ["farming", "trading", "mining", "fishing", "military", "religious"]
	return types[rng.randi() % types.size()]
