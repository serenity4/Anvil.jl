struct FilledCircle
  radius::Float64
  center::Point2
end
FilledCircle(radius) = FilledCircle(radius, (0, 0))

GeometryExperiments.centroid(circle::FilledCircle) = circle.center
GeometryExperiments.boundingelement(circle::FilledCircle) = Box(circle.center .- circle.radius, circle.center .+ circle.radius)
function Base.in(p, circle::FilledCircle)
  x, y = p .- circle.center
  hypot(x, y) < circle.radius
end

@enum GeometryType begin
  GEOMETRY_TYPE_RECTANGLE
  GEOMETRY_TYPE_FILLED_CIRCLE
  GEOMETRY_TYPE_USER_DEFINED
end

short_name(x::GeometryType) = lowercase(replace(string(x), r"^GEOMETRY_TYPE_" => ""))

struct GeometryComponent
  type::GeometryType
  aabb::Box2
  data::Any
end

GeometryComponent(box::Box2) = GeometryComponent(GEOMETRY_TYPE_RECTANGLE, box, box)
GeometryComponent(circle::FilledCircle) = GeometryComponent(GEOMETRY_TYPE_FILLED_CIRCLE, boundingelement(circle), circle)
GeometryComponent(f::F, aabb) where {F<:Function} = GeometryComponent(GEOMETRY_TYPE_USER_DEFINED, aabb, f)

compute_bounding_box(box::Box2) = box
compute_bounding_box(geometry) = boundingelement(geometry)

GeometryExperiments.boundingelement(geometry::GeometryComponent) = geometry.aabb
GeometryExperiments.centroid(geometry::GeometryComponent) = centroid(geometry.aabb)

function Base.in(p, geometry::GeometryComponent)
  @match geometry.type begin
    &GEOMETRY_TYPE_RECTANGLE => in(p, geometry.rectangle)
    &GEOMETRY_TYPE_FILLED_CIRCLE => in(p, geometry.circle)
    &GEOMETRY_USER_DEFINED => geometry.in(p)
  end
end

function Base.getproperty(geometry::GeometryComponent, name::Symbol)
  name === :circle && return geometry.data::FilledCircle
  name === :rectangle && return geometry.data::Box2
  name === :in && return geometry.data::Function
  getfield(geometry, name)
end

function resize_geometry(geometry::GeometryComponent, aabb::Box2)
  @match geometry.type begin
    &GEOMETRY_TYPE_RECTANGLE => return GeometryComponent(aabb)
    _ => error("Resizing geometry is not supported for geometries of type ", geometry.type)
  end
end

Entities.remap_type_for_dataframe_display(::Type{GeometryComponent}) = Union{String, Missing}
Entities.remap_value_for_dataframe_display(component::GeometryComponent) = short_name(component.type)

Base.show(io::IO, geometry::GeometryComponent) = print(io, GeometryComponent, "(", short_name(geometry.type), ", ", geometry.aabb, ", ", geometry.data, ')')
