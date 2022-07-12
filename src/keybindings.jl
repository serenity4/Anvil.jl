struct KeyBindings
  bindings::Dictionary{KeyCombination, Any #= Callable =#}
end

KeyBindings(bindings...) = KeyBindings(dictionary(bindings))

@forward KeyBindings.bindings (Base.haskey, Base.get, Base.getindex)

for f in (:merge, :merge!)
  @eval Base.$f(kb::KeyBindings, kbs::KeyBindings...) = $f(kb.bindings, getproperty.(kbs, :bindings)...)
end

function on_key_pressed(kb::KeyBindings, args...)
  function _on_key_pressed(ed::EventDetails)
    (; data) = ed
    (; key, modifiers) = data
    kc = KeyCombination(key, modifiers)
    f = get(kb.bindings, kc, nothing)
    isnothing(f) && return
    f(ed, args...)
  end
end
