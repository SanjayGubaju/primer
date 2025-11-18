module primer_ecs

// EntityRecord tracks where an entity is stored
struct EntityRecord {
	archetype_id ArchetypeID
	row          int
}

// World is the main ECS container
pub struct World {
mut:
	entity_manager  EntityManager
	type_registry   TypeRegistry
	archetypes      map[ArchetypeID]Archetype
	entity_index    map[EntityID]EntityRecord
	component_sizes map[ComponentTypeID]int
	query_systems   []&QuerySystem
}

// Helper struct for passing component data
pub struct ComponentData {
pub:
	size    int
	type_id ComponentTypeID
	data    voidptr
}

// new_world creates a new world
pub fn new_world() World {
	return World{
		entity_manager:  new_entity_manager()
		type_registry:   TypeRegistry{}
		archetypes:      map[ArchetypeID]Archetype{}
		entity_index:    map[EntityID]EntityRecord{}
		component_sizes: map[ComponentTypeID]int{}
		query_systems:   []&QuerySystem{}
	}
}

// register_type registers a component type (must be called before using components)
pub fn (mut world World) register_type[T]() ComponentTypeID {
	type_id := world.type_registry.add[T]()
	world.component_sizes[type_id] = int(sizeof(T))
	return type_id
}

// get_type_id get registered component type ID
pub fn (world &World) get_type_id[T]() ComponentTypeID {
	return world.type_registry.get[T]() or { panic(err) }
}

// register_query_system registers a query system for automatic cache invalidation
pub fn (mut world World) register_query_system(mut qs QuerySystem) {
	unsafe {
		world.query_systems << &qs
	}
}

pub fn (world &World) get_query_system_size() int {
	return world.query_systems.len
}

// invalidate_query_caches invalidates all query system caches
fn (mut world World) invalidate_query_caches() {
	for mut qs in world.query_systems {
		qs.invalidate_cache()
	}
}

// create_with_components creates entity with multiple components
pub fn (mut world World) create_with_components(components []ComponentData) !EntityHandle {
	entity_handle := world.entity_manager.create()
	entity_id := entity_handle.id()

	mut component_types := []ComponentTypeID{}
	mut component_data := map[ComponentTypeID]voidptr{}
	for comp in components {
		component_types << comp.type_id
		component_data[comp.type_id] = comp.data
	}
	component_types.sort()
	mut arch := world.get_or_create_archetype(component_types)
	arch.add(entity_id, component_data) or {
		return error('Failed to add entity to archetype: ${err}')
	}
	world.entity_index[entity_id] = EntityRecord{
		archetype_id: arch.id
		row:          arch.size() - 1
	}
	world.archetypes[arch.id] = arch
	return entity_handle
}

// create creates a new entity
pub fn (mut world World) create() EntityHandle {
	entity_handle := world.entity_manager.create()
	entity_id := entity_handle.id()
	mut arch := world.get_or_create_archetype([])
	arch.add(entity_id, map[ComponentTypeID]voidptr{}) or {
		panic('Failed to add entity to empty archetype')
	}
	world.entity_index[entity_id] = EntityRecord{
		archetype_id: arch.id
		row:          arch.size() - 1
	}
	world.archetypes[arch.id] = arch
	return entity_handle
}

@[inline]
pub fn (world &World) is_alive(entity EntityHandle) bool {
	return world.entity_manager.is_alive(entity)
}

// add adds component to entity
pub fn (mut world World) add[T](entity EntityHandle, component T) bool {
	if !world.is_alive(entity) {
		eprintln('Entity is not alive')
		return false
	}
	entity_id := entity.id()
	comp_type_id := world.type_registry.get[T]() or {
		eprintln('Component type not registered')
		return false
	}
	record := world.entity_index[entity_id] or {
		eprintln('Entity not found in index')
		return false
	}

	mut old_arch := world.archetypes[record.archetype_id] or {
		eprintln('Archetype not found')
		return false
	}

	if old_arch.has_component_type(comp_type_id) {
		eprintln('Entity already has this component')
		return false
	}

	old_arch.get_add_edge(comp_type_id) or {
		mut new_types := old_arch.component_types.clone()
		new_types << comp_type_id
		new_types.sort()
		computed_id := compute_archetype_id_from_types(new_types)
		old_arch.set_add_edge(comp_type_id, computed_id)
		world.archetypes[old_arch.id] = old_arch
		computed_id
	}

	mut new_types := old_arch.component_types.clone()
	new_types << comp_type_id
	new_types.sort()

	mut new_arch := world.get_or_create_archetype(new_types)
	new_arch.set_remove_edge(comp_type_id, old_arch.id)
	mut component_data := old_arch.extract(entity_id) or {
		eprintln('Failed to extract entity from old archetype')
		return false
	}

	size := int(sizeof(T))
	new_comp_ptr := unsafe { malloc(size) }
	unsafe { vmemcpy(new_comp_ptr, &component, size) }
	component_data[comp_type_id] = new_comp_ptr
	new_arch.add(entity_id, component_data) or {
		unsafe { free(new_comp_ptr) }

		eprintln('Failed to add entity to new archetype: ${err}')
		return false
	}

	world.entity_index[entity_id] = EntityRecord{
		archetype_id: new_arch.id
		row:          new_arch.size() - 1
	}
	world.archetypes[old_arch.id] = old_arch
	world.archetypes[new_arch.id] = new_arch
	return true
}

// remove removes component from entity
pub fn (mut world World) remove[T](entity EntityHandle) bool {
	if !world.is_alive(entity) {
		eprintln('Entity is not alive')
		return false
	}
	entity_id := entity.id()
	comp_type_id := world.type_registry.get[T]() or {
		eprintln('Component type not registered')
		return false
	}
	record := world.entity_index[entity_id] or {
		eprintln('Entity not found in index')
		return false
	}

	mut old_arch := world.archetypes[record.archetype_id] or {
		eprintln('Archetype not found')
		return false
	}
	if !old_arch.has_component_type(comp_type_id) {
		eprintln('Entity does not have this component')
		return false
	}
	old_arch.get_remove_edge(comp_type_id) or {
		mut new_types := []ComponentTypeID{}
		for comp_type in old_arch.component_types {
			if comp_type != comp_type_id {
				new_types << comp_type
			}
		}
		computed_id := compute_archetype_id_from_types(new_types)
		old_arch.set_remove_edge(comp_type_id, computed_id)
		world.archetypes[old_arch.id] = old_arch
		computed_id
	}

	mut new_types := []ComponentTypeID{}
	for comp_type in old_arch.component_types {
		if comp_type != comp_type_id {
			new_types << comp_type
		}
	}

	mut new_arch := world.get_or_create_archetype(new_types)
	new_arch.set_add_edge(comp_type_id, old_arch.id)
	mut component_data := old_arch.extract(entity_id) or {
		eprintln('Failed to extract entity from old archetype')
		return false
	}
	if removed_ptr := component_data[comp_type_id] {
		unsafe { free(removed_ptr) }
	}
	component_data.delete(comp_type_id)
	new_arch.add(entity_id, component_data) or {
		eprintln('Failed to add entity to new archetype: ${err}')
		return false
	}

	world.entity_index[entity_id] = EntityRecord{
		archetype_id: new_arch.id
		row:          new_arch.size() - 1
	}
	world.archetypes[old_arch.id] = old_arch
	world.archetypes[new_arch.id] = new_arch
	return true
}

@[inline]
pub fn (world &World) get[T](entity EntityHandle) ?&T {
	if !world.is_alive(entity) {
		return none
	}
	entity_id := entity.id()
	comp_type_id := world.type_registry.get[T]() or { return none }
	record := world.entity_index[entity_id] or { return none }
	arch := world.archetypes[record.archetype_id] or { return none }
	data := arch.get_component(entity_id, comp_type_id) or { return none }
	unsafe {
		return &T(data)
	}
}

@[inline]
pub fn (world &World) has[T](entity EntityHandle) bool {
	if !world.is_alive(entity) {
		return false
	}
	entity_id := entity.id()
	comp_type_id := world.type_registry.get[T]() or { return false }
	record := world.entity_index[entity_id] or { return false }
	arch := world.archetypes[record.archetype_id] or { return false }
	return arch.has_component_type(comp_type_id)
}

// despawn despawns entity
pub fn (mut world World) despawn(entity EntityHandle) bool {
	if !world.is_alive(entity) {
		return false
	}
	entity_id := entity.id()
	record := world.entity_index[entity_id] or { return false }
	mut arch := world.archetypes[record.archetype_id] or { return false }
	arch.remove(entity_id)
	world.archetypes[arch.id] = arch
	world.entity_index.delete(entity_id)
	world.entity_manager.destroy(entity)
	return true
}

// clear clears all entities and archetypes
pub fn (mut world World) clear() {
	for mut arch in world.archetypes.values() {
		arch.clear()
	}
	world.entity_manager.clear()
	world.archetypes.clear()
	world.entity_index.clear()
	world.invalidate_query_caches()
}

// get_all_entities gets all alive entity handles
pub fn (world &World) get_all_entities() []EntityHandle {
	mut handles := []EntityHandle{cap: world.entity_index.len}
	for entity_id in world.entity_index.keys() {
		if entity_id < u32(world.entity_manager.generations.len) {
			gen := world.entity_manager.generations[int(entity_id)]
			handles << pack_entity(entity_id, gen)
		}
	}
	return handles
}

@[inline]
pub fn (world &World) entity_count() int {
	return world.entity_manager.alive_count
}

@[inline]
pub fn (world &World) archetype_count() int {
	return world.archetypes.len
}

// component creates ComponentData from a component
pub fn (world &World) component[T](component T) ComponentData {
	type_id := world.get_type_id[T]()
	size := int(sizeof(T))
	return ComponentData{
		size:    size
		type_id: type_id
		data:    voidptr(&component)
	}
}

// get_or_create_archetype gets or create archetype with given component types
fn (mut world World) get_or_create_archetype(component_types []ComponentTypeID) &Archetype {
	arch_id := compute_archetype_id_from_types(component_types)
	if arch_id in world.archetypes {
		unsafe {
			return &world.archetypes[arch_id]
		}
	}
	mut sizes := map[ComponentTypeID]int{}
	for comp_type in component_types {
		sizes[comp_type] = world.component_sizes[comp_type] or { 0 }
	}
	mut new_arch := new_archetype(component_types, sizes)
	new_arch.id = arch_id
	world.archetypes[arch_id] = new_arch
	world.invalidate_query_caches()
	unsafe {
		return &world.archetypes[arch_id]
	}
}

// compute_archetype_id_from_types computes archetype id
fn compute_archetype_id_from_types(types []ComponentTypeID) ArchetypeID {
	mut sorted := types.clone()
	sorted.sort()
	return compute_archetype_id(sorted)
}
