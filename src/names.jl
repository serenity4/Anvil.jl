"""
    @set_name menu = Menu(...)
    @set_name "navigation" menu = Menu(...)
    @set_name menu "navigation/menu"
"""
macro set_name(ex, exs...)
  exs = (ex, exs...)
  exs, ex = collect(exs[1:(end - 1)]), exs[end]
  if isexpr(ex, :(=), 2)
    name = QuoteNode(ex.args[1]::Symbol)
    ex = esc(ex)
  else
    isempty(exs) && throw(ArgumentError("Assignment or 2+ arguments expected"))
    name = :($(esc(ex))::Symbol)
    ex = esc(pop!(exs))
  end

  if isempty(exs)
    quote
      named = $ex
      set_name(named, $name)
    end
  else
    quote
      named = $ex
      namespace = join($(Expr(:tuple, esc.(exs)...)), '/')
      set_name(named, Symbol(namespace, '/', $name))
    end
  end
end

"""
    @set_name menu image text
"""
macro set_name(ex::Symbol, exs::Symbol...)
  ex = (ex, exs...)
  ret = Expr(:block)
  for ex in exs
    push!(ret.args, :(set_name($(esc(ex)), $(QuoteNode(ex)))))
  end
  ret
end

set_name(object, name::Symbol) = set_name(convert(EntityID, object), name)
function set_name(entity::EntityID, name::Symbol)
  is_release() && return nothing
  app.ecs.entity_names[entity] = name
  nothing
end

get_name(entity::EntityID) = isdefined(app, :ecs) ? get(app.ecs.entity_names, entity, nothing) : nothing
