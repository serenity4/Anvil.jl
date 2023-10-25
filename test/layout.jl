using Givre
using Givre: LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, positional_feature, P2
using Givre: object_type, position_type, coordinate_type, geometry_type, get_position, get_coordinates, set_coordinates, get_geometry, set_position!, set_geometry!
using GeometryExperiments
using Entities
using Entities: new!
using Test

function test_engine_interface!(engine::LayoutEngine, objects)
  @testset "`LayoutEngine` interface for $(nameof(typeof(engine)))" begin
    O, P, C, G = object_type(engine), position_type(engine), coordinate_type(engine), geometry_type(engine)
    for object in objects
      @test isa(object, O)
      position = get_position(engine, object)
      @test isa(position, P)
      coordinates = get_coordinates(engine, object)
      @test isa(coordinates, C)
      new_position = set_coordinates(engine, position, coordinates .+ 1)
      set_position!(engine, object, new_position)
      @test get_position(engine, object) === new_position
      set_position!(engine, object, position)
      @test get_position(engine, object) === position
      geometry = get_geometry(engine, object)
      @test isa(geometry, G)
      set_geometry!(engine, object, geometry)
      @test get_geometry(engine, object) === geometry
    end
  end
end

pool = EntityPool()
ecs = ECSDatabase()
engine = ECSLayoutEngine{P2,Box{2,Float64},P2,Box{2,Float64}}(ecs)

objects = [new!(pool) for _ in 1:3]
locations = P2[(10, 10), (30, 30), (76, 54)]
geometries = Box.(P2[(1.0, 2.0), (30.0, 45.0), (100.0, 0.5)])
reset_location(i) = ecs[objects[i], LOCATION_COMPONENT_ID] = locations[i]
reset_locations() = reset_location.(eachindex(objects))
reset_geometry(i) = ecs[objects[i], GEOMETRY_COMPONENT_ID] = geometries[i]
reset_geometries() = reset_geometry.(eachindex(objects))

reset_locations()
reset_geometries()

test_engine_interface!(engine, objects)
test_engine_interface!(ArrayLayoutEngine{Int64}(locations, geometries), eachindex(objects))

@testset "Features" begin
  feature = positional_feature(nothing)
  @test feature == at(nothing)
  @test feature == PositionalFeature(nothing, FEATURE_LOCATION_ORIGIN, nothing)
  @test feature == PositionalFeature(nothing, :origin, nothing)
  @test positional_feature(feature) === feature
  @test at(nothing, 4.0) == PositionalFeature(nothing, FEATURE_LOCATION_CUSTOM, 4.0)
  @test at(nothing, FEATURE_LOCATION_CENTER) == PositionalFeature(nothing, FEATURE_LOCATION_CENTER, nothing)
  @test at(nothing, :center) == PositionalFeature(nothing, :center, nothing)

  reset_location(1)
  @test get_coordinates(engine, objects[1]) == locations[1]
  @test get_coordinates(engine, at(objects[1])) == locations[1]
  @test get_coordinates(engine, at(objects[1], P2(2, 3))) == locations[1] + P2(2, 3)

  reset_geometry(1)
  @test get_coordinates(engine, at(objects[1], :center)) == locations[1] # origin == center in this case
  @test get_coordinates(engine, at(objects[1], :corner, :bottom_left)) == P2(9, 8)
  @test get_coordinates(engine, at(objects[1], :corner, :bottom_right)) == P2(11, 8)
  @test get_coordinates(engine, at(objects[1], :corner, :top_right)) == P2(11, 12)
  @test get_coordinates(engine, at(at(objects[1], P2(0.1, 0.1)), P2(-0.1, -0.1))) == get_coordinates(engine, objects[1])
  @test get_coordinates(engine, at(objects[1], :edge, :left)) == Segment(P2(9, 8), P2(9, 12))
  @test get_coordinates(engine, at(objects[1], :edge, :right)) == Segment(P2(11, 8), P2(11, 12))
  @test get_coordinates(engine, at(objects[1], :edge, :bottom)) == Segment(P2(9, 8), P2(11, 8))
  @test get_coordinates(engine, at(objects[1], :edge, :top)) == Segment(P2(9, 12), P2(11, 12))
end

@testset "Layout computations" begin
  reset_location.([1, 2])
  compute_layout!(engine, [attach(objects[2], objects[1])])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[1]
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[1]

  reset_location.([1, 2])
  compute_layout!(engine, [attach(objects[2], at(at(objects[1], P2(2, 3)), P2(-2, -3)))])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[1]
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[1]

  reset_location.([1, 2])
  compute_layout!(engine, [attach(objects[2], at(objects[1], P2(2, 3)))])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

  reset_location.([1, 2])
  compute_layout!(engine, [attach(at(objects[2], P2(1, 5)), at(objects[1], P2(3, 8)))])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

  # Idempotence.
  reset_location.([1, 2])
  compute_layout!(engine, repeat([attach(at(objects[2], P2(1, 5)), at(objects[1], P2(3, 8)))], 2))
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

  reset_location.([1, 2])
  @test_throws "attach the same object at two different locations" compute_layout!(engine, [
    attach(objects[2], at(objects[1], P2(2, 3))),
    attach(objects[2], at(objects[1], P2(4, 5))),
  ])

  # Layout out 3 objects.
  reset_location.([1, 2, 3])
  compute_layout!(engine, [
    attach(objects[2], at(objects[1], P2(2, 3))),
    attach(at(objects[3], P2(4, 9)), objects[1]),
  ])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)
  @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(6, 1)

  # Align objects.
  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    align(objects[1:3], :horizontal, ALIGNMENT_TARGET_MINIMUM),
  ])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 10)
  @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    align([objects[1], at(objects[2], P2(2, 5)), objects[3]], :horizontal, ALIGNMENT_TARGET_MINIMUM),
  ])
  @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 5)
  @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  @test_throws "variable segment" compute_layout!(engine, [
    align(objects[2:3], :horizontal, at(objects[1], :edge, :right)),
  ])
  compute_layout!(engine, [
    align(objects[2:3], :vertical, at(objects[1], :edge, :right)),
  ])
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(11, 30)
  @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(11, 54)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    align(at.(objects[2:3], :edge, :right), :vertical, at(objects[1], :edge, :right)),
  ])
  @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(-19, 30)
  @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(-89, 54)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    distribute(objects, :horizontal, 2.0, :point),
  ])
  xs = get_coordinates.(engine, objects)
  @test xs[1] == locations[1]
  @test xs[2] == P2(12, locations[2].y)
  @test xs[3] == P2(14, locations[3].y)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    distribute(objects, :vertical, 2.0, :point),
  ])
  xs = get_coordinates.(engine, objects)
  @test xs[1] == locations[1]
  @test xs[2] == P2(locations[2].x, 12)
  @test xs[3] == P2(locations[3].x, 14)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    distribute(objects, :horizontal, 2.0, :geometry),
  ])
  xs = get_coordinates.(engine, objects)
  @test xs[1] == locations[1]
  @test xs[2] == P2(43, locations[2].y)
  @test xs[3] == P2(175, locations[3].y)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    distribute(objects, :vertical, 2.0, :geometry),
  ])
  xs = get_coordinates.(engine, objects)
  @test xs[1] == locations[1]
  @test xs[2] == P2(locations[2].x, 59)
  @test xs[3] == P2(locations[3].x, 106.5)

  reset_location.([1, 2, 3])
  reset_geometry.([1, 2, 3])
  compute_layout!(engine, [
    distribute(at.(objects, :edge, :right), :horizontal, 2.0, :point),
  ])
  xs = get_coordinates.(engine, objects)
  @test xs[1] == locations[1]
  @test xs[2] == P2(-17, locations[2].y)
  @test xs[3] == P2(-85, locations[3].y)
end;
