abstract type System end

shutdown(::System) = nothing

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
  for (location, geometry, input) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, INPUT_COMPONENT_ID), Tuple{Point2, GeometryComponent, InputComponent})
    area = get(system.ui.areas, input.entity, nothing)
    contains = x -> in(x .- location, geometry.object)
    if isnothing(area)
      area = InputArea(geometry.object, geometry.z, contains, input.events, input.actions)
      insert!(system.ui, input.entity, area)
      push!(updated, area)
    else
      area.aabb = geometry.object
      area.z = geometry.z
      area.contains = contains
      push!(updated, area)
    end
  end
  get!(Set{InputArea}, system.ui.overlay.areas, system.ui.window)
  system.ui.overlay.areas[system.ui.window] = updated
end

struct RenderingSystem
  renderer::Renderer
end

function shutdown(system::RenderingSystem)
  wait(shutdown(system.renderer.task))
  wait(system.renderer.device)
end

function (rendering::RenderingSystem)(ecs::ECSDatabase, target::Resource)
  nodes = RenderNode[]
  depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, dimensions(target.attachment))
  parameters = ShaderParameters(target; depth)
  push!(nodes, render_opaque_objects(rendering, ecs, @set parameters.depth_clear = ClearValue(1f0)))
  push!(nodes, render_transparent_objects(rendering, ecs, @set parameters.color_clear[1] = nothing))
  nodes
end

function render_opaque_objects((; renderer)::RenderingSystem, ecs::ECSDatabase, parameters::ShaderParameters)
  (; program_cache) = renderer
  commands = Command[]

  for (location, geometry, object) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID), Tuple{Point2,GeometryComponent,RenderComponent})
    location = Point3f(location..., 1/geometry.z)
    command = @match object.type begin
      &RENDER_OBJECT_RECTANGLE => begin
        rect = Rectangle(geometry.object, location, object.vertex_data, nothing)
        gradient = object.primitive_data::Gradient
        Command(program_cache, gradient, parameters, Primitive(rect))
      end
      &RENDER_OBJECT_IMAGE => begin
        # Assume that images are opaque for now.
        rect = Rectangle(geometry.object, location, full_image_uv(), nothing)
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

  for (location, geometry, object) in components(ecs, (LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID), Tuple{Point2,GeometryComponent,RenderComponent})
    location = Point3f(location..., 1/geometry.z)
    command = @match object.type begin
      &RENDER_OBJECT_TEXT => begin
        text = object.primitive_data::Text
        renderables(program_cache, text, parameters, location)
      end
      _ => continue
    end
    push!(commands, command)
  end
  RenderNode(commands)
end

full_image_uv() = Vec2[(0, 0), (0, 1), (1, 0), (1, 1)]

struct Systems
  event::EventSystem
  rendering::RenderingSystem
end

# Only call that from the application thread.
function shutdown(systems::Systems)
  shutdown(systems.event)
  shutdown(systems.rendering)
end
