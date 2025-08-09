macro observable(ex)
  isa(ex, Expr) || throw(ArgumentError("Expected struct definition, got $ex"))
  def = find_struct(ex)
  isnothing(def) && throw(ArgumentError("No struct definition was found in $ex"))
  ismutable, decl, block = def.args
  isexpr(decl, :(<:)) && (decl = decl.args[1])
  name, params = isexpr(decl, :curly) ? (esc(decl.args[1]), decl.args[2:end]) : (esc(decl::Symbol), [])
  fields = copy(block.args)
  pushfirst!(block.args, LineNumberNode(@__LINE__, @__FILE__), :(field_callbacks::$FieldCallbacks))
  has_constructors = false
  names = extract_fieldnames(fields)
  for subex in block.args
    isexpr(subex, :(::)) && continue
    isa(subex, Symbol) && continue
    isexpr(subex, :function) || isexpr(subex, :(=)) || continue
    constructor = subex
    has_constructors = true
    for new in find_new_callsites(constructor)
      insert!(new.args, 2, :($FieldCallbacks()))
    end
  end

  if !has_constructors
    # Add a default constructor that provides the FieldCallbacks argument.
    # If there are constructors present already, calls to `new` will already be provided with it.
    body = Expr(:block)
    constructor = Expr(:function, Expr(:call, decl, names...), body)
    if isexpr(decl, :curly)
      new = :(new{$(decl.args[2:end]...)})
      constructor.args[1] = Expr(:where, constructor.args[1], decl.args[2:end]...)
    else
      new = :new
    end
    call = Expr(:call, new, :($FieldCallbacks()), names...)
    push!(body.args, call)
    push!(block.args, constructor)
  end

  quote
    $(esc(def))
    $(esc(:(Base.setproperty!)))(x::$name, name::Symbol, value) = setproperty_observed!(x, name, value)
    $(esc(:(Base.propertynames)))(::Type{<:$name}) = $(Tuple(filter(≠(:field_callbacks), names)))
    $(esc(:($(@__MODULE__()).field_callbacks)))(x::$name) = x.field_callbacks
    $name
  end
end

function extract_fieldnames(fields)
  names = Symbol[]
  for field in fields
    @trymatch field begin
      :($name::$field) || name::Symbol => push!(names, name)
    end
  end
  names
end

function setproperty_observed!(x, name::Symbol, value)
  old = isdefined(x, name) ? getproperty(x, name) : missing
  new = setfield!(x, name, value)
  old === new && return new
  callbacks = get(x.field_callbacks, name, nothing)
  isnothing(callbacks) && return new
  to_delete = nothing
  for (i, callback) in enumerate(callbacks)
    code = callback(old, new)
    if code === OBSERVABLE_DELETE_CALLBACK
      to_delete = @something(to_delete, Int[])
      push!(to_delete, i)
    end
  end
  !isnothing(to_delete) && splice!(callbacks, to_delete)
  isempty(callbacks) && delete!(x.field_callbacks, name)
  new
end

find_new_callsites(ex::Expr) = find_new_callsites!(Expr[], ex)
function find_new_callsites!(results, ex::Expr)
  if isexpr(ex, :call)
    f = ex.args[1]
    isexpr(f, :curly) && (f = f.args[1])
    f == :new && push!(results, ex)
  end
  for subex in ex.args
    isa(subex, Expr) && find_new_callsites!(results, subex)
  end
  results
end

field_callbacks(x) = error("Value of type $(typeof(x)) is not an observable!")

function observe!(f, x, name)
  callbacks = field_callbacks(x)
  push!(get!(Vector{Any}, callbacks, name), f)
end

unobserve!(x) = empty!(field_callbacks(x))

function find_struct(ex::Expr)
  isexpr(ex, :struct) && return ex
  for subex in ex.args
    isa(subex, Expr) || continue
    result = find_struct(subex)
    !isnothing(result) && return result
  end
end

const FieldCallbacks = Dict{Symbol, Vector{Any}}

throw_malformed_bind_expression(ex) = throw(ArgumentError("Expected an expression of the form `x.property_1 => y.property_2`, got $ex"))

@enum ObservableMessage OBSERVABLE_DELETE_CALLBACK

"""
    @bind x.a => y.b

Bind the field `x.a` to `y.b`, such that `setproperty!(y, :b, value)` results in `x.a` updated with `value`.
"""
macro bind(ex)
  isexpr(ex, :call) && ex.args[1] == :(=>) || throw_malformed_bind_expression(ex)
  x = ex.args[2]
  y = ex.args[3]
  isexpr(x, :(.)) || throw_malformed_bind_expression(ex)
  isexpr(y, :(.)) || throw_malformed_bind_expression(ex)
  x, xprop = esc(x.args[1]), x.args[2]
  y, yprop = esc(y.args[1]), y.args[2]
  quote
    let xw = WeakRef($x)
      observe!($y, $yprop) do _, value
        $x = xw.value
        $x === nothing && return OBSERVABLE_DELETE_CALLBACK
        $(Expr(:., x, xprop)) = value
      end
    end
  end
end
