using Givre
using Givre: LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, Point2
using Entities
using Entities: new!
using Test

pool = EntityPool()
ecs = ECSDatabase()
engine = ECSLayoutEngine{Point2}(ecs)

objects = [new!(pool) for _ in 1:3]
insert!(ecs, objects[1], LOCATION_COMPONENT_ID, Point2(10, 10))
insert!(ecs, objects[2], LOCATION_COMPONENT_ID, Point2(30, 30))
insert!(ecs, objects[3], LOCATION_COMPONENT_ID, Point2(33, 35))

compute_layout!(engine, objects[1:2], [
  Constraint(CONSTRAINT_TYPE_ATTACH, objects[1], objects[2], PositionalFeature(objects[1], Point2(2, 3))),
])
@test ecs[objects[2], LOCATION_COMPONENT_ID] == Point2(12, 13)
@test_throws "attach the same object at two different locations" compute_layout!(engine, objects, [
  Constraint(CONSTRAINT_TYPE_ATTACH, objects[1], objects[2], PositionalFeature(objects[1], Point2(2, 3))),
  Constraint(CONSTRAINT_TYPE_ATTACH, objects[1], objects[2], PositionalFeature(objects[1], Point2(4, 5))),
])
