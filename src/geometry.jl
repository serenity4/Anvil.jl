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
end

struct GeometryComponent
  type::GeometryType
  aabb::Box2
  data::Any
end

GeometryComponent(box::Box2) = GeometryComponent(GEOMETRY_TYPE_RECTANGLE, box, box)
GeometryComponent(circle::FilledCircle) = GeometryComponent(GEOMETRY_TYPE_FILLED_CIRCLE, boundingelement(circle), circle)

compute_bounding_box(box::Box2) = box
compute_bounding_box(geometry) = boundingelement(geometry)

GeometryExperiments.boundingelement(geometry::GeometryComponent) = geometry.aabb
GeometryExperiments.centroid(geometry::GeometryComponent) = centroid(geometry.aabb)

function Base.in(p, geometry::GeometryComponent)
  @match geometry.type begin
    &GEOMETRY_TYPE_RECTANGLE => in(p, geometry.rectangle)
    &GEOMETRY_TYPE_FILLED_CIRCLE => in(p, geometry.circle)
  end
end

function Base.getproperty(geometry::GeometryComponent, name::Symbol)
  name === :circle && return geometry.data::FilledCircle
  name === :rectangle && return geometry.data::Box2
  getfield(geometry, name)
end

function resize_geometry(geometry::GeometryComponent, aabb::Box2)
  @match geometry.type begin
    &GEOMETRY_TYPE_RECTANGLE => return GeometryComponent(aabb)
    _ => error("Resizing geometry is not supported for geometries of type ", geometry.type)
  end
end
