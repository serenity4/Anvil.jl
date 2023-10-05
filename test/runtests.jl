using Givre, Test, ConcurrencyGraph

ENV["JULIA_DEBUG"] = "Givre"
# ENV["JULIA_DEBUG"] = "Givre,ConcurrencyGraph"
# ENV["GIVRE_LOG_FRAMECOUNT"] = false
ENV["GIVRE_RELEASE"] = true # circumvent issue with validation layers

#= Known issues:
=# main()

GC.gc()
