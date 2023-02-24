struct GivreApplication
  wm::WindowManager
  queue::EventQueue{WindowManager}
  rdr::Renderer
  # Vulkan devices are freely usable from multiple threads.
  # Only specific functions require external synchronization, hopefully we don't need those outside of the renderer.
  device::Device
  window::Window
  function GivreApplication()
    wm = XWindowManager()
    window = Window(wm, "Givre"; width = 1920, height = 1080, map = false)
    rdr = Renderer(window)
    givre = new(wm, EventQueue(wm), rdr, rdr.device, window)
    start_renderer(givre)
    map_window(window)
    givre
  end
end

function start_renderer(givre::GivreApplication)
  (; rdr) = givre
  options = SpawnOptions(start_threadid = RENDERER_THREADID, allow_task_migration = false, execution_mode = LoopExecution(0.005))
  rdr.task = spawn(() -> render(givre, rdr), options)
end

# Only call that from the application thread.
shutdown_renderer(givre::GivreApplication) = wait(shutdown_children())

struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication)
  @debug "Shutting down renderer"
  shutdown_renderer(givre)
  wait(givre.device)
  close(givre.wm, givre.window)
  @debug "Exiting application"
  Exit(0)
end

function (givre::GivreApplication)(event::Event)
  if event.type == KEY_PRESSED
    matches(key"ctrl+q", event) && return exit(givre)
  end
end

function (givre::GivreApplication)()
  isempty(givre.queue) && collect_events!(givre.queue)
  isempty(givre.queue) && return
  event = popfirst!(givre.queue)
  ret = givre(event)
  isa(ret, Exit) && schedule_shutdown()
end

function main()
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  application_thread = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    givre = GivreApplication()
    LoopExecution(0.002; shutdown = false)(givre)()
  end
  monitor_children()
end
