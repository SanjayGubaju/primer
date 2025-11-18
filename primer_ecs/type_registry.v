module primer_ecs

pub type ComponentTypeID = u32

// Each component type gets an integer ID assigned once
pub struct TypeRegistry {
mut:
	names       []string                // Stores component type names
	runtime_id  ComponentTypeID         // Stores next available sequential runtime id
	runtime_map map[int]ComponentTypeID // Maps static type id with runtime id
}

pub fn (mut type_registry TypeRegistry) add[T]() ComponentTypeID {
	type_id := typeof[T]().idx
	type_name := typeof[T]().name

	if type_id in type_registry.runtime_map {
		eprintln('Component type "${type_name}" is already registered. Returning existing RegistryID.')
		return type_registry.runtime_map[type_id]
	}

	id := type_registry.runtime_id
	type_registry.runtime_id++
	type_registry.runtime_map[type_id] = id
	type_registry.names << type_name
	return id
}

pub fn (type_registry &TypeRegistry) get[T]() !ComponentTypeID {
	type_id := typeof[T]().idx
	type_name := typeof[T]().name

	return type_registry.runtime_map[type_id] or {
		panic('Component type "${type_name}" is not registered.')
	}
}
