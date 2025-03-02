const ENTITY_COMPONENT_ID = ComponentID(0) # EntityID
const RENDER_COMPONENT_ID = ComponentID(1) # RenderComponent
const LOCATION_COMPONENT_ID = ComponentID(3) # LocationComponent
const GEOMETRY_COMPONENT_ID = ComponentID(4) # GeometryComponent
const ZCOORDINATE_COMPONENT_ID = ComponentID(5) # ZCoordinateComponent
const WIDGET_COMPONENT_ID = ComponentID(6) # WidgetComponent
const WINDOW_COMPONENT_ID = ComponentID(7) # Window

@enum RenderObjectType begin
  RENDER_OBJECT_RECTANGLE = 1
  RENDER_OBJECT_IMAGE = 2
  RENDER_OBJECT_TEXT = 3
  RENDER_OBJECT_USER_DEFINED = 4
end

struct RectangleVisual
  color::RGBA{Float32}
  # TODO: add borders, corner roundness, etc.
end

RectangleVisual(color::RGB) = RectangleVisual(RGBA(color.r, color.g, color.b, 1f0))

function vertex_colors(visual::RectangleVisual)
  (; r, g, b, alpha) = visual.color
  [Vec4(r, g, b, alpha) for _ in 1:4]
end

struct ImageModeStretched end

struct ImageModeTiled
  scale::Float64
  offset::Vec{2,Float64}
end

ImageModeTiled(; scale = 1.0, offset = Vec(0.0, 0.0)) = ImageModeTiled(scale, offset)

struct ImageModeCropped
  focus::Optional{Vec2}
  zoom::Optional{Float64}
end

function ImageModeCropped(; focus = nothing, zoom = nothing)
  !isnothing(zoom) && (zoom ≈ 1 || zoom ≥ 1 || throw(ArgumentError("The zoom factor must be greater than 1")))
  ImageModeCropped(focus, zoom)
end

struct ImageParameters
  is_opaque::Bool
  mode::Union{ImageModeStretched, ImageModeTiled, ImageModeCropped}
end

function ImageParameters(; is_opaque = false, mode = ImageModeStretched())
  ImageParameters(is_opaque, mode)
end

struct ImageVisual
  sprite::Sprite
  parameters::ImageParameters
end

function ImageVisual(texture::Texture, parameters::ImageParameters)
  (; sampling) = texture
  if isa(parameters.mode, ImageModeTiled)
    @reset sampling.address_modes = ntuple(_ -> Vk.SAMPLER_ADDRESS_MODE_REPEAT, 3)
    @reset texture.sampling = sampling
  end
  sprite = Sprite(texture)
  ImageVisual(sprite, parameters)
end

function generate_quad_uvs((umin, umax), (vmin, vmax))
  Vec2[(umin, vmax), (umax, vmax), (umin, vmin), (umax, vmin)]
end

const FULL_IMAGE_UV = generate_quad_uvs((0, 1), (0, 1))

image_uvs(geometry, visual::ImageVisual) = image_uvs(geometry, visual.parameters.mode, visual)
image_uvs(geometry, mode::ImageModeStretched, visual::ImageVisual) = FULL_IMAGE_UV

function image_uvs(geometry, mode::ImageModeTiled, visual::ImageVisual)
  (; width, height) = geometry
  (; scale, offset) = mode
  generate_quad_uvs((0, width * scale) .+ offset, (0, height * scale) .+ offset)
end

function image_uvs(geometry, mode::ImageModeCropped, visual::ImageVisual)
  (; resource) = visual.sprite.texture
  image_width, image_height = dimensions(resource)
  focus = @something(mode.focus, Vec(0.5, 0.5))
  @reset focus.y = 1 - focus.y
  zoom = 0.5 / something(mode.zoom, 1.0)
  image_aspect_ratio = image_width / image_height
  geometry_aspect_ratio = geometry.width / geometry.height
  image_aspect_ratio ≈ geometry_aspect_ratio && zoom ≈ 1 && return FULL_IMAGE_UV
  if geometry_aspect_ratio > image_aspect_ratio
    # The geometry is wider than the image.
    # The image will be cropped vertically.
    ratio = image_aspect_ratio / geometry_aspect_ratio
    umin, umax = focus.x .+ (-zoom, zoom)
    vmin, vmax = focus.y .+ (-ratio, ratio) .* zoom
    @assert umin ≥ 0 || umax ≤ 1
    @assert vmin ≥ 0 || vmax ≤ 1
    umax > 1 && ((umin, umax) = (umin - (umax - 1), 1.0))
    umin < 0 && ((umin, umax) = (0.0, umax + (0 - umin)))
    vmax > 1 && ((vmin, vmax) = (vmin - (vmax - 1), 1.0))
    vmin < 0 && ((vmin, vmax) = (0.0, vmax + (0 - vmin)))
    generate_quad_uvs((umin, umax), (vmin, vmax))
  else
    # The geometry is thinner than the image.
    # The image will be cropped horizontally.
    ratio = geometry_aspect_ratio / image_aspect_ratio
    umin, umax = focus.x .+ (-ratio, ratio) .* zoom
    vmin, vmax = focus.y .+ (-zoom, zoom)
    @assert umin ≥ 0 || umax ≤ 1
    @assert vmin ≥ 0 || vmax ≤ 1
    umax > 1 && ((umin, umax) = (umin - (umax - 1), 1.0))
    umin < 0 && ((umin, umax) = (0.0, umax + (0 - umin)))
    vmax > 1 && ((vmin, vmax) = (vmin - (vmax - 1), 1.0))
    vmin < 0 && ((vmin, vmax) = (0.0, vmax + (0 - vmin)))
    generate_quad_uvs((umin, umax), (vmin, vmax))
  end
end

const LocationComponent = P2
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

RenderComponent(visual::RectangleVisual) = RenderComponent(RENDER_OBJECT_RECTANGLE, vertex_colors(visual), Gradient{Vec4}(); is_opaque = isone(visual.color.alpha))
RenderComponent(visual::ImageVisual) = RenderComponent(RENDER_OBJECT_IMAGE, nothing, visual; visual.parameters.is_opaque)

add_command!(pass::Vector{Command}, command::Command) = push!(pass, command)
add_commands!(pass::Vector{Command}, commands::Vector{Command}) = append!(pass, commands)
add_commands!(pass::Vector{Command}, command_lists::Vector{Vector{Command}}) = foreach(commands -> add_commands!(pass, commands), command_lists)

struct TransparencyPass
  pass_1::Vector{Command}
  pass_2::Vector{Command}
end
TransparencyPass() = TransparencyPass(Command[], Command[])

add_command!(pass::TransparencyPass, command::Command) = push!(pass.pass_1, command)

add_commands!(pass::TransparencyPass, commands::Vector{Command}) = append!(pass.pass_1, commands)

function add_commands!(pass::TransparencyPass, commands::Vector{Vector{Command}})
  length(commands) == 2 || error("Expected two sets of commands, got $(length(commands)) sets")
  append!(pass.pass_1, commands[1])
  append!(pass.pass_2, commands[2])
end

struct UserDefinedRender
  create_renderables!::Any
  is_opaque::Bool
end

UserDefinedRender(f; is_opaque::Bool = false) = UserDefinedRender(f, is_opaque)

function add_commands!(pass, program_cache::ProgramCache, component::RenderComponent, location, geometry::GeometryComponent, parameters::ShaderParameters)
  @switch component.type begin
    @case &RENDER_OBJECT_RECTANGLE
    rect = ShaderLibrary.Rectangle(geometry.aabb, component.vertex_data, nothing)
    gradient = component.primitive_data::Gradient
    primitive = Primitive(rect, location)
    command = Command(program_cache, gradient, parameters, primitive)
    add_command!(pass, command)

    @case &RENDER_OBJECT_IMAGE
    render = component.primitive_data::ImageVisual
    uvs = image_uvs(geometry.aabb, render)
    rect = ShaderLibrary.Rectangle(geometry.aabb, uvs, nothing)
    primitive = Primitive(rect, location)
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    command = Command(program_cache, render.sprite, parameters_ssaa, primitive)
    add_command!(pass, command)

    @case &RENDER_OBJECT_TEXT
    text = component.primitive_data::ShaderLibrary.Text
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    # XXX: We may want to draw all opaque text backgrounds in the corresponding pass,
    # not in the transparency pass.
    add_commands!(pass, renderables(program_cache, text, parameters_ssaa, location))

    @case &RENDER_OBJECT_USER_DEFINED
    (; create_renderables!) = component.primitive_data::UserDefinedRender
    create_renderables!(pass, program_cache, location, geometry, parameters)
  end
end

Base.show(io::IO, render::RenderComponent) = print(io, RenderComponent, "(", render.type, ", ", typeof(render.vertex_data), ", ", typeof(render.primitive_data))

function new_database()
  ecs = ECSDatabase(component_names = Dict(), entity_names = Dict())
  ecs.components[ENTITY_COMPONENT_ID] = ComponentStorage{EntityID}()
  ecs.components[RENDER_COMPONENT_ID] = ComponentStorage{RenderComponent}()
  ecs.components[LOCATION_COMPONENT_ID] = ComponentStorage{LocationComponent}()
  ecs.components[GEOMETRY_COMPONENT_ID] = ComponentStorage{GeometryComponent}()
  ecs.components[ZCOORDINATE_COMPONENT_ID] = ComponentStorage{ZCoordinateComponent}()
  ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()
  ecs.components[WINDOW_COMPONENT_ID] = ComponentStorage{Window}()

  ecs.component_names[ENTITY_COMPONENT_ID] = :Entity
  ecs.component_names[RENDER_COMPONENT_ID] = :Render
  ecs.component_names[LOCATION_COMPONENT_ID] = :Location
  ecs.component_names[GEOMETRY_COMPONENT_ID] = :Geometry
  ecs.component_names[ZCOORDINATE_COMPONENT_ID] = :Z
  ecs.component_names[WIDGET_COMPONENT_ID] = :Widget
  ecs.component_names[WINDOW_COMPONENT_ID] = :Window
  ecs
end
