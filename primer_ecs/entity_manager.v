module primer_ecs

pub type EntityID = u32
pub type EntityGeneration = u32
pub type EntityHandle = u64

// -------------------- Pack / Unpack --------------------

// pack_entity packs/unpacks entity into u64 (high 32 = generation, low 32 = id)
fn pack_entity(entity_id EntityID, generation EntityGeneration) EntityHandle {
	return (EntityHandle(generation) << 32) | EntityHandle(entity_id)
}

pub fn (e EntityHandle) id() EntityID {
	return EntityID(e & 0xffffffff)
}

pub fn (e EntityHandle) gen() EntityGeneration {
	return EntityGeneration(e >> 32)
}

struct EntityManager {
mut:
	generations   []EntityGeneration
	free_entities []EntityID
	next_id       EntityID
	alive_count   int
}

pub fn new_entity_manager() EntityManager {
	return EntityManager{}
}

fn (mut em EntityManager) ensure_generation_capacity(id EntityID) {
	for em.generations.len <= int(id) {
		em.generations << 0
	}
}

pub fn (mut em EntityManager) create() EntityHandle {
	mut entity_id := EntityID(0)
	if em.free_entities.len > 0 {
		entity_id = em.free_entities.pop()
	} else {
		entity_id = em.next_id
		em.next_id++
		em.ensure_generation_capacity(entity_id)
	}
	em.alive_count++
	gen := em.generations[int(entity_id)]
	return pack_entity(entity_id, gen)
}

pub fn (mut em EntityManager) destroy(entity EntityHandle) bool {
	id, gen := entity.id(), entity.gen()
	if id >= u32(em.generations.len) || em.generations[int(id)] != gen {
		return false
	}
	em.generations[int(id)]++
	em.free_entities << id
	em.alive_count--
	return true
}

pub fn (mut em EntityManager) clear() {
	em.free_entities.clear()
	em.next_id = 0
	em.alive_count = 0
	for i in 0 .. em.generations.len {
		em.generations[i] = 0
	}
}

pub fn (em &EntityManager) size() int {
	return em.alive_count
}

pub fn (em &EntityManager) is_alive(entity EntityHandle) bool {
	id, gen := entity.id(), entity.gen()
	return id < u32(em.generations.len) && em.generations[int(id)] == gen
}
