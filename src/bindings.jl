mutable struct Counter{T}
  val::T
end
Counter{T}() where {T} = Counter(zero(T))
next!(counter::Counter{T}) where {T} = (counter.val += one(T))
reset!(counter::Counter{T}) where {T} = (counter.val = zero(T))
Base.getindex(counter::Counter) = counter.val

const KeyBindingsToken = Int64

struct KeyBindings
  active::Dictionary{KeyCombination, Callable}
  inactive::Dictionary{KeyCombination, Vector{Callable}}
  bindings::Dictionary{KeyBindingsToken, Vector{Pair{KeyCombination, Callable}}}
  counter::Counter{KeyBindingsToken}
end

KeyBindings() = KeyBindings(Dictionary(), Dictionary(), Dictionary(), Counter{KeyBindingsToken}())

Base.isempty(kb::KeyBindings) = isempty(kb.active) && isempty(kb.inactive) && isempty(kb.bindings)

function execute_binding(kb::KeyBindings, event::KeyEvent)
  if get(ENV, "ANVIL_LOG_KEY_PRESS", "false") == "true"
    print_key_info(stdout, app.wm.keymap, event)
    println()
  end
  key = KeyCombination(event.key, (event.modifiers & ~event.consumed_modifiers))
  matches(key, event) || return
  callable = get(kb.active, key, nothing)
  isnothing(callable) && return
  hasmethod(callable, Tuple{}) ? callable() : callable(key)
  nothing
end

function bind!(f::Callable, kb::KeyBindings, bindings::Pair...)
  token = bind!(kb, bindings...)
  try
    f()
  finally
    unbind!(kb, token)
  end
  nothing
end
bind!(kb::KeyBindings, bindings::Pair...) = bind!(kb, aggregate_bindings(bindings))
function bind!(kb::KeyBindings, bindings::Vector{Pair{KeyCombination, Callable}})
  token = next!(kb.counter)
  insert!(kb.bindings, token, bindings)
  for (key, callable) in bindings
    active = get(kb.active, key, nothing)
    if isnothing(active)
      insert!(kb.active, key, callable)
    else
      kb.active[key] = callable
      push!(get!(Vector{Callable}, kb.inactive, key), active)
    end
  end
  token
end

function unbind!(kb::KeyBindings, token::KeyBindingsToken)
  bindings = get(kb.bindings, token, nothing)
  isnothing(bindings) && return
  delete!(kb.bindings, token)
  for (key, callable) in bindings
    active = get(kb.active, key, nothing)
    if !isnothing(active)
      prev = get(kb.inactive, key, nothing)
      if !isnothing(prev) && !isempty(prev)
        kb.active[key] = pop!(prev)
      else
        delete!(kb.active, key)
      end
    end
    inactive = get(kb.inactive, key, nothing)
    if !isnothing(inactive)
      i = findfirst(==(callable), inactive)
      !isnothing(i) && deleteat!(inactive, i)
      isempty(inactive) && delete!(kb.inactive, key)
    end
  end
end

function aggregate_bindings(bindings)
  aggregated = Pair{KeyCombination, Callable}[]
  for (keys, callable) in bindings
    isa(keys, KeyCombination) && (keys = [keys])
    for key in keys
      push!(aggregated, key => callable)
    end
  end
  aggregated
end

function set_contextual_shortcuts_visibility(visible::Bool)
  new_annotation = ifelse(visible, :application_shortcut_show, :application_shortcut_hide)
  old_annotation = ifelse(visible, :application_shortcut_hide, :application_shortcut_show)
  for widget in components(app.ecs, WIDGET_COMPONENT_ID, WidgetComponent)
    isa(widget, Text) || continue
    (; text) = widget
    for (i, (region, (label, annotation))) in enumerate(Base.annotations(text))
      label == :face || continue
      annotation == old_annotation || continue
      widget.text.annotations[i] = (region, label => new_annotation)
      # Changes made to mutable fields are not tracked by the Widget `setproperty!`
      # and must be synchronized manually.
      !widget.disabled && synchronize(widget)
      break
    end
  end
end
