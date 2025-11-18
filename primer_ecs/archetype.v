module primer_ecs

// ArchetypeID uniquely identifies an archetype by its component combination
pub type ArchetypeID = u64

// ComponentStorage holds properly allocated component data
struct ComponentStorage {
mut:
	data       []voidptr // Pointers to heap-allocated component data
	size       int       // Size of each component in bytes
	destructor fn (voidptr) = unsafe { nil } // Optional destructor for cleanup
}

// ArchetypeEdge represents a transition between archetypes
struct ArchetypeEdge {
mut:
	add    map[ComponentTypeID]ArchetypeID // Archetype IDs when adding a component
	remove map[ComponentTypeID]ArchetypeID // Archetype IDs when removing a component
}

// Archetype stores entities that share the same component combination
pub struct Archetype {
pub mut:
	id              ArchetypeID                          // Unique archetype identifier
	component_types []ComponentTypeID                    // Sorted component type IDs
	entities        []EntityID                           // Dense array of entity IDs
	components      map[ComponentTypeID]ComponentStorage // Component data per type
	entity_to_row   map[EntityID]int                     // Maps entity to row index
	edges           ArchetypeEdge                        // Cached archetype transitions
}

// new_archetype creates a new archetype with given component types and sizes
pub fn new_archetype(component_types []ComponentTypeID, component_sizes map[ComponentTypeID]int) Archetype {
	mut sorted := component_types.clone()
	sorted.sort()
	arch_id := compute_archetype_id(sorted)
	mut comp_map := map[ComponentTypeID]ComponentStorage{}
	for comp_type in sorted {
		size := component_sizes[comp_type] or { 0 }
		comp_map[comp_type] = ComponentStorage{
			data:       []voidptr{cap: 64}
			size:       size
			destructor: unsafe { nil }
		}
	}
	return Archetype{
		id:              arch_id
		component_types: sorted
		entities:        []EntityID{cap: 64}
		components:      comp_map
		entity_to_row:   map[EntityID]int{}
		edges:           ArchetypeEdge{}
	}
}

@[inline]
pub fn (arch &Archetype) size() int {
	return arch.entities.len
}

@[inline]
pub fn (arch &Archetype) has(entity_id EntityID) bool {
	return entity_id in arch.entity_to_row
}

@[inline]
pub fn (arch &Archetype) get_row(entity_id EntityID) ?int {
	return arch.entity_to_row[entity_id] or { return none }
}

pub fn (arch &Archetype) get_component(entity_id EntityID, comp_type ComponentTypeID) ?voidptr {
	row := arch.entity_to_row[entity_id] or { return none }
	storage := arch.components[comp_type] or { return none }
	if row >= storage.data.len {
		return none
	}
	return storage.data[row]
}

pub fn (arch &Archetype) get_entities() []EntityID {
	return arch.entities
}

pub fn (arch &Archetype) get_component_array(comp_type ComponentTypeID) ?[]voidptr {
	if component_storage := arch.components[comp_type] {
		return component_storage.data
	}
	return none
}

@[inline]
pub fn (arch &Archetype) has_component_type(comp_type ComponentTypeID) bool {
	return comp_type in arch.components
}

pub fn (arch &Archetype) matches(required []ComponentTypeID) bool {
	for comp_type in required {
		if !arch.has_component_type(comp_type) {
			return false
		}
	}
	return true
}

pub fn (mut arch Archetype) add(entity_id EntityID, component_data map[ComponentTypeID]voidptr) !bool {
	if arch.has(entity_id) {
		return error('Entity already exists in archetype')
	}
	for comp_type in arch.component_types {
		if comp_type !in component_data {
			return error('Missing required component type: ${comp_type}')
		}
	}
	row := arch.entities.len
	arch.entities << entity_id
	arch.entity_to_row[entity_id] = row
	for comp_type in arch.component_types {
		mut storage := unsafe { arch.components[comp_type] }
		src_ptr := component_data[comp_type] or { continue }

		unsafe {
			dst_ptr := malloc(storage.size)
			vmemcpy(dst_ptr, src_ptr, storage.size)
			storage.data << dst_ptr
		}
		arch.components[comp_type] = storage
	}
	return true
}

pub fn (mut arch Archetype) remove(entity_id EntityID) bool {
	row := arch.entity_to_row[entity_id] or { return false }
	last_idx := arch.entities.len - 1
	for comp_type in arch.component_types {
		mut storage := unsafe { arch.components[comp_type] }
		if storage.destructor != unsafe { nil } {
			storage.destructor(storage.data[row])
		}
		unsafe { free(storage.data[row]) }
	}
	if row != last_idx {
		moved_entity := arch.entities[last_idx]
		arch.entities[row] = moved_entity
		arch.entity_to_row[moved_entity] = row
		for comp_type in arch.component_types {
			mut storage := unsafe { arch.components[comp_type] }
			storage.data[row] = storage.data[last_idx]
			arch.components[comp_type] = storage
		}
	}
	arch.entities.pop()
	arch.entity_to_row.delete(entity_id)
	for comp_type in arch.component_types {
		mut storage := unsafe { arch.components[comp_type] }
		storage.data.pop()
		arch.components[comp_type] = storage
	}
	return true
}

pub fn (mut arch Archetype) extract(entity_id EntityID) ?map[ComponentTypeID]voidptr {
	row := arch.entity_to_row[entity_id] or { return none }
	last_idx := arch.entities.len - 1
	mut component_data := map[ComponentTypeID]voidptr{}
	for comp_type in arch.component_types {
		storage := unsafe { arch.components[comp_type] }
		component_data[comp_type] = storage.data[row]
	}
	if row != last_idx {
		moved_entity := arch.entities[last_idx]
		arch.entities[row] = moved_entity
		arch.entity_to_row[moved_entity] = row
		for comp_type in arch.component_types {
			mut storage := unsafe { arch.components[comp_type] }
			storage.data[row] = storage.data[last_idx]
			arch.components[comp_type] = storage
		}
	}
	arch.entities.pop()
	arch.entity_to_row.delete(entity_id)
	for comp_type in arch.component_types {
		mut storage := arch.components[comp_type] or { continue }
		storage.data.pop()
		arch.components[comp_type] = storage
	}
	return component_data
}

pub fn (mut arch Archetype) clear() {
	for comp_type in arch.component_types {
		mut storage := arch.components[comp_type] or { continue }
		for ptr in storage.data {
			if storage.destructor != unsafe { nil } {
				storage.destructor(ptr)
			}
			unsafe { free(ptr) }
		}
		storage.data.clear()
		arch.components[comp_type] = storage
	}
	arch.entities.clear()
	arch.entity_to_row.clear()
}

pub fn (mut arch Archetype) set_add_edge(comp_type ComponentTypeID, target_arch_id ArchetypeID) {
	arch.edges.add[comp_type] = target_arch_id
}

pub fn (mut arch Archetype) set_remove_edge(comp_type ComponentTypeID, target_arch_id ArchetypeID) {
	arch.edges.remove[comp_type] = target_arch_id
}

pub fn (arch &Archetype) get_add_edge(comp_type ComponentTypeID) ?ArchetypeID {
	return arch.edges.add[comp_type] or { return none }
}

pub fn (arch &Archetype) get_remove_edge(comp_type ComponentTypeID) ?ArchetypeID {
	return arch.edges.remove[comp_type] or { return none }
}

// compute_archetype_id computes archetype ID from sorted component types using FNV-1a hash
fn compute_archetype_id(sorted_types []ComponentTypeID) ArchetypeID {
	mut hash := u64(14695981039346656037)
	for comp_type in sorted_types {
		hash ^= u64(comp_type)
		hash *= 1099511628211
	}
	return hash
}

// @[inline]
// fn vmemcpy(dest voidptr, src voidptr, n int) {
// 	unsafe {
// 		d := &u8(dest)
// 		s := &u8(src)
// 		for i := 0; i < n; i++ {
// 			d[i] = s[i]
// 		}
// 	}
// }
