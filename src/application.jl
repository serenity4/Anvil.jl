mutable struct Application
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  windows::Dict{Window, EntityID}
  systems::Systems
  fonts::Dict{String, OpenTypeFont}
  is_release::Bool
  Application() = new()
end

is_release() = app.is_release

function initialize()
  app.is_release = get(ENV, "GIVRE_RELEASE", "false") == "true"

  ecs = new_database()
  app.ecs = ecs

  wm = XWindowManager()

  WINDOW_ENTITY_COUNTER.val = typemax(UInt32) - 100U
  window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
  window_id = new_entity(EntityID(Entities.next!(WINDOW_ENTITY_COUNTER)))
  set_location(window_id, zero(P2))
  set_geometry(window_id, Box(Point2(screen_semidiagonal(aspect_ratio(extent(window))))))

  systems = Systems(
    SynchronizationSystem(),
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

  initialize_components()
  start(systems.rendering.renderer)
  map_window(window)
  nothing
end

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

macro set_name(exs::Symbol...)
  ret = Expr(:block)
  for ex in exs
    push!(ret.args, :(set_name($(esc(ex)), $(QuoteNode(ex)))))
  end
  ret
end
get_name(entity::EntityID) = get(app.ecs.entity_names, entity, nothing)

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
set_widget(entity, widget::WidgetComponent) = app.ecs[entity, WIDGET_COMPONENT_ID] = widget
get_window(entity) = app.ecs[entity, WINDOW_COMPONENT_ID]::Window
set_window(entity, window::Window) = app.ecs[entity, WINDOW_COMPONENT_ID] = window

font_file(font_name) = joinpath(pkgdir(Givre), "assets", "fonts", font_name * ".ttf")
get_font(name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), app.fonts, name)

add_constraint(constraint) = add_constraint!(app.systems.layout, constraint)
remove_constraints(entity::EntityID) = remove_constraints!(app.systems.layout, entity)
remove_constraints(entity) = remove_constraints!(app.systems.layout, convert(EntityID, entity))
put_behind(behind, of) = put_behind!(app.systems.drawing_order, behind, of)

function start(renderer::Renderer)
  options = SpawnOptions(start_threadid = RENDERER_THREADID, allow_task_migration = false, execution_mode = LoopExecution(0.005))
  renderer.task = spawn(() -> render(app, renderer), options)
end

function Lava.render(app::Application, rdr::Renderer)
  state = cycle!(rdr.frame_cycle) do image
    if collect(Int, extent(app.window)) ≠ dimensions(rdr.color.attachment)
      rdr.color = color_attachment(rdr.device, app.window)
    end
    (; color) = rdr
    ret = tryfetch(execute(() -> frame_nodes(color), task_owner()))
    iserror(ret) && shutdown_scheduled() && return draw_and_prepare_for_presentation(rdr.device, RenderNode[], color, image)
    nodes = unwrap(ret)::Vector{RenderNode}
    draw_and_prepare_for_presentation(rdr.device, nodes, color, image)
  end
  !isnothing(state) && push!(rdr.pending, state)
  filter!(exec -> !wait(exec, 0), rdr.pending)
  next!(rdr.frame_diagnostics)
  get(ENV, "GIVRE_LOG_FRAMECOUNT", "true") == "true" && print_framecount(rdr.frame_diagnostics)
  nothing
end

"Run systems that are common to and essential for both rendering and event handling."
function run_systems()
  app.systems.synchronization(app.ecs)
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
