module Layout

using Accessors: @set
using ForwardMethods: @forward_methods
using MLStyle: @match, @switch, @when
using StaticArrays: SVector
using Graphs
using GeometryExperiments: GeometryExperiments, boundingelement, Box, centroid

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

function Base.getindex(feature::PositionalFeature{O}) where {O}
  (; object) = feature
  while isa(object, PositionalFeature{O})
    (; object) = object
  end
  object
end

const GroupElement{O} = Union{O,Group{O}}

@enum OperationType begin
  OPERATION_TYPE_PLACE
  OPERATION_TYPE_ALIGN
  OPERATION_TYPE_DISTRIBUTE
  OPERATION_TYPE_PIN
end

# TODO: Update docstrings.
"Attach two features together, resulting in an identical position for both."
OPERATION_TYPE_PLACE
"""
Position a set of features on a line along a [`Direction`](@ref), either along a horizontal (i.e. the vertical position is set to rest on a horizontal line) or along a vertical (the horizontal position is set to rest on a vertical line).
"""
OPERATION_TYPE_ALIGN
"""
Evenly space out a set of features along a [`Direction`](@ref).

The notion of "space" may be defined with respect to points, or to geometries: either we talk about the distance between points, or about the distance between geometries.

The desired spacing may be provided as a floating point value. However, for convenience, we also allow a [`SpacingAmount`](@ref) value, which will automatically compute the required spacing depending on the desired behavior.

Automatic spacing includes taking the minimum, maximum or average of the distances between the provided features. Which notion of distance is used depends on the mode (see [`SpacingMode`](@ref)).

Providing any positional feature for a [`SPACING_MODE_GEOMETRY`](@ref) mode will result in considering the geometry of associated objects to be offset by the relative offset between the feature and the center of the geometry. Therefore, the spacing will not appear even if any positional features are not positioned to the center of the objects.
"""
OPERATION_TYPE_DISTRIBUTE

struct Operation{O}
  type::OperationType
  by::Optional{PositionalFeature{O}}
  on::Union{PositionalFeature{O}, Vector{PositionalFeature{O}}}
  data::Any
end

function Base.getproperty(operation::Operation{O}, name::Symbol) where {O}
  name === :alignment && return getfield(operation, :data)::Alignment{O}
  name === :spacing && return getfield(operation, :data)::Spacing
  name === :pinning && return getfield(operation, :data)::PinningParameters
  getfield(operation, name)
end

struct LayoutEngine{O,S<:LayoutStorage{O}}
  storage::S
  operations::Vector{Operation{O}}
end
LayoutEngine(storage::LayoutStorage{O}) where {O} = LayoutEngine{O,typeof(storage)}(storage, Operation{O}[])

@forward_methods LayoutEngine field = :storage begin
  object_type
  position_type
  coordinate_type
  geometry_type
  get_geometry(_, object)
  set_geometry!(_, object, geometry)
  coordinates(_, x)
  get_coordinates(_, object)
  set_coordinates(_, position, coords)
  get_position(_, object)
  set_position!(_, object, position)
end

Base.broadcastable(engine::LayoutEngine) = Ref(engine)

to_object(engine::LayoutEngine{O}, object::O) where {O} = object
to_object(engine::LayoutEngine{O}, feature::PositionalFeature{O}) where {O} = feature
to_object(engine::LayoutEngine{O}, group::Group{O}) where {O} = group
to_object(engine::LayoutEngine{O}, object) where {O} = convert(O, object)

positional_feature(::Type{O}, object::O) where {O} = PositionalFeature(object, FEATURE_LOCATION_ORIGIN)
positional_feature(::Type{O}, group::Group{O}) where {O} = PositionalFeature(group, FEATURE_LOCATION_ORIGIN)
positional_feature(::Type{O}, feature::PositionalFeature{O}) where {O} = feature
positional_feature(engine::LayoutEngine{O}, object) where {O} = positional_feature(O, to_object(engine, object))

remove_operations!(engine::LayoutEngine) = empty!(engine.operations)
function remove_operations!(engine::LayoutEngine{O}, object) where {O}
  object = to_object(engine, object)
  to_delete = Int[]
  for (i, operation) in enumerate(engine.operations)
    if !isnothing(operation.by) && operation.by[] == object
      push!(to_delete, i)
      continue
    end
    on = @match operation.on begin
      on::PositionalFeature{O} => [on]
      on::Vector{PositionalFeature{O}} => on
    end
    any(x -> in_feature(object, x), on) && push!(to_delete, i)
  end
  isempty(to_delete) && return false
  splice!(engine.operations, to_delete)
  true
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

Group(engine::LayoutEngine, object, objects...) = Group(engine, to_group_element.(engine, ((object, objects...))))
function Group(engine::LayoutEngine{O}, objects::Tuple) where {O}
  length(objects) > 1 || throw(ArgumentError("More than one objects are required to form a group"))
  Group{O}(GroupElement{O}[objects...])
end

get_coordinates(engine::LayoutEngine, group::Group) = centroid(boundingelement(engine, group))
get_position(engine::LayoutEngine, group::Group) = get_coordinates(engine, group)

function GeometryExperiments.boundingelement(engine::LayoutEngine, group::Group)
  object, objects = Iterators.peel(group.objects)
  geometry = get_geometry(engine, object) + get_position(engine, object)
  foldl((x, y) -> boundingelement(x, get_geometry(engine, y) + get_position(engine, y)), objects; init = geometry)
end
 
function get_geometry(engine::LayoutEngine, group::Group)
  geometry = boundingelement(engine, group)
  geometry - centroid(geometry)
end
 
get_relative_coordinates(engine::LayoutEngine, group::Group) = get(engine.group_positions, group, zero(position_type(engine)))
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

function compute_layout!(engine::LayoutEngine{O}) where {O}
  for operation in engine.operations
    apply_operation!(engine, operation)
  end
end

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
    &FEATURE_LOCATION_CUSTOM => feature.data
  end
end

add_coordinates(x, y) = x .+ y

get_coordinates(engine::LayoutEngine, feature::PositionalFeature) = add_coordinates(get_coordinates(engine, feature.object), get_relative_coordinates(engine, feature))

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
at(engine::LayoutEngine, location::Symbol) = x -> at(engine, x, location)

at(engine::LayoutEngine, object) = positional_feature(engine, object)
at(engine::LayoutEngine{O}, object, position) where {O} = at(O, to_object(engine, object), FEATURE_LOCATION_CUSTOM, position)
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

@enum AlignmentTarget begin
  ALIGNMENT_TARGET_MINIMUM = 1
  ALIGNMENT_TARGET_MAXIMUM = 2
  ALIGNMENT_TARGET_AVERAGE = 3
end

struct Alignment{O}
  direction::Direction
  target::Union{AlignmentTarget,PositionalFeature{O}}
end
Alignment{O}(direction::Symbol, target) where {O} = Alignment{O}(Direction(direction), target)

@enum SpacingAmount begin
  SPACING_TARGET_MINIMUM = 1
  SPACING_TARGET_MAXIMUM = 2
  SPACING_TARGET_AVERAGE = 3
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

struct Spacing
  direction::Direction
  amount::Union{Float64,SpacingAmount}
  mode::SpacingMode
  Spacing(direction::Direction, amount::Real, mode) = new(direction, convert(Float64, amount), mode)
  Spacing(direction::Direction, amount::SpacingAmount, mode) = new(direction, amount, mode)
end
Spacing(direction::Symbol, amount, mode) = Spacing(Direction(direction), amount, mode)
Spacing(direction, amount, mode::Symbol) = Spacing(direction, amount, SpacingMode(mode))
Spacing(direction::Symbol, amount, mode::Symbol) = Spacing(Direction(direction), amount, SpacingMode(mode))

function pinned_part(part::Symbol)
  in(part, (:left, :right, :bottom, :top)) && return Edge(part)
  in(part, (:bottom_left, :bottom_right, :top_left, :top_right)) && return Corner(part)
  throw(ArgumentError("Expected part to designate an edge or corner, got $part"))
end

struct PinningParameters
  part::Union{Edge, Corner}
  offset::Float64
end

function PinningParameters(part::Symbol, offset)
  part = pinned_part(part)
  PinningParameters(part, offset)
end

# Apply operations.

function apply_operation!(engine::LayoutEngine{O}, operation::Operation) where {O}
  @switch operation.type begin
    @case &OPERATION_TYPE_PLACE
    operand = operation.on::PositionalFeature{O}
    old = get_position(engine, operand[])
    new = set_coordinates(engine, old, apply_place_operation(engine, operation, coordinates(engine, old)))
    old ≠ new && set_position!(engine, operand[], new)

    @case &OPERATION_TYPE_ALIGN
    alignment = compute_alignment(engine, operation)
    for feature in operation.on
      object = feature[]
      old = get_position(engine, object)
      new = apply_alignment(engine, operation, feature, alignment)
      new ≠ old && set_position!(engine, object, new)
    end

    @case &OPERATION_TYPE_DISTRIBUTE
    spacing = compute_spacing(engine, operation)
    operands = operation.on::Vector{PositionalFeature{O}}
    isempty(operands) && return
    reference = operands[1]
    for feature in @view operands[2:end]
      object = feature[]
      old = get_position(engine, object)
      new = apply_spacing(engine, operation, reference, feature, spacing)
      new ≠ old && set_position!(engine, object, new)
      reference = feature
    end

    @case &OPERATION_TYPE_PIN
    operand = operation.on::PositionalFeature{O}
    operand.location === FEATURE_LOCATION_ORIGIN || throw(ArgumentError("Operand to pinning operation should represent an object or group with no positional features"))
    object = operand.object::Union{O, Group{O}}
    old = get_geometry(engine, object)
    new = apply_pinning_operation(engine, operation, object, old)
    old ≠ new && set_geometry!(engine, object, new)
  end
end

function apply_place_operation(engine::LayoutEngine, operation::Operation, point)
  on = get_coordinates(engine, operation.on)
  to = get_coordinates(engine, operation.by)
  displacement = place_operation_displacement(on, to)
  point .+ displacement
end

place_operation_displacement(on, to) = to .- on

function compute_alignment(engine::LayoutEngine, operation::Operation)
  @assert operation.type == OPERATION_TYPE_ALIGN
  (; direction, target) = operation.alignment
  i = 3 - Int64(direction)
  @match target begin
    &ALIGNMENT_TARGET_MINIMUM => minimum(get_coordinates(engine, object)[i] for object in operation.on)
    &ALIGNMENT_TARGET_MAXIMUM => maximum(get_coordinates(engine, object)[i] for object in operation.on)
    &ALIGNMENT_TARGET_AVERAGE => sum(get_coordinates(engine, object)[i] for object in operation.on)/length(operation.on)
    _ => alignment_target(get_coordinates(engine, target), direction)
  end
end

alignment_target(coordinates, direction::Direction) = alignment_or_distribution_target(coordinates, 3 - Int64(direction))
alignment_or_distribution_target(p::SVector, i::Integer) = p[i]

function apply_alignment(engine::LayoutEngine, operation::Operation, feature::PositionalFeature, alignment)
  C = coordinate_type(engine)
  object = feature[]
  position = get_position(engine, object)
  coords = coordinates(engine, position)
  relative = alignment_target(get_relative_coordinates(engine, feature), operation.alignment.direction)
  @match operation.alignment.direction begin
    &DIRECTION_HORIZONTAL => set_coordinates(engine, position, C(coords[1], alignment - relative))
    &DIRECTION_VERTICAL => set_coordinates(engine, position, C(alignment - relative, coords[2]))
  end
end

"Compute the required spacing between two elements `x` and `y` according to the provided `operation`."
function compute_spacing(engine::LayoutEngine, operation::Operation)
  @assert operation.type == OPERATION_TYPE_DISTRIBUTE
  (; spacing) = operation
  objects = operation.on
  xs, ys = @view(objects[1:(end - 1)]), @view(objects[2:end])
  i = 3 - Int64(spacing.direction)
  edges = ((:left, :right), (:top, :bottom))[i]
  if isa(spacing.amount, Float64)
    value = spacing.amount
  else
    spacings = [get_coordinates(engine, at(engine, y, :edge, edges[1])).a[i] - get_coordinates(engine, at(engine, x, :edge, edges[2])).a[i] for (x, y) in zip(xs, ys)]
    value = @match spacing.amount begin
      &SPACING_TARGET_MINIMUM => minimum(spacings)
      &SPACING_TARGET_MAXIMUM => maximum(spacings)
      &SPACING_TARGET_AVERAGE => sum(spacings)/length(spacings)
    end
  end
  # Negate vertical spacing so that objects are laid out from top to bottom
  spacing.direction == DIRECTION_VERTICAL && (value = -value)
  value
end

function apply_spacing(engine::LayoutEngine, operation::Operation, x::PositionalFeature, y::PositionalFeature, spacing)
  C = coordinate_type(engine)
  (; direction) = operation.spacing
  position = get_position(engine, y[])
  coords = coordinates(engine, position)
  @when &SPACING_MODE_GEOMETRY = operation.spacing.mode begin
    xb, yb = get_geometry(engine, x[]), get_geometry(engine, y[])
    sx, sy = (xb.max - xb.min) ./ 2, (yb.max - yb.min) ./ 2
    spacing -= @match direction begin
      &DIRECTION_HORIZONTAL => sx[1] + sy[1]
      &DIRECTION_VERTICAL => sx[2] + sy[2]
    end
  end
  xc, yr = get_coordinates(engine, x), get_relative_coordinates(engine, y)
  base, offset = alignment_or_distribution_target.((xc, yr), Int64(direction))
  @match direction begin
    &DIRECTION_HORIZONTAL => set_coordinates(engine, position, C(base - offset + spacing, coords[2]))
    &DIRECTION_VERTICAL => set_coordinates(engine, position, C(coords[1], base - offset + spacing))
  end
end

function apply_pinning_operation(engine::LayoutEngine{O}, operation::Operation, object::Union{O, Group{O}}, geometry) where {O}
  target = get_coordinates(engine, operation.by)
  parameters = operation.pinning
  location = get_coordinates(engine, PositionalFeature(object, parameters.part))
  displacement = (target .+ parameters.offset) .- location
  distort_geometry(geometry, displacement, parameters)
end

function distort_geometry(geometry::Box{2}, displacement, parameters::PinningParameters)
  dx, dy = displacement
  @match (parameters.part) begin
    &CORNER_BOTTOM_LEFT => Box(geometry.min .+ displacement, geometry.max)
    &CORNER_BOTTOM_RIGHT => Box(geometry.min .+ (zero(dy), dy), geometry.max .+ (dx, zero(dx)))
    &CORNER_TOP_LEFT => Box(geometry.min .+ (dx, zero(dx)), geometry.max .+ (zero(dy), dy))
    &CORNER_TOP_RIGHT => Box(geometry.min, geometry.max .+ displacement)
    &EDGE_LEFT => Box(geometry.min .+ (dx, zero(dx)), geometry.max)
    &EDGE_RIGHT => Box(geometry.min, geometry.max .+ (dx, zero(dx)))
    &EDGE_BOTTOM => Box(geometry.min .+ (zero(dy), dy), geometry.max)
    &EDGE_TOP => Box(geometry.min, geometry.max .+ (zero(dy), dy))
  end
end

# Record operations.

function place!(engine::LayoutEngine{O}, object, onto) where {O}
  operation = Operation{O}(OPERATION_TYPE_PLACE, positional_feature(engine, onto), positional_feature(engine, object), nothing)
  push!(engine.operations, operation)
end

function place_after!(engine::LayoutEngine, object, after; spacing = 0.0, direction::Union{Symbol, Direction} = DIRECTION_HORIZONTAL)
  isa(direction, Symbol) && (direction = Direction(direction))
  offset = direction == DIRECTION_HORIZONTAL ? (spacing, 0.0) : (0.0, spacing)
  place!(engine, at(engine, object, :left), after |> at(engine, :right) |> at(engine, offset))
end

align!(engine::LayoutEngine, object, direction, target) = align!(engine, [positional_feature(engine, object)], direction, target)

function align!(engine::LayoutEngine, objects::AbstractVector, direction, target)
  align!(engine, positional_feature.(engine, objects), direction, target)
end

function align!(engine::LayoutEngine{O}, objects::AbstractVector{PositionalFeature{O}}, direction, target::AlignmentTarget) where {O}
  operation = Operation{O}(OPERATION_TYPE_ALIGN, nothing, objects, Alignment{O}(direction, target))
  push!(engine.operations, operation)
end

function align!(engine::LayoutEngine{O}, objects::AbstractVector{PositionalFeature{O}}, direction, target) where {O}
  operation = Operation{O}(OPERATION_TYPE_ALIGN, nothing, objects, Alignment{O}(direction, positional_feature(engine, target)))
  push!(engine.operations, operation)
end

function distribute!(engine::LayoutEngine, objects::AbstractVector, direction, spacing, mode = SPACING_MODE_POINT)
  distribute!(engine, positional_feature.(engine, objects), direction, spacing, mode)
end

function distribute!(engine::LayoutEngine{O}, objects::AbstractVector{PositionalFeature{O}}, direction, spacing, mode = SPACING_MODE_POINT) where {O}
  operation = Operation(OPERATION_TYPE_DISTRIBUTE, nothing, objects, Spacing(direction, spacing, mode))
  push!(engine.operations, operation)
end

function pin!(engine::LayoutEngine{O}, object, part, to; offset = 0.0) where {O}
  object = to_object(engine, object)
  parameters = PinningParameters(part, offset)
  to = positional_feature(engine, to)
  pin!(engine, object, to, parameters)
end

function pin!(engine::LayoutEngine{O}, object::Union{O, Group{O}}, to::PositionalFeature{O}, parameters::PinningParameters) where {O}
  object = positional_feature(engine, object)
  operation = Operation(OPERATION_TYPE_PIN, to, object, parameters)
  push!(engine.operations, operation)
end

export
  LayoutEngine,
  LayoutStorage, ECSLayoutStorage, ArrayLayoutStorage,
  compute_layout!,
  place!, place_after!, align!, distribute!, pin!,
  remove_operations!,
  Group,

  Operation,
  OPERATION_TYPE_PLACE,
  OPERATION_TYPE_ALIGN,
  OPERATION_TYPE_DISTRIBUTE,
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
  AlignmentTarget,
  ALIGNMENT_TARGET_MINIMUM,
  ALIGNMENT_TARGET_MAXIMUM,
  ALIGNMENT_TARGET_AVERAGE,
  SpacingAmount,
  SPACING_AMOUNT_MINIMUM,
  SPACING_AMOUNT_MAXIMUM,
  SPACING_AMOUNT_AVERAGE,
  SpacingMode,
  SPACING_MODE_POINT,
  SPACING_MODE_GEOMETRY

end # module
