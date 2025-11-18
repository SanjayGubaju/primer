module primer_ecs

import time

// -------------------- System Stages --------------------

pub enum SystemStage {
	pre_update
	update
	post_update
	render
	cleanup
}

pub fn get_all_stages() []SystemStage {
	return [
		SystemStage.pre_update,
		SystemStage.update,
		SystemStage.post_update,
		SystemStage.render,
		SystemStage.cleanup,
	]
}

// -------------------- Core System Interface --------------------

pub interface ISystem {
	update(mut app App, dt f64) !
	name() string
}

// Optional interfaces
pub interface IPrioritizer {
	priority() int
}

pub interface IDependencies {
	depends_on() []string // System names this depends on
}

pub interface IParallel {
	can_run_parallel() bool
}

// -------------------- System Statistics --------------------

pub struct SystemStats {
pub mut:
	total_time_ns i64
	call_count    u64
	error_count   u64
}

pub fn (ss &SystemStats) avg_time_ms() f64 {
	if ss.call_count == 0 {
		return 0.0
	}
	return f64(ss.total_time_ns) / f64(ss.call_count) / 1_000_000.0
}

fn (mut ss SystemStats) record_execution(duration_ns i64, had_error bool) {
	ss.total_time_ns += duration_ns
	ss.call_count++
	if had_error {
		ss.error_count++
	}
}

// -------------------- System Wrapper --------------------

struct SystemWrapper {
	system ISystem
	stage  SystemStage
mut:
	enabled         bool = true
	stats           SystemStats
	execution_order int // Computed order based on dependencies
}

fn get_priority(system ISystem) int {
	if system is IPrioritizer {
		return system.priority()
	}
	return 0
}

fn get_dependencies(system ISystem) []string {
	if system is IDependencies {
		return system.depends_on()
	}
	return []string{}
}

fn can_run_parallel(system ISystem) bool {
	if system is IParallel {
		return system.can_run_parallel()
	}
	return false
}

// -------------------- System Manager --------------------

pub struct SystemManager {
mut:
	systems          []SystemWrapper
	stats_enabled    bool
	dependency_graph DependencyGraph
	needs_reorder    bool = true
}

pub fn new_system_manager() SystemManager {
	return SystemManager{
		systems:          []SystemWrapper{}
		stats_enabled:    false
		dependency_graph: new_dependency_graph()
		needs_reorder:    true
	}
}

pub fn (mut sm SystemManager) add(system ISystem, stage SystemStage) ! {
	name := system.name()
	if sm.find_system(name) != none {
		return error('System with name "${name}" already exists')
	}

	sm.systems << SystemWrapper{
		system:          system
		stage:           stage
		enabled:         true
		stats:           SystemStats{}
		execution_order: 0
	}

	sm.needs_reorder = true
}

fn (sm &SystemManager) find_system(name string) ?int {
	for i, wrapper in sm.systems {
		if wrapper.system.name() == name {
			return i
		}
	}
	return none
}

pub fn (mut sm SystemManager) remove(name string) !bool {
	for i, wrapper in sm.systems {
		if wrapper.system.name() == name {
			sm.systems.delete(i)
			sm.needs_reorder = true
			return true
		}
	}
	return false
}

pub fn (mut sm SystemManager) set_enabled(name string, enabled bool) {
	if idx := sm.find_system(name) {
		sm.systems[idx].enabled = enabled
	}
}

pub fn (sm &SystemManager) is_enabled(name string) bool {
	if idx := sm.find_system(name) {
		return sm.systems[idx].enabled
	}
	return false
}

pub fn (mut sm SystemManager) enable_stats(enabled bool) {
	sm.stats_enabled = enabled
}

pub fn (sm &SystemManager) get_stats(name string) ?SystemStats {
	if idx := sm.find_system(name) {
		return sm.systems[idx].stats
	}
	return none
}

pub fn (mut sm SystemManager) reset_stats() {
	for mut wrapper in sm.systems {
		wrapper.stats = SystemStats{}
	}
}

pub fn (sm &SystemManager) len() int {
	return sm.systems.len
}

// -------------------- Dependency Resolution --------------------

struct DependencyGraph {
mut:
	adjacency map[string][]string // system -> dependencies
}

fn new_dependency_graph() DependencyGraph {
	return DependencyGraph{
		adjacency: map[string][]string{}
	}
}

fn (mut dg DependencyGraph) add_system(name string, dependencies []string) {
	dg.adjacency[name] = dependencies
}

// topological_sort sorts using Kahn's algorithm
fn (dg &DependencyGraph) topological_sort() ![]string {
	mut in_degree := map[string]int{}
	mut all_nodes := map[string]bool{}

	// Initialize in-degree for all nodes
	for node, dependencies in dg.adjacency {
		all_nodes[node] = true
		if node !in in_degree {
			in_degree[node] = 0
		}
		for dep in dependencies {
			all_nodes[dep] = true
			in_degree[dep] = in_degree[dep] or { 0 } + 1
		}
	}

	// Find nodes with no dependencies
	mut queue := []string{}
	for node, _ in all_nodes {
		if in_degree[node] or { 0 } == 0 {
			queue << node
		}
	}

	mut result := []string{}

	for queue.len > 0 {
		current := queue[0]
		queue = queue[1..].clone()
		result << current

		// Reduce in-degree for dependents
		for node, dependencies in dg.adjacency {
			if current in dependencies {
				in_degree[node] = in_degree[node] - 1
				if in_degree[node] == 0 {
					queue << node
				}
			}
		}
	}

	// Check for cycles
	if result.len != all_nodes.len {
		return error('Circular dependency detected in systems')
	}

	return result
}

// -------------------- System Ordering --------------------

fn (mut sm SystemManager) compute_execution_order() ! {
	if !sm.needs_reorder {
		return
	}

	// Group systems by stage
	mut stages := map[SystemStage][]int{}
	for i, wrapper in sm.systems {
		if wrapper.stage !in stages {
			stages[wrapper.stage] = []int{}
		}
		stages[wrapper.stage] << i
	}

	// Process each stage independently
	for stage, indices in stages {
		sm.order_stage(stage, indices)!
	}

	sm.needs_reorder = false
}

fn (mut sm SystemManager) order_stage(stage SystemStage, indices []int) ! {
	mut graph := new_dependency_graph()

	// Build dependency graph for this stage
	for idx in indices {
		system := sm.systems[idx].system
		name := system.name()
		dependencies := get_dependencies(system)

		// Validate dependencies exist in same stage
		for dep in dependencies {
			if dep_idx := sm.find_system(dep) {
				if sm.systems[dep_idx].stage != stage {
					return error('System "${name}" depends on "${dep}" which is in a different stage')
				}
			} else {
				return error('System "${name}" depends on unknown system "${dep}"')
			}
		}

		graph.add_system(name, dependencies)
	}

	// Get topological order
	ordered_names := graph.topological_sort()!

	// Create name to order mapping
	mut name_to_order := map[string]int{}
	for i, name in ordered_names {
		name_to_order[name] = i
	}

	// Assign execution order (considering priority as tiebreaker)
	for idx in indices {
		name := sm.systems[idx].system.name()
		base_order := name_to_order[name] or { 0 }
		priority := get_priority(sm.systems[idx].system)

		// Higher priority = lower execution order (runs first within dependency level)
		sm.systems[idx].execution_order = base_order * 1000 - priority
	}
}

// -------------------- Update Logic --------------------

pub fn (mut sm SystemManager) update_stage(mut app App, stage SystemStage, dt f64) ! {
	// Reorder if needed
	sm.compute_execution_order()!

	// Collect enabled systems for this stage
	mut system_indices := []int{}
	for i, wrapper in sm.systems {
		if wrapper.stage == stage && wrapper.enabled {
			system_indices << i
		}
	}

	// Sort by execution order
	system_indices.sort_with_compare(fn [sm] (a &int, b &int) int {
		return sm.systems[*a].execution_order - sm.systems[*b].execution_order
	})

	// Group parallel and sequential systems
	mut parallel_groups := [][]int{}
	mut sequential := []int{}

	mut current_parallel := []int{}
	for idx in system_indices {
		if can_run_parallel(sm.systems[idx].system) {
			current_parallel << idx
		} else {
			// Flush parallel group if any
			if current_parallel.len > 0 {
				parallel_groups << current_parallel.clone()
				current_parallel.clear()
			}
			sequential << idx
		}
	}

	// Flush remaining parallel group
	if current_parallel.len > 0 {
		parallel_groups << current_parallel
	}

	// Execute systems
	for group in parallel_groups {
		// TODO: Actually run in parallel with threads when V supports it better
		// For now, run sequentially
		for idx in group {
			sm.execute_system(idx, mut app, dt)!
		}
	}

	for idx in sequential {
		sm.execute_system(idx, mut app, dt)!
	}
}

fn (mut sm SystemManager) execute_system(idx int, mut app App, dt f64) ! {
	if sm.stats_enabled {
		start := time.now()
		sm.systems[idx].system.update(mut app, dt) or {
			duration := (time.now() - start).nanoseconds()
			sm.systems[idx].stats.record_execution(duration, true)
			return err
		}
		duration := (time.now() - start).nanoseconds()
		sm.systems[idx].stats.record_execution(duration, false)
	} else {
		sm.systems[idx].system.update(mut app, dt)!
	}
}

pub fn (mut sm SystemManager) update_all(mut app App, dt f64) ! {
	for stage in get_all_stages() {
		sm.update_stage(mut app, stage, dt)!
	}
}

pub fn (mut sm SystemManager) update(mut app App, dt f64) ! {
	sm.update_stage(mut app, SystemStage.update, dt)!
}

pub fn (mut sm SystemManager) render(mut app App, dt f64) ! {
	sm.update_stage(mut app, SystemStage.render, dt)!
}

pub fn (mut sm SystemManager) pre_update(mut app App, dt f64) ! {
	sm.update_stage(mut app, SystemStage.pre_update, dt)!
}

pub fn (mut sm SystemManager) post_update(mut app App, dt f64) ! {
	sm.update_stage(mut app, SystemStage.post_update, dt)!
}

pub fn (mut sm SystemManager) cleanup(mut app App, dt f64) ! {
	sm.update_stage(mut app, SystemStage.cleanup, dt)!
}

// -------------------- Initialization --------------------

pub interface IInitializer {
	init(mut app App) !
}

pub fn (mut sm SystemManager) init_all(mut app App) ! {
	for mut wrapper in sm.systems {
		if wrapper.system is IInitializer {
			wrapper.system.init(mut app)!
		}
	}
}

pub interface IFinalizer {
	finalize(mut app App) !
}

pub fn (mut sm SystemManager) finalize_all(mut app App) ! {
	for mut wrapper in sm.systems {
		if wrapper.system is IFinalizer {
			wrapper.system.finalize(mut app)!
		}
	}
}

// -------------------- Utilities --------------------

pub fn (sm &SystemManager) get_all_systems() []string {
	mut names := []string{}
	for wrapper in sm.systems {
		names << wrapper.system.name()
	}
	return names
}

pub fn (mut sm SystemManager) clear() {
	sm.systems.clear()
	sm.dependency_graph = new_dependency_graph()
	sm.needs_reorder = true
}

// Get execution order info (for debugging)
pub struct SystemExecutionInfo {
pub:
	name            string
	stage           SystemStage
	execution_order int
	dependencies    []string
	can_parallel    bool
	priority        int
}

pub fn (sm &SystemManager) get_execution_info() []SystemExecutionInfo {
	mut info := []SystemExecutionInfo{}

	for wrapper in sm.systems {
		system := wrapper.system
		info << SystemExecutionInfo{
			name:            system.name()
			stage:           wrapper.stage
			execution_order: wrapper.execution_order
			dependencies:    get_dependencies(system)
			can_parallel:    can_run_parallel(system)
			priority:        get_priority(system)
		}
	}

	return info
}
