using Anvil, Test, Logging

!@isdefined(includet) && (includet = include)
includet("main.jl")

Logging.disable_logging(Logging.Info)
# Logging.disable_logging(Logging.BelowMinLevel)
ENV["JULIA_DEBUG"] = "Anvil"
# ENV["JULIA_DEBUG"] = "Anvil,CooperativeTasks"
# ENV["ANVIL_LOG_FRAMECOUNT"] = false
# ENV["ANVIL_LOG_KEY_PRESS"] = true
# ENV["ANVIL_RELEASE"] = true # may circumvent issues with validation layers

main()

@testset "Anvil.jl" begin
  include("layout.jl")
  include("bindings.jl")
  include("observables.jl")
  include("application.jl")
end;

using DataFrames
df = DataFrame(Anvil.app.ecs)
select(df, :Name, :Render)
select(df, :Name, :Z)
select(df, :Name, :Location)

GC.gc()
