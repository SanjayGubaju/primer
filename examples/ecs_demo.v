import gg
import math
import rand
import sokol.audio
import time
import primer_ecs { App, BasePlugin, EntityHandle, IPlugin, ISystem, QuerySystem }
import primer_input { InputManager }

// ========================================
// COMPONENTS
// ========================================

struct Position {
pub mut:
	x f64
	y f64
}

struct Velocity {
pub mut:
	x f64
	y f64
}

struct Size {
pub mut:
	w f64
	h f64
}

struct Paddle {
pub mut:
	speed f64
}

struct Ball {
pub mut:
	speed f64
}

struct Brick {
pub mut:
	color gg.Color
}

// ========================================
// RESOURCES
// ========================================

struct GameConfig {
pub mut:
	title  string
	width  int = 800
	height int = 600
}

struct GameScore {
pub mut:
	points int
	lives  int = 3
}

struct GameState {
pub mut:
	paused       bool
	game_over    bool
	won          bool
	bricks_count int
}

struct FrameTiming {
pub mut:
	last_frame_time time.Time
}

// ========================================
// AUDIO MANAGER
// ========================================

enum SoundKind {
	paddle
	brick
	wall
	lose_ball
}

struct SoundManager {
mut:
	sounds      [4][]f32
	initialised bool
}

fn (mut sm SoundManager) init() {
	if !audio.is_valid() {
		audio.setup(buffer_frames: 512)
	}

	sample_rate := f32(audio.sample_rate())
	duration := 0.09
	volume := f32(0.25)
	frames := int(sample_rate * duration)
	frequencies := [f32(936), 432, 174, 123]
	for i, freq in frequencies {
		for j in 0 .. frames {
			t := f32(j) / sample_rate
			val := if i == 3 {
				math.sinf(t * freq * 2 * math.pi) // lose_ball has no volume
			} else {
				volume * math.sinf(t * freq * 2 * math.pi)
			}
			sm.sounds[i] << val
		}
	}
	sm.initialised = true
}

fn (mut sm SoundManager) play(kind SoundKind) {
	if sm.initialised {
		sound := sm.sounds[int(kind)]
		audio.push(sound.data, sound.len)
	}
}

fn (mut _ SoundManager) fade_out(ms int) {
	samples := int(f32(audio.sample_rate()) * f32(ms) / 1000.0)
	silence := []f32{len: samples, init: 0.0}
	audio.push(silence.data, silence.len)
}

// ========================================
// BREAKOUT PLUGIN
// ========================================

struct BreakoutPlugin implements IPlugin {
	BasePlugin
pub:
	config GameConfig
}

fn new_breakout_plugin(config GameConfig) BreakoutPlugin {
	return BreakoutPlugin{
		BasePlugin: BasePlugin{
			name: 'BreakoutPlugin'
		}
		config:     config
	}
}

fn (_ &BreakoutPlugin) name() string {
	return 'BreakoutPlugin'
}

fn (_ &BreakoutPlugin) dependencies() []string {
	return ['InputPlugin']
}

fn (bp &BreakoutPlugin) build(mut app App) ! {
	// Register components
	app.world.register_type[Position]()
	app.world.register_type[Velocity]()
	app.world.register_type[Size]()
	app.world.register_type[Paddle]()
	app.world.register_type[Ball]()
	app.world.register_type[Brick]()

	// Initialize resources
	app.resource_manager.insert(bp.config)
	app.resource_manager.insert(GameScore{ lives: 3 })
	app.resource_manager.insert(GameState{})
	app.resource_manager.insert(SoundManager{})
	app.resource_manager.insert(FrameTiming{ last_frame_time: time.now() })

	// Add systems (each system owns its QuerySystem)
	app.system_manager.add(new_paddle_control_system(app), .update)!
	app.system_manager.add(new_movement_system(app), .update)!
	app.system_manager.add(new_ball_physics_system(app), .update)!
	app.system_manager.add(new_collision_system(app), .post_update)!
	app.system_manager.add(new_render_system(app), .render)!
}

fn (_ &BreakoutPlugin) on_enable(mut app App) ! {
	setup_game(mut app)
}

fn (_ &BreakoutPlugin) on_disable(mut _ App) ! {}

// ========================================
// SYSTEMS (system-owned QuerySystem)
// ========================================

struct PaddleControlSystem implements ISystem {
	QuerySystem
}

fn new_paddle_control_system(app &App) PaddleControlSystem {
	query_types := [
		app.world.get_type_id[Paddle](),
		app.world.get_type_id[Velocity](),
	]
	return PaddleControlSystem{
		QuerySystem: primer_ecs.new_query_system(query_types)
	}
}

fn (_ &PaddleControlSystem) name() string {
	return 'PaddleControlSystem'
}

fn (ps &PaddleControlSystem) update(mut app App, _ f64) ! {
	input := app.resource_manager.get[InputManager]() or { return }
	mut query_sys := ps.QuerySystem
	for result in query_sys.query(app.world) {
		paddle := result.get[Paddle](app.world) or { continue }
		mut vel := result.get[Velocity](app.world) or { continue }
		vel.x = 0

		if input.keys[int(gg.KeyCode.a)].pressed {
			vel.x = -paddle.speed
		}
		if input.keys[int(gg.KeyCode.d)].pressed {
			vel.x = paddle.speed
		}
	}
}

struct MovementSystem {
	QuerySystem
}

fn new_movement_system(app &App) MovementSystem {
	query_types := [
		app.world.get_type_id[Position](),
		app.world.get_type_id[Velocity](),
	]
	return MovementSystem{
		QuerySystem: primer_ecs.new_query_system(query_types)
	}
}

fn (_ &MovementSystem) name() string {
	return 'MovementSystem'
}

fn (ms &MovementSystem) update(mut app App, dt f64) ! {
	config := app.resource_manager.get[GameConfig]() or { return }
	mut query_sys := ms.QuerySystem

	for result in query_sys.query(app.world) {
		mut pos := result.get[Position](app.world) or { continue }
		vel := result.get[Velocity](app.world) or { continue }
		pos.x += vel.x * dt
		pos.y += vel.y * dt

		// Keep paddle on screen
		if app.world.has[Paddle](result.entity) {
			if size := app.world.get[Size](result.entity) {
				pos.x = math.clamp(pos.x, 0, config.width - size.w)
			}
		}
	}
}

struct BallPhysicsSystem {
	QuerySystem
}

fn new_ball_physics_system(app &App) BallPhysicsSystem {
	return BallPhysicsSystem{
		QuerySystem: primer_ecs.new_query_system([
			app.world.get_type_id[Ball](),
			app.world.get_type_id[Position](),
			app.world.get_type_id[Velocity](),
			app.world.get_type_id[Size](),
		])
	}
}

fn (_ &BallPhysicsSystem) name() string {
	return 'BallPhysicsSystem'
}

fn (bps &BallPhysicsSystem) update(mut app App, dt f64) ! {
	config := app.resource_manager.get[GameConfig]() or { return }
	mut score := app.resource_manager.get[GameScore]() or { return }
	mut state := app.resource_manager.get[GameState]() or { return }
	mut sound := app.resource_manager.get[SoundManager]() or { return }
	mut query_sys := bps.QuerySystem

	for result in query_sys.query(app.world) {
		pos := result.get[Position](app.world) or { continue }
		size := result.get[Size](app.world) or { continue }
		mut vel := result.get[Velocity](app.world) or { continue }

		// Bounce off walls
		if pos.x <= 0 || pos.x + size.w >= config.width {
			vel.x *= -1
			sound.play(.wall)
		}
		if pos.y <= 0 {
			vel.y *= -1
			sound.play(.wall)
		}

		// Ball fell off bottom
		if pos.y > config.height {
			sound.play(.lose_ball)

			// Update scores
			score.lives--
			state.paused = true
			if score.lives <= 0 {
				state.game_over = true
			}

			reset_ball(mut app, result.entity)
			reset_paddle(mut app, config)
		}
	}
}

struct CollisionSystem {
	QuerySystem
}

fn new_collision_system(app &App) CollisionSystem {
	pos_id := app.world.get_type_id[Position]()
	size_id := app.world.get_type_id[Size]()
	return CollisionSystem{
		QuerySystem: primer_ecs.new_query_system([pos_id, size_id])
	}
}

fn (_ &CollisionSystem) name() string {
	return 'CollisionSystem'
}

fn (_ &CollisionSystem) update(mut app App, _ f64) ! {
	mut score := app.resource_manager.get[GameScore]() or { return }
	mut state := app.resource_manager.get[GameState]() or { return }
	mut sound := app.resource_manager.get[SoundManager]() or { return }

	ball_id := app.world.get_type_id[Ball]()
	paddle_id := app.world.get_type_id[Paddle]()
	brick_id := app.world.get_type_id[Brick]()
	pos_id := app.world.get_type_id[Position]()
	vel_id := app.world.get_type_id[Velocity]()
	size_id := app.world.get_type_id[Size]()

	for ball in app.world.query([ball_id, pos_id, vel_id, size_id]) {
		mut ball_pos := ball.get[Position](app.world) or { continue }
		ball_size := ball.get[Size](app.world) or { continue }
		mut ball_vel := ball.get[Velocity](app.world) or { continue }

		for paddle in app.world.query([paddle_id, pos_id, size_id]) {
			paddle_pos := paddle.get[Position](app.world) or { continue }
			paddle_size := paddle.get[Size](app.world) or { continue }
			if collides(ball_pos, ball_size, paddle_pos, paddle_size) {
				// Position ball above paddle
				ball_pos.y = paddle_pos.y - ball_size.h - 1

				// Calculate bounce angle based on hit position
				hit_x := (ball_pos.x + ball_size.w / 2) - (paddle_pos.x + paddle_size.w / 2)
				normalized := math.clamp(hit_x / (paddle_size.w / 2), -1.0, 1.0)

				// Fixed speed with angle variation (±60°)
				speed := 300.0
				angle := normalized * math.pi / 3.0
				ball_vel.x = speed * math.sin(angle)
				ball_vel.y = -math.abs(speed * math.cos(angle))

				sound.play(.paddle)
			}
		}

		for brick in app.world.query([brick_id, pos_id, size_id]) {
			brick_pos := brick.get[Position](app.world) or { continue }
			brick_size := brick.get[Size](app.world) or { continue }

			if collides(ball_pos, ball_size, brick_pos, brick_size) {
				ball_vel.y *= -1
				ball_vel.x *= 1.03
				ball_vel.y *= 1.03

				sound.play(.brick)
				app.world.despawn(brick.entity)

				// Update scores
				score.points += 10
				state.bricks_count--
				if state.bricks_count <= 0 {
					state.won = true
				}
				break
			}
		}
	}
}

struct RenderSystem {
	QuerySystem
}

fn new_render_system(app &App) RenderSystem {
	return RenderSystem{
		QuerySystem: primer_ecs.new_query_system([
			app.world.get_type_id[Position](),
			app.world.get_type_id[Size](),
		])
	}
}

fn (_ &RenderSystem) name() string {
	return 'RenderSystem'
}

fn (rs &RenderSystem) update(mut app App, _ f64) ! {
	mut ctx := app.resource_manager.get_ref[gg.Context]() or { return }
	mut query_sys := rs.QuerySystem

	for result in query_sys.query(app.world) {
		pos := result.get[Position](app.world) or { continue }
		size := result.get[Size](app.world) or { continue }

		if app.world.has[Ball](result.entity) {
			draw_ball(mut ctx, pos, size)
		} else if app.world.has[Paddle](result.entity) {
			draw_paddle(mut ctx, pos, size)
		} else if brick := app.world.get[Brick](result.entity) {
			draw_brick(mut ctx, pos, size, brick.color)
		}
	}
	draw_ui(mut app)
}

// ========================================
// GAME LOGIC HELPERS, RENDER, COLLISION, UI
// ========================================

const bevel_size = 4
const highlight = gg.rgba(255, 255, 255, 65)
const shadow = gg.rgba(0, 0, 0, 65)

fn draw_ball(mut ctx gg.Context, pos Position, size Size) {
	radius := f32(size.w) / 2
	cx := f32(pos.x) + radius
	cy := f32(pos.y) + radius

	// Draw ball
	ctx.draw_circle_filled(cx, cy, radius, gg.red)

	// Highlight effect
	mut r := radius
	for _ in 0 .. 3 {
		r *= 0.8
		ctx.draw_circle_filled(cx - radius + r, cy - radius + r, r, highlight)
	}
}

fn draw_paddle(mut ctx gg.Context, pos Position, size Size) {
	x := f32(pos.x)
	y := f32(pos.y)
	w := f32(size.w)
	h := f32(size.h)

	// Rounded edges
	ctx.draw_circle_filled(x - 5, y + h, 18, gg.blue)
	ctx.draw_circle_filled(x + w + 5, y + h, 18, gg.blue)

	// Main body
	ctx.draw_rect_filled(x, y, w, h, gg.blue)
	ctx.draw_rect_filled(x, y, w, bevel_size, highlight)
}

fn draw_brick(mut ctx gg.Context, pos Position, size Size, color gg.Color) {
	x := f32(pos.x)
	y := f32(pos.y)
	w := f32(size.w)
	h := f32(size.h)

	ctx.draw_rect_filled(x, y, w, h, color)
	ctx.draw_rect_filled(x, y, w, bevel_size, highlight)
	ctx.draw_rect_filled(x, y, bevel_size, h - bevel_size, highlight)
	ctx.draw_rect_filled(x + w - bevel_size, y, bevel_size, h - bevel_size, shadow)
	ctx.draw_rect_filled(x, y + h - bevel_size, w, bevel_size, shadow)
}

fn draw_ui(mut app App) {
	mut ctx := app.resource_manager.get_ref[gg.Context]() or { return }
	score := app.resource_manager.get[GameScore]() or { return }
	state := app.resource_manager.get[GameState]() or { return }
	config := app.resource_manager.get[GameConfig]() or { return }

	// Score display
	ctx.draw_text(20, 20, 'Score: ${score.points}', size: 24, color: gg.white)
	ctx.draw_text(20, 50, 'Lives: ${score.lives}', size: 24, color: gg.white)
	ctx.draw_text(20, 80, 'Bricks: ${state.bricks_count}', size: 20, color: gg.white)

	// Game over screen
	if state.game_over {
		draw_overlay(mut ctx, config, 'GAME OVER', gg.red, score.points)
	} else if state.won {
		draw_overlay(mut ctx, config, 'YOU WIN!', gg.green, score.points)
	}
}

fn draw_overlay(mut ctx gg.Context, config GameConfig, title string, title_color gg.Color, score_points int) {
	ctx.draw_rect_filled(0, 0, f32(config.width), f32(config.height), gg.rgba(0, 0, 0,
		180))
	center_x := config.width / 2
	center_y := config.height / 2

	ctx.draw_text(center_x, center_y, title, size: 50, color: title_color, align: .center)
	ctx.draw_text(center_x, center_y + 60, 'Score: ${score_points}',
		size:  30
		color: gg.white
		align: .center
	)
	ctx.draw_text(center_x, center_y + 100, 'Press SPACE to restart',
		size:  20
		color: gg.white
		align: .center
	)
}

fn collides(pos1 Position, size1 Size, pos2 Position, size2 Size) bool {
	return pos1.x < pos2.x + size2.w && pos1.x + size1.w > pos2.x && pos1.y < pos2.y + size2.h
		&& pos1.y + size1.h > pos2.y
}

fn reset_ball(mut app App, ball_entity EntityHandle) {
	mut pos := app.world.get[Position](ball_entity) or { return }
	mut vel := app.world.get[Velocity](ball_entity) or { return }
	pos.x = 390
	pos.y = 520
	vel.x = 200 * if rand.intn(2) or { 0 } == 0 { 1 } else { -1 }
	vel.y = -250
}

fn reset_paddle(mut app App, config GameConfig) {
	paddle_id := app.world.get_type_id[Paddle]()
	size_id := app.world.get_type_id[Size]()
	pos_id := app.world.get_type_id[Position]()
	for result in app.world.query([paddle_id, size_id, pos_id]) {
		if size := app.world.get[Size](result.entity) {
			mut pos := result.get[Position](app.world) or { continue }
			pos.x = (config.width - size.w) / 2
			break
		}
	}
}

fn setup_game(mut app App) {
	mut state := app.resource_manager.get[GameState]() or { return }
	eprintln('Before ---------------------------')
	// Create paddle
	app.world.create_with_components([
		app.world.component[Position](Position{ x: 350, y: 550 }),
		app.world.component[Size](Size{ w: 100, h: 15 }),
		app.world.component[Velocity](Velocity{}),
		app.world.component[Paddle](Paddle{ speed: 500 }),
	]) or {
		eprintln(err)
		return
	}

	// Create ball
	app.world.create_with_components([
		app.world.component[Position](Position{ x: 390, y: 520 }),
		app.world.component[Size](Size{ w: 15, h: 15 }),
		app.world.component[Velocity](Velocity{ x: 200, y: -250 }),
		app.world.component[Ball](Ball{ speed: 250 }),
	]) or {
		eprintln(err)
		return
	}

	// Create bricks
	cols := 10
	rows := 5
	colors := [gg.red, gg.orange, gg.yellow, gg.cyan, gg.blue]

	for y in 0 .. rows {
		for x in 0 .. cols {
			app.world.create_with_components([
				app.world.component[Position](Position{
					x: 60 + f64(x) * 70
					y: 50 + f64(y) * 30
				}),
				app.world.component[Size](Size{ w: 60, h: 20 }),
				app.world.component[Brick](Brick{ color: colors[y] }),
			]) or { continue }
			state.bricks_count++
		}
	}

	// Initialize audio
	mut sound := app.resource_manager.get[SoundManager]() or { return }
	sound.init()
	sound.play(.paddle)
}

fn restart_game(mut app App) {
	app.world.clear()

	mut score := app.resource_manager.get[GameScore]() or { return }
	score.points = 0
	score.lives = 3

	mut state := app.resource_manager.get[GameState]() or { return }
	state.game_over = false
	state.won = false
	state.bricks_count = 0

	setup_game(mut app)
}

// ========================================
// MAIN GAME LOOP
// ========================================

struct Game {
mut:
	app App
}

fn frame(mut game Game) {
	mut ctx := game.app.resource_manager.get_ref[gg.Context]() or { return }
	ctx.begin()

	// Calculate actual delta time
	mut timing := game.app.resource_manager.get[FrameTiming]() or {
		ctx.end()
		return
	}
	now := time.now()
	dt := (now - timing.last_frame_time).seconds()
	timing.last_frame_time = now
	game.app.resource_manager.insert(timing)

	// Handle game state
	mut state := game.app.resource_manager.get[GameState]() or {
		ctx.end()
		return
	}

	is_paused := state.paused || state.game_over || state.won
	if is_paused {
		mut sound := game.app.resource_manager.get[SoundManager]() or {
			ctx.end()
			return
		}
		sound.fade_out(100)
	}
	game.app.system_manager.set_enabled('MovementSystem', !is_paused)
	game.app.system_manager.set_enabled('BallPhysicsSystem', !is_paused)
	game.app.system_manager.set_enabled('CollisionSystem', !is_paused)

	// Update all systems
	game.app.system_manager.update_all(mut game.app, dt) or {
		eprintln('[ERROR] System update failed: ${err}')
		ctx.end()
		return
	}

	// Handle input
	if input := game.app.resource_manager.get[InputManager]() {
		if input.keys[int(gg.KeyCode.space)].just_pressed {
			if state.game_over || state.won {
				restart_game(mut game.app)
			} else if state.paused {
				state.paused = false
			}
		}
	}

	ctx.end()
}

fn main() {
	println('=== Starting Breakout ===')
	mut game := Game{
		app: primer_ecs.new_app()
	}
	mut plugin_mgr := primer_ecs.new_plugin_manager()

	// Add plugins
	plugin_mgr.add(primer_input.new_input_plugin())!
	plugin_mgr.add(new_breakout_plugin(GameConfig{
		title:  'Breakout ECS'
		width:  800
		height: 600
	}))!

	// Build and initialize
	plugin_mgr.build(mut game.app)!
	game.app.system_manager.init_all(mut game.app)!

	// Create window and run
	config := game.app.resource_manager.get[GameConfig]() or { panic('No config') }
	mut ctx := gg.new_context(
		width:        config.width
		height:       config.height
		window_title: config.title
		bg_color:     gg.black
		frame_fn:     frame
		user_data:    &game
	)
	game.app.resource_manager.insert_ref(ctx)

	ctx.run()
}
