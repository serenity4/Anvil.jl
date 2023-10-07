using Givre
using Givre: LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, positional_feature, get_coordinates, get_geometry
using GeometryExperiments
using Entities
using Entities: new!
using Test

const P2 = Point2

pool = EntityPool()
ecs = ECSDatabase()
engine = ECSLayoutEngine{P2,Box{2,Float64}}(ecs)

objects = [new!(pool) for _ in 1:3]
locations = P2[(10, 10), (30, 30), (76, 54)]
geometries = Box.([Scaling(1.0, 2.0), Scaling(30.0, 45.0), Scaling(100.0, 0.5)])
reset_location(i) = ecs[objects[i], LOCATION_COMPONENT_ID] = locations[i]
reset_geometry(i) = ecs[objects[i], GEOMETRY_COMPONENT_ID] = geometries[i]

@testset "Features" begin
  feature = positional_feature(nothing)
  @test feature == at(nothing)
  @test feature == PositionalFeature(nothing, FEATURE_LOCATION_ORIGIN, nothing)
  @test positional_feature(feature) === feature
  @test at(nothing, 4.0) == PositionalFeature(nothing, FEATURE_LOCATION_CUSTOM, 4.0)
  @test at(nothing, FEATURE_LOCATION_CENTER) == PositionalFeature(nothing, FEATURE_LOCATION_CENTER, nothing)

  reset_location(1)
  @test get_coordinates(engine, objects[1]) == locations[1]
  @test get_coordinates(engine, at(objects[1])) == locations[1]
  @test get_coordinates(engine, at(objects[1], P2(2, 3))) == locations[1] + P2(2, 3)

  reset_geometry(1)
  @test get_coordinates(engine, at(objects[1], FEATURE_LOCATION_CENTER)) == locations[1] # origin == center in this case
  @test get_coordinates(engine, at(objects[1], FEATURE_LOCATION_CORNER, CORNER_BOTTOM_LEFT)) == P2(9, 8)
  @test get_coordinates(engine, at(objects[1], FEATURE_LOCATION_CORNER, CORNER_BOTTOM_RIGHT)) == P2(11, 8)
  @test get_coordinates(engine, at(objects[1], FEATURE_LOCATION_CORNER, CORNER_TOP_RIGHT)) == P2(11, 12)
end

reset_location.((1, 2))
compute_layout!(engine, objects[1:2], [attach(at(objects[1], P2(2, 3)), objects[2])])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

reset_location.((1, 2))
compute_layout!(engine, objects[1:2], [attach(at(objects[1], P2(3, 8)), at(objects[2], P2(1, 5)))])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

# Idempotence.
reset_location.((1, 2))
compute_layout!(engine, objects[1:2], repeat([attach(at(objects[1], P2(3, 8)), at(objects[2], P2(1, 5)))], 2))
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

reset_location.((1, 2))
@test_throws "attach the same object at two different locations" compute_layout!(engine, objects, [
  attach(at(objects[1], P2(2, 3)), objects[2]),
  attach(at(objects[1], P2(4, 5)), objects[2]),
])

# Layout out 3 objects.
reset_location.((1, 2, 3))
compute_layout!(engine, objects[1:3], [
  attach(at(objects[1], P2(2, 3)), objects[2]),
  attach(objects[1], at(objects[3], P2(4, 9))),
])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)
@test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(6, 1)

# Align objects.
reset_location.((1, 2, 3))
reset_geometry.((1, 2, 3))
compute_layout!(engine, objects[1:3], [
  align(objects[1:3], DIRECTION_HORIZONTAL, ALIGNMENT_TARGET_MINIMUM),
])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 10)
@test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)

reset_location.((1, 2, 3))
reset_geometry.((1, 2, 3))
compute_layout!(engine, objects[1:3], [
  align([objects[1], at(objects[2], P2(2, 5)), objects[3]], DIRECTION_HORIZONTAL, ALIGNMENT_TARGET_MINIMUM),
])
@test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
@test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 5)
@test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)
