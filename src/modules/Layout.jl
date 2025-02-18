module Layout

using Accessors: @set
using ForwardMethods: @forward_methods
using MLStyle: @match, @switch, @when
using StaticArrays: SVector
using Graphs
using GeometryExperiments: GeometryExperiments, boundingelement, Box, centroid

using Base: RefValue
using Core: OpaqueClosure
using Base.Experimental: @opaque

const Optional{T} = Union{Nothing, T}

"""
    LayoutStorage{O,P,C,G}

Abstract type for a layout storage where:
- `O` represents the type of objects to be laid out by the engine, e.g. `Widget`.
- `P` is the type of position values to be manipulated, e.g. `SVector{2,Float64}`.
- `C` is the coordinate type for the position, which will usually be the same as `P`.
- `G` is the type of geometry to be manipulated, e.g. `Box{2,Float64}`.

!!! note
    `P` and `C` were made to be different parameters such that a given position type is allowed to differ from the numerical type that represents its data. For example, with `struct LocationComponent; metadata::Any; coords::SVector{2,Float64}; end`, `LocationComponent` is the position type `P`, while `SVector{2,Float64}` is the coordinate type `C`. This relaxation is meant to facilitate integration with larger codebases that may have their custom data structures.
"""
abstract type LayoutStorage{O,P,C,G} end

object_type(::LayoutStorage{O}) where {O} = O
position_type(::LayoutStorage{<:Any,P}) where {P} = P
coordinate_type(::LayoutStorage{<:Any,<:Any,C}) where {C} = C
geometry_type(::LayoutStorage{<:Any,<:Any,<:Any,G}) where {G} = G

Base.broadcastable(storage::LayoutStorage) = Ref(storage)

"""
    coordinates(storage::LayoutStorage{<:Any,P,C}, position::P)::C where {P,C}
"""
function coordinates end

"""
    get_position(storage::LayoutStorage{O,P}, object::O)::P where {O,P}
"""
function get_position end

"""
    set_position!(storage::LayoutStorage{O,P}, object::O, position::P) where {O,P}
"""
function set_position! end

"""
    get_geometry(storage::LayoutStorage{O,<:Any,<:Any,G}, object::O)::G where {O,G}
"""
function get_geometry end

coordinates(storage::LayoutStorage{<:Any,P,P}, position::P) where {P} = position
get_coordinates(storage::LayoutStorage{O,P}, object::O) where {O,P} = coordinates(storage, get_position(storage, object))
set_coordinates(storage::LayoutStorage{<:Any,T,T}, position::T, coords::T) where {T} = coords
# will also need similar functions to access geometry

@enum FeatureLocation begin
  FEATURE_LOCATION_CENTER   = 1
  FEATURE_LOCATION_ORIGIN   = 2
  FEATURE_LOCATION_CORNER   = 3
  FEATURE_LOCATION_EDGE     = 4
  FEATURE_LOCATION_GEOMETRY = 5
  FEATURE_LOCATION_CUSTOM   = 6
end

function FeatureLocation(name::Symbol)
  names = (:center, :origin, :corner, :edge, :custom)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  FeatureLocation(i)
end

struct Group{O}
  objects::Any
  Group{O}(objects) where {O} = new{O}(convert(Vector{GroupElement{O}}, objects))
end

Base.broadcastable(group::Group) = Ref(group)
Base.iterate(group::Group) = (group, nothing)
Base.iterate(group::Group, state) = nothing

function Base.getproperty(group::Group{O}, name::Symbol) where {O}
  name === :objects && return getfield(group, name)::Vector{GroupElement{O}}
  getfield(group, name)
end

struct PositionalFeature{O}
  "Object the feature is attached to."
  object::Union{PositionalFeature{O},O,Group{O}}
  location::FeatureLocation
  "Position of the feature relative to the origin (position) of the object."
  data::Any
end

PositionalFeature(object, location::FeatureLocation) = PositionalFeature(object, location, nothing)

Base.iterate(feature::PositionalFeature) = (feature, nothing)
Base.iterate(feature::PositionalFeature, state) = nothing
Base.broadcastable(feature::PositionalFeature) = Ref(feature)

function Base.getindex(feature::PositionalFeature{O}) where {O}
  (; object) = feature
  while isa(object, PositionalFeature{O})
    (; object) = object
  end
  object
end

const GroupElement{O} = Union{O,Group{O}}

struct ObjectData{P,G}
  index::Int
  position::P
  geometry::G
end

ObjectData(engine, i, object) = ObjectData(i, get_position(engine, object), get_geometry(engine, object))

get_position(object::ObjectData) = object.position
get_geometry(object::ObjectData) = object.geometry

set_position(object::ObjectData, position) = @set object.position = position
set_geometry(object::ObjectData, geometry) = @set object.geometry = geometry

struct Operation{O,OD<:ObjectData}
  callable::OpaqueClosure{Tuple{Vector{OD},Vector{OD}}, Nothing}
  by::Optional{Union{PositionalFeature{O}, Vector{PositionalFeature{O}}}}
  on::Union{PositionalFeature{O}, Vector{PositionalFeature{O}}}
  may_cache::Bool
  result::Vector{OD}
end

broadcast_positional_feature(engine, object) = positional_feature(engine, object)
broadcast_positional_feature(engine, objects::AbstractVector) = positional_feature.(engine, objects)

function Operation(f!, engine, by, on)
  OD = object_data_type(engine)
  callable = @opaque (outputs::Vector{OD}, inputs::Vector{OD}) -> begin
    f!(outputs, inputs)
    nothing
  end
  O = object_type(engine)
  !isnothing(by) && (by = broadcast_positional_feature(engine, by))
  on = broadcast_positional_feature(engine, on)
  Operation{O,OD}(callable, by, on, may_cache(engine, by, on), OD[])
end

function may_cache(engine, inputs, outputs)
  C = coordinate_type(engine)
  any(input -> contains_ref(C, input), inputs) && return false
  any(output -> contains_ref(C, output), outputs) && return false
  # true
  false
end

contains_ref(::Type{C}, group::Group) where {C} = any(object -> contains_ref(C, object), group.objects)
contains_ref(::Type{C}, object) where {C} = false

function contains_ref(::Type{C}, feature::PositionalFeature) where {C}
  uses_ref(C, feature) || contains_ref(C, feature.object)
end

function uses_ref(::Type{C}, feature) where {C}
  feature.location === FEATURE_LOCATION_CUSTOM || return false
  isa(feature.data, RefValue{C}) && return true
  T = eltype(C)
  isa(feature.data, RefValue{T}) && return true
  false
end

struct LayoutEngine{O,S<:LayoutStorage{O},OP<:Operation{O}}
  storage::S
  operations::Vector{OP}
end

function LayoutEngine(storage::LayoutStorage{O}) where {O}
  OD = object_data_type(storage)
  OP = Operation{O,OD}
  LayoutEngine{O,typeof(storage),OP}(storage, OP[])
end

function object_data_type(storage::LayoutStorage)
  P = position_type(storage)
  G = geometry_type(storage)
  ObjectData{P,G}
end

@forward_methods LayoutEngine field = :storage begin
  object_type
  position_type
  coordinate_type
  geometry_type
  object_data_type
  get_geometry(_, object)
  set_geometry!(_, object, geometry)
  coordinates(_, x)
  get_coordinates(_, object)
  set_coordinates(_, position, coords)
  get_position(_, object)
  set_position!(_, object, position)
end

get_position(engine::LayoutEngine, feature::PositionalFeature) = get_coordinates(engine, feature)
get_geometry(engine::LayoutEngine, feature::PositionalFeature) = get_geometry(engine, feature[])

function set_position!(engine::LayoutEngine, feature::PositionalFeature, position)
  object = feature[]
  displacement = get_coordinates(engine, feature) .- get_coordinates(engine, object)
  set_position!(engine, object, position .- displacement)
end
set_geometry!(engine::LayoutEngine, feature::PositionalFeature, geometry) = set_geometry!(engine, feature[], geometry)
set_geometry!(engine::LayoutEngine, group::Group, geometry) = error("Setting geometry for groups is not supported")

Base.broadcastable(engine::LayoutEngine) = Ref(engine)

to_object(::Type{O}, object::O) where {O} = object
to_object(::Type{O}, feature::PositionalFeature{O}) where {O} = feature
to_object(::Type{O}, group::Group{O}) where {O} = group
to_object(::Type{O}, object) where {O} = convert(O, object)
to_object(engine::LayoutEngine{O}, object) where {O} = to_object(O, object)

positional_feature(::Type{O}, object::O) where {O} = PositionalFeature(object, FEATURE_LOCATION_ORIGIN)
positional_feature(::Type{O}, group::Group{O}) where {O} = PositionalFeature(group, FEATURE_LOCATION_ORIGIN)
positional_feature(::Type{O}, feature::PositionalFeature{O}) where {O} = feature
positional_feature(::Type{O}, object) where {O} = positional_feature(O, to_object(O, object))
positional_feature(engine::LayoutEngine{O}, object) where {O} = positional_feature(O, object)

function find_operations_using(engine::LayoutEngine, object)
  O = object_type(engine)
  object = to_object(engine, object)
  indices = Int[]
  for (i, operation) in enumerate(engine.operations)
    if !isnothing(operation.by) && any(by[] == object for by in operation.by)
      push!(indices, i)
      continue
    end
    on = @match operation.on begin
      on::PositionalFeature{O} => [on]
      on::Vector{PositionalFeature{O}} => on
    end
    any(x -> in_feature(object, x), on) && push!(indices, i)
  end
  indices
end

remove_operations!(engine::LayoutEngine) = empty!(engine.operations)
function remove_operations!(engine::LayoutEngine, object)
  to_delete = find_operations_using(engine, object)
  isempty(to_delete) && return false
  splice!(engine.operations, to_delete)
  true
end

function invalidate!(operation::Operation)
  isempty(operation.result) && return false
  empty!(operation.result)
  true
end

function invalidate!(engine::LayoutEngine, object)
  invalidated = 0
  for i in find_operations_using(engine, object)
    invalidated += invalidate!(engine.operations[i])
  end
  invalidated
end

function in_feature(object::O, feature::PositionalFeature{O}) where {O}
  @match feature[] begin
    item::O => item == object
    group::Group{O} => in_group(object, group)
  end
end

function in_group(object::O, group::Group{O}) where {O}
  for item in group.objects
    found = @match item begin
      ::Group{O} => in_group(object, item)
      ::O => item == object
    end
    found && return true
  end
  false
end

to_group_element(engine, x) = to_object(engine, x)
to_group_element(engine, feature::PositionalFeature) = throw(ArgumentError("Positional features are not supported within groups. A group accepts objects or other groups."))

Group{O}(engine::LayoutEngine{O}, object, objects...) where {O} = Group{O}(engine, to_group_element.(engine, ((object, objects...))))
Group(engine::LayoutEngine, args...) = Group{object_type(engine)}(engine, args...)
function Group{O}(engine::LayoutEngine{O}, objects::Tuple) where {O}
  length(objects) > 1 || throw(ArgumentError("More than one objects are required to form a group"))
  Group{O}(GroupElement{O}[objects...])
end

get_coordinates(engine::LayoutEngine, group::Group) = centroid(boundingelement(engine, group))
get_position(engine::LayoutEngine, group::Group) = get_coordinates(engine, group)

function GeometryExperiments.boundingelement(engine::LayoutEngine, group::Group)
  object = group.objects[1]
  objects = @view group.objects[2]
  geometry = get_geometry(engine, object) + get_position(engine, object)
  foldl((x, y) -> boundingelement(x, get_geometry(engine, y) + get_position(engine, y)), objects; init = geometry)::geometry_type(engine)
end

function get_geometry(engine::LayoutEngine, group::Group)
  geometry = boundingelement(engine, group)
  geometry - centroid(geometry)
end

function set_position!(engine::LayoutEngine, group::Group, position)
  offset = position .- get_position(engine, group)
  for object in group.objects
    set_position!(engine, object, get_position(engine, object) .+ offset)
  end
end

"""
Array-backed layout storage, where "objects" are indices to `Vector`s of positions and geometries.
"""
struct ArrayLayoutStorage{O,P,C,G} <: LayoutStorage{O,P,C,G}
  positions::Vector{P}
  geometries::Vector{G}
end

get_position(storage::ArrayLayoutStorage{O}, object::O) where {O} = storage.positions[object]
set_position!(storage::ArrayLayoutStorage{O,P}, object::O, position::P) where {O,P} = storage.positions[object] = position
get_geometry(storage::ArrayLayoutStorage{O}, object::O) where {O} = storage.geometries[object]
set_geometry!(storage::ArrayLayoutStorage{O,<:Any,<:Any,G}, object::O, geometry::G) where {O,G} = storage.geometries[object] = geometry

ArrayLayoutStorage{P,G}() where {P,G} = ArrayLayoutStorage{P,P,G}()
ArrayLayoutStorage{P,C,G}() where {P,C,G} = ArrayLayoutStorage{Int64,P,C,G}()
ArrayLayoutStorage{O,P,C,G}() where {O,P,C,G} = ArrayLayoutStorage{O,P,C,G}(P[], G[])
ArrayLayoutStorage(positions, geometries) = ArrayLayoutStorage{Int64}(positions, geometries)
ArrayLayoutStorage{O}(positions::AbstractVector{P}, geometries::AbstractVector{G}) where {O,P,G} = ArrayLayoutStorage{O,P,P,G}(positions, geometries)

@enum Edge begin
  EDGE_LEFT = 1
  EDGE_RIGHT = 2
  EDGE_BOTTOM = 3
  EDGE_TOP = 4
end

const EDGE_NAMES = (:left, :right, :bottom, :top)

function Edge(name::Symbol)
  i = findfirst(==(name), EDGE_NAMES)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $EDGE_NAMES"))
  Edge(i)
end

@enum Corner begin
  CORNER_BOTTOM_LEFT = 1
  CORNER_BOTTOM_RIGHT = 2
  CORNER_TOP_LEFT = 3
  CORNER_TOP_RIGHT = 4
end

const CORNER_NAMES = (:bottom_left, :bottom_right, :top_left, :top_right)

function Corner(name::Symbol)
  i = findfirst(==(name), CORNER_NAMES)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $CORNER_NAMES"))
  Corner(i)
end

@enum GeometryAttribute begin
  GEOMETRY_ATTRIBUTE_WIDTH  = 1
  GEOMETRY_ATTRIBUTE_HEIGHT = 2
end

struct GeometryFeature
  attribute::GeometryAttribute
  fraction::Float64
end

GeometryFeature(attribute) = GeometryFeature(attribute, 1.0)

width_of(object) = PositionalFeature(object, FEATURE_LOCATION_GEOMETRY, GeometryFeature(GEOMETRY_ATTRIBUTE_WIDTH))
height_of(object) = PositionalFeature(object, FEATURE_LOCATION_GEOMETRY, GeometryFeature(GEOMETRY_ATTRIBUTE_HEIGHT))

Base.:(*)(x::Real, ::typeof(width_of)) = object -> x * width_of(object)
Base.:(*)(x::Real, ::typeof(height_of)) = object -> x * height_of(object)

Base.:(*)(::typeof(width_of), x::Real) = x * width_of
Base.:(*)(::typeof(height_of), x::Real) = x * height_of

Base.:(*)(x::Real, feature::GeometryFeature) = GeometryFeature(feature.attribute, feature.fraction * x)
Base.:(*)(feature::GeometryFeature, x::Real) = x * feature

function Base.:(*)(x::Real, feature::PositionalFeature)
  feature.location == FEATURE_LOCATION_GEOMETRY || error("Multiplication is only supported with geometry features")
  @set feature.data = x * feature.data
end
Base.:(*)(feature::PositionalFeature, x::Real) = x * feature

FeatureLocation(::Edge) = FEATURE_LOCATION_EDGE
FeatureLocation(::Corner) = FEATURE_LOCATION_CORNER
FeatureLocation(::GeometryFeature) = FEATURE_LOCATION_GEOMETRY

PositionalFeature(object, edge::Edge) = PositionalFeature(object, FeatureLocation(edge), edge)
PositionalFeature(object, corner::Corner) = PositionalFeature(object, FeatureLocation(corner), corner)

function PositionalFeature(object, name::Symbol)
  name === :origin && return PositionalFeature(object, FEATURE_LOCATION_ORIGIN)
  name === :center && return PositionalFeature(object, FEATURE_LOCATION_CENTER)
  in(name, EDGE_NAMES) && return PositionalFeature(object, Edge(name))
  in(name, CORNER_NAMES) && return PositionalFeature(object, Corner(name))
  throw(ArgumentError("Unrecognized positional feature $(repr(name)); available features are $(join(repr.((:origin, :center, EDGE_NAMES..., CORNER_NAMES...)), ", "))"))
end

function get_relative_coordinates(engine::LayoutEngine, feature::PositionalFeature)
  C = coordinate_type(engine)
  T = eltype(C)
  @match feature.location begin
    &FEATURE_LOCATION_ORIGIN => zero(C)
    &FEATURE_LOCATION_CENTER => centroid(get_geometry(engine, feature[]))
    &FEATURE_LOCATION_CORNER => coordinates(get_geometry(engine, feature[])::Box{2,T}, feature.data::Corner)
    &FEATURE_LOCATION_EDGE => coordinates(get_geometry(engine, feature[])::Box{2,T}, feature.data::Edge)
    &FEATURE_LOCATION_GEOMETRY => coordinates(get_geometry(engine, feature[])::Box{2,T}, feature.data::GeometryFeature)
    &FEATURE_LOCATION_CUSTOM => extract_custom_attribute(feature.data::Union{T, C, RefValue{T}, RefValue{C}})::Union{T, C}
  end
end

extract_custom_attribute(attribute::RefValue) = attribute[]
extract_custom_attribute(attribute) = attribute

add_coordinates(x, y) = x .+ y

function get_coordinates(engine::LayoutEngine, feature::PositionalFeature)
  C = coordinate_type(engine)
  T = eltype(C)
  absolute = get_coordinates(engine, feature.object)::C
  relative = get_relative_coordinates(engine, feature)::Union{C, T}
  add_coordinates(absolute, relative)
end

function coordinates(geometry::Box{2}, corner::Corner)
  @match corner begin
    &CORNER_BOTTOM_LEFT => geometry.bottom_left
    &CORNER_BOTTOM_RIGHT => geometry.bottom_right
    &CORNER_TOP_LEFT => geometry.top_left
    &CORNER_TOP_RIGHT => geometry.top_right
  end
end

function coordinates(geometry::Box{2,T}, edge::Edge) where {T}
  @match edge begin
    &EDGE_LEFT => 0.5 .* (geometry.bottom_left .+ geometry.top_left)
    &EDGE_RIGHT => 0.5 .* (geometry.bottom_right .+ geometry.top_right)
    &EDGE_BOTTOM => 0.5 .* (geometry.bottom_left .+ geometry.bottom_right)
    &EDGE_TOP => 0.5 .* (geometry.top_left .+ geometry.top_right)
  end
end

function coordinates(geometry::Box{2,T}, feature::GeometryFeature) where {T}
  feature.attribute == GEOMETRY_ATTRIBUTE_WIDTH && return SVector{2,T}(geometry.width * feature.fraction, 0.0)
  feature.attribute == GEOMETRY_ATTRIBUTE_HEIGHT && return SVector{2,T}(0.0, geometry.height * feature.fraction)
  @assert false
end

# Closures.
at(engine::LayoutEngine, x::Real, y::Real) = at(engine, (x, y))
at(engine::LayoutEngine, (x, y)::Tuple) = at(engine, SVector(x, y))
at(engine::LayoutEngine, p::SVector{2}) = x -> at(engine, x, p)
at(engine::LayoutEngine, coord::Real) = x -> at(engine, x, coord)
at(engine::LayoutEngine, p::RefValue) = x -> at(engine, x, p)
at(engine::LayoutEngine, location::Symbol) = x -> at(engine, x, location)

at(engine::LayoutEngine, object) = positional_feature(engine, object)
function at(engine::LayoutEngine{O}, object, position::Real) where {O}
  C = coordinate_type(engine)
  T = eltype(C)
  position = convert(T, position)::T
  at(O, to_object(engine, object), FEATURE_LOCATION_CUSTOM, position)
end
function at(engine::LayoutEngine{O}, object, position) where {O}
  C = coordinate_type(engine)
  T = eltype(C)
  if isa(position, RefValue)
    isa(position, RefValue{T}) || isa(position, RefValue{C}) || throw(ArgumentError("If a `Ref` is provided for a custom feature location, it must be of type $T or of type $C; automatic conversion cannot be made for mutable objects"))
    at(O, to_object(engine, object), FEATURE_LOCATION_CUSTOM, position)
  else
    position = convert(C, position)::C
    at(O, to_object(engine, object), FEATURE_LOCATION_CUSTOM, position)
  end
end
at(engine::LayoutEngine{O}, object, location::FeatureLocation, argument = nothing) where {O} = at(O, to_object(engine, object), location, argument)
function at(::Type{O}, object::Union{O, PositionalFeature{O}, Group{O}}, location::FeatureLocation, argument = nothing) where {O}
  if location in (FEATURE_LOCATION_ORIGIN, FEATURE_LOCATION_CENTER)
    isnothing(argument) || throw(ArgumentError("No argument must be provided for feature location in (`FEATURE_LOCATION_ORIGIN`, `FEATURE_LOCATION_CENTER`)"))
  elseif location == FEATURE_LOCATION_CORNER
    isa(argument, Corner) || throw(ArgumentError("`$location` requires a `Corner` argument"))
  elseif location == FEATURE_LOCATION_EDGE
    isa(argument, Edge) || throw(ArgumentError("`$location` requires an `Edge` argument"))
  elseif location == FEATURE_LOCATION_CUSTOM
    !isnothing(location) || throw(ArgumentError("`$location` requires an argument"))
  end
  PositionalFeature(object, location, argument)
end
at(engine::LayoutEngine{O}, object, location::Symbol) where {O} = PositionalFeature(to_object(engine, object), location)

@enum Direction begin
  DIRECTION_HORIZONTAL = 1
  DIRECTION_VERTICAL = 2
end
other_axis(direction) = Direction(3 - Int(direction))

function Direction(name::Symbol)
  names = (:horizontal, :vertical)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  Direction(i)
end

"""
Specify which notion of distance to use for spacing out objects.

Either we're talking about point distances, or we're talking about gaps between objects.
"""
@enum SpacingMode begin
  SPACING_MODE_POINT = 1
  SPACING_MODE_GEOMETRY = 2
end

"Consider the distance to be that between feature points."
SPACING_MODE_POINT
"Consider the distance to be that between the geometries of the objects."
SPACING_MODE_GEOMETRY

function SpacingMode(name::Symbol)
  names = (:point, :geometry)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  SpacingMode(i)
end

function pinned_part(part::Symbol)
  in(part, (:left, :right, :bottom, :top)) && return Edge(part)
  in(part, (:bottom_left, :bottom_right, :top_left, :top_right)) && return Corner(part)
  throw(ArgumentError("Expected part to designate an edge or corner, got $part"))
end

# Apply operations.

function compute_layout!(engine::LayoutEngine)
  OD = object_data_type(engine)
  O = object_type(engine)
  inputs = OD[]
  previous = OD[]
  for operation in engine.operations
    outputs = operation.result

    if operation.may_cache && !isempty(outputs)
      for (output, feature) in zip(outputs, operation.on)
        set_position!(engine, feature, output.position)
        isa(feature[], Group{O}) && continue
        set_geometry!(engine, feature, output.geometry)
      end
      continue
    end
    @debug "Computing layout for $operation"

    empty!(inputs)
    empty!(previous)
    empty!(outputs)
    if !isnothing(operation.by)
      for (i, object) in enumerate(operation.by) push!(inputs, ObjectData(engine, i, object)) end
    end
    for (i, object) in enumerate(operation.on) push!(outputs, ObjectData(engine, i, object)) end
    append!(previous, outputs)
    operation.callable(outputs, inputs)
    length(previous) == length(outputs) || error("Pushing and deleting output objects is not allowed")
    for (previous, output, feature) in zip(previous, outputs, operation.on)
      previous.position ≠ output.position && set_position!(engine, feature, output.position)
      previous.geometry ≠ output.geometry && set_geometry!(engine, feature, output.geometry)
    end
  end
end

# Record operations.

record!(engine::LayoutEngine, operation::Operation) = push!(engine.operations, operation)
record!(f!, engine::LayoutEngine, input, output) = record!(engine, Operation(f!, engine, input, output))
record!(f!, engine::LayoutEngine, object) = record!(f!, engine, object, object)

function apply_place!(outputs::Vector{<:ObjectData}, inputs::Vector{<:ObjectData})
  outputs .= set_position.(outputs, get_position.(inputs))
end

place!(engine::LayoutEngine, object, onto) = record!(apply_place!, engine, onto, object)

function place_after!(engine::LayoutEngine, object, after; spacing = 0.0, direction::Union{Symbol, Direction} = DIRECTION_HORIZONTAL)
  isa(direction, Symbol) && (direction = Direction(direction))
  offset = direction == DIRECTION_HORIZONTAL ? (spacing, 0.0) : (0.0, spacing)
  place!(engine, at(engine, object, :left), after |> at(engine, :right) |> at(engine, offset))
end

function apply_align!(target::F, outputs::Vector{<:ObjectData}, inputs::Vector{<:ObjectData}, direction::Direction) where {F}
  i = Int(other_axis(direction))
  alignment = target(get_position(input)[i] for input in inputs)
  project = (position, value) -> @set position[i] = value
  outputs .= set_position.(outputs, project.(get_position.(outputs), alignment))
end

function align!(target, engine::LayoutEngine, objects, onto, direction)
  isa(direction, Symbol) && (direction = Direction(direction))
  record!((outputs, inputs) -> apply_align!(target, outputs, inputs, direction), engine, onto, objects)
end

align!(target, engine::LayoutEngine, objects, direction) = align!(target, engine, objects, objects, direction)

align!(engine::LayoutEngine, objects, args...) = align!(average, engine, objects, args...)

average(xs) = sum(xs) ./ length(xs)

function apply_distribute!(outputs::Vector{<:ObjectData}, inputs::Vector{<:ObjectData}, direction::Direction, mode::SpacingMode, spacing::Union{Float64, F}) where {F<:Function}
  spacing = compute_spacing(inputs, direction, spacing)
  for i in 2:length(outputs)
    outputs[i] = apply_spacing(outputs[i], outputs[i - 1], direction, mode, spacing)
  end
end

function compute_spacing(objects, direction::Direction, spacing::F) where {F<:Union{Float64, Function}}
  isa(spacing, Float64) && return spacing
  xs, ys = @view(objects[1:(end - 1)]), @view(objects[2:end])
  i = Int(other_axis(direction))
  spacings = map(((x, y),) -> x.position[i] - y.position[i], zip(xs, ys))
  spacing(spacings)::Float64
end

function apply_spacing(object, reference, direction::Direction, mode::SpacingMode, spacing::Float64)
  @when &SPACING_MODE_GEOMETRY = mode begin
    spacing += @match direction begin
      &DIRECTION_HORIZONTAL => (object.geometry.width + reference.geometry.width) / 2
      &DIRECTION_VERTICAL => (object.geometry.height + reference.geometry.height) / 2
    end
  end
  i = Int(direction)
  # Negate vertical spacing so that objects are laid out from top to bottom
  spacing *= ifelse(direction == DIRECTION_VERTICAL, -1, 1)
  @set object.position[i] = reference.position[i] + spacing
end

function distribute!(engine::LayoutEngine, objects, onto, direction; mode = SPACING_MODE_POINT, spacing = average)
  isa(direction, Symbol) && (direction = Direction(direction))
  isa(mode, Symbol) && (mode = SpacingMode(mode))
  isa(spacing, Real) && (spacing = convert(Float64, spacing))
  record!((outputs, inputs) -> apply_distribute!(outputs, inputs, direction, mode, spacing), engine, onto, objects)
end

function distribute!(engine::LayoutEngine, objects, direction; mode = SPACING_MODE_POINT, spacing = average)
  distribute!(engine, objects, objects, direction; mode, spacing)
end

function apply_pin!(outputs::Vector{<:ObjectData}, inputs::Vector{<:ObjectData}, part::Union{Edge, Corner}, offset::Float64)
  outputs .= pin_geometry.(outputs, inputs, part, offset)
end

function pin_geometry(object::ObjectData, target::ObjectData, part::Union{Edge, Corner}, offset::Float64)
  displacement = target.position .+ offset .- (object.position .+ coordinates(object.geometry, part))
  dx, dy = displacement
  (; geometry) = object
  pinned_geometry = @match part begin
    &CORNER_BOTTOM_LEFT => Box(geometry.min .+ displacement, geometry.max)
    &CORNER_BOTTOM_RIGHT => Box(geometry.min .+ (zero(dy), dy), geometry.max .+ (dx, zero(dx)))
    &CORNER_TOP_LEFT => Box(geometry.min .+ (dx, zero(dx)), geometry.max .+ (zero(dy), dy))
    &CORNER_TOP_RIGHT => Box(geometry.min, geometry.max .+ displacement)
    &EDGE_LEFT => Box(geometry.min .+ (dx, zero(dx)), geometry.max)
    &EDGE_RIGHT => Box(geometry.min, geometry.max .+ (dx, zero(dx)))
    &EDGE_BOTTOM => Box(geometry.min .+ (zero(dy), dy), geometry.max)
    &EDGE_TOP => Box(geometry.min, geometry.max .+ (zero(dy), dy))
  end
  set_geometry(object, pinned_geometry)
end

function pin!(engine::LayoutEngine{O}, object, part, to; offset = 0.0) where {O}
  isa(part, Symbol) && (part = pinned_part(part))
  offset = convert(Float64, offset)
  record!((outputs, inputs) -> apply_pin!(outputs, inputs, part, offset), engine, to, object)
end

export
  LayoutEngine,
  LayoutStorage, ECSLayoutStorage, ArrayLayoutStorage,
  compute_layout!,
  place!, place_after!, align!, distribute!, pin!,
  remove_operations!,

  Operation,
  PositionalFeature, width_of, height_of,
  FEATURE_LOCATION_ORIGIN,
  FEATURE_LOCATION_CENTER,
  FEATURE_LOCATION_CORNER,
  FEATURE_LOCATION_EDGE,
  FEATURE_LOCATION_GEOMETRY,
  FEATURE_LOCATION_CUSTOM,
  Corner,
  CORNER_BOTTOM_LEFT,
  CORNER_BOTTOM_RIGHT,
  CORNER_TOP_LEFT,
  CORNER_TOP_RIGHT,
  Direction,
  DIRECTION_HORIZONTAL,
  DIRECTION_VERTICAL,
  SpacingMode,
  SPACING_MODE_POINT,
  SPACING_MODE_GEOMETRY

end # module
