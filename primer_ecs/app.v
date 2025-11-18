module primer_ecs

pub struct App {
pub mut:
	world            World
	resource_manager ResourceManager
	plugin_manager   PluginManager
	system_manager   SystemManager
}

pub fn new_app() &App {
	return &App{
		world:            new_world()
		resource_manager: new_resource_manager()
		plugin_manager:   new_plugin_manager()
		system_manager:   new_system_manager()
	}
}
