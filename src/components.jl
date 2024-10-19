const ENTITY_COMPONENT_ID = ComponentID(0) # EntityID
const RENDER_COMPONENT_ID = ComponentID(1) # RenderComponent
const INPUT_COMPONENT_ID = ComponentID(2) # InputComponent
const LOCATION_COMPONENT_ID = ComponentID(3) # LocationComponent
const GEOMETRY_COMPONENT_ID = ComponentID(4) # GeometryComponent
const ZCOORDINATE_COMPONENT_ID = ComponentID(5) # ZCoordinateComponent
const WIDGET_COMPONENT_ID = ComponentID(6) # WidgetComponent
const WINDOW_COMPONENT_ID = ComponentID(7) # Window

@enum RenderObjectType begin
  RENDER_OBJECT_RECTANGLE = 1
  RENDER_OBJECT_IMAGE = 2
  RENDER_OBJECT_TEXT = 3
end

const LocationComponent = P2
const GeometryComponent = Box2
const ZCoordinateComponent = Float32

struct RenderComponent
  type::RenderObjectType
  vertex_data::Any
  primitive_data::Any
  is_opaque::Bool
end
function RenderComponent(type::RenderObjectType, vertex_data, primitive_data; is_opaque::Optional{Bool} = nothing)
  is_opaque = @something is_opaque type ≠ RENDER_OBJECT_TEXT
  RenderComponent(type, vertex_data, primitive_data, is_opaque)
end

function add_renderables!(commands, program_cache::ProgramCache, component::RenderComponent, location, geometry, parameters::ShaderParameters)
  @switch component.type begin
    @case &RENDER_OBJECT_RECTANGLE
    rect = ShaderLibrary.Rectangle(geometry, component.vertex_data, nothing)
    gradient = component.primitive_data::Gradient
    primitive = Primitive(rect, location)
    command = Command(program_cache, gradient, parameters, primitive)
    push!(commands, command)

    @case &RENDER_OBJECT_IMAGE
    rect = ShaderLibrary.Rectangle(geometry, FULL_IMAGE_UV, nothing)
    sprite = component.primitive_data::Sprite
    primitive = Primitive(rect, location)
    command = Command(program_cache, sprite, parameters, primitive)
    push!(commands, command)

    @case &RENDER_OBJECT_TEXT
    text = component.primitive_data::ShaderLibrary.Text
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    append!(commands, renderables(program_cache, text, parameters_ssaa, location))
  end
end

Base.show(io::IO, render::RenderComponent) = print(io, RenderComponent, "(", render.type, ", ", typeof(render.vertex_data), ", ", typeof(render.primitive_data))

struct InputComponent
  on_input::Function
  events::EventType
  actions::ActionType
end

Base.show(io::IO, input::InputComponent) = print(io, InputComponent, "(", input.events, ", ", input.actions, ')')

function new_database()
  ecs = ECSDatabase(component_names = Dict(), entity_names = Dict())
  ecs.components[ENTITY_COMPONENT_ID] = ComponentStorage{EntityID}()
  ecs.components[RENDER_COMPONENT_ID] = ComponentStorage{RenderComponent}()
  ecs.components[INPUT_COMPONENT_ID] = ComponentStorage{InputComponent}()
  ecs.components[LOCATION_COMPONENT_ID] = ComponentStorage{LocationComponent}()
  ecs.components[GEOMETRY_COMPONENT_ID] = ComponentStorage{GeometryComponent}()
  ecs.components[ZCOORDINATE_COMPONENT_ID] = ComponentStorage{ZCoordinateComponent}()
  ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()
  ecs.components[WINDOW_COMPONENT_ID] = ComponentStorage{Window}()

  ecs.component_names[ENTITY_COMPONENT_ID] = :Entity
  ecs.component_names[RENDER_COMPONENT_ID] = :Render
  ecs.component_names[INPUT_COMPONENT_ID] = :Input
  ecs.component_names[LOCATION_COMPONENT_ID] = :Location
  ecs.component_names[GEOMETRY_COMPONENT_ID] = :Geometry
  ecs.component_names[ZCOORDINATE_COMPONENT_ID] = :Z
  ecs.component_names[WIDGET_COMPONENT_ID] = :Widget
  ecs.component_names[WINDOW_COMPONENT_ID] = :Window
  ecs
end
