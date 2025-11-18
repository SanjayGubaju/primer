module primer_ecs

pub struct ResourceManager {
mut:
	resources map[int]voidptr
}

pub fn new_resource_manager() ResourceManager {
	return ResourceManager{
		resources: map[int]voidptr{}
	}
}

// ==================== Value Types ====================

// insert adds or updates a resource (for value types)
pub fn (mut rm ResourceManager) insert[T](resource T) {
	type_id := typeof[T]().idx
	// Store a heap-allocated copy
	mut ptr := &T{}
	unsafe {
		*ptr = resource
	}
	rm.resources[type_id] = voidptr(ptr)
}

// get retrieves a resource (for value types)
pub fn (rm &ResourceManager) get[T]() ?&T {
	type_id := typeof[T]().idx
	if ptr := rm.resources[type_id] {
		return unsafe { &T(ptr) }
	}
	return none
}

// ==================== Reference Types ====================

// insert_ref stores a reference directly (for reference types like &gg.Context)
pub fn (mut rm ResourceManager) insert_ref[T](resource &T) {
	type_id := typeof[T]().idx
	// Store the pointer directly (no allocation needed)
	rm.resources[type_id] = voidptr(resource)
}

// get_ref retrieves a reference (for reference types)
pub fn (rm &ResourceManager) get_ref[T]() ?&T {
	type_id := typeof[T]().idx
	if ptr := rm.resources[type_id] {
		return unsafe { &T(ptr) }
	}
	return none
}

// ==================== Common Operations ====================

// has checks if a resource exists
pub fn (rm &ResourceManager) has[T]() bool {
	type_id := typeof[T]().idx
	return type_id in rm.resources
}

// remove removes a resource
pub fn (mut rm ResourceManager) remove[T]() bool {
	type_id := typeof[T]().idx
	if type_id in rm.resources {
		rm.resources.delete(type_id)
		return true
	}
	return false
}

// clear removes all resources
pub fn (mut rm ResourceManager) clear() {
	rm.resources.clear()
}
