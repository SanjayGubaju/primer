module primer_input

import primer_ecs { App, BasePlugin, IPluginLifecycle }
import gg

// ===============================
//    Input Update System
// ===============================

// InputUpdateSystem: Updates the InputManager each frame using GG context.
// Should run first in .pre_update ECS stage.
pub struct InputUpdateSystem {}

// name returns system name
pub fn (_ &InputUpdateSystem) name() string {
	return 'InputUpdateSystem'
}

pub fn (_ &InputUpdateSystem) priority() int {
	return 1000 // Run very first
}

// update updates GG key/mouse state into InputManager resource.
pub fn (_ &InputUpdateSystem) update(mut app App, _ f64) ! {
	mut input := app.resource_manager.get[InputManager]() or { return }
	mut ctx := app.resource_manager.get_ref[gg.Context]() or { return }

	// Ensure maps exist
	if input.keys.len == 0 {
		input.keys = map[int]ButtonState{}
	}
	if input.mouse_buttons.len == 0 {
		input.mouse_buttons = map[int]ButtonState{}
	}

	// --- Update keyboard state using pressed_keys array ---
	for key_code in 0 .. ctx.pressed_keys.len {
		state := ctx.pressed_keys[key_code]
		old := input.keys[key_code] or { ButtonState{} }
		input.keys[key_code] = ButtonState{
			pressed:       state
			just_pressed:  state && !old.pressed
			just_released: !state && old.pressed
		}
	}

	// --- Update mouse buttons --- (left, right, middle)
	left_down := (ctx.mouse_buttons & gg.MouseButtons.left) == gg.MouseButtons.left
	right_down := (ctx.mouse_buttons & gg.MouseButtons.right) == gg.MouseButtons.right
	middle_down := (ctx.mouse_buttons & gg.MouseButtons.middle) == gg.MouseButtons.middle

	for idx, down in {
		int(gg.MouseButton.left):   left_down
		int(gg.MouseButton.right):  right_down
		int(gg.MouseButton.middle): middle_down
	} {
		old := input.mouse_buttons[idx] or { ButtonState{} }
		input.mouse_buttons[idx] = ButtonState{
			pressed:       down
			just_pressed:  down && !old.pressed
			just_released: !down && old.pressed
		}
	}

	// --- Mouse position & movement delta ---
	input.mouse_pos = Vec2{
		x: f64(ctx.mouse_pos_x)
		y: f64(ctx.mouse_pos_y)
	}
	input.mouse_delta = Vec2{
		x: f64(ctx.mouse_dx)
		y: f64(ctx.mouse_dy)
	}
}

// ================================
//      Input Plugin for ECS
// ================================

// InputPlugin sets up InputManager and InputUpdateSystem in the app.
// Implements IPluginLifecycle for setup/teardown hooks.
pub struct InputPlugin implements IPluginLifecycle {
	BasePlugin
}

// new_input_plugin creates a new InputPlugin instance.
pub fn new_input_plugin() InputPlugin {
	return InputPlugin{
		BasePlugin: BasePlugin{
			name: 'InputPlugin'
		}
	}
}

// name returns plugin name
pub fn (_ &InputPlugin) name() string {
	return 'InputPlugin'
}

// build registers input resources and systems.
pub fn (_ &InputPlugin) build(mut app App) ! {
	// Register InputManager resource with empty maps.
	app.resource_manager.insert(InputManager{
		keys:          map[int]ButtonState{}
		mouse_buttons: map[int]ButtonState{}
		actions:       map[string]InputAction{}
	})
	// Register InputUpdateSystem to run in .pre_update stage.
	app.system_manager.add(InputUpdateSystem{}, .pre_update)!
}

// Lifecycle: optional feedback on enable/disable.

pub fn (ip &InputPlugin) on_enable(mut _ App) ! {
	println('${ip.name()} plugin enabled')
}

pub fn (ip &InputPlugin) on_disable(mut _ App) ! {
	println('${ip.name()} plugin disabled')
}
