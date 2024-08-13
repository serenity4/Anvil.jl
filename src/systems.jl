abstract type System end

shutdown(::System) = nothing

struct SynchronizationSystem <: System end

function (::SynchronizationSystem)(ecs::ECSDatabase)
  for widget in components(ecs, WIDGET_COMPONENT_ID, WidgetComponent)
    widget.modified || continue
    widget.disabled && continue
    synchronize!(widget)
  end
end

struct LayoutSystem <: System
  engine::ECSLayoutEngine{P2, Box{2,Float64}, LocationComponent, GeometryComponent}
  constraints::Vector{Constraint{EntityID}}
end
LayoutSystem(ecs::ECSDatabase) = LayoutSystem(ECSLayoutEngine{P2, Box{2,Float64}, LocationComponent, GeometryComponent}(ecs), [])

add_constraint!(layout::LayoutSystem, constraint::Constraint{EntityID}) = push!(layout.constraints, constraint)
function remove_constraints!(layout::LayoutSystem, entity::EntityID)
  to_delete = Int[]
  for (i, constraint) in enumerate(layout.constraints)
    if !isnothing(constraint.by) && constraint.by[] == entity
      push!(to_delete, i)
      continue
    end
    (; on) = constraint
    isa(on, PositionalFeature{EntityID}) && (on = [on])
    any(target -> target[] == entity, on) && push!(to_delete, i)
  end
  isempty(to_delete) && return false
  splice!(layout.constraints, to_delete)
  true
end

function ((; engine, constraints)::LayoutSystem)(ecs::ECSDatabase)
  compute_layout!(engine, constraints)
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
  wait(ConcurrencyGraph.shutdown(system.renderer.task))
  wait(system.renderer.device)
end

function (rendering::RenderingSystem)(ecs::ECSDatabase, target::Resource)
  nodes = RenderNode[]
  depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, dimensions(target.attachment))
  color_clear = [ClearValue((BACKGROUND_COLOR.r, BACKGROUND_COLOR.g, BACKGROUND_COLOR.b, 1.0))]
  parameters = ShaderParameters(target; depth, color_clear)
  push!(nodes, render_opaque_objects(rendering, ecs, @set parameters.depth_clear = ClearValue(1f0)))
  push!(nodes, render_transparent_objects(rendering, ecs, @set parameters.color_clear[1] = nothing))
  nodes
end

function render_opaque_objects((; renderer)::RenderingSystem, ecs::ECSDatabase, parameters::ShaderParameters)
  (; program_cache) = renderer
  commands = Command[]

  for (location, geometry, object, z) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{P2,GeometryComponent,RenderComponent,ZCoordinateComponent})
    location = Point3f(location..., -1/z)
    command = @match object.type begin
      &RENDER_OBJECT_RECTANGLE => begin
        rect = ShaderLibrary.Rectangle(geometry, object.vertex_data, nothing)
        gradient = object.primitive_data::Gradient
        Command(program_cache, gradient, parameters, Primitive(rect, location))
      end
      &RENDER_OBJECT_IMAGE => begin
        # Assume that images are opaque for now.
        rect = ShaderLibrary.Rectangle(geometry, FULL_IMAGE_UV, nothing)
        sprite = object.primitive_data::Sprite
        Command(program_cache, sprite, parameters, Primitive(rect, location))
      end
      _ => continue
    end
    push!(commands, command)
  end
  RenderNode(commands)
end

function render_transparent_objects((; renderer)::RenderingSystem, ecs::ECSDatabase, parameters::ShaderParameters)
  (; program_cache) = renderer
  commands = Command[]

  for (location, geometry, object, z) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{P2,GeometryComponent,RenderComponent,ZCoordinateComponent})
    location = Point3f(location..., -1/z)
    command = @match object.type begin
      &RENDER_OBJECT_TEXT => begin
        text = object.primitive_data::ShaderLibrary.Text
        renderables(program_cache, text, parameters, location)
      end
      _ => continue
    end
    push!(commands, command)
  end
  RenderNode(commands)
end

const FULL_IMAGE_UV = Vec2[(0, 0), (0, 1), (1, 0), (1, 1)]

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
    code = system(ecs, to_rendering_coordinate_system(event))
    isa(code, Int) && return code
  end
end

function to_rendering_coordinate_system(event::Event)
  ar = aspect_ratio(extent(event.win))
  xmax, ymax = (max(1.0, ar), max(1.0, 1/ar))
  x, y = event.location
  y = 1 - y # make bottom-left at (0, 0) and top-right at (1, 1)
  location = remap.((x, y), 0, 1, (-xmax, -ymax), (xmax, ymax))
  @set event.location = location
end

function (system::EventSystem)(ecs::ECSDatabase, event::Event)
  event.type == KEY_PRESSED && matches(key"ctrl+q", event) && return 0
  update_overlays!(system, ecs)
  input = input_from_event(system.ui.overlay, event)
  isnothing(input) && return
  consume!(input)
end

function update_overlays!(system::EventSystem, ecs::ECSDatabase)
  updated = Set{InputArea}()
  for (entity, location, geometry, input, z) in components(ecs, (ENTITY_COMPONENT_ID, LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, INPUT_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{EntityID, P2, GeometryComponent, InputComponent, ZCoordinateComponent})
    zindex = Float64(z)
    area = get(system.ui.areas, entity, nothing)
    contains = x -> in(x .- location, geometry)
    if isnothing(area)
      area = InputArea(input.on_input, geometry, zindex, contains, input.events, input.actions)
      insert!(system.ui, entity, area)
      push!(updated, area)
    else
      area.aabb = geometry
      area.z = zindex
      area.contains = contains
      push!(updated, area)
    end
  end
  set!(system.ui.overlay.areas, system.ui.window, updated)
end

struct Systems
  synchronization::SynchronizationSystem
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
  shutdown(systems.synchronization)
end
