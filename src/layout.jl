using Graphs

export
  LayoutEngine,
  LayoutStorage, ECSLayoutStorage, ArrayLayoutStorage,
  PositionalFeature, at,
  Constraint, attach, align, distribute,
  compute_layout!,

  Constraint,
  CONSTRAINT_TYPE_ATTACH,
  CONSTRAINT_TYPE_ALIGN,
  CONSTRAINT_TYPE_DISTRIBUTE,
  PositionalFeature,
  FEATURE_LOCATION_ORIGIN,
  FEATURE_LOCATION_CENTER,
  FEATURE_LOCATION_CORNER,
  FEATURE_LOCATION_EDGE,
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

"""
    LayoutStorage{O,P,C,G}

Abstract type for a layout storage where:
- `O` represents the type of objects to be laid out by the engine, e.g. `Widget`.
- `P` is the type of position values to be manipulated, e.g. `Point{2,Float64}`.
- `C` is the coordinate type for the position, which will usually be the same as `P`.
- `G` is the type of geometry to be manipulated, e.g. `Box{2,Float64}`.

!!! note
    `P` and `C` were made to be different parameters such that a given position type is allowed to differ from the numerical type that represents its data. For example, with `struct LocationComponent; metadata::Any; coords::Point{2,Float64}; end`, `LocationComponent` is the position type `P`, while `Point{2,Float64}` is the coordinate type `C`. This relaxation is meant to facilitate integration with larger codebases that may have their custom data structures.
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
report_unsolvable_decision(storage::LayoutStorage) = error("No solution was found which satisfies all requested constraints.")
# will also need similar functions to access geometry

@enum FeatureLocation begin
  FEATURE_LOCATION_CENTER = 1
  FEATURE_LOCATION_ORIGIN = 2
  FEATURE_LOCATION_CORNER = 3
  FEATURE_LOCATION_EDGE = 4
  FEATURE_LOCATION_CUSTOM = 5
end

function FeatureLocation(name::Symbol)
  names = (:center, :origin, :corner, :edge, :custom)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  FeatureLocation(i)
end

struct PositionalFeature{O}
  "Object the feature is attached to."
  object::Union{PositionalFeature{O},O}
  location::FeatureLocation
  "Position of the feature relative to the origin (position) of the object."
  data::Any
end

PositionalFeature(object, location::FeatureLocation) = PositionalFeature(object, location, nothing)
PositionalFeature(object, location::Symbol, data = nothing) = PositionalFeature(object, FeatureLocation(location), data)

function Base.getindex(feature::PositionalFeature{O}) where {O}
  (; object) = feature
  while !isa(object, O)
    (; object) = object
  end
  object
end

struct Group{O}
  objects::Vector{Union{O,PositionalFeature{O}}}
end

group(objects...) = Group(objects)
Group(objects::Tuple) = Group([objects...])

struct LayoutEngine{O,S<:LayoutStorage{O}}
  storage::S
  groups::Vector{Group{O}}
end
LayoutEngine(storage::LayoutStorage{O}) where {O} = LayoutEngine{O,typeof(storage)}(storage, Group{O}[])

@forward_methods LayoutEngine field = :storage object_type position_type coordinate_type geometry_type get_geometry(_, object) set_geometry!(_, object, geometry) coordinates(_, x) get_coordinates(_, object) set_coordinates(_, position, coords) get_position(_, object) set_position!(_, object, position)

Base.broadcastable(engine::LayoutEngine) = Ref(engine)

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

struct ECSLayoutStorage{C,G,PC,GC} <: LayoutStorage{EntityID,C,C,G}
  ecs::ECSDatabase
end

position(storage::ECSLayoutStorage{C,<:Any,C}, position::C) where {C} = position
get_position(storage::ECSLayoutStorage{<:Any,<:Any,PC}, object::EntityID) where {PC} = position(storage, storage.ecs[object, LOCATION_COMPONENT_ID]::PC)
set_position!(storage::ECSLayoutStorage{C}, object::EntityID, position::C) where {C} = storage.ecs[object, LOCATION_COMPONENT_ID] = position
geometry(storage::ECSLayoutStorage{<:Any,G,<:Any,G}, geometry::G) where {G} = geometry
get_geometry(storage::ECSLayoutStorage{<:Any,GC,<:Any,GC}, object::EntityID) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID]::GC
set_geometry!(storage::ECSLayoutStorage{<:Any,GC}, object::EntityID, geometry::GC) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID] = geometry

function compute_layout!(engine::LayoutEngine, constraints)
  O = object_type(engine)
  C = Constraint{O}
  dg = DependencyGraph(engine, constraints)
  for v in topological_sort(dg.graph)
    node = dg.nodes[v]
    @switch node begin
      @case ::O
      cs = dg.node_constraints[v]
      isnothing(cs) && continue
      # TODO: Re-enable when partial constraints are supported, otherwise the check is too restrictive.
      # validate_constraints(engine, cs)
      original = get_position(engine, node)
      position = foldl(cs; init = original) do position, constraint
        apply_constraint(engine, constraint, position)
      end
      position ≠ original && set_position!(engine, node, position)

      @case ::C
      @switch node.type begin
        @case &CONSTRAINT_TYPE_ALIGN
        alignment = compute_alignment(engine, node)
        for feature in node.on
          object = feature[]
          original = get_position(engine, object)
          position = apply_alignment(engine, node, feature, alignment)
          position ≠ original && set_position!(engine, object, position)
        end

        @case &CONSTRAINT_TYPE_DISTRIBUTE
        spacing = compute_spacing(engine, node)
        length(node.on) == 1 && continue
        reference = node.on[1]
        for feature in @view node.on[2:end]
          object = feature[]
          original = get_position(engine, object)
          position = apply_spacing(engine, node, reference, feature, spacing)
          position ≠ original && set_position!(engine, object, position)
          reference = feature
        end
      end
    end
  end
end

@enum Edge begin
  EDGE_LEFT = 1
  EDGE_RIGHT = 2
  EDGE_BOTTOM = 3
  EDGE_TOP = 4
end

function Edge(name::Symbol)
  names = (:left, :right, :bottom, :top)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  Edge(i)
end

@enum Corner begin
  CORNER_BOTTOM_LEFT = 1
  CORNER_BOTTOM_RIGHT = 2
  CORNER_TOP_LEFT = 3
  CORNER_TOP_RIGHT = 4
end

function Corner(name::Symbol)
  names = (:bottom_left, :bottom_right, :top_left, :top_right)
  i = findfirst(==(name), names)
  isnothing(i) && throw(ArgumentError("Symbol `$name` must be one of $names"))
  Corner(i)
end

function PositionalFeature(object, location::FeatureLocation, name::Symbol)
  @match location begin
    &FEATURE_LOCATION_CORNER => PositionalFeature(object, location, Corner(name))
    &FEATURE_LOCATION_EDGE => PositionalFeature(object, location, Edge(name))
    _ => throw(ArgumentError("Symbol data `$name` is not allowed for $location"))
  end
end

function get_relative_coordinates(engine::LayoutEngine, feature::PositionalFeature)
  C = coordinate_type(engine)
  T = eltype(C)
  @match feature.location begin
    &FEATURE_LOCATION_ORIGIN => zero(C)
    &FEATURE_LOCATION_CENTER => centroid(get_geometry(engine, feature[]))
    &FEATURE_LOCATION_CORNER => coordinates(get_geometry(engine, feature[])::Box{2,T}, feature.data::Corner)
    &FEATURE_LOCATION_EDGE => begin
        geometry = get_geometry(engine, feature[])::Box{2,T}
        (x, y) = @match edge = feature.data::Edge begin
          &EDGE_BOTTOM => (coordinates(geometry, CORNER_BOTTOM_LEFT), coordinates(geometry, CORNER_BOTTOM_RIGHT))
          &EDGE_TOP => (coordinates(geometry, CORNER_TOP_LEFT), coordinates(geometry, CORNER_TOP_RIGHT))
          &EDGE_LEFT => (coordinates(geometry, CORNER_BOTTOM_LEFT), coordinates(geometry, CORNER_TOP_LEFT))
          &EDGE_RIGHT => (coordinates(geometry, CORNER_BOTTOM_RIGHT), coordinates(geometry, CORNER_TOP_RIGHT))
        end
        Segment(x, y)
      end
    &FEATURE_LOCATION_CUSTOM => feature.data
  end
end

add_coordinates(x, y) = x .+ y
add_coordinates(x::Segment, y::Segment) = Segment(x.a + y.a, x.b + y.b)
add_coordinates(x::Segment, y) = Segment(x.a + y, x.b + y)
add_coordinates(x, y::Segment) = add_coordinates(y, x)
add_coordinates(x::Number, y::Segment{2,T}) where {T} = add_coordinates(y, x)
function add_coordinates(x::Segment{2,T}, y::Number) where {T}
  if x.a.y == x.b.y
    # Offset the segment in the Y direction.
    offset = Point{2,T}(zero(T), y)
  elseif x.a.x == x.b.x
    # Offset the segment in the X direction.
    offset = Point{2,T}(y, zero(T))
  else
    error("Segment is neither horizontal nor vertical")
  end
  Segment(x.a + offset, x.b + offset)
end

get_coordinates(engine::LayoutEngine, feature::PositionalFeature) = add_coordinates(get_coordinates(engine, feature.object), get_relative_coordinates(engine, feature))
get_coordinates(engine::LayoutEngine, group::Group) = get_position(engine, group)

coordinates(geometry::Box{2,T}, corner::Corner) where {T} = PointSet(geometry).points[Int64(corner)]

# Closures.
at(x::Real, y::Real) = at((x, y))
at((x, y)::Tuple) = at(P2(x, y))
at(p::P2) = x -> at(x, p)
at(coord::Real) = x -> at(x, coord)
at(location::Symbol, argument = nothing) = x -> at(x, location, argument)
at(location::Symbol, argument::Symbol) = x -> at(x, location, argument)

at(object) = positional_feature(object)
at(object, position) = at(object, FEATURE_LOCATION_CUSTOM, position)
function at(object, location::FeatureLocation, argument = nothing)
  if location in (FEATURE_LOCATION_ORIGIN, FEATURE_LOCATION_CENTER)
    isnothing(argument) || throw(ArgumentError("No argument must be provided for feature location in (`FEATURE_LOCATION_ORIGIN`, `FEATURE_LOCATION_CENTER`)"))
  elseif location == FEATURE_LOCATION_CORNER
    isa(argument, Union{Symbol,Corner}) || throw(ArgumentError("`$location` requires a `Corner` argument"))
  elseif location == FEATURE_LOCATION_EDGE
    isa(argument, Union{Symbol,Edge}) || throw(ArgumentError("`$location` requires a `Edge` argument"))
  elseif location == FEATURE_LOCATION_CUSTOM
    !isnothing(location) || throw(ArgumentError("`$location` requires an argument"))
  end
  PositionalFeature(object, location, argument)
end
at(object, location::Symbol, argument = nothing) = at(object, FeatureLocation(location), argument)

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

@enum ConstraintType begin
  CONSTRAINT_TYPE_ATTACH
  CONSTRAINT_TYPE_ALIGN
  CONSTRAINT_TYPE_DISTRIBUTE
end

"Attach two features together, resulting in an identical position for both."
CONSTRAINT_TYPE_ATTACH
"""
Position a set of features on a line along a [`Direction`](@ref), either along a horizontal (i.e. the vertical position is set to rest on a horizontal line) or along a vertical (the horizontal position is set to rest on a vertical line).
"""
CONSTRAINT_TYPE_ALIGN
"""
Evenly space out a set of features along a [`Direction`](@ref).

The notion of "space" may be defined with respect to points, or to geometries: either we talk about the distance between points, or about the distance between geometries.

The desired spacing may be provided as a floating point value. However, for convenience, we also allow a [`SpacingAmount`](@ref) value, which will automatically compute the required spacing depending on the desired behavior.

Automatic spacing includes taking the minimum, maximum or average of the distances between the provided features. Which notion of distance is used depends on the mode (see [`SpacingMode`](@ref)).

Providing any positional feature for a [`SPACING_MODE_GEOMETRY`](@ref) mode will result in considering the geometry of associated objects to be offset by the relative offset between the feature and the center of the geometry. Therefore, the spacing will not appear even if any positional features are not positioned to the center of the objects.
"""
CONSTRAINT_TYPE_DISTRIBUTE

struct Constraint{O}
  type::ConstraintType
  by::Optional{PositionalFeature{O}}
  on::Union{PositionalFeature{O}, Vector{PositionalFeature{O}}}
  data::Any
end

function Base.getproperty(constraint::Constraint{O}, name::Symbol) where {O}
  name === :alignment && return getfield(constraint, :data)::Alignment{O}
  name === :spacing && return getfield(constraint, :data)::Spacing
  getfield(constraint, name)
end

function apply_constraint(engine::LayoutEngine, constraint::Constraint, position)
  C = coordinate_type(engine)
  @match constraint.type begin
    &CONSTRAINT_TYPE_ATTACH => set_coordinates(engine, position, apply_attach_constraint(engine, constraint, coordinates(engine, position)))
  end
end

function compute_alignment(engine::LayoutEngine, constraint::Constraint)
  @assert constraint.type == CONSTRAINT_TYPE_ALIGN
  (; direction, target) = constraint.alignment
  i = 3 - Int64(direction)
  @match target begin
    &ALIGNMENT_TARGET_MINIMUM => minimum(get_coordinates(engine, object)[i] for object in constraint.on)
    &ALIGNMENT_TARGET_MAXIMUM => maximum(get_coordinates(engine, object)[i] for object in constraint.on)
    &ALIGNMENT_TARGET_AVERAGE => sum(get_coordinates(engine, object)[i] for object in constraint.on)/length(constraint.on)
    _ => alignment_target(get_coordinates(engine, target), direction)
  end
end

alignment_target(coordinates, direction::Direction) = alignment_or_distribution_target(coordinates, 3 - Int64(direction))
alignment_or_distribution_target(p::Point, i::Integer) = p[i]
function alignment_or_distribution_target(s::Segment, i::Integer)
  s.a[i] ≈ s.b[i] || error("Alignment or distribution along a variable segment is not supported; you should instead provide a point location, or either a vertical segment for horizontal alignment/distribution or a horizontal segment for vertical alignment/distribution.")
  s.a[i]
end

function apply_alignment(engine::LayoutEngine, constraint::Constraint, feature::PositionalFeature, alignment)
  C = coordinate_type(engine)
  object = feature[]
  position = get_position(engine, object)
  coords = coordinates(engine, position)
  relative = alignment_target(get_relative_coordinates(engine, feature), constraint.alignment.direction)
  @match constraint.alignment.direction begin
    &DIRECTION_HORIZONTAL => set_coordinates(engine, position, C(coords[1], alignment - relative))
    &DIRECTION_VERTICAL => set_coordinates(engine, position, C(alignment - relative, coords[2]))
  end
end

"Compute the required spacing between two elements `x` and `y` according to the provided `constraint`."
function compute_spacing(engine::LayoutEngine, constraint::Constraint)
  @assert constraint.type == CONSTRAINT_TYPE_DISTRIBUTE
  (; spacing) = constraint
  objects = constraint.on
  xs, ys = @view(objects[1:(end - 1)]), @view(objects[2:end])
  i = 3 - Int64(spacing.direction)
  edges = ((:left, :right), (:top, :bottom))[i]
  if isa(spacing.amount, Float64)
    value = spacing.amount
  else
    spacings = [get_coordinates(engine, at(y, :edge, edges[1])).a[i] - get_coordinates(engine, at(x, :edge, edges[2])).a[i] for (x, y) in zip(xs, ys)]
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

function apply_spacing(engine::LayoutEngine, constraint::Constraint, x::PositionalFeature, y::PositionalFeature, spacing)
  C = coordinate_type(engine)
  (; direction) = constraint.spacing
  position = get_position(engine, y[])
  coords = coordinates(engine, position)
  @when &SPACING_MODE_GEOMETRY = constraint.spacing.mode begin
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

# XXX To avoid having to infer types in such a way, perhaps require an `engine::LayoutEngine` argument in `attach`/`align`/etc?
function object_type(xs::AbstractVector) # of `PositionalFeature` or possibly `Any`.
  T = eltype(xs)
  # If concrete, we'll have a `PositionalFeature` type.
  if isconcretetype(T)
    @assert T <: PositionalFeature
    return object_type(T)
  end
  # Try to pick off a `PositionalFeature{O}` and infer `O` from that.
  for x in xs
    if isa(x, PositionalFeature)
      for y in xs
        typeof(y) === typeof(x) || throw(ArgumentError("Multiple possible object types detected in `$xs`"))
      end
      return object_type(typeof(x))
    end
  end
  isempty(xs) && return throw(ArgumentError("Cannot infer object type from $xs"))
  # Fall back to the supertype of all components, assumed to be "objects".
  Ts = unique(typeof.(xs))
  object_type(reduce(typejoin, Ts; init = Union{}))
end

object_type(::Type{T}) where {O,T<:PositionalFeature{O}} = O
object_type(::Type{T}) where {T} = T

attach(object, onto) = Constraint(CONSTRAINT_TYPE_ATTACH, positional_feature(onto), positional_feature(object), nothing)
align(object, direction, target) = align([object], direction, target)
align(objects::AbstractVector{PositionalFeature{O}}, direction, target::O) where {O} = align(objects, direction, positional_feature(target))
align(objects::AbstractVector{<:PositionalFeature}, direction, target) = Constraint(CONSTRAINT_TYPE_ALIGN, nothing, objects, Alignment{object_type(objects)}(direction, target))
align(objects::AbstractVector, direction, target) = align(positional_feature.(objects), direction, target)
distribute(objects::AbstractVector{<:PositionalFeature}, direction, spacing, mode = SPACING_MODE_POINT) = Constraint(CONSTRAINT_TYPE_DISTRIBUTE, nothing, objects, Spacing(direction, spacing, mode))
distribute(objects::AbstractVector, direction, spacing, mode = SPACING_MODE_POINT) = distribute(positional_feature.(objects), direction, spacing, mode)

function apply_attach_constraint(engine::LayoutEngine, constraint::Constraint, point)
  on = get_coordinates(engine, constraint.on)
  to = get_coordinates(engine, constraint.by)
  displacement = attach_constraint_displacement(on, to)
  point .+ displacement
end

attach_constraint_displacement(on, to) = to .- on
attach_constraint_displacement(on, to::Segment) = axis_aligned_projection(on, to) .- to
attach_constraint_displacement(on::Segment, to) = to .- axis_aligned_projection(to, on)
attach_constraint_displacement(on::Segment, to::Segment) = attach_constraint_displacement(on, centroid(to))

function axis_aligned_projection(point::Point, segment::Segment, along_axis::Direction = perpendicular_axis(segment))
  P = typeof(point)
  @match along_axis begin
    &DIRECTION_HORIZONTAL => P(segment.a[1], point[2])
    &DIRECTION_VERTICAL => P(point[1], segment.a[2])
  end
end

aligned_axis(segment::Segment) = other_axis(perpendicular_axis(segment))
function perpendicular_axis(segment::Segment)
  segment.a[1] ≈ segment.b[1] && return DIRECTION_HORIZONTAL
  segment.a[2] ≈ segment.b[2] && return DIRECTION_VERTICAL
  throw(ArgumentError("Segment $segment is not axis-aligned!"))
end

positional_feature(feature::PositionalFeature) = feature
positional_feature(object) = PositionalFeature(object, FEATURE_LOCATION_ORIGIN)

function validate_constraints(engine::LayoutEngine, constraints)
  # XXX: Handle partial constraints (e.g. where one axis only is affected).
  point = nothing
  for constraint in constraints
    if constraint.type == CONSTRAINT_TYPE_ATTACH
      if isnothing(point)
        point = apply_attach_constraint(engine, constraint)
      else
        other_point = apply_attach_constraint(engine, constraint)
        point == other_point || point ≈ other_point || error("Attempting to attach the same object at two different locations")
      end
    end
  end
end

const DependencyNode{O} = Union{O, Constraint{O}}

struct DependencyGraph{O}
  graph::SimpleDiGraph{Int64}
  nodes::Vector{DependencyNode{O}}
  node_constraints::Vector{Optional{Vector{Constraint{O}}}}
end

function DependencyGraph(engine::LayoutEngine{O}, constraints) where {O}
  C = Constraint{O}
  g = SimpleDiGraph{Int64}()
  verts = Dict{DependencyNode{O}, Int64}()
  nodes = DependencyNode{O}[]
  node_constraints = Optional{Vector{C}}[]
  # Constraint nodes to be considered with respect to dependency order instead of an individual object.
  constraint_proxies = Dict{O, Union{C, Vector{C}}}()
  function get_node!(object::O)
    proxy = get(constraint_proxies, object, object)
    get!(() -> add_node!(proxy), verts, object)
  end
  function add_node!(x::DependencyNode{O})
    push!(nodes, x)
    push!(node_constraints, nothing)
    Graphs.add_vertex!(g)
    Graphs.nv(g)
  end

  for constraint in unique(constraints)
    @switch constraint.type begin
      @case &CONSTRAINT_TYPE_ATTACH
      src = constraint.by[]
      dst = constraint.on[]
      u = get_node!(src)
      v = get_node!(dst)
      isnothing(node_constraints[v]) && (node_constraints[v] = Vector{Constraint}[])
      push!(node_constraints[v], constraint)
      Graphs.add_edge!(g, u, v)

      @case &CONSTRAINT_TYPE_ALIGN || &CONSTRAINT_TYPE_DISTRIBUTE
      v = add_node!(constraint)
      dependencies = @match constraint.type begin
        &CONSTRAINT_TYPE_ALIGN => begin
          (; target) = constraint.alignment
          isa(target, PositionalFeature{O}) ? [constraint.on; target] : constraint.on
        end
        &CONSTRAINT_TYPE_DISTRIBUTE => constraint.on
      end
      for to in dependencies
        src = to[]
        u = get!(() -> add_node!(src), verts, src)
        existing = get(constraint_proxies, src, nothing)
        @match existing begin
          ::Nothing => (constraint_proxies[src] = constraint)
          ::C => (constraint_proxies[src] = [existing, constraint])
          ::Vector{C} => push!(existing, constraint)
        end
        Graphs.add_edge!(g, u, v)
      end
    end
  end

  !is_cyclic(g) || error("Cyclic dependencies are not supported.")
  DependencyGraph(g, nodes, node_constraints)
end
