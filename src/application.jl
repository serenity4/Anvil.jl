mutable struct Application
  task::Task
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  windows::Dict{Window, EntityID}
  systems::Systems
  fonts::Dict{String, OpenTypeFont}
  is_release::Bool
  show_shortcuts::Bool
  Application() = new()
end

is_release() = app.is_release

function Base.show(io::IO, app::Application)
  print(io, Application, '(', isdefined(app, :task) ? app.task : "#undef", ", ", isdefined(app, :wm) ? app.wm : "#undef", ", ", isdefined(app, :ecs) ? app.ecs : "#undef", ", release: ", is_release(), ')')
end

function initialize(f::Function)
  app.is_release = get(ENV, "ANVIL_RELEASE", "false") == "true"

  ecs = new_database()
  app.ecs = ecs

  wm = XWindowManager()

  WINDOW_ENTITY_COUNTER.val = typemax(UInt32) - 100U
  window = Window(wm, "Anvil"; width = 1920, height = 1080, map = false)
  window_id = new_entity(EntityID(Entities.next!(WINDOW_ENTITY_COUNTER)))
  ecs[window_id, WINDOW_COMPONENT_ID] = window
  set_location(window_id, zero(P2))
  set_geometry(window_id, window_geometry(window))

  systems = Systems(
    LayoutSystem(ecs),
    DrawingOrderSystem(),
    RenderingSystem(Renderer(window)),
    EventSystem(EventQueue(wm), UserInterface(window)),
  )
  app.wm = wm
  app.entity_pool = EntityPool(; limit = WINDOW_ENTITY_COUNTER[] - 1)
  app.window = window
  app.windows = Dict(window => window_id)
  app.systems = systems
  app.fonts = Dict()
  app.show_shortcuts = false

  bind(exit, key"ctrl+q")
  bind(key"alt_left") do
    app.show_shortcuts = !app.show_shortcuts
    set_contextual_shortcuts_visibility(app.show_shortcuts)
  end

  # Required because `WidgetComponent` is a Union, so `typeof(value)` at first insertion will be too narrow.
  app.ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()
  f()

  start(systems.rendering.renderer)
  map_window(window)
  nothing
end

window_geometry(window::XCBWindow) = Box(Point2(screen_semidiagonal(aspect_ratio(extent(window)))))

is_left_click(event::Event) = event.mouse_event.button == BUTTON_LEFT
is_left_click(input::Input) = (input.type === BUTTON_PRESSED || input.type === BUTTON_RELEASED) && is_left_click(input.event)

WindowAbstractions.matches(kc::KeyCombination, input::Input) = (input.type === KEY_PRESSED || input.type === KEY_RELEASED) && matches(kc, input.event)

function new_entity(entity::EntityID = new!(app.entity_pool))
  app.ecs[entity, ENTITY_COMPONENT_ID] = entity
  entity
end
Base.delete!(app::Application, object) = delete!(app.ecs, convert(EntityID, object))

set_name(object, name::Symbol) = set_name(convert(EntityID, object), name)
function set_name(entity::EntityID, name::Symbol)
  is_release() && return nothing
  app.ecs.entity_names[entity] = name
  nothing
end

macro set_name(ex::Expr)
  Meta.isexpr(ex, :(=), 2) || error("Expected assignment of the form `lhs = rhs`, got $(repr(ex))")
  name = ex.args[1]::Symbol
  lhs = esc(name)
  ex = esc(ex)
  quote
    $ex
    set_name($lhs, $(QuoteNode(name)))
  end
end
macro set_name(exs::Symbol...)
  ret = Expr(:block)
  for ex in exs
    push!(ret.args, :(set_name($(esc(ex)), $(QuoteNode(ex)))))
  end
  ret
end
get_name(entity::EntityID) = isdefined(app, :ecs) ? get(app.ecs.entity_names, entity, nothing) : nothing
function get_entity(name::Symbol)
  # This function is slow. Use for tests or non-performance critical code only.
  for (entity, entity_name) in pairs(app.ecs.entity_names)
    entity_name === name && return entity
  end
end

# Deliberate type piracy.
function Base.show(io::IO, entity::EntityID)
  print(io, "EntityID(", reinterpret(UInt32, entity))
  name = get_name(entity)
  !isnothing(name) && print(io, ", ", repr(name))
  print(io, ')')
end

unset!(collection, indices...) = haskey(collection, indices...) ? delete!(collection, indices...) : nothing

get_location(entity) = app.ecs[entity, LOCATION_COMPONENT_ID]::LocationComponent
set_location(entity, location::LocationComponent) = app.ecs[entity, LOCATION_COMPONENT_ID] = location
get_geometry(entity) = app.ecs[entity, GEOMETRY_COMPONENT_ID]::GeometryComponent
set_geometry(entity, geometry::GeometryComponent) = app.ecs[entity, GEOMETRY_COMPONENT_ID] = geometry
get_z(entity) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID]::ZCoordinateComponent
set_z(entity, z::Real) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID] = convert(ZCoordinateComponent, z)
has_z(entity) = haskey(app.ecs, entity, ZCOORDINATE_COMPONENT_ID)
get_render(entity) = app.ecs[entity, RENDER_COMPONENT_ID]::RenderComponent
set_render(entity, render::RenderComponent) = app.ecs[entity, RENDER_COMPONENT_ID] = render
has_render(entity) = haskey(app.ecs, entity, RENDER_COMPONENT_ID)
unset_render(entity) = unset!(app.ecs, entity, RENDER_COMPONENT_ID)
get_input_handler(entity) = app.ecs[entity, INPUT_COMPONENT_ID]::InputComponent
set_input_handler(entity, input::InputComponent) = app.ecs[entity, INPUT_COMPONENT_ID] = input
unset_input_handler(entity) = unset!(app.ecs, entity, INPUT_COMPONENT_ID)
get_widget(entity) = app.ecs[entity, WIDGET_COMPONENT_ID]::WidgetComponent
get_widget(name::Symbol) = get_widget(get_entity(name)::EntityID)
set_widget(entity, widget::WidgetComponent) = app.ecs[entity, WIDGET_COMPONENT_ID] = widget
get_window(entity) = app.ecs[entity, WINDOW_COMPONENT_ID]::Window
set_window(entity, window::Window) = app.ecs[entity, WINDOW_COMPONENT_ID] = window

bind(f::Callable, key::KeyCombination) = bind(key => f)
bind(f::Callable, bindings::Pair...) = bind!(f, app.systems.event.ui.bindings, bindings...)
bind(bindings::Pair...) = bind!(app.systems.event.ui.bindings, bindings...)
bind(bindings::AbstractVector) = bind!(app.systems.event.ui.bindings, bindings)
unbind(token) = unbind!(app.systems.event.ui.bindings, token)

font_file(font_name) = joinpath(pkgdir(Anvil), "assets", "fonts", font_name * ".ttf")
get_font(name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), app.fonts, name)

add_constraint(constraint) = add_constraint!(app.systems.layout, constraint)
remove_constraints(entity::EntityID) = remove_constraints!(app.systems.layout, entity)
remove_constraints(entity) = remove_constraints!(app.systems.layout, convert(EntityID, entity))
put_behind(behind, of) = put_behind!(app.systems.drawing_order, behind, of)

"Run systems that are common to and essential for both rendering and event handling."
function run_systems()
  app.systems.layout(app.ecs)
  app.systems.drawing_order(app.ecs)
end

# Called by the application thread.
function frame_nodes(target::Resource)
  run_systems()
  app.systems.rendering(app.ecs, target)
end

function shutdown(app::Application)
  shutdown(app.systems)
  wait(shutdown_children())
end

Base.wait(app::Application) = monitor_children()

function exit(code::Int = 0)
  if current_task() === app.task
    _exit(code)
    true
  else
    execute(_exit, app.task, code)
    wait(app)
  end
end

function _exit(code::Int)
  shutdown(app)
  close(app.wm, app.window)
  @debug "Exiting application" * (!iszero(code) ? " (exit code: $(code))" : "")
  schedule_shutdown()
  code
end

function (app::Application)()
  shutdown_scheduled() && return
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems()
  app.systems.event(app.ecs)
end

function main(f; async = false)
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  GC.gc(true)
  reset_mpi_state()
  app.task = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    initialize(f)
    LoopExecution(0.001; shutdown = false)(app)()
  end
  async && return false
  wait(app)
end

synchronize() = fetch(execute(() -> (app(); true), app.task))
