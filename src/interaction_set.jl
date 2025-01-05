"""
Group a set of widgets to later be deleted altogether.

The aim of interaction sets is to provide a mechanism through which applications
may wipe parts of their user interface, e.g. when a new panel is selected and
a given window region must be cleared to give room to new widgets.

Usage:
```julia
set = InteractionSet()

push!(set, widget_id::WidgetID)
push!(set, widget) # `widget` will be converted to a `WidgetID`

delete!(set, widget_id::WidgetID)
delete!(set, widget) # `widget` will be converted to a `WidgetID`

wipe!(set) # delete all widgets that were pushed to the interaction set

empty!(set) # in case you want to clear all widgets without wiping them
```

To automate the process of registering widgets with an interaction set,
a global interaction set may be used via [`use_interaction_set`](@ref)
(queried with [`current_interaction_set`](@ref)). All widgets constructed
while a global interaction set exists will added to this `set`, removing
the need to manually `push!` them.

This enables the following pattern:
```julia
set = InteractionSet()
use_interaction_set(set)

# Somewhere else (possibly in a different function that does not
# have `set` in scope), create widgets as you like.
widget = Text("hello")
# ...

# Somewhere else (possibly in a different function than the last)
set = current_interaction_set()
wipe!(set)
```

See also: [`use_interaction_set`](@ref), [`current_interaction_set`](@ref), [`wipe!`](@ref)
"""
struct InteractionSet
  widgets::Set{WidgetID}
end

InteractionSet() = InteractionSet(Set{WidgetID}())

Base.empty!(set::InteractionSet) = empty!(set.widgets)
Base.push!(set::InteractionSet, widget, widgets...) = push!(set.widgets, convert(WidgetID, widget), convert.(WidgetID, widgets)...)
Base.delete!(set::InteractionSet, widget, widgets...) = delete!(set.widgets, convert(WidgetID, widget), convert.(WidgetID, widgets)...)

"""
Delete all widgets contained in the provided interaction set.
"""
function wipe!(set::InteractionSet)
  for id in set.widgets
    has_widget(id) || continue
    widget = get_widget(id)
    delete_widget(widget)
  end
  empty!(set)
end

"Reference to a global interaction set with which widgets will be registered on construction."
const INTERACTION_SET = Ref{Optional{InteractionSet}}(nothing)

"""
Set the global interaction set, returning the one previously in use.

Use `nothing` as an argument to unset the global interaction set.
"""
function use_interaction_set(set::Optional{InteractionSet})
  old = INTERACTION_SET[]
  setindex!(INTERACTION_SET, set)
  old
end

"Call `f()` using the provided interaction set, then restore the original set."
function use_interaction_set(f, set::InteractionSet)
  old = use_interaction_set(set)
  try
    f()
  finally
    use_interaction_set(old)
  end
end

"Return the interaction set currently in use."
current_interaction_set() = INTERACTION_SET[]
