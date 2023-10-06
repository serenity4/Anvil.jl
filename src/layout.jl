using Graphs

export
  LayoutEngine, ECSLayoutEngine,
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
    target = dg.objects[v]
    original = get_position(engine, target)
    position = foldl(cs; init = original) do position, constraint
      apply_constraint(engine, constraint, position)
    end
    position ≠ original && set_position!(engine, target, position)
  end
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
  source::Optional{O}
  target::Union{O, Vector{O}}
  data::Any
end

function Base.getproperty(constraint::Constraint, name::Symbol)
  name === :attach_point && return getfield(constraint, :data)::PositionalFeature
  name === :alignment && return getfield(constraint, :data)::AlignedElements
  getfield(constraint, name)
end

function apply_constraint(engine::LayoutEngine, constraint::Constraint, position)
  C = coordinate_type(engine)
  @match constraint.type begin
    &CONSTRAINT_TYPE_ATTACH => set_coordinates(engine, position, get_coordinates(engine, constraint.attach_point))
  end
end

struct PositionalFeature{O,P}
  "Object the feature is attached to."
  object::O
  "Position of the feature relative to the position of the object."
  position::P
end

get_coordinates(engine::LayoutEngine, feature::PositionalFeature) = get_coordinates(engine, feature.object) .+ coordinates(engine, feature.position)

@enum AlignmentType begin
  ALIGNMENT_TYPE_ALONG_VERTICAL
  ALIGNMENT_TYPE_ALONG_HORIZONTAL
end

struct AlignedElements{O}
  type::AlignmentType
  objects::Vector{O}
end

# @enum PositionalFeature begin
#   POSITIONAL_FEATURE_CENTER
#   POSITIONAL_FEATURE_ORIGIN
#   POSITIONAL_FEATURE_EDGE
#   POSITIONAL_FEATURE_CUSTOM
# end

# @enum Direction DIRECTION_HORIZONTAL DIRECTION_VERTICAL
# @enum AlignmentTarget ALIGN_BOTTOM ALIGN_TOP ALIGN_CENTER

# align(rectangles, DIRECTION_HORIZONTAL, ALIGN_BOTTOM)::Constraint

function validate_constraints(engine::LayoutEngine, constraints)
  attach_point = nothing
  for constraint in constraints
    if constraint.type == CONSTRAINT_TYPE_ATTACH
      if isnothing(attach_point)
        (; attach_point) = constraint
      else
        coords = get_coordinates(engine, constraint.attach_point)
        coords == get_coordinates(engine, attach_point) || error("Attempting to attach the same object at two different locations")
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
    from = constraint.source
    !isnothing(from) && (from = (from,))
    to = constraint.target
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
