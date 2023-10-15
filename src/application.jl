struct GivreApplication
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  systems::Systems
  fonts::Dict{String, OpenTypeFont}
  function GivreApplication()
    wm = XWindowManager()
    window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
    systems = Systems(
      SynchronizationSystem(),
      DrawingOrderSystem(),
      RenderingSystem(Renderer(window)),
      EventSystem(EventQueue(wm), UserInterface(window)),
    )
    givre = new(wm, EntityPool(), ECSDatabase(), window, systems, Dict())
    initialize!(givre)
    start(systems.rendering.renderer, givre)
    map_window(window)
    givre
  end
end

function new_entity!(givre::GivreApplication)
  entity = new!(givre.entity_pool)
  givre.ecs[entity, ENTITY_COMPONENT_ID] = entity
  entity
end
get_location(givre::GivreApplication, entity) = givre.ecs[entity, LOCATION_COMPONENT_ID]::LocationComponent
set_location!(givre::GivreApplication, entity, location::LocationComponent) = givre.ecs[entity, LOCATION_COMPONENT_ID] = location
get_geometry(givre::GivreApplication, entity) = givre.ecs[entity, GEOMETRY_COMPONENT_ID]::GeometryComponent
set_geometry!(givre::GivreApplication, entity, geometry::GeometryComponent) = givre.ecs[entity, GEOMETRY_COMPONENT_ID] = geometry
get_render(givre::GivreApplication, entity) = givre.ecs[entity, RENDER_COMPONENT_ID]::RenderComponent
set_render!(givre::GivreApplication, entity, render::RenderComponent) = givre.ecs[entity, RENDER_COMPONENT_ID] = render

font_file(font_name) = joinpath(pkgdir(Givre), "assets", "fonts", font_name * ".ttf")
get_font(givre, name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), givre.fonts, name)

put_behind!(givre::GivreApplication, behind, of) = put_behind!(givre.systems.drawing_order, behind, of)

function start(renderer::Renderer, givre::GivreApplication)
  options = SpawnOptions(start_threadid = RENDERER_THREADID, allow_task_migration = false, execution_mode = LoopExecution(0.005))
  renderer.task = spawn(() -> render(givre, renderer), options)
end

function Lava.render(givre::GivreApplication, rdr::Renderer)
  next = acquire_next_image(rdr.frame_cycle)
  if next === Vk.ERROR_OUT_OF_DATE_KHR
    recreate!(rdr.frame_cycle)
    render(givre, rdr)
  else
    isa(next, Int) || error("Could not acquire an image from the swapchain (returned $next)")
    if collect(Int, extent(givre.window)) ≠ dimensions(rdr.color.attachment)
      rdr.color = color_attachment(rdr.device, givre.window)
    end
    (; color) = rdr
    fetched = tryfetch(execute(() -> frame_nodes(givre, color), task_owner()))
    iserror(fetched) && shutdown_scheduled() && return
    nodes = unwrap(fetched)::Vector{RenderNode}
    state = cycle!(image -> draw_and_prepare_for_presentation(rdr.device, nodes, color, image), rdr.frame_cycle, next)
    next!(rdr.frame_diagnostics)
    get(ENV, "GIVRE_LOG_FRAMECOUNT", "true") == "true" && print_framecount(rdr.frame_diagnostics)
    filter!(exec -> !wait(exec, 0), rdr.pending)
    push!(rdr.pending, state)
  end
end

# Called by the application thread.
function frame_nodes(givre::GivreApplication, target::Resource)
  givre.systems.synchronization(givre)
  givre.systems.drawing_order(givre.ecs)
  givre.systems.rendering(givre.ecs, target)
end

function shutdown(givre::GivreApplication)
  shutdown(givre.systems)
  wait(shutdown_children())
end
