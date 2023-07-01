const RENDER_COMPONENT_ID = ComponentID(1) # RenderComponent
const INPUT_COMPONENT_ID = ComponentID(2) # InputComponent
const LOCATION_COMPONENT_ID = ComponentID(3) # Point2
const GEOMETRY_COMPONENT_ID = ComponentID(4) # GeometryComponent

@enum RenderObjectType begin
  RENDER_OBJECT_RECTANGLE = 1
end

struct GeometryComponent
  object::Any
  z::Float64
end

struct RenderComponent
  type::RenderObjectType
  vertex_data::Any
  primitive_data::Any
end

struct InputComponent
  entity::EntityID
  on_input::Function
  events::EventType
  actions::ActionType
end
