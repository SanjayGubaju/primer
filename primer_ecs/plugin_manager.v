module primer_ecs

// ------------- Plugin System -------------

// IPlugin interface: required for engine plugins.
// Each plugin must have a unique name and a build() method for setup.
pub interface IPlugin {
	name() string        // Unique plugin identifier
	build(mut app App) ! // Called when plugin added; setup/register here
}

// Optional: plugins can declare other plugins they depend on
pub interface IPluginDependencies {
	dependencies() []string // Names of required plugins
}

// Optional: plugins with lifecycle hooks for enable/disable
pub interface IPluginLifecycle {
	on_enable(mut app App) !  // Called after build
	on_disable(mut app App) ! // Called on plugin unload/disable
}

// Common base plugin: convenient constructor for plugin_name/enable flag.
pub struct BasePlugin {
pub:
	name string // Unique name
pub mut:
	enabled bool = true // Enable flag
}

// PluginManager: owns all plugins, tracks order/dependencies/state.
pub struct PluginManager {
mut:
	plugins      map[string]IPlugin // All registered plugins
	plugin_order []string           // Order of build/init
	initialized  bool               // Has build() run?
}

// new_plugin_manager creates a new manager.
pub fn new_plugin_manager() PluginManager {
	return PluginManager{
		plugins:      map[string]IPlugin{}
		plugin_order: []string{}
		initialized:  false
	}
}

// add adds plugin, checking for duplicates/dependencies.
pub fn (mut pm PluginManager) add(plugin IPlugin) ! {
	name := plugin.name()
	if name in pm.plugins {
		return error('Plugin "${name}" already added')
	}
	if plugin is IPluginDependencies {
		dependencies := plugin.dependencies()
		for dep in dependencies {
			if dep !in pm.plugins {
				return error('Plugin "${name}" requires missing dependency "${dep}"')
			}
		}
	}
	pm.plugins[name] = plugin
	pm.plugin_order << name
}

// add_before adds plugin before another plugin by name (ordering).
pub fn (mut pm PluginManager) add_before(plugin IPlugin, before_plugin string) ! {
	name := plugin.name()
	if before_plugin !in pm.plugins {
		return error('Plugin "${before_plugin}" not found')
	}
	mut idx := -1
	for i, plugin_name in pm.plugin_order {
		if plugin_name == before_plugin {
			idx = i
			break
		}
	}
	if idx == -1 {
		return error('Plugin "${before_plugin}" not in order list')
	}
	pm.plugins[name] = plugin
	pm.plugin_order.insert(idx, name)
}

// add_after adds plugin after another plugin by name (ordering).
pub fn (mut pm PluginManager) add_after(plugin IPlugin, after_plugin string) ! {
	name := plugin.name()
	if after_plugin !in pm.plugins {
		return error('Plugin "${after_plugin}" not found')
	}
	mut idx := -1
	for i, plugin_name in pm.plugin_order {
		if plugin_name == after_plugin {
			idx = i
			break
		}
	}
	if idx == -1 {
		return error('Plugin "${after_plugin}" not in order list')
	}
	pm.plugins[name] = plugin
	pm.plugin_order.insert(idx + 1, name)
}

// build initializes/builds all plugins in order. Call lifecycle hooks if implemented.
pub fn (mut pm PluginManager) build(mut app App) ! {
	if pm.initialized {
		return error('Plugins already initialized')
	}
	for name in pm.plugin_order {
		plugin := pm.plugins[name] or { continue }
		plugin.build(mut app)!
		if plugin is IPluginLifecycle {
			plugin.on_enable(mut app)!
		}
	}
	pm.initialized = true
}

// has checks if manager contains a plugin.
pub fn (pm &PluginManager) has(name string) bool {
	return name in pm.plugins
}

// list lists all registered plugin names (build order).
pub fn (pm &PluginManager) list() []string {
	return pm.plugin_order.clone()
}

// get gets a plugin by name (if present).
pub fn (pm &PluginManager) get(name string) ?IPlugin {
	return pm.plugins[name]
}

// remove removes plugin before initialization.
pub fn (mut pm PluginManager) remove(name string) ! {
	if pm.initialized {
		return error('Cannot remove plugins after initialization')
	}
	if name !in pm.plugins {
		return error('Plugin "${name}" not found')
	}
	pm.plugins.delete(name)
	pm.plugin_order = pm.plugin_order.filter(it != name)
}
