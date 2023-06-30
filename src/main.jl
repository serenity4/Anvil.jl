const RENDER_COMPONENT_ID = ComponentID(1)
const INPUT_COMPONENT_ID = ComponentID(2)
const LOCATION_COMPONENT_ID = ComponentID(3)

struct UserInterface
  overlay::UIOverlay
  entities::Dict{InputArea, EntityID}
  areas::Dict{EntityID, InputArea}
  window::Window
end
UserInterface(window::Window) = UserInterface(UIOverlay{Window}(), Dict(), Dict(), window)

function Base.insert!(ui::UserInterface, entity::EntityID, area::InputArea)
  ui.entities[area] = entity
  ui.areas[entity] = area
  overlay!(ui.overlay, ui.window, area)
end

function Base.delete!(ui::UserInterface, entity::EntityID)
  area = ui.areas[entity]
  delete!(ui.entities, area)
  delete!(ui.areas, entity)
  unoverlay!(ui.overlay, area)
end

function Base.setindex!(ui::UserInterface, area::InputArea, entity::EntityID)
  delete!(ui, entity)
  insert!(ui, entity, area)
end

struct GivreApplication
  wm::WindowManager
  queue::EventQueue{WindowManager}
  entity_pool::EntityPool
  ecs::ECSDatabase
  ui::UserInterface
  rdr::Renderer
  # Vulkan devices are freely usable from multiple threads.
  # Only specific functions require external synchronization, hopefully we don't need those outside of the renderer.
  device::Device
  window::Window
  function GivreApplication()
    wm = XWindowManager()
    window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
    rdr = Renderer(window)
    givre = new(wm, EventQueue(wm), EntityPool(), ECSDatabase(), UserInterface(window), rdr, rdr.device, window)
    initialize!(givre)
    start_renderer(givre)
    map_window(window)
    givre
  end
end

function start_renderer(givre::GivreApplication)
  (; rdr) = givre
  options = SpawnOptions(start_threadid = RENDERER_THREADID, allow_task_migration = false, execution_mode = LoopExecution(0.005))
  rdr.task = spawn(() -> render(givre, rdr), options)
end

# Only call that from the application thread.
shutdown_renderer(givre::GivreApplication) = wait(shutdown_children())

struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication)
  @debug "Shutting down renderer"
  shutdown_renderer(givre)
  wait(givre.device)
  close(givre.wm, givre.window)
  @debug "Exiting application"
  Exit(0)
end

function (givre::GivreApplication)(input::Input)
  @show input.type
  entity = givre.ui.entities[input.area]
  f = givre.ecs[entity, INPUT_COMPONENT_ID]
  f()
  nothing
end

function (givre::GivreApplication)(event::Event)
  if event.type == KEY_PRESSED
    matches(key"ctrl+q", event) && return exit(givre)
  end
  ar = aspect_ratio(extent(event.win))
  input = react_to_event(givre.ui.overlay, @set event.location = render_coordinates(event.location, ar))
  isnothing(input) && return
  givre(input)
end

function (givre::GivreApplication)()
  isempty(givre.queue) && collect_events!(givre.queue)
  isempty(givre.queue) && return
  event = popfirst!(givre.queue)
  ret = givre(event)
  isa(ret, Exit) && schedule_shutdown()
end

function main()
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  application_thread = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    givre = GivreApplication()
    LoopExecution(0.002; shutdown = false)(givre)()
  end
  monitor_children()
end

function initialize!(givre::GivreApplication)
  rect = new!(givre.entity_pool)
  rect_geometry = Rectangle((0.5, 0.5), (-0.4, -0.4), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
  location = Float64.(rect_geometry.location)
  insert!(givre.ecs, rect, LOCATION_COMPONENT_ID, location)
  rect_visual = RenderObject(RENDER_OBJECT_RECTANGLE, Primitive(rect_geometry))
  insert!(givre.ecs, rect, RENDER_COMPONENT_ID, rect_visual)
  input_geometry = Translated(rect_geometry.geometry, Translation(location))
  rect_input = InputArea(input_geometry, 1.0, in(input_geometry), NO_EVENT, DROP)
  insert!(givre.ui, rect, rect_input)
  on_input = function (input::Input)
    if input.type === DRAG
      target, event = input.dragged
      givre.ecs[rect, LOCATION_COMPONENT_ID] = event.location
      # XXX: How to propagate that to the input area geometry in a better way?
      updated_geometry = @set input_geometry = Translated(rect_geometry.geometry, Translation(event.location))
      rect_input.aabb = boundingelement(updated_geometry)
      rect_input.contains = in(rect_input.aabb)
    end
  end
  insert!(givre.ecs, rect, INPUT_COMPONENT_ID, on_input)
end
