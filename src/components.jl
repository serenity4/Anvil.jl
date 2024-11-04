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

struct ImageParameters
  is_opaque::Bool
  tiled::Bool
  scale::Float64
end

ImageParameters(; is_opaque = false, tiled = false, scale = 1.0) = ImageParameters(is_opaque, tiled, scale)

struct RenderImageData
  sprite::Sprite
  parameters::ImageParameters
end

function RenderImageData(texture::Texture, parameters::ImageParameters)
  (; sampling) = texture
  if parameters.tiled
    @reset sampling.address_modes = ntuple(_ -> Vk.SAMPLER_ADDRESS_MODE_REPEAT, 3)
    @reset texture.sampling = sampling
  end
  sprite = Sprite(texture)
  RenderImageData(sprite, parameters)
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

RenderComponent(data::RenderImageData) = RenderComponent(RENDER_OBJECT_IMAGE, nothing, data; data.parameters.is_opaque)

function add_renderables!(commands, program_cache::ProgramCache, component::RenderComponent, location, geometry, parameters::ShaderParameters)
  @switch component.type begin
    @case &RENDER_OBJECT_RECTANGLE
    rect = ShaderLibrary.Rectangle(geometry, component.vertex_data, nothing)
    gradient = component.primitive_data::Gradient
    primitive = Primitive(rect, location)
    command = Command(program_cache, gradient, parameters, primitive)
    push!(commands, command)

    @case &RENDER_OBJECT_IMAGE
    render = component.primitive_data::RenderImageData
    uvs = render.parameters.tiled ? tiled_uvs(geometry, render.parameters.scale) : FULL_IMAGE_UV
    rect = ShaderLibrary.Rectangle(geometry, uvs, nothing)
    primitive = Primitive(rect, location)
    command = Command(program_cache, render.sprite, parameters, primitive)
    push!(commands, command)

    @case &RENDER_OBJECT_TEXT
    text = component.primitive_data::ShaderLibrary.Text
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    text_span = boundingelement(text)
    origin = Point3((location[1:2] .- centroid(text_span))..., location[3])
    append!(commands, renderables(program_cache, text, parameters_ssaa, origin))
  end
end

function tiled_uvs(geometry::Box, scale::Real)
  (; width, height) = geometry
  generate_quad_uvs((0, width * scale), (0, height * scale))
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
