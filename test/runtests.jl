using Givre, Test, Logging, DataFrames

Logging.disable_logging(Logging.Info)
ENV["JULIA_DEBUG"] = "Givre"
# ENV["JULIA_DEBUG"] = "Givre,ConcurrencyGraph"
# ENV["GIVRE_LOG_FRAMECOUNT"] = false
# ENV["GIVRE_RELEASE"] = true # may circumvent issues with validation layers

#= Known issues:
- `at(model_text, :center)` seems broken, as the dropdown background is not positioned correctly.
=# main()

df = DataFrame(Givre.app.ecs)
select(df, :Entity, :Render, :Input)
select(df, :Entity, :Z)
df.Name .=> df.Input

GC.gc()
