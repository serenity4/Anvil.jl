using Preferences: Preferences, @load_preference
set_preferences!(args...; kwargs...) = Preferences.set_preferences!(@__MODULE__, args...; kwargs...)

macro is_release()
  :(@load_preference("RELEASE", "false") == "true")
end
