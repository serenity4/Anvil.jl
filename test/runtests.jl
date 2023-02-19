using Givre, Test, ConcurrencyGraph

ENV["JULIA_DEBUG"] = "Givre"

#= Known issues:
The command pool is occasionally reported as used simultaneously from multiple threads.
Could be related to finalizers or to task migration. Task migration should however be disabled, so I would look into finalizers.

A deadlock sometimes appears when exiting the application - the application and renderer threads waiting for each other, it seems.
This could explain why the finalizers do not run for the window, as it would be held by either.
There is also an issue that manifests when closing the application, related to errors from finalizers within FileWatching - could be due to that too.
=# main()

ts = children_tasks()
Base.get_task_tls(ts[1])
reset_mpi_state()

GC.gc()
