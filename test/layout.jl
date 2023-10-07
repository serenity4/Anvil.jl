using Givre
using Givre: LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, Point2
using Entities
using Entities: new!
using Test

pool = EntityPool()
ecs = ECSDatabase()
engine = ECSLayoutEngine{Point2}(ecs)

objects = [new!(pool) for _ in 1:3]
locations = Point2[(10, 10), (30, 30), (76, 54)]
reset_location(i) = ecs[objects[i], LOCATION_COMPONENT_ID] = locations[i]

reset_location.((1, 2))
compute_layout!(engine, objects[1:2], [attach(at(objects[1], Point2(2, 3)), objects[2])])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == Point2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == Point2(12, 13)

reset_location.((1, 2))
compute_layout!(engine, objects[1:2], [attach(at(objects[1], Point2(3, 8)), at(objects[2], Point2(1, 5)))])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == Point2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == Point2(12, 13)

reset_location.((1, 2))
compute_layout!(engine, objects[1:2], repeat([attach(at(objects[1], Point2(3, 8)), at(objects[2], Point2(1, 5)))], 2))
@test ecs[objects[1], LOCATION_COMPONENT_ID] == Point2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == Point2(12, 13)

reset_location.((1, 2))
@test_throws "attach the same object at two different locations" compute_layout!(engine, objects, [
  attach(at(objects[1], Point2(2, 3)), objects[2]),
  attach(at(objects[1], Point2(4, 5)), objects[2]),
])
