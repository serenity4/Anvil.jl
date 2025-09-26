mutable struct Application
  task::Task
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  windows::Dict{Window, EntityID}
  systems::Systems
  fonts::Dict{String, OpenTypeFont}
  textures::Dict{String, Texture}
  is_release::Bool
  show_shortcuts::Bool
  state::Any # user state
  Application() = new()
end

Base.broadcastable(app::Application) = (app,)

is_release() = app.is_release

function Base.show(io::IO, app::Application)
  print(io, Application, '(', isdefined(app, :task) ? app.task : "#undef", ", ", isdefined(app, :wm) ? app.wm : "#undef", ", ", isdefined(app, :ecs) ? app.ecs : "#undef", ", release: ", is_release(), ')')
end

function read_application_config()
  config_file = nothing
  for file in readdir(APPLICATION_DIRECTORY; join = false)
    if file == "Application.toml" || file == "JuliaApplication.toml"
      config_file = file
      break
    end
  end
  isnothing(config_file) && return Dict{String,Any}()
  open(TOML.parse, joinpath(APPLICATION_DIRECTORY, config_file))
end

function initialize(f::Optional{Function} = nothing; record_events::Bool = false, renderer_period = 0.000)
  options = read_application_config()
  app.is_release = get(ENV, "ANVIL_RELEASE", "false") == "true"

  window_options = get(Dict{String,Any}, options, "window")
  window_decoration_options = get(Dict{String,Any}, window_options, "decorations")

  wm = XWindowManager()
  initialize_ecs!(app)

  title = get(window_options, "title", "Anvil")
  window = Window(
    wm,
    title;
    icon_title = get(window_options, "icon_title", title),
    width = 1920, height = 1080,
    map = false,
    with_decorations = get(window_decoration_options, "use_default", true),
    border_width = get(window_decoration_options, "border_width", 1),
  )
  window_id = new_entity(EntityID(Entities.next!(WINDOW_ENTITY_COUNTER)))
  set_name(window_id, :window)
  app.ecs[window_id, WINDOW_COMPONENT_ID] = window
  set_location(window_id, zero(P2); invalidate = false)
  set_geometry(window_id, window_geometry(window); invalidate = false)

  systems = Systems(
    LayoutSystem(app.ecs),
    DrawingOrderSystem(),
    RenderingSystem(Renderer(window)),
    EventSystem(EventQueue(wm; record_history = record_events), UserInterface(window)),
  )
  app.wm = wm
  app.window = window
  app.windows = Dict(window => window_id)
  app.systems = systems
  app.fonts = Dict()
  app.textures = Dict()
  app.show_shortcuts = false

  bind(exit, key"ctrl+q")
  bind(key"alt_left") do
    app.show_shortcuts = !app.show_shortcuts
    set_contextual_shortcuts_visibility(app.show_shortcuts)
  end

  # Required because `WidgetComponent` is a Union, so `typeof(value)` at first insertion will be too narrow.
  app.ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()

  f === nothing && return

  start(systems.rendering.renderer; period = renderer_period)
  f()
  map_window(window)
  nothing
end

function initialize_ecs!(app::Application)
  app.ecs = new_database()
  WINDOW_ENTITY_COUNTER[] = 4000000000
  app.entity_pool = EntityPool(; limit = WINDOW_ENTITY_COUNTER[] - 1)
end

get_geometry(window::Window) = get_geometry(app.windows[window])
set_geometry(window::Window, geometry::Tuple) = set_geometry(app.windows[window], geometry)
window_geometry(window::Window) = physical_size(window)

is_left_click(event::Event) = event.mouse_event.button == BUTTON_LEFT
is_left_click(input::Input) = (input.type === BUTTON_PRESSED || input.type === BUTTON_RELEASED) && is_left_click(input.event)

WindowAbstractions.matches(kc::KeyCombination, input::Input) = (input.type === KEY_PRESSED || input.type === KEY_RELEASED) && matches(kc, input.event)

function new_entity(entity::EntityID = new!(app.entity_pool))
  app.ecs[entity, ENTITY_COMPONENT_ID] = entity
  entity
end
Base.delete!(app::Application, object) = delete!(app.ecs, convert(EntityID, object))

function get_entity(name::Symbol)
  # This function is slow. Use for tests or non-performance critical code only.
  for (entity, entity_name) in pairs(app.ecs.entity_names)
    entity_name === name && return entity
  end
end

macro get_widget(name::Symbol, names::Symbol...)
  ex = Expr(:block)
  for name in (name, names...)
    push!(ex.args, :($(esc(name)) = get_widget($(QuoteNode(name)))))
  end
  ex
end

# Deliberate type piracy.
function Base.show(io::IO, entity::EntityID)
  print(io, "EntityID(", reinterpret(UInt32, entity))
  name = get_name(entity)
  !isnothing(name) && print(io, ", ", repr(name))
  print(io, ')')
end

function unset!(collection, indices...)
  haskey(collection, indices...) || return false
  delete!(collection, indices...)
  true
end

geometry(width, height) = Box(P2(width/2, height/2))

get_location(entity) = app.ecs[entity, LOCATION_COMPONENT_ID, LocationComponent]
function set_location(entity, location; invalidate = true)
  app.ecs[entity, LOCATION_COMPONENT_ID, LocationComponent] = location
  !invalidate && return
  engine = get_layout_engine()
  isnothing(engine) && return
  Layout.invalidate!(engine, entity)
end
unset_location(entity) = unset!(app.ecs, entity, LOCATION_COMPONENT_ID)
get_geometry(entity) = app.ecs[entity, GEOMETRY_COMPONENT_ID, GeometryComponent]
get_bounding_box(entity) = get_geometry(entity).aabb
function set_geometry(entity, geometry::GeometryComponent; invalidate = true)
  app.ecs[entity, GEOMETRY_COMPONENT_ID, GeometryComponent] = geometry
  !invalidate && return
  engine = get_layout_engine()
  isnothing(engine) && return
  Layout.invalidate!(engine, entity)
end
set_geometry(entity, geometry; kwargs...) = set_geometry(entity, GeometryComponent(geometry); kwargs...)
set_geometry(entity, (width, height)::Tuple; kwargs...) = set_geometry(entity, geometry(width, height); kwargs...)
set_geometry(f, entity, aabb) = set_geometry(entity, GeometryComponent(f, aabb))
unset_geometry(entity) = unset!(app.ecs, entity, GEOMETRY_COMPONENT_ID)
get_z(entity) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID, ZCoordinateComponent]
set_z(entity, z::Real) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID, ZCoordinateComponent] = convert(ZCoordinateComponent, z)
unset_z(entity) = unset!(app.ecs, entity, ZCOORDINATE_COMPONENT_ID)
has_z(entity) = haskey(app.ecs, entity, ZCOORDINATE_COMPONENT_ID)
get_render(entity) = app.ecs[entity, RENDER_COMPONENT_ID, RenderComponent]
function set_render(entity, render::RenderComponent)
  entity = convert(EntityID, entity)
  app.ecs[entity, RENDER_COMPONENT_ID, RenderComponent] = render
  stage_for_render!(app.systems.rendering, entity)
end
set_render(entity, render::UserDefinedRender) = set_render(entity, RenderComponent(RENDER_OBJECT_USER_DEFINED, nothing, render; render.is_opaque))
set_render(f, entity; is_opaque::Bool = false) = set_render(entity, UserDefinedRender(f; is_opaque))
has_render(entity) = haskey(app.ecs, entity, RENDER_COMPONENT_ID)
function unset_render(entity)
  entity = convert(EntityID, entity)
  unset!(app.ecs, entity, RENDER_COMPONENT_ID)
  unstage_for_render!(app.systems.rendering, entity)
end
function update_render(entity)
  entity = convert(EntityID, entity)
  isdefined(app, :systems) && stage_for_render!(app.systems.rendering, entity)
end
get_widget(entity) = app.ecs[entity, WIDGET_COMPONENT_ID, WidgetComponent]
function get_widget(name::Symbol)
  entity = get_entity(name)
  isnothing(entity) && throw(ArgumentError("No widget exists with the name $(repr(name))"))
  get_widget(entity)
end
has_widget(entity) = haskey(app.ecs, entity, WIDGET_COMPONENT_ID)
set_widget(entity, widget::WidgetComponent) = app.ecs[entity, WIDGET_COMPONENT_ID, WidgetComponent] = widget
unset_widget(entity) = unset!(app.ecs, entity, WIDGET_COMPONENT_ID)
get_window(entity) = app.ecs[entity, WINDOW_COMPONENT_ID, Window]
set_window(entity, window::Window) = app.ecs[entity, WINDOW_COMPONENT_ID, Window] = window

add_callback(f, entity, args...; kwargs...) = add_callback(entity, InputCallback(f, args...); kwargs...)

overlay(args...; kwargs...) = overlay!(app.systems.event.ui, args...; kwargs...)
unoverlay(args...; kwargs...) = unoverlay!(app.systems.event.ui, args...; kwargs...)

add_callback(entity, callback::InputCallback; kwargs...) = overlay(entity, callback; options = OverlayOptions(; kwargs...))
remove_callback(entity, callback::InputCallback) = unoverlay(entity, callback)

AbstractGUI.InputArea(widget::Widget) = InputArea(app, widget)
AbstractGUI.InputArea(app::Application, entity) = InputArea(app.systems.event.ui, entity)

bind(f::Callable, key::KeyCombination) = bind(key => f)
bind(f::Callable, bindings::Pair...) = bind!(f, app.systems.event.ui.bindings, bindings...)
bind(bindings::Pair...) = bind!(app.systems.event.ui.bindings, bindings...)
bind(bindings::AbstractVector) = bind!(app.systems.event.ui.bindings, bindings)
unbind(token) = unbind!(app.systems.event.ui.bindings, token)

put_behind(behind, of) = put_behind!(app.systems.drawing_order, behind, of)
put_in_front(in_front, of) = put_in_front!(app.systems.drawing_order, in_front, of)

get_layout_engine() = isdefined(app, :systems) ? app.systems.layout.engine : nothing
group(object, objects...; origin = nothing) = Group(get_layout_engine(), object, objects...; origin)
place(object, onto) = place!(get_layout_engine(), object, onto)
place_after(object, onto; kwargs...) = place_after!(get_layout_engine(), object, onto; kwargs...)
align(objects, direction) = align!(get_layout_engine(), objects, direction)
align(target::Function, objects, direction) = align!(target, get_layout_engine(), objects, direction)
align(objects, onto, direction) = align!(get_layout_engine(), objects, onto, direction)
align(target::Function, objects, onto, direction) = align!(get_layout_engine(), objects, direction, target)
distribute(objects, onto, direction; mode = SPACING_MODE_POINT, spacing = Layout.average) = distribute!(get_layout_engine(), objects, onto, direction; mode, spacing)
distribute(objects, direction; mode = SPACING_MODE_POINT, spacing = Layout.average) = distribute!(get_layout_engine(), objects, direction; mode, spacing)
pin(object, part, to; offset = 0.0) = pin!(get_layout_engine(), object, part, to; offset)
remove_layout_operations(entity) = remove_operations!(get_layout_engine(), entity)
execute_now(operation::Operation) = execute_now!(get_layout_engine(), operation)

"Run systems that are common to and essential for both rendering and event handling."
function run_systems()
  app.systems.layout(app.ecs)
  app.systems.drawing_order(app.ecs)
end

function exit(code::Int = 0)
  if current_task() === app.task
    exit_application(code)
    true
  else
    execute(exit_application, code)
    wait(app)
  end
end

function exit_application(code::Int)
  @debug "Exiting application" * (!iszero(code) ? " (exit code: $(code))" : "")
  shutdown(app)
  code
end

function shutdown(app::Application)
  shutdown_systems(app)
  wait(shutdown_owned_tasks())
  schedule_shutdown()
end

function shutdown_systems(app::Application)
  shutdown(app.systems)
  close_windows(app)
end

close_windows(app::Application) = close(app.wm, app.window)

Base.wait(app::Application) = monitor_owned_tasks()

function run_application_cycle(app::Application)
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems()
  queue = app.systems.event.queue
  while refill_event_queue!(queue)
    event = popfirst!(queue)
    while event.type === WINDOW_EXPOSED # ignore these events
      isempty(queue) && return true
      event = popfirst!(queue)
    end
    shutdown_scheduled() && return false
    app.systems.event(app.ecs, event)
    run_systems()
  end
  return true
end

function refill_event_queue!(queue::EventQueue)
  isempty(queue) && collect_events!(queue)
  !isempty(queue) && return true
  false
end

function main(f; async = false, application_period = 0.002, renderer_period = 0.005, record_events = false)
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  GC.gc(true)
  CooperativeTasks.reset()
  app.task = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, disallow_task_migration = true)) do
    initialize(f; record_events, renderer_period)
    cycle = () -> run_application_cycle(app)
    loop = LoopExecution(application_period; shutdown = false)(cycle)
    try
      loop()
    finally
      if shutdown_scheduled()
        close_windows(app)
      else
        shutdown_systems(app)
      end
    end
  end
  async && return false
  wait(app)
end

save_events() = save_history(app.systems.event.queue.wm, app.systems.event.queue)
replay_events(events; time_factor = 1.0) = replay_history(app.systems.event.queue.wm, events; time_factor, stop = () -> istaskdone(app.task))

execute(f, args...; kwargs...) = fetch(CooperativeTasks.execute(f, app.task, args...; kwargs...))

macro execute(ex)
  :(execute(() -> $(esc(ex))))
end

synchronize() = execute(app)
