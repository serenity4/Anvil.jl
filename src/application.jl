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

  ecs = new_database()
  app.ecs = ecs

  wm = XWindowManager()

  WINDOW_ENTITY_COUNTER.val = typemax(UInt32) - 100U
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
  ecs[window_id, WINDOW_COMPONENT_ID] = window
  set_location(window_id, zero(P2))
  set_geometry(window_id, window_geometry(window))

  app.entity_pool = EntityPool(; limit = WINDOW_ENTITY_COUNTER[] - 1)
  systems = Systems(
    LayoutSystem(ecs),
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
  start(systems.rendering.renderer; period = renderer_period)
  !isnothing(f) && f()

  map_window(window)
  nothing
end

window_geometry(window::Window) = physical_size(window)

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

macro set_name(ex, exs...)
  exs = (ex, exs...)
  exs, ex = exs[1:(end - 1)], exs[end]
  Meta.isexpr(ex, :(=), 2) || error("Expected assignment of the form `lhs = rhs`, got $(repr(ex))")
  name = ex.args[1]::Symbol
  lhs = esc(name)
  ex = esc(ex)
  if isempty(exs)
    quote
      $ex
      set_name($lhs, $(QuoteNode(name)))
    end
  else
    quote
      $ex
      namespace = join($(Expr(:tuple, esc.(exs)...)), '/')
      set_name($lhs, Symbol(namespace, '/', $(QuoteNode(name))))
    end
  end
end

macro set_name(ex::Symbol, exs::Symbol...)
  ex = (ex, exs...)
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
set_location(entity, location) = app.ecs[entity, LOCATION_COMPONENT_ID, LocationComponent] = location
unset_location(entity) = unset!(app.ecs, entity, LOCATION_COMPONENT_ID)
get_geometry(entity) = app.ecs[entity, GEOMETRY_COMPONENT_ID, GeometryComponent]
set_geometry(entity, geometry::GeometryComponent) = app.ecs[entity, GEOMETRY_COMPONENT_ID, GeometryComponent] = geometry
set_geometry(entity, (width, height)::Tuple) = set_geometry(entity, geometry(width, height))
unset_geometry(entity) = unset!(app.ecs, entity, GEOMETRY_COMPONENT_ID)
get_z(entity) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID, ZCoordinateComponent]
set_z(entity, z::Real) = app.ecs[entity, ZCOORDINATE_COMPONENT_ID, ZCoordinateComponent] = convert(ZCoordinateComponent, z)
unset_z(entity) = unset!(app.ecs, entity, ZCOORDINATE_COMPONENT_ID)
has_z(entity) = haskey(app.ecs, entity, ZCOORDINATE_COMPONENT_ID)
get_render(entity) = app.ecs[entity, RENDER_COMPONENT_ID, RenderComponent]
set_render(entity, render::RenderComponent) = app.ecs[entity, RENDER_COMPONENT_ID, RenderComponent] = render
set_render(entity, render::UserDefinedRender) = set_render(entity, RenderComponent(RENDER_OBJECT_USER_DEFINED, nothing, render; render.is_opaque))
set_render(f, entity; is_opaque::Bool = false) = set_render(entity, UserDefinedRender(f; is_opaque))
has_render(entity) = haskey(app.ecs, entity, RENDER_COMPONENT_ID)
unset_render(entity) = unset!(app.ecs, entity, RENDER_COMPONENT_ID)
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

Group(object, objects...) = Group(app.systems.layout.engine, object, objects...)
place(object, onto) = place!(app.systems.layout.engine, object, onto)
place_after(object, onto; kwargs...) = place_after!(app.systems.layout.engine, object, onto; kwargs...)
align(objects, direction, target) = align!(app.systems.layout.engine, objects, direction, target)
distribute(objects, direction, spacing, mode = SPACING_MODE_POINT) = distribute!(app.systems.layout.engine, objects, direction, spacing, mode)
pin(object, part, to; offset = 0.0) = pin!(app.systems.layout.engine, object, part, to; offset)
remove_layout_operations(entity) = remove_operations!(app.systems.layout.engine, entity)

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
  close(app.wm, app.window)
  wait(shutdown_owned_tasks())
  schedule_shutdown()
end

Base.wait(app::Application) = monitor_owned_tasks()

function exit(code::Int = 0)
  if current_task() === app.task
    _exit(code)
    true
  else
    execute(_exit, code)
    wait(app)
  end
end

function _exit(code::Int)
  @debug "Exiting application" * (!iszero(code) ? " (exit code: $(code))" : "")
  shutdown(app)
  code
end

function (app::Application)()
  shutdown_scheduled() && return false
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems()
  app.systems.event(app.ecs)
  true
end

function main(f; async = false, application_period = 0.000, renderer_period = 0.000, record_events = false)
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  GC.gc(true)
  CooperativeTasks.reset()
  app.task = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, disallow_task_migration = true)) do
    initialize(f; record_events, renderer_period)
    LoopExecution(application_period; shutdown = false)(app)()
    finalize(app)
  end
  async && return false
  wait(app)
end

save_events() = save_history(app.systems.event.queue.wm, app.systems.event.queue)
replay_events(events; time_factor = 1.0) = replay_history(app.systems.event.queue.wm, events; time_factor)

execute(f, args...; kwargs...) = fetch(CooperativeTasks.execute(f, app.task, args...; kwargs...))

macro execute(ex)
  :(execute(() -> $(esc(ex))))
end

synchronize() = execute(app)
