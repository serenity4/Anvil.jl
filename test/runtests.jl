using Givre, Test, ConcurrencyGraph

ENV["JULIA_DEBUG"] = "Givre"
# ENV["JULIA_DEBUG"] = "Givre,ConcurrencyGraph"
# ENV["GIVRE_LOG_FRAMECOUNT"] = false
# ENV["GIVRE_RELEASE"] = true # may circumvent issues with validation layers

#= Known issues:
- The dragging effect may be stuck, i.e. it sometimes doesn't release on button release and there is no way to undo it (besides waiting for some other bug later which apparently unsticks it).
- `at(model_text, :center)` seems broken, as the dropdown background is not positioned correctly.
=# main()

GC.gc()
