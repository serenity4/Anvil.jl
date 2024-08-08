mutable struct Application
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  systems::Systems
  fonts::Dict{String, OpenTypeFont}
  Application() = new()
end

function initialize()
  wm = XWindowManager()
  window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
  ecs = ECSDatabase()
  systems = Systems(
    SynchronizationSystem(),
    LayoutSystem(ecs),
    DrawingOrderSystem(),
    RenderingSystem(Renderer(window)),
    EventSystem(EventQueue(wm), UserInterface(window)),
  )
  app.wm = wm
  app.entity_pool = EntityPool()
  app.ecs = ecs
  app.window = window
  app.systems = systems
  app.fonts = Dict()
  initialize_components()
  start(systems.rendering.renderer)
  map_window(window)
  nothing
end

function new_entity!()
  entity = new!(app.entity_pool)
  app.ecs[entity, ENTITY_COMPONENT_ID] = entity
  entity
end
Base.delete!(app::Application, object) = delete!(app.ecs, convert(EntityID, object))

get_location(entity) = app.ecs[entity, LOCATION_COMPONENT_ID]::LocationComponent
set_location(entity, location::LocationComponent) = app.ecs[entity, LOCATION_COMPONENT_ID] = location
get_geometry(entity) = app.ecs[entity, GEOMETRY_COMPONENT_ID]::GeometryComponent
set_geometry(entity, geometry::GeometryComponent) = app.ecs[entity, GEOMETRY_COMPONENT_ID] = geometry
get_render(entity) = app.ecs[entity, RENDER_COMPONENT_ID]::RenderComponent
set_render(entity, render::RenderComponent) = app.ecs[entity, RENDER_COMPONENT_ID] = render

font_file(font_name) = joinpath(pkgdir(Givre), "assets", "fonts", font_name * ".ttf")
get_font(name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), app.fonts, name)

add_constraint(constraint) = add_constraint!(app.systems.layout, constraint)
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
