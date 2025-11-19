# Primer
Simple ECS implementation in V.

***
## Usage
### Basic Setup

```v
import primer_ecs { World }

struct Position { mut: x f32, y f32 }
struct Velocity { mut: dx f32, dy f32 }

mut world := primer_ecs.new_world()
world.register_type[Position]()
world.register_type[Velocity]()
```

### Create Entities with Components

```v
player := world.create_with_components([
    world.component(Position{ x: 0, y: 0 }),
    world.component(Velocity{ dx: 5, dy: 5 }),
]) or { panic(err) }
```
### Query System

```v
pos_id := world.get_type_id[Position]()
vel_id := world.get_type_id[Velocity]()

mut movement_query := primer_ecs.new_query_system([pos_id, vel_id])
world.register_query_system(mut movement_query)

results := movement_query.query(&world)
for row in results {
    // row.entity, row.components
}
```

### Filtered Queries

```v
import primer_ecs { QueryFilter }

player_id := world.get_type_id[Player]()
enemy_id := world.get_type_id[Enemy]()

mut player_filter_query := primer_ecs.new_query_system_filtered([pos_id, health_id],
    [
        QueryFilter{ component_type: player_id, op: .with },
        QueryFilter{ component_type: enemy_id, op: .without },
    ])

filtered_results := player_filter_query.query(&world)
```

### Archetype Graph Transitions

```v
test_entity := world.create()

world.add(test_entity, Position{ x: 10, y: 20 })
world.add(test_entity, Velocity{ dx: 1, dy: 1 })

world.remove[Position](test_entity)
```

### Entity Despawn and Safety

```v
world.despawn(test_entity)
```

### Query Chunks

```v
chunks := movement_query.query_chunked(&world, 25)
for chunk in chunks {
    // chunk.results
}
```

***

<div align="center">⁂</div>
