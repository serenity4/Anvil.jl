mutable struct WindowState
  overlay::Vector{InputArea}
  callbacks::WindowCallbacks
  key_bindings::KeyBindings
  render_nodes::Vector{RenderNode}
end

struct GivreState
  windows::Dictionary{Window, WindowState}
end

GivreState(pairs...) = GivreState(dictionary(pairs))

function set_key_bindings(app::Application, win::Window, win_state::WindowState)
  (; callbacks) = win_state
  set_callbacks(app, win, @set callbacks.on_key_pressed = on_key_pressed(win_state.kb, app))
end

function update!(app::Application, givre::GivreState)
  for (win, win_state) in pairs(givre.windows)
    overlay(app, win, win_state.overlay)
    set_callbacks(app, win, win_state.callbacks)
    set_key_bindings(app, win, win_state)
    execute(Base.Fix1(task_local_storage, :givre_renderables), app.renderer, copy(win_state.renderables))
  end
end

function render_main_window(rg::RenderGraph, image, renderables)
  color = attachment_resource(ImageView(image), WRITE)
  @reset color.id = COLOR_ATTACHMENT.id
  substitute_color_attachment!
end

function main()
  app = Application()
  main_task = current_task()
  win = create_window(app, "Givre"; map = false)
  givre = GivreState(
    win => WindowState(
      [],
      WindowCallbacks(),
      KeyBindings(
        key"ctrl+q" => (_, app::Application, _...) -> execute(finalize, main_task, app),
      ),
      [
        Rectangle(Point(0.0, 0.0), Box(Scaling(0.2f0, 0.3f0)), RGBA(0.5, 0.5, 0.9, 1.0))
      ],
    ),
  )
  update!(app, givre)
  unwrap(fetch(render((rg, image) -> render_main_window(rg, image, givre.windows[win].render_components), app, win)))
  map_window(win)
  monitor_children()
end
