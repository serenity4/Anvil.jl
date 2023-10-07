struct GivreApplication
  wm::WindowManager
  entity_pool::EntityPool
  ecs::ECSDatabase
  window::Window
  systems::Systems
  function GivreApplication()
    wm = XWindowManager()
    window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
    systems = Systems(
      EventSystem(EventQueue(wm), UserInterface(window)),
      RenderingSystem(Renderer(window)),
    )
    givre = new(wm, EntityPool(), ECSDatabase(), window, systems)
    initialize!(givre)
    start(systems.rendering.renderer, givre)
    map_window(window)
    givre
  end
end

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
  commands = givre.systems.rendering(givre.ecs, target)
  [RenderNode(commands)]
end

function shutdown(givre::GivreApplication)
  shutdown(givre.systems)
  wait(shutdown_children())
end

struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication, code::Int)
  @debug "Shutting down renderer"
  shutdown(givre)
  close(givre.wm, givre.window)
  @debug "Exiting application" * (!iszero(code) ? "(exit code: $(code))" : "")
  Exit(code)
end

function (givre::GivreApplication)()
  code = givre.systems.event(givre.ecs)
  if isa(code, Int)
    exit(givre, code)
    schedule_shutdown()
  end
end

function main()
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  application_thread = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    givre = GivreApplication()
    LoopExecution(0.000; shutdown = false)(givre)()
  end
  monitor_children()
end

function initialize!(givre::GivreApplication)
  layout = ECSLayoutEngine{Point2, Box{2,Float64}, Point2, GeometryComponent}(givre.ecs)

  texture = new!(givre.entity_pool)
  location = Point2(-0.4, -0.4)
  insert!(givre.ecs, texture, LOCATION_COMPONENT_ID, location)
  geometry = GeometryComponent(Box(Scaling(0.5, 0.5)), 1.0)
  insert!(givre.ecs, texture, GEOMETRY_COMPONENT_ID, geometry)
  visual = RenderComponent(RENDER_OBJECT_IMAGE, nothing, image_resource(givre.systems.rendering.renderer.device, rand(RGBA{Float32}, 512, 512)))
  insert!(givre.ecs, texture, RENDER_COMPONENT_ID, visual)
  on_input = let threshold = Ref((0.0, 0.0)), origin = Ref{Point2}()
    function (input::Input)
      if input.type === BUTTON_PRESSED
        threshold[] = (0.0, 0.0)
        origin[] = givre.ecs[texture, LOCATION_COMPONENT_ID]::Point2
      elseif input.type === DRAG
        target, event = input.dragged
        drag_amount = event.location .- input.source.event.location
        givre.ecs[texture, LOCATION_COMPONENT_ID] = origin[] .+ drag_amount
        if sqrt(sum((drag_amount .- threshold[]) .^ 2)) > 0.5
          threshold[] = drag_amount
          renderable = givre.ecs[texture, RENDER_COMPONENT_ID]::RenderComponent
          givre.ecs[texture, RENDER_COMPONENT_ID] = @set renderable.vertex_data = fill(Vec3(rand(3)), 4)
        end
      end
    end
  end
  insert!(givre.ecs, texture, INPUT_COMPONENT_ID, InputComponent(texture, on_input, BUTTON_PRESSED, DRAG))
  button_bg = new!(givre.entity_pool)
  insert!(givre.ecs, button_bg, LOCATION_COMPONENT_ID, Point2(0, 0))
  geometry = GeometryComponent(Box(Scaling(0.1, 0.05)), 2.0)
  insert!(givre.ecs, button_bg, GEOMETRY_COMPONENT_ID, geometry)
  compute_layout!(layout, [texture, button_bg], [attach(at(texture, FEATURE_LOCATION_CENTER), at(button_bg, Point(-1.0, 0.0)))])
  visual = RenderComponent(RENDER_OBJECT_RECTANGLE, repeat([Vec3(0.3, 0.2, 0.9)], 4), nothing)
  insert!(givre.ecs, button_bg, RENDER_COMPONENT_ID, visual)
end
