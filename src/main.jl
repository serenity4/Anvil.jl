struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication, code::Int)
  @debug "Shutting down the rendering system"
  shutdown(givre)
  close(givre.wm, givre.window)
  @debug "Exiting application" * (!iszero(code) ? "(exit code: $(code))" : "")
  Exit(code)
end

function (givre::GivreApplication)()
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems(givre)
  code = givre.systems.event(givre.ecs)
  if isa(code, Int)
    exit(givre, code)
    schedule_shutdown()
  end
end

function main()
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  application_thread = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    givre = GivreApplication()
    LoopExecution(0.001; shutdown = false)(givre)()
  end
  monitor_children()
end

function initialize!(givre::GivreApplication)
  # Required because `WidgetComponent` is a Union, so `typeof(value)` at first insertion will be too narrow.
  givre.ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()

  # TODO: Use a `Widget` for this.
  texture = new_entity!(givre)
  set_location!(givre, texture, P2(-0.5, 0))
  set_geometry!(givre, texture, Box(P2(0.5, 0.5)))
  image = image_resource(givre.systems.rendering.renderer.device, RGBA.(rand(AGray{Float32}, 512, 512)))
  set_render!(givre, texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image)))

  settings_background = Rectangle(givre, Box(P2(0.4, 0.9)), RGB(0.01, 0.01, 0.01))
  model_text = Text(givre, "Model")
  path_text = Text(givre, "Path")
  box = get_geometry(givre, model_text)
  dropdown_bg = Rectangle(givre, box, RGB(0.3, 0.2, 0.9))
  put_behind!(givre, dropdown_bg, model_text)

  checkbox = Checkbox(identity, givre, false, Box(P2(0.02, 0.02)))
  button = Button(givre, Box(P2(0.15, 0.05)); text = Text(givre, "Save")) do
    button.background_color = rand(RGB{Float32})
  end

  on_input = let threshold = Ref((0.0, 0.0)), origin = Ref{P2}()
    function (input::Input)
      if input.type === BUTTON_PRESSED
        threshold[] = (0.0, 0.0)
        origin[] = get_location(givre, texture)
        dropdown_bg.color = rand(RGB{Float32})
      elseif input.type === DRAG
        target, event = input.dragged
        drag_amount = event.location .- input.source.event.location
        set_location!(givre, texture, origin[] .+ drag_amount)
        if sqrt(sum((drag_amount .- threshold[]) .^ 2)) > 0.5
          threshold[] = drag_amount
          renderable = get_render(givre, texture)
          set_render!(givre, texture, @set renderable.vertex_data = fill(Vec3(rand(3)), 4))
        end
      end
    end
  end
  insert!(givre.ecs, texture, INPUT_COMPONENT_ID, InputComponent(on_input, BUTTON_PRESSED, DRAG))

  vline_left = at(at(settings_background, :edge, :left), P2(0.2, 0))
  vline_right = at(vline_left, P2(0.05, 0))
  vspacing = 0.1

  add_constraint!(givre, attach(at(at(settings_background, :center), P2(-0.4, 0.0)), at(at(texture, :center), P2(0.5, 0.0))))

  add_constraint!(givre, align(at.([model_text, path_text], :edge, :right), :vertical, vline_left))
  add_constraint!(givre, align(at.([checkbox, dropdown_bg], :edge, :left), :vertical, vline_right))
  left_column = EntityID[model_text, path_text]
  right_column = EntityID[checkbox, dropdown_bg]

  for column in (left_column, right_column)
    add_constraint!(givre, distribute(column, :vertical, vspacing, :point))
  end

  add_constraint!(givre, attach(button, at(checkbox, P2(0.0, -0.2))))
end
