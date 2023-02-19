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

struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication)
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
  isa(ret, Exit) && shutdown()
end

function main()
  reset_mpi_state()
  application_thread = @spawn begin
    givre = GivreApplication()
    LoopExecution(0.002)(givre)()
  end
  monitor_children()
end
