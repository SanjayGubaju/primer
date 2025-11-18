module primer_ecs

// -------------------- Query Result --------------------

pub struct QueryResult {
pub:
	entity     EntityHandle
	components map[ComponentTypeID]voidptr
}

// get is a generic getter for component from result
@[inline]
pub fn (query_result &QueryResult) get[T](world &World) ?&T {
	type_id := world.get_type_id[T]()
	if comp := query_result.components[type_id] {
		unsafe {
			return &T(comp)
		}
	}
	return none
}

// get_mut is a mutable component getter
@[inline]
pub fn (query_result &QueryResult) get_mut[T](world &World) ?&T {
	type_id := world.get_type_id[T]()
	if comp := query_result.components[type_id] {
		unsafe {
			return &T(comp)
		}
	}
	return none
}

// -------------------- Query Filter --------------------

pub enum FilterOp {
	with
	without
	changed
}

pub struct QueryFilter {
pub:
	component_type ComponentTypeID
	op             FilterOp
}

// -------------------- Archetype-based Querying --------------------

pub fn (world &World) query_into(component_type_ids []ComponentTypeID, mut out []QueryResult) {
	query_into_filtered(world, component_type_ids, [], mut out)
}

pub fn query_into_filtered(world &World, component_type_ids []ComponentTypeID, filters []QueryFilter, mut out []QueryResult) {
	out.clear()
	if component_type_ids.len == 0 {
		return
	}

	for arch in world.archetypes.values() {
		if !arch.matches(component_type_ids) {
			continue
		}

		mut matches_filters := true
		for filter in filters {
			match filter.op {
				.with {
					if !arch.has_component_type(filter.component_type) {
						matches_filters = false
						break
					}
				}
				.without {
					if arch.has_component_type(filter.component_type) {
						matches_filters = false
						break
					}
				}
				.changed {
					continue
				} // change detection stub
			}
		}
		if !matches_filters {
			continue
		}

		for entity_idx, entity_id in arch.entities {
			if int(entity_id) >= world.entity_manager.generations.len {
				continue
			}
			current_gen := world.entity_manager.generations[int(entity_id)]
			entity_handle := pack_entity(entity_id, current_gen)

			mut comps := map[ComponentTypeID]voidptr{}
			for ct_id in component_type_ids {
				storage := arch.components[ct_id] or { continue }
				if entity_idx >= storage.data.len {
					continue
				}
				comps[ct_id] = storage.data[entity_idx]
			}

			out << QueryResult{
				entity:     entity_handle
				components: comps
			}
		}
	}
}

pub fn (world &World) query(component_type_ids []ComponentTypeID) []QueryResult {
	mut out := []QueryResult{cap: 256}
	world.query_into(component_type_ids, mut out)
	return out
}

pub fn (world &World) query_filtered(component_type_ids []ComponentTypeID, filters []QueryFilter) []QueryResult {
	mut out := []QueryResult{cap: 256}
	query_into_filtered(world, component_type_ids, filters, mut out)
	return out
}

// -------------------- Query System --------------------

pub struct QuerySystem {
	component_types []ComponentTypeID
	filters         []QueryFilter
pub mut:
	query_buffer      []QueryResult
	cached_archetypes []ArchetypeID
	cache_dirty       bool
}

pub fn new_query_system(component_types []ComponentTypeID) QuerySystem {
	return QuerySystem{
		component_types:   component_types
		filters:           []
		query_buffer:      []QueryResult{cap: 256}
		cached_archetypes: []
		cache_dirty:       true
	}
}

pub fn new_query_system_filtered(component_types []ComponentTypeID, filters []QueryFilter) QuerySystem {
	return QuerySystem{
		component_types:   component_types
		filters:           filters
		query_buffer:      []QueryResult{cap: 256}
		cached_archetypes: []
		cache_dirty:       true
	}
}

pub fn (mut qs QuerySystem) invalidate_cache() {
	qs.cache_dirty = true
}

fn (mut qs QuerySystem) rebuild_cache(world &World) {
	qs.cached_archetypes.clear()
	for arch in world.archetypes.values() {
		if !arch.matches(qs.component_types) {
			continue
		}

		mut matches := true
		for filter in qs.filters {
			match filter.op {
				.with {
					if !arch.has_component_type(filter.component_type) {
						matches = false
						break
					}
				}
				.without {
					if arch.has_component_type(filter.component_type) {
						matches = false
						break
					}
				}
				.changed {
					continue
				}
			}
		}
		if matches {
			qs.cached_archetypes << arch.id
		}
	}
	qs.cache_dirty = false
}

pub fn (mut qs QuerySystem) query(world &World) []QueryResult {
	if qs.cache_dirty {
		qs.rebuild_cache(world)
	}
	qs.query_buffer.clear()

	for arch_id in qs.cached_archetypes {
		arch := world.archetypes[arch_id] or { continue }
		for entity_idx, entity_id in arch.entities {
			if int(entity_id) >= world.entity_manager.generations.len {
				continue
			}
			current_gen := world.entity_manager.generations[int(entity_id)]
			entity_handle := pack_entity(entity_id, current_gen)

			mut comps := map[ComponentTypeID]voidptr{}
			for ct_id in qs.component_types {
				storage := arch.components[ct_id] or { continue }
				if entity_idx >= storage.data.len {
					continue
				}
				comps[ct_id] = storage.data[entity_idx]
			}

			qs.query_buffer << QueryResult{
				entity:     entity_handle
				components: comps
			}
		}
	}
	return qs.query_buffer
}

pub fn (mut qs QuerySystem) count(world &World) int {
	if qs.cache_dirty {
		qs.rebuild_cache(world)
	}
	mut total := 0
	for arch_id in qs.cached_archetypes {
		arch := world.archetypes[arch_id] or { continue }
		total += arch.size()
	}
	return total
}

pub fn (mut qs QuerySystem) is_empty(world &World) bool {
	return qs.count(world) == 0
}

// -------------------- Parallel Query Support --------------------

pub struct QueryChunk {
pub:
	results []QueryResult
	start   int
	end     int
}

pub fn (mut qs QuerySystem) query_chunked(world &World, chunk_size int) []QueryChunk {
	results := qs.query(world)
	if results.len == 0 {
		return []
	}
	mut chunks := []QueryChunk{cap: (results.len / chunk_size) + 1}
	for i := 0; i < results.len; i += chunk_size {
		end := if i + chunk_size > results.len { results.len } else { i + chunk_size }
		chunks << QueryChunk{
			results: results[i..end]
			start:   i
			end:     end
		}
	}
	return chunks
}
