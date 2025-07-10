using Anvil, Test, Logging

!@isdefined(includet) && (includet = include)
includet("main.jl")

filter_validation_message("VUID-VkImageViewCreateInfo-usage-02275")
filter_validation_message("VUID-VkSwapchainCreateInfoKHR-presentMode-02839")

Logging.disable_logging(Logging.Info)
# Logging.disable_logging(Logging.BelowMinLevel)
# ENV["JULIA_DEBUG"] = "Anvil"
# ENV["JULIA_DEBUG"] = "Anvil,CooperativeTasks"
# ENV["ANVIL_LOG_FRAMECOUNT"] = false
# ENV["ANVIL_LOG_KEY_PRESS"] = true
# ENV["ANVIL_RELEASE"] = true # may circumvent issues with validation layers

STAGED_RENDERING[] = true
# STAGED_RENDERING[] = false
main()

# XXX: We are running out of fences, investigate
# XXX: Stutters are seemingly caused by fence and memory destructors.
# XXX: Lots of overhead due to memory allocations as well.
# XXX: Transparent renders seem to not work properly in either staged rendering or not.

#=
TODO:
- Test interaction sets.
- Test geometry features.
- Test image modes.
=#

@testset "Anvil.jl" begin
  include("layout.jl")
  include("bindings.jl")
  include("observables.jl")
  include("debug.jl")
  include("application.jl")
end;

# For debugging.

using DataFrames
df = DataFrame(Anvil.app.ecs; remap = true)
df = DataFrame(Anvil.app.ecs)
select(df, :Name, :Render)
select(df, :Name, :Z)
select(df, :Name, :Location)
df.Render

GC.gc()
main(replay = true, exit_after_replay = false)
