using Givre, Test, ConcurrencyGraph

ENV["JULIA_DEBUG"] = "Givre"
# ENV["GIVRE_LOG_FRAMECOUNT"] = false
# ENV["GIVRE_RELEASE"] = true

#= Known issues:
A deadlock sometimes appears when exiting the application - the application and renderer threads waiting for each other, it seems.
This could explain why the finalizers do not run for the window, as it would be held by either.
There is also an issue that manifests when closing the application, related to errors from finalizers within FileWatching - could be due to that too.
=# main()

ts = children_tasks()
Base.get_task_tls(ts[1])
reset_mpi_state()

GC.gc()
