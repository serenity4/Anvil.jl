abstract type System end

shutdown(::System) = nothing

struct SynchronizationSystem <: System end

function (::SynchronizationSystem)(givre #=::GivreApplication=#)
  for widget in components(givre.ecs, WIDGET_COMPONENT_ID, WidgetComponent)
    widget.modified || continue
    synchronize!(givre, widget)
    widget.modified = false
  end
end

"System determining which objects are going to be in front of other objects when displayed on the screen."
struct DrawingOrderSystem <: System
  """
  Map an entity to an object it should be behind.

  Very basic at the moment - objects can only be specified as behind *a single other object*. Furthermore, if two objects are behind another,
  they will be ordered with respect to one another by their entity ID: `A` and `B` behind `C` implies that `A` is behind `B` iff
  `A` would naturally be behind `B` (i.e. as determined by their entity ID).
  """
  behind::Dict{EntityID, EntityID}
end
DrawingOrderSystem() = DrawingOrderSystem(Dict())

put_behind!(drawing_order::DrawingOrderSystem, behind, of) = drawing_order.behind[convert(EntityID, behind)] = of

function ((; behind)::DrawingOrderSystem)(ecs::ECSDatabase)
  for id in components(ecs, ENTITY_COMPONENT_ID, EntityID)
    # Only process entities which are to be rendered.
    haskey(ecs, id, RENDER_COMPONENT_ID) || continue
    # First, do not process the objects if the value of their z-coordinate will depend on other objects first.
    haskey(behind, id) && continue
    n = reinterpret(UInt32, id)
    z = Float32(n)
    ecs[id, ZCOORDINATE_COMPONENT_ID] = 1/z
  end
  for (id, in_front) in behind
    n = reinterpret(UInt32, id)
    haskey(ecs, in_front, ZCOORDINATE_COMPONENT_ID) || error("Object $id has been placed behind object $in_front, but $in_front ", haskey(behind, in_front) ? "is also to be placed behind another object" : "has no render component", '.')
    z_front = ecs[in_front, ZCOORDINATE_COMPONENT_ID]::Float32
    z = nextfloat(z_front, Int64(n))
    ecs[id, ZCOORDINATE_COMPONENT_ID] = z
  end
end

struct RenderingSystem <: System
  renderer::Renderer
end

function shutdown(system::RenderingSystem)
  wait(shutdown(system.renderer.task))
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
    location = Point3f(location..., z)
    command = @match object.type begin
      &RENDER_OBJECT_RECTANGLE => begin
        rect = ShaderLibrary.Rectangle(geometry, location, object.vertex_data, nothing)
        gradient = object.primitive_data::Gradient
        Command(program_cache, gradient, parameters, Primitive(rect))
      end
      &RENDER_OBJECT_IMAGE => begin
        # Assume that images are opaque for now.
        rect = ShaderLibrary.Rectangle(geometry, location, full_image_uv(), nothing)
        sprite = object.primitive_data::Sprite
        Command(program_cache, sprite, parameters, Primitive(rect))
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
    location = Point3f(location..., z)
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

full_image_uv() = Vec2[(0, 0), (0, 1), (1, 0), (1, 1)]

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
  input = react_to_event(system.ui.overlay, event)
  isnothing(input) && return
  entity = system.ui.entities[input.area]
  input_component = ecs[entity, INPUT_COMPONENT_ID]::InputComponent
  input_component.on_input(input)
  nothing
end

function update_overlays!(system::EventSystem, ecs::ECSDatabase)
  updated = Set{InputArea}()
  for (entity, location, geometry, input, z) in components(ecs, (ENTITY_COMPONENT_ID, LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, INPUT_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{EntityID, P2, GeometryComponent, InputComponent, ZCoordinateComponent})
    zindex = round(Float64, 1/z)
    area = get(system.ui.areas, entity, nothing)
    contains = x -> in(x .- location, geometry)
    if isnothing(area)
      area = InputArea(geometry, zindex, contains, input.events, input.actions)
      insert!(system.ui, entity, area)
      push!(updated, area)
    else
      area.aabb = geometry
      area.z = zindex
      area.contains = contains
      push!(updated, area)
    end
  end
  get!(Set{InputArea}, system.ui.overlay.areas, system.ui.window)
  system.ui.overlay.areas[system.ui.window] = updated
end

struct Systems
  synchronization::SynchronizationSystem
  drawing_order::DrawingOrderSystem
  rendering::RenderingSystem
  event::EventSystem
end

# Only call that from the application thread.
function shutdown(systems::Systems)
  shutdown(systems.event)
  shutdown(systems.rendering)
  shutdown(systems.drawing_order)
  shutdown(systems.synchronization)
end
