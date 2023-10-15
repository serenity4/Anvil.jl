const ENTITY_COMPONENT_ID = ComponentID(0) # EntityID
const RENDER_COMPONENT_ID = ComponentID(1) # RenderComponent
const INPUT_COMPONENT_ID = ComponentID(2) # InputComponent
const LOCATION_COMPONENT_ID = ComponentID(3) # LocationComponent
const GEOMETRY_COMPONENT_ID = ComponentID(4) # GeometryComponent
const ZCOORDINATE_COMPONENT_ID = ComponentID(5) # ZCoordinateComponent
const WIDGET_COMPONENT_ID = ComponentID(6) # WidgetComponent

@enum RenderObjectType begin
  RENDER_OBJECT_RECTANGLE = 1
  RENDER_OBJECT_IMAGE = 2
  RENDER_OBJECT_TEXT = 3
end

const LocationComponent = Point2
const GeometryComponent = Box2
const ZCoordinateComponent = Float32

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
