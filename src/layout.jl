using Graphs

export
  LayoutEngine, ECSLayoutEngine,
  PositionalFeature, at,
  Constraint, attach,
  compute_layout!,

  Constraint,
  CONSTRAINT_TYPE_ATTACH,
  CONSTRAINT_TYPE_ALIGN,
  CONSTRAINT_TYPE_DISTRIBUTE,
  PositionalFeature

abstract type LayoutEngine{O,P,C} end

object_type(::LayoutEngine{O}) where {O} = O
coordinate_type(::LayoutEngine{<:Any,<:Any,C}) where {C} = C

# coordinates(engine::LayoutEngine{<:Any,P,C}, position::P)::C where {P,C}
# get_position(engine::LayoutEngine{O,P}, object::O)::P where {O,P}
# set_position!(engine::LayoutEngine{O,P}, object::O, position::P) where {O,P}
get_coordinates(engine::LayoutEngine{O,P}, object::O) where {O,P} = coordinates(engine, get_position(engine, object))
set_coordinates(engine::LayoutEngine{<:Any,T,T}, position::T, coords::T) where {T} = coords
report_unsolvable_decision(engine::LayoutEngine) = error("No solution was found which satisfies all requested constraints.")
# will also need similar functions to access geometry

struct ECSLayoutEngine{C} <: LayoutEngine{EntityID,C,C}
  ecs::ECSDatabase
end

coordinates(engine::ECSLayoutEngine{C}, position::C) where {C} = position
get_position(engine::ECSLayoutEngine{C}, object::EntityID) where {C} = engine.ecs[object, LOCATION_COMPONENT_ID]::C
set_position!(engine::ECSLayoutEngine{C}, object::EntityID, position::C) where {C} = engine.ecs[object, LOCATION_COMPONENT_ID] = position

"Materialize constraints present in the `input` and add them to the existing `constraints`."
materialize_constraints(objects, constraints) = union!(materialize_constraints(objects), constraints)
# XXX: Actually do something or remove.
materialize_constraints(objects) = Constraint[]

function compute_layout!(engine::LayoutEngine, objects, constraints)
  constraints = materialize_constraints(objects, constraints)
  dg = DependencyGraph(engine, constraints)
  for v in topological_sort(dg.graph)
    cs = dg.object_constraints[v]
    isnothing(cs) && continue
    validate_constraints(engine, cs)
    object = dg.objects[v]
    original = get_position(engine, object)
    position = foldl(cs; init = original) do position, constraint
      apply_constraint(engine, constraint, position)
    end
    position ≠ original && set_position!(engine, object, position)
  end
end

@enum FeatureLocation begin
  FEATURE_LOCATION_CENTER
  FEATURE_LOCATION_ORIGIN
  FEATURE_LOCATION_CORNER
  FEATURE_LOCATION_EDGE
  FEATURE_LOCATION_CUSTOM
end

struct PositionalFeature{O}
  "Object the feature is attached to."
  object::O
  location::FeatureLocation
  "Position of the feature relative to the origin (position) of the object."
  data::Any
end

PositionalFeature(object, location::FeatureLocation) = PositionalFeature(object, location, nothing)

@enum Direction begin
  DIRECTION_HORIZONTAL = 1
  DIRECTION_VERTICAL = 2
end

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
  name === :direction && return getfield(constraint, :data)::Direction
  getfield(constraint, name)
end

function apply_constraint(engine::LayoutEngine, constraint::Constraint, position)
  C = coordinate_type(engine)
  @match constraint.type begin
    &CONSTRAINT_TYPE_ATTACH => set_coordinates(engine, position, attach_point(engine, constraint))
  end
end

attach(by, on) = Constraint(CONSTRAINT_TYPE_ATTACH, positional_feature(by), positional_feature(on), nothing)

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

struct DependencyGraph{O}
  graph::SimpleDiGraph{Int64}
  objects::Vector{O}
  object_constraints::Vector{Optional{Vector{Constraint}}}
  cycles::Vector{Vector{Int64}}
end

function DependencyGraph(engine::LayoutEngine, constraints)
  O = object_type(engine)
  g = SimpleDiGraph{Int64}()
  verts = Dict{O, Int64}()
  objects = O[]
  object_constraints = Optional{Vector{Constraint}}[]
  function add_node!(object)
    get!(verts, object) do
      push!(objects, object)
      push!(object_constraints, nothing)
      Graphs.add_vertex!(g)
      Graphs.nv(g)
    end
  end

  for constraint in constraints
    from = constraint.by.object
    !isnothing(from) && (from = (from,))
    to = constraint.on.object
    isa(to, O) && (to = (to,))
    from = something(from, to)
    for x in from
      u = get!(() -> add_node!(x), verts, x)
      for y in to
        x === y && continue
        v = get!(() -> add_node!(y), verts, y)
        isnothing(object_constraints[v]) && (object_constraints[v] = Vector{Constraint}[])
        push!(object_constraints[v], constraint)
        Graphs.add_edge!(g, u, v)
      end
    end
  end

  cycles = simplecycles(g)
  isempty(cycles) || error("Cyclic dependencies not yet supported.")
  DependencyGraph(g, objects, object_constraints, cycles)
end
