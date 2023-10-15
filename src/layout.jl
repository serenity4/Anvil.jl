using Graphs

export
  LayoutEngine, ECSLayoutEngine,
  PositionalFeature, at,
  Constraint, attach, align,
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
  ALIGNMENT_TARGET_AVERAGE

abstract type LayoutEngine{O,P,C,G} end

object_type(::LayoutEngine{O}) where {O} = O
position_type(::LayoutEngine{<:Any,P}) where {P} = P
coordinate_type(::LayoutEngine{<:Any,<:Any,C}) where {C} = C
geometry_type(::LayoutEngine{<:Any,<:Any,<:Any,G}) where {G} = G

# coordinates(engine::LayoutEngine{<:Any,P,C}, position::P)::C where {P,C}
# get_position(engine::LayoutEngine{O,P}, object::O)::P where {O,P}
# set_position!(engine::LayoutEngine{O,P}, object::O, position::P) where {O,P}
# get_geometry(engine::LayoutEngine{O,<:Any,<:Any,G}, object::O)::G where {O,G}
get_coordinates(engine::LayoutEngine{O,P}, object::O) where {O,P} = coordinates(engine, get_position(engine, object))
set_coordinates(engine::LayoutEngine{<:Any,T,T}, position::T, coords::T) where {T} = coords
report_unsolvable_decision(engine::LayoutEngine) = error("No solution was found which satisfies all requested constraints.")
# will also need similar functions to access geometry

struct ECSLayoutEngine{C,G,PC,GC} <: LayoutEngine{EntityID,C,C,G}
  ecs::ECSDatabase
end

coordinates(engine::ECSLayoutEngine{C}, position::C) where {C} = position
position(engine::ECSLayoutEngine{C,<:Any,C}, position::C) where {C} = position
get_position(engine::ECSLayoutEngine{<:Any,<:Any,PC}, object::EntityID) where {PC} = position(engine, engine.ecs[object, LOCATION_COMPONENT_ID]::PC)
set_position!(engine::ECSLayoutEngine{C}, object::EntityID, position::C) where {C} = engine.ecs[object, LOCATION_COMPONENT_ID] = position
geometry(engine::ECSLayoutEngine{<:Any,G,<:Any,G}, geometry::G) where {G} = geometry
get_geometry(engine::ECSLayoutEngine{<:Any,GC,<:Any,GC}, object::EntityID) where {GC} = engine.ecs[object, GEOMETRY_COMPONENT_ID]::GC
# get_geometry(engine::ECSLayoutEngine{<:Any,<:Any,<:Any,GC}, object::EntityID) where {GC} = geometry(engine, engine.ecs[object, GEOMETRY_COMPONENT_ID]::GC)
# geometry(engine::ECSLayoutEngine{<:Any,G,<:Any,GC}, component::GC) where {G,GC<:GeometryComponent} = component.object::G

"Materialize constraints present in the `input` and add them to the existing `constraints`."
materialize_constraints(objects, constraints) = union!(materialize_constraints(objects), constraints)
# XXX: Actually do something or remove.
materialize_constraints(objects) = Constraint[]

function compute_layout!(engine::LayoutEngine, objects, constraints)
  O = object_type(engine)
  C = Constraint{O}
  constraints = materialize_constraints(objects, constraints)
  dg = DependencyGraph(engine, constraints)
  for v in topological_sort(dg.graph)
    node = dg.nodes[v]
    @switch node begin
      @case ::O
      cs = dg.node_constraints[v]
      isnothing(cs) && continue
      validate_constraints(engine, cs)
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
      end
    end
  end
end

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
  object::O
  location::FeatureLocation
  "Position of the feature relative to the origin (position) of the object."
  data::Any
end

PositionalFeature(object, location::FeatureLocation) = PositionalFeature(object, location, nothing)
PositionalFeature(object, location::Symbol, data = nothing) = PositionalFeature(object, FeatureLocation(location), data)

Base.getindex(feature::PositionalFeature) = feature.object

@enum Edge begin
  EDGE_LEFT = 1
  EDGE_RIGHT = 2
  EDGE_BOTTOM = 3
  EDGE_TOP = 4
end

@enum Corner begin
  CORNER_BOTTOM_LEFT = 1
  CORNER_BOTTOM_RIGHT = 2
  CORNER_TOP_LEFT = 3
  CORNER_TOP_RIGHT = 4
end

function get_relative_coordinates(engine::LayoutEngine, feature::PositionalFeature)
  C = coordinate_type(engine)
  T = eltype(C)
  @match feature.location begin
    &FEATURE_LOCATION_ORIGIN => zero(C)
    &FEATURE_LOCATION_CENTER => centroid(get_geometry(engine, feature.object))
    &FEATURE_LOCATION_CORNER => coordinates(get_geometry(engine, feature.object)::Box{2,T}, feature.data::Corner)
    &FEATURE_LOCATION_EDGE => begin
        geometry = get_geometry(engine, feature.object)::Box{2,T}
        (x, y) = @match edge = feature.data::Edge begin
          &EDGE_BOTTOM => (coordinates(geometry, CORNER_BOTTOM_LEFT), coordinates(geometry, CORNER_BOTTOM_RIGHT))
          &EDGE_TOP => (coordinates(geometry, CORNER_TOP_LEFT), coordinates(geometry, CORNER_TOP_RIGHT))
          &EDGE_LEFT => (coordinates(geometry, CORNER_BOTTOM_LEFT), coordinates(geometry, CORNER_TOP_LEFT))
          &EDGE_RIGHT => (coordinates(geometry, CORNER_BOTTOM_RIGHT), coordinates(geometry, CORNER_TOP_RIGHT))
        end
        Segment(x, y)
      end
    &FEATURE_LOCATION_CUSTOM => feature.data::C
  end
end

get_coordinates(engine::LayoutEngine, feature::PositionalFeature) = get_coordinates(engine, feature.object) .+ get_relative_coordinates(engine, feature)

coordinates(geometry::Box{2,T}, corner::Corner) where {T} = PointSet(geometry).points[Int64(corner)]

at(object) = positional_feature(object)
at(object, position) = at(object, FEATURE_LOCATION_CUSTOM, position)
function at(object, location::FeatureLocation, argument = nothing)
  if location in (FEATURE_LOCATION_ORIGIN, FEATURE_LOCATION_CENTER)
    isnothing(argument) || throw(ArgumentError("No argument must be provided for feature location in (`FEATURE_LOCATION_ORIGIN`, `FEATURE_LOCATION_CENTER`)"))
  elseif location == FEATURE_LOCATION_CORNER
    isa(argument, Corner) || throw(ArgumentError("`$location` requires a `Corner` argument"))
  elseif location == FEATURE_LOCATION_EDGE
    isa(argument, Edge) || throw(ArgumentError("`$location` requires a `Edge` argument"))
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

@enum AlignmentTarget begin
  ALIGNMENT_TARGET_MINIMUM = 1
  ALIGNMENT_TARGET_MAXIMUM = 2
  ALIGNMENT_TARGET_AVERAGE = 3
end

struct Alignment
  direction::Direction
  target::AlignmentTarget
end

@enum ConstraintType begin
  CONSTRAINT_TYPE_ATTACH
  CONSTRAINT_TYPE_ALIGN
  CONSTRAINT_TYPE_DISTRIBUTE
end

"Attach two features together, resulting in an identical position for both."
CONSTRAINT_TYPE_ATTACH
"Align features together, either vertically or horizontally, according to a specified [`AlignmentType`](@ref)."
CONSTRAINT_TYPE_ALIGN
"Evenly distribute gaps between features, either vertically or horizontally, according to a specified [`AlignmentType`](@ref)."
CONSTRAINT_TYPE_DISTRIBUTE

struct Constraint{O}
  type::ConstraintType
  by::Optional{PositionalFeature{O}}
  on::Union{PositionalFeature{O}, Vector{PositionalFeature{O}}}
  data::Any
end

function Base.getproperty(constraint::Constraint, name::Symbol)
  name === :alignment && return getfield(constraint, :data)::Alignment
  getfield(constraint, name)
end

function apply_constraint(engine::LayoutEngine, constraint::Constraint, position)
  C = coordinate_type(engine)
  @match constraint.type begin
    &CONSTRAINT_TYPE_ATTACH => set_coordinates(engine, position, attach_point(engine, constraint))
  end
end

function compute_alignment(engine::LayoutEngine, constraint::Constraint)
  @assert constraint.type == CONSTRAINT_TYPE_ALIGN
  (; direction, target) = constraint.alignment
  i = 2 - Int64(direction)
  @match target begin
    &ALIGNMENT_TARGET_MINIMUM => minimum(get_coordinates(engine, object)[i] for object in constraint.on)
    &ALIGNMENT_TARGET_MAXIMUM => maximum(get_coordinates(engine, object)[i] for object in constraint.on)
    &ALIGNMENT_TARGET_AVERAGE => sum(get_coordinates(engine, object)[i] for object in constraint.on)/length(constraint.on)
  end
end

function apply_alignment(engine::LayoutEngine, constraint::Constraint, feature::PositionalFeature, alignment)
  C = coordinate_type(engine)
  object = feature[]
  position = get_position(engine, object)
  coords = coordinates(engine, position)
  relative = get_relative_coordinates(engine, feature)
  @match constraint.alignment.direction begin
    &DIRECTION_HORIZONTAL => set_coordinates(engine, position, C(coords[1], alignment - relative[2]))
    &DIRECTION_VERTICAL => set_coordinates(engine, position, C(alignment - relative[1], coords[2]))
  end
end

attach(object, onto) = Constraint(CONSTRAINT_TYPE_ATTACH, positional_feature(onto), positional_feature(object), nothing)
align(objects::AbstractVector{<:PositionalFeature}, direction::Direction, target::AlignmentTarget) = Constraint(CONSTRAINT_TYPE_ALIGN, nothing, objects, Alignment(direction, target))
align(objects, direction::Direction, target::AlignmentTarget) = Constraint(CONSTRAINT_TYPE_ALIGN, nothing, positional_feature.(objects), Alignment(direction, target))

attach_point(engine::LayoutEngine, constraint::Constraint) = get_coordinates(engine, constraint.by) .- get_relative_coordinates(engine, constraint.on)

positional_feature(feature::PositionalFeature) = feature
positional_feature(object) = PositionalFeature(object, FEATURE_LOCATION_ORIGIN)

function validate_constraints(engine::LayoutEngine, constraints)
  point = nothing
  for constraint in constraints
    if constraint.type == CONSTRAINT_TYPE_ATTACH
      if isnothing(point)
        point = attach_point(engine, constraint)
      else
        other_point = attach_point(engine, constraint)
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
    get!(() -> add_node!(proxy), verts, proxy)
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
      for to in constraint.on
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
