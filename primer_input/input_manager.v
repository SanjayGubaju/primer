module primer_input

// ------------------------------
//  Input Action & State Structs
// ------------------------------

// ButtonState tracks current and transition moment for key or mouse button.
pub struct ButtonState {
pub mut:
	pressed       bool
	just_pressed  bool
	just_released bool
}

// Vec2 for mouse position and movement.
pub struct Vec2 {
pub mut:
	x f64
	y f64
}

// InputAction maps any number of keys/mouse buttons to a single high-level action.
pub struct InputAction {
pub:
	keys          []int // Key codes mapped to this action
	mouse_buttons []int // Mouse button codes mapped to this action
}

// ------------------------------
//   Input Manager Resource
// ------------------------------

// InputManager is the engine's input resource for all keys, mouse, and actions.
// Register as a resource and update each frame for consistent behavior.
pub struct InputManager {
pub mut:
	keys          map[int]ButtonState    // KeyCode => ButtonState
	mouse_buttons map[int]ButtonState    // MouseCode => ButtonState
	mouse_pos     Vec2                   // Current position
	mouse_delta   Vec2                   // Movement since last frame
	actions       map[string]InputAction // Named actions for high-level input
}

// register_action registers a new named action mapping for easy queries.
pub fn (mut im InputManager) register_action(name string, action InputAction) {
	im.actions[name] = action
}

// unregister_action unregisters a named input action.
pub fn (mut im InputManager) unregister_action(name string) {
	im.actions.delete(name)
}

// is_action_pressed checks if *any* key or button for this action is currently pressed.
pub fn (im &InputManager) is_action_pressed(name string) bool {
	action := im.actions[name] or { return false }
	for key in action.keys {
		if state := im.keys[key] {
			if state.pressed {
				return true
			}
		}
	}
	for mb in action.mouse_buttons {
		if state := im.mouse_buttons[mb] {
			if state.pressed {
				return true
			}
		}
	}
	return false
}

// is_action_just_pressed checks if any key/button for this action was *just pressed* this frame.
pub fn (im &InputManager) is_action_just_pressed(name string) bool {
	action := im.actions[name] or { return false }
	for key in action.keys {
		if state := im.keys[key] {
			if state.just_pressed {
				return true
			}
		}
	}
	for mb in action.mouse_buttons {
		if state := im.mouse_buttons[mb] {
			if state.just_pressed {
				return true
			}
		}
	}
	return false
}

// is_action_just_released checks if any key/button for this action was *just released* this frame.
pub fn (im &InputManager) is_action_just_released(name string) bool {
	action := im.actions[name] or { return false }
	for key in action.keys {
		if state := im.keys[key] {
			if state.just_released {
				return true
			}
		}
	}
	for mb in action.mouse_buttons {
		if state := im.mouse_buttons[mb] {
			if state.just_released {
				return true
			}
		}
	}
	return false
}

// frame_update calls once per frame after GG events to clear transient states.
pub fn (mut im InputManager) frame_update() {
	for mut st in im.keys.values() {
		st.just_pressed = false
		st.just_released = false
	}
	for mut st in im.mouse_buttons.values() {
		st.just_pressed = false
		st.just_released = false
	}
	im.mouse_delta = Vec2{
		x: 0
		y: 0
	}
}

// set_key_state sets pressed flag for a key.
pub fn (mut im InputManager) set_key_state(key int, pressed bool) {
	mut state := im.keys[key] or { ButtonState{} }
	if pressed && !state.pressed {
		state.just_pressed = true
	} else if !pressed && state.pressed {
		state.just_released = true
	}
	state.pressed = pressed
	im.keys[key] = state
}

// set_mouse_button_state sets pressed flag for a mouse button.
pub fn (mut im InputManager) set_mouse_button_state(btn int, pressed bool) {
	mut state := im.mouse_buttons[btn] or { ButtonState{} }
	if pressed && !state.pressed {
		state.just_pressed = true
	} else if !pressed && state.pressed {
		state.just_released = true
	}
	state.pressed = pressed
	im.mouse_buttons[btn] = state
}

// set_mouse_pos sets mouse position and update delta.
pub fn (mut im InputManager) set_mouse_pos(x f64, y f64) {
	im.mouse_delta = Vec2{
		x: x - im.mouse_pos.x
		y: y - im.mouse_pos.y
	}
	im.mouse_pos = Vec2{
		x: x
		y: y
	}
}

// clear resets all states (for resets or clean shutdown).
pub fn (mut im InputManager) clear() {
	im.keys.clear()
	im.mouse_buttons.clear()
	im.actions.clear()
	im.mouse_pos = Vec2{}
	im.mouse_delta = Vec2{}
}
