using Anvil
using Anvil: LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, P2
using Anvil.Layout: object_type, position_type, coordinate_type, geometry_type, get_position, get_coordinates, set_coordinates, set_position!, set_geometry!, positional_feature, Group
import Anvil.Layout as L
using GeometryExperiments
using Entities
using Entities: new!
using Test

function test_storage_interface!(engine::LayoutStorage, objects)
  @testset "`LayoutStorage` interface for $(nameof(typeof(engine)))" begin
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
      geometry = L.get_geometry(engine, object)
      @test isa(geometry, G)
      set_geometry!(engine, object, geometry)
      @test L.get_geometry(engine, object) === geometry
    end
  end
end

pool = EntityPool()
ecs = ECSDatabase()
engine = LayoutEngine(ECSLayoutStorage{P2,Box{2,Float64},P2,Box{2,Float64}}(ecs))

objects = [new!(pool) for _ in 1:3]
locations = P2[(10, 10), (30, 30), (76, 54)]
geometries = Box.(P2[(1.0, 2.0), (30.0, 45.0), (100.0, 0.5)])
reset_location(i) = ecs[objects[i], LOCATION_COMPONENT_ID] = locations[i]
reset_locations() = reset_location.(eachindex(objects))
reset_geometry(i) = ecs[objects[i], GEOMETRY_COMPONENT_ID] = geometries[i]
reset_geometries() = reset_geometry.(eachindex(objects))

reset_locations()
reset_geometries()

test_storage_interface!(engine.storage, objects)
test_storage_interface!(ArrayLayoutStorage{Int64}(locations, geometries), eachindex(objects))

@testset "Layout" begin
  at(args...) = L.at(engine, args...)

  @testset "Features" begin
    object = EntityID(1)
    feature = positional_feature(engine, object)
    @test feature == at(object)
    @test feature == PositionalFeature(object, FEATURE_LOCATION_ORIGIN, nothing)
    @test feature == PositionalFeature(object, :origin)
    @test positional_feature(engine, feature) === feature
    @test at(object, 4.0) == PositionalFeature(object, FEATURE_LOCATION_CUSTOM, 4.0)
    ref = Movable(5.0)
    @test at(object, ref) == PositionalFeature(object, FEATURE_LOCATION_CUSTOM, ref)
    ref = Movable(P2(1, 2))
    @test_throws "automatic conversion cannot be made" at(object, Movable((1, 2)))
    @test at(object, ref) == PositionalFeature(object, FEATURE_LOCATION_CUSTOM, ref)
    @test at(object, FEATURE_LOCATION_CENTER) == PositionalFeature(object, FEATURE_LOCATION_CENTER, nothing)
    @test at(object, :center) == PositionalFeature(object, :center)

    reset_location(1)
    @test get_coordinates(engine, objects[1]) == locations[1]
    @test get_coordinates(engine, at(objects[1])) == locations[1]
    @test get_coordinates(engine, at(objects[1], P2(2, 3))) == locations[1] + P2(2, 3)

    reset_geometry(1)
    @test get_coordinates(engine, at(objects[1], :center)) == locations[1] # origin == center in this case
    @test get_coordinates(engine, at(objects[1], :bottom_left)) == P2(9, 8)
    @test get_coordinates(engine, at(objects[1], :bottom_right)) == P2(11, 8)
    @test get_coordinates(engine, at(objects[1], :top_right)) == P2(11, 12)
    @test get_coordinates(engine, at(at(objects[1], P2(0.1, 0.1)), P2(-0.1, -0.1))) == get_coordinates(engine, objects[1])

    @test get_coordinates(engine, at(objects[1], :left)) == P2(9, 10)
    @test get_coordinates(engine, at(objects[1], :right)) == P2(11, 10)
    @test get_coordinates(engine, at(objects[1], :bottom)) == P2(10, 8)
    @test get_coordinates(engine, at(objects[1], :top)) == P2(10, 12)

    height = height_of(objects[1])
    @test isa(height, PositionalFeature)
    @test height.data.fraction == 1.0
    height *= 0.7
    @test height.data.fraction == 0.7
    height *= 0.9
    @test height.data.fraction == 0.63
    @test get_coordinates(engine, height_of(objects[1])) == locations[1] .+ (0, geometries[1].height)
    @test get_coordinates(engine, width_of(objects[1])) == locations[1] .+ (geometries[1].width, 0)
  end

  @testset "Layout computations" begin
    @testset "Placement" begin
      reset_location.([1, 2])
      remove_operations!(engine)
      place!(engine, objects[2], objects[1])
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[1]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[1]

      reset_location.([1, 2])
      remove_operations!(engine)
      place!(engine, objects[2], at(at(objects[1], P2(2, 3)), P2(-2, -3)))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[1]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[1]

      reset_location.([1, 2])
      remove_operations!(engine)
      place!(engine, objects[2], at(objects[1], P2(2, 3)))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

      reset_location.([1, 2])
      remove_operations!(engine)
      place!(engine, at(objects[2], P2(1, 5)), at(objects[1], P2(3, 8)))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

      # Idempotence.
      reset_location.([1, 2])
      remove_operations!(engine)
      place!(engine, at(objects[2], P2(1, 5)), at(objects[1], P2(3, 8)))
      place!(engine, at(objects[2], P2(1, 5)), at(objects[1], P2(3, 8)))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)

      # Layout out 3 objects.
      reset_location.([1, 2, 3])
      remove_operations!(engine)
      place!(engine, objects[2], at(objects[1], P2(2, 3)))
      place!(engine, at(objects[3], P2(4, 9)), objects[1])
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(12, 13)
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(6, 1)

      # Place an object after another.
      reset_location.([1, 2])
      remove_operations!(engine)
      place_after!(engine, objects[2], objects[1])
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(10 + 1 + 30, 10)

      # Use a `Movable` for dynamic placement.
      reset_location.([1, 2])
      remove_operations!(engine)
      ref = Movable(P2(0, 0))
      place!(engine, objects[2], at(objects[1], ref))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(10, 10)
      ref[] = P2(5, 2)
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(15, 12)

      reset_location.([1, 2])
      remove_operations!(engine)
      ref = Movable(0.0)
      place!(engine, objects[2], at(objects[1], ref))
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(10, 10)
      ref[] = 7
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(17, 17)

      # Placing multiple objects at once.
      reset_location.([1, 2, 3])
      remove_operations!(engine)
      place!(engine, objects[1:2], objects[2:3])
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[3]
    end

    @testset "Alignment" begin
      # Align objects.
      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      align!(minimum, engine, objects[1:3], :horizontal)
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 10)
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      align!(minimum, engine, [objects[1], at(objects[2], P2(2, 5)), objects[3]], :horizontal)
      compute_layout!(engine)
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == P2(10, 10)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, 5)
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, 10)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      align!(engine, objects[2:3], at(objects[1], :right), :vertical)
      compute_layout!(engine)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(11, 30)
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(11, 54)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      align!(engine, at.(objects[2:3], :right), at(objects[1], :right), :vertical)
      compute_layout!(engine)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(-19, 30)
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(-89, 54)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      align!(engine, objects[2:3], objects[1], :horizontal)
      compute_layout!(engine)
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == P2(30, locations[1][2])
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == P2(76, locations[1][2])
    end

    @testset "Distribution" begin
      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, objects, :horizontal; spacing = 2.0)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs[1] == locations[1]
      @test xs[2] == P2(12, locations[2].y)
      @test xs[3] == P2(14, locations[3].y)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, objects, :vertical; spacing = 2.0)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs[1] == locations[1]
      @test xs[2] == P2(locations[2].x, 8)
      @test xs[3] == P2(locations[3].x, 6)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, objects, :horizontal; spacing = 2.0, mode = :geometry)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs[1] == locations[1]
      @test xs[2] == P2(43, locations[2].y)
      @test xs[3] == P2(175, locations[3].y)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, objects, :vertical; spacing = 2.0, mode = :geometry)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs[1] == P2(locations[1].x, 10)
      @test xs[2] == P2(locations[2].x, xs[1].y - (45 + 2 + 2))
      @test xs[3] == P2(locations[3].x, xs[2].y - (45 + 0.5 + 2))

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, at.(objects, :right), :horizontal; spacing = 2.0)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs[1] == locations[1]
      @test xs[2] == P2(-17, locations[2].y)
      @test xs[3] == P2(-85, locations[3].y)

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      distribute!(engine, at.(objects, :right), :horizontal; spacing = L.average)
      compute_layout!(engine)
      xs = get_coordinates.(engine, objects)
      @test xs ≠ locations
      compute_layout!(engine)
      @test get_coordinates.(engine, objects) == xs
    end

    @testset "Pinning" begin
      # Edge pinning.
      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      pin!(engine, objects[1], :right, objects[2] |> at(:right))
      compute_layout!(engine)
      @test get_coordinates.(engine, objects) == locations
      gs = L.get_geometry.(engine, objects)
      @test gs[1].top_right[1] == 30 + 30 - 10
      @test gs[1].bottom_left == geometries[1].bottom_left
      @test gs[2:3] == geometries[2:3]

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      pin!(engine, objects[1], :left, objects[2] |> at(:left))
      compute_layout!(engine)
      @test get_coordinates.(engine, objects) == locations
      gs = L.get_geometry.(engine, objects)
      @test gs[1].bottom_left[1] == 0 - 10
      @test gs[1].top_right == geometries[1].top_right
      compute_layout!(engine)
      @test gs == L.get_geometry.(engine, objects)

      # Corner pinning.
      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      pin!(engine, objects[1], :bottom_right, objects[2] |> at(:bottom_right))
      compute_layout!(engine)
      @test get_coordinates.(engine, objects) == locations
      gs = L.get_geometry.(engine, objects)
      @test gs[1] ≠ geometries[1]
      @test gs[2:3] == geometries[2:3]
    end

    @testset "Groups" begin
      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      group = Group(engine, objects[1], objects[3])
      @test get_coordinates(engine, group) == [76, 31.25]
      place!(engine, group, group)
      compute_layout!(engine)
      @test get_coordinates(engine, group) == [76, 31.25]

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      group = Group(engine, objects[1], objects[3]; origin = objects[1])
      @test get_coordinates(engine, group) == locations[1]
      place!(engine, group, objects[2])
      compute_layout!(engine)
      @test get_coordinates(engine, group) == locations[2]
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == locations[3] .+ (locations[2] .- locations[1])
      compute_layout!(engine)
      @test get_coordinates(engine, group) == locations[2]
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == locations[3] .+ (locations[2] .- locations[1])

      reset_location.([1, 2, 3])
      reset_geometry.([1, 2, 3])
      remove_operations!(engine)
      group = Group(engine, objects[1], objects[3])
      place!(engine, group, group |> at((10, 10)))
      compute_layout!(engine)
      @test get_coordinates(engine, group) == [86, 41.25]
      @test ecs[objects[1], LOCATION_COMPONENT_ID] == 10 .+ locations[1]
      @test ecs[objects[2], LOCATION_COMPONENT_ID] == locations[2]
      @test ecs[objects[3], LOCATION_COMPONENT_ID] == 10 .+ locations[3]
    end
  end
end;
