using Givre, Test, Logging, DataFrames
using Givre: exit

Logging.disable_logging(Logging.Info)
# Logging.disable_logging(Logging.BelowMinLevel)
ENV["JULIA_DEBUG"] = "Givre"
# ENV["JULIA_DEBUG"] = "Givre,CooperativeTasks"
# ENV["GIVRE_LOG_FRAMECOUNT"] = false
# ENV["GIVRE_LOG_KEY_PRESS"] = true
# ENV["GIVRE_RELEASE"] = true # may circumvent issues with validation layers

#= Known issues:
- `at(model_text, :center)` seems broken, as the dropdown background is not positioned correctly.
=# main()

@testset "Givre.jl" begin
  include("layout.jl")
  include("bindings.jl")
  include("application.jl")
end
df = DataFrame(Givre.app.ecs)
select(df, :Entity, :Render, :Input)
select(df, :Entity, :Z)
select(df, :Entity, :Location)
df.Name .=> df.Input

GC.gc()
