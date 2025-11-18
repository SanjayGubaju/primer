import primer_ecs { QueryFilter, World }

struct Position {
mut:
	x f32
	y f32
}

struct Velocity {
mut:
	dx f32
	dy f32
}

struct Health {
mut:
	current int
	max     int
}

struct Enemy {
	damage int
}

struct Player {
	score int
}

fn make_world() World {
	mut world := primer_ecs.new_world()
	world.register_type[Position]()
	world.register_type[Velocity]()
	world.register_type[Health]()
	world.register_type[Enemy]()
	world.register_type[Player]()

	return world
}

fn test_component_type_registration() {
	mut world := primer_ecs.new_world()
	pos_id := world.register_type[Position]()
	vel_id := world.register_type[Velocity]()
	health_id := world.register_type[Health]()
	enemy_id := world.register_type[Enemy]()
	player_id := world.register_type[Player]()

	assert pos_id == 0
	assert vel_id == 1
	assert health_id == 2
	assert enemy_id == 3
	assert player_id == 4
}

fn test_bulk_entity_creation() {
	mut world := make_world()
	player := world.create_with_components([
		world.component(Position{ x: 0, y: 0 }),
		world.component(Velocity{ dx: 5, dy: 5 }),
		world.component(Health{ current: 100, max: 100 }),
		world.component(Player{ score: 0 }),
	]) or { panic(err) }

	assert player == 0
	mut enemies := []primer_ecs.EntityHandle{cap: 100}

	for i in 0 .. 100 {
		enemy := world.create_with_components([
			world.component(Position{ x: f32(i * 10), y: f32(i * 10) }),
			world.component(Velocity{ dx: -2, dy: -2 }),
			world.component(Health{ current: 50, max: 50 }),
			world.component(Enemy{ damage: 10 }),
		]) or { panic(err) }
		enemies << enemy
	}

	assert enemies.len == 100
	assert world.entity_count() == 101
	assert world.archetype_count() == 2
}

fn test_query_system_and_caching() {
	mut world := make_world()
	pos_id := world.get_type_id[Position]()
	vel_id := world.get_type_id[Velocity]()
	health_id := world.get_type_id[Health]()
	enemy_id := world.get_type_id[Enemy]()
	player_id := world.get_type_id[Player]()
	player := world.create_with_components([
		world.component(Position{ x: 0, y: 0 }),
		world.component(Velocity{ dx: 5, dy: 5 }),
		world.component(Health{ current: 100, max: 100 }),
		world.component(Player{ score: 0 }),
	]) or { panic(err) }

	for _ in 0 .. 100 {
		world.create_with_components([
			world.component(Position{ x: 0, y: 0 }),
			world.component(Velocity{ dx: 1, dy: 1 }),
			world.component(Health{ current: 42, max: 100 }),
			world.component(Enemy{ damage: 1 }),
		]) or { panic(err) }
	}
	mut movement_query := primer_ecs.new_query_system([pos_id, vel_id])
	mut enemy_query := primer_ecs.new_query_system([pos_id, health_id, enemy_id])
	mut player_query := primer_ecs.new_query_system([pos_id, health_id, player_id])

	world.register_query_system(mut movement_query)
	world.register_query_system(mut enemy_query)
	world.register_query_system(mut player_query)

	assert world.get_query_system_size() == 3
}

fn test_query_filtering() {
	mut world := make_world()
	pos_id := world.get_type_id[Position]()
	health_id := world.get_type_id[Health]()
	enemy_id := world.get_type_id[Enemy]()
	player_id := world.get_type_id[Player]()
	player := world.create_with_components([
		world.component(Position{ x: 0, y: 0 }),
		world.component(Health{ current: 100, max: 100 }),
		world.component(Player{ score: 0 }),
	]) or { panic(err) }

	for _ in 0 .. 100 {
		world.create_with_components([
			world.component(Position{ x: 1, y: 1 }),
			world.component(Health{ current: 1, max: 1 }),
			world.component(Enemy{ damage: 1 }),
		]) or { panic(err) }
	}

	mut player_filter_query := primer_ecs.new_query_system_filtered([pos_id, health_id],
		[
		QueryFilter{ component_type: player_id, op: .with },
		QueryFilter{
			component_type: enemy_id
			op:             .without
		},
	])
	filtered_results := player_filter_query.query(&world)

	assert filtered_results.len == 1
	assert filtered_results[0].entity == player
}

fn test_archetype_graph_transitions() {
	mut world := make_world()

	test_entity := world.create()
	assert world.archetype_count() == 1

	world.add(test_entity, Position{ x: 10, y: 20 })
	assert world.archetype_count() == 2

	world.add(test_entity, Velocity{ dx: 1, dy: 1 })
	assert world.archetype_count() == 3

	world.remove[Position](test_entity)
	assert world.archetype_count() == 4

	world.add(test_entity, Position{ x: 1, y: 2 })
	assert world.archetype_count() == 4
}

fn test_query_performance_and_stats() {
	mut world := make_world()
	pos_id := world.get_type_id[Position]()
	vel_id := world.get_type_id[Velocity]()

	for _ in 0 .. 102 {
		world.create_with_components([
			world.component(Position{ x: 0, y: 0 }),
			world.component(Velocity{ dx: 1, dy: 1 }),
		]) or { panic(err) }
	}
	mut movement_query := primer_ecs.new_query_system([pos_id, vel_id])
	world.register_query_system(mut movement_query)
	results1 := world.query([pos_id, vel_id])
	assert results1.len == 102

	results2 := movement_query.query(&world)
	assert results2.len == 102

	count := movement_query.count(&world)
	assert count == 102
}

fn test_parallel_query_chunks() {
	mut world := make_world()
	pos_id := world.get_type_id[Position]()
	vel_id := world.get_type_id[Velocity]()

	for _ in 0 .. 60 {
		world.create_with_components([
			world.component(Position{ x: 0, y: 0 }),
			world.component(Velocity{ dx: 1, dy: 1 }),
		]) or { panic(err) }
	}

	mut movement_query := primer_ecs.new_query_system([pos_id, vel_id])
	world.register_query_system(mut movement_query)
	chunks := movement_query.query_chunked(&world, 25)

	assert chunks.len == 3
	assert chunks[0].results.len <= 25
	assert chunks[1].results.len <= 25
	assert chunks[2].results.len <= 25
}

fn test_entity_despawn_and_memory_safety() {
	mut world := make_world()
	e := world.create_with_components([
		world.component(Position{ x: 1, y: 1 }),
	]) or { panic(err) }

	assert world.is_alive(e)

	world.despawn(e)
	assert !world.is_alive(e)
	assert world.entity_count() == 0
}

fn test_error_handling() {
	mut world := make_world()
	e := world.create_with_components([
		world.component(Position{ x: 1, y: 2 }),
	]) or { panic(err) }

	world.add(e, Position{ x: 1, y: 2 })
	world.remove[Velocity](e)
}
