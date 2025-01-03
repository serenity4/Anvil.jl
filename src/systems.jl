abstract type System end

shutdown(::System) = nothing

struct LayoutSystem{E<:LayoutEngine} <: System
  engine::E
end
function LayoutSystem(ecs::ECSDatabase)
  storage = ECSLayoutStorage{P2, Box{2,Float64}, LocationComponent, GeometryComponent}(ecs)
  engine = LayoutEngine(storage)
  LayoutSystem{typeof(engine)}(engine)
end

function (layout::LayoutSystem)(ecs::ECSDatabase)
  compute_layout!(layout.engine)
end

"System determining which objects are going to be in front of other objects when displayed on the screen."
struct DrawingOrderSystem <: System
  """
  Map an entity to an object it should be behind.

  Very basic at the moment - objects can only be specified as behind *a single other object*. Furthermore, if two objects are behind another,
  they will be ordered with respect to one another in specification order: `A` and `B` behind `C` implies that `A` is behind `B` iff
  `A` was specified as behind `C` *before* `B`.
  """
  behind::Dictionary{EntityID, EntityID}
end
DrawingOrderSystem() = DrawingOrderSystem(Dictionary())

put_behind!(drawing_order::DrawingOrderSystem, behind, of) = set!(drawing_order.behind, convert(EntityID, behind), of)

function drawing_order_graph(behind)
  g = SimpleDiGraph{Int64}()
  node_indices = Dict{EntityID, Int64}()
  entities = Dict{Int64, EntityID}()
  for (id, in_front) in pairs(behind)
    v = get!(node_indices, in_front) do
      Graphs.add_vertex!(g)
      Graphs.nv(g)
    end
    entities[v] = in_front
    w = get!(node_indices, id) do
      Graphs.add_vertex!(g)
      Graphs.nv(g)
    end
    entities[w] = id
    Graphs.add_edge!(g, v, w)
  end
  !is_cyclic(g) || error("Cyclic dependencies are not supported.")
  g, entities
end

function ((; behind)::DrawingOrderSystem)(ecs::ECSDatabase)
  for id in components(ecs, ENTITY_COMPONENT_ID, EntityID)
    # Do not process objects whose z-coordinate will depend on other objects first.
    haskey(behind, id) && continue
    has_z(id) && isinf(get_z(id)) && continue
    n = reinterpret(UInt32, id)
    z = Float32(n)
    set_z(id, z)
  end
  g, entities = drawing_order_graph(behind)
  for v in topological_sort(g)
    in_front = entities[v]
    z_front = get_z(in_front)
    prev = z_front
    for w in outneighbors(g, v)
      id = entities[w]
      n = reinterpret(UInt32, id)
      has_z(in_front) || error("Object $id has been placed behind object $in_front, but $in_front has no assigned Z component.")
      z_behind = prevfloat(prev, 100)
      set_z(id, z_behind)
      prev = z_behind
    end
  end
end

struct RenderingSystem <: System
  renderer::Renderer
end

function shutdown(system::RenderingSystem)
  wait(CooperativeTasks.shutdown(system.renderer.task))
  wait(system.renderer.device)
end

function (rendering::RenderingSystem)(ecs::ECSDatabase, target::Resource)
  nodes = RenderNode[]
  depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, dimensions(target.attachment))
  color_clear = [ClearValue((BACKGROUND_COLOR.r, BACKGROUND_COLOR.g, BACKGROUND_COLOR.b, 1f0))]
  camera = camera_metric_to_viewport(target, rendering.renderer.frame_cycle.swapchain.surface.target)
  parameters = ShaderParameters(target; depth, color_clear, camera)
  @reset parameters.depth_clear = ClearValue(1f0)
  render_opaque_objects!(nodes, rendering, ecs, parameters)
  @reset parameters.color_clear[1] = nothing
  @reset parameters.render_state.enable_depth_write = false
  render_transparent_objects!(nodes, rendering, ecs, parameters)
  nodes
end

function camera_metric_to_viewport(target::Resource, window::Window)
  viewport_dimensions = 2 .* screen_semidiagonal(aspect_ratio(target))
  window_size = physical_size(window)
  metric_to_viewport = viewport_dimensions ./ window_size
  camera = Camera(; extent = 2 ./ metric_to_viewport)
end

"Retrieve the physical size of a window, in centimeters."
function physical_size(window::Window)
  (; screen) = window
  screen_size = (screen.width_in_millimeters, screen.height_in_millimeters)
  screen_dimensions = (screen.width_in_pixels, screen.height_in_pixels)
  window_dimensions = extent(window)
  all(iszero, window_dimensions) && return (0.0, 0.0)
  physical_scale = screen_size ./ screen_dimensions
  physical_scale = physical_scale ./ 10 # mm to cm
  window_dimensions .* physical_scale
end

function render_opaque_objects!(nodes, (; renderer)::RenderingSystem, ecs::ECSDatabase, parameters::ShaderParameters)
  commands = Command[]
  for (location, geometry, object, z) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{P2,GeometryComponent,RenderComponent,ZCoordinateComponent})
    object.is_opaque || continue
    location = Point3f(location..., -1/z)
    add_commands!(commands, renderer.program_cache, object, location, geometry, parameters)
  end
  !isempty(commands) && push!(nodes, RenderNode(commands))
end

function render_transparent_objects!(nodes, (; renderer)::RenderingSystem, ecs::ECSDatabase, parameters::ShaderParameters)
  pass = TransparencyPass()
  for (location, geometry, object, z) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{P2,GeometryComponent,RenderComponent,ZCoordinateComponent})
    object.is_opaque && continue
    location = Point3f(location..., -1/z)
    add_commands!(pass, renderer.program_cache, object, location, geometry, parameters)
  end
  !isempty(pass.pass_1) && push!(nodes, RenderNode(pass.pass_1))
  !isempty(pass.pass_2) && push!(nodes, RenderNode(pass.pass_2))
end

struct UserInterface
  overlay::UIOverlay
  entities::Dictionary{InputArea, EntityID}
  areas::Dictionary{EntityID, InputArea}
  window::Window
  root::EntityID
  bindings::KeyBindings
end

function UserInterface(window::Window)
  overlay = UIOverlay{Window}()
  bindings = KeyBindings()
  root = new_entity()
  set_name(root, :root)
  ui = UserInterface(overlay, Dictionary(), Dictionary(), window, root, bindings)
  set_location(root, (0, 0))
  set_geometry(root, (Inf, Inf))
  set_z(root, Inf)
  overlay!(ui, root, KEY_PRESSED) do input
    bound = execute_binding(bindings, input.event.key_event)
    !bound && propagate!(input)
  end
  ui
end

function InputArea(ui::UserInterface, entity)
  entity = convert(EntityID, entity)
  ui.areas[entity]
end

retrieve_input_area!(ui::UserInterface, entity) = retrieve_input_area!(ui, convert(EntityID, entity))

function retrieve_input_area!(ui::UserInterface, entity::EntityID)
  get!(ui.areas, entity) do
    InputArea(geometry(0, 0), 0, () -> false)
  end
end

function overlay!(f, ui::UserInterface, entity, args...; options = OverlayOptions())
  entity = convert(EntityID, entity)
  overlay!(ui, entity, InputCallback(f, args...); options)
end

function overlay!(ui::UserInterface, entity, callback::InputCallback; options = OverlayOptions())
  entity = convert(EntityID, entity)
  area = retrieve_input_area!(ui, entity)
  overlay!(ui.overlay, ui.window, area, callback; options)
end

function unoverlay!(ui::UserInterface, entity)
  entity = convert(EntityID, entity)
  area = get(ui.areas, entity, nothing)
  isnothing(area) && return false
  unoverlay!(ui.overlay, ui.window, area)
  delete!(ui.areas, entity)
end

function unoverlay!(ui::UserInterface, entity, callback::InputCallback)
  entity = convert(EntityID, entity)
  area = get(ui.areas, entity, nothing)
  isnothing(area) && return false
  remaining = unoverlay!(ui.overlay, ui.window, area, callback)
  !is_area_active(ui.overlay, ui.window, area) || return
  delete!(ui.areas, entity)
end

function Base.insert!(ui::UserInterface, entity::EntityID, area::InputArea)
  insert!(ui.entities, area, entity)
  insert!(ui.areas, entity, area)
end

function Base.delete!(ui::UserInterface, entity::EntityID)
  area = ui.areas[entity]
  delete!(ui.entities, area)
  delete!(ui.areas, entity)
end

function Base.setindex!(ui::UserInterface, area::InputArea, entity::EntityID)
  delete!(ui, entity)
  insert!(ui, entity, area)
end

struct EventSystem <: System
  queue::EventQueue
  ui::UserInterface
end

function (system::EventSystem)(ecs::ECSDatabase)
  isempty(system.queue) && collect_events!(system.queue)
  while !isempty(system.queue)
    event = popfirst!(system.queue)
    code = system(ecs, to_metric_coordinate_system(event))
    isa(code, Int) && return code
  end
end

function to_metric_coordinate_system(event::Event)
  @set event.location = to_metric_coordinate_system(event.location, event.window)
end

function to_metric_coordinate_system((x, y), window::Window)
  # Invert the Y axis (Y descending from top-left to Y ascending from bottom-left).
  y = 1 - y

  xmax, ymax = physical_size(window)
  # Put the origin at the center of the window.
  remap.((x, y), 0, 1, (-xmax/2, -ymax/2), (xmax/2, ymax/2))
end
function to_window_coordinate_system((x, y), window::Window)
  xmax, ymax = physical_size(window)
  # Put the origin at the bottom-left corner of the window.
  x, y = remap.((x, y), (-xmax/2, -ymax/2), (xmax/2, ymax/2), 0, 1)

  # Invert the Y axis (Y ascending from bottom-left to Y descending from top-left).
  y = 1 - y

  (x, y)
end

"Convert a point in pixels to a point in centimeters."
function pixel_to_metric(point::Point{2}, screen = app.window.screen)
  screen_size = (screen.width_in_millimeters, screen.height_in_millimeters)
  screen_dimensions = (screen.width_in_pixels, screen.height_in_pixels)
  physical_scale = screen_size ./ screen_dimensions
  physical_scale = physical_scale ./ 10 # mm to cm
  point .* physical_scale
end
pixel_to_metric(box::Box{2}) = Box(pixel_to_metric(box.min), pixel_to_metric(box.max))

function (system::EventSystem)(ecs::ECSDatabase, event::Event)
  event.type == WINDOW_RESIZED && (set_geometry(app.windows[event.window], window_geometry(event.window)))
  update_overlays!(system, ecs)
  consume!(system.ui.overlay, event)
  event.type == WINDOW_CLOSED && exit()
end

function update_overlays!(system::EventSystem, ecs::ECSDatabase)
  for (entity, area) in pairs(system.ui.areas)
    location = get_location(entity)
    geometry = get_geometry(entity)
    z = get_z(entity)
    area.aabb = geometry
    area.z = z
    area.contains = x -> in(x .- location, geometry)
  end
end

struct Systems
  layout::LayoutSystem
  drawing_order::DrawingOrderSystem
  rendering::RenderingSystem
  event::EventSystem
end

# Only call that from the application thread.
function shutdown(systems::Systems)
  shutdown(systems.event)
  @debug "Shutting down the rendering system"
  shutdown(systems.rendering)
  shutdown(systems.drawing_order)
  shutdown(systems.layout)
end
