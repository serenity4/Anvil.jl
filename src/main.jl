struct Exit
  code::Int
end

function exit(code::Int)
  shutdown(givre)
  close(givre.wm, givre.window)
  @debug "Exiting application" * (!iszero(code) ? "(exit code: $(code))" : "")
  Exit(code)
end

function (givre::GivreApplication)()
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems()
  code = givre.systems.event(givre.ecs)
  if isa(code, Int)
    exit(code)
    schedule_shutdown()
  end
end

function main()
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  application_thread = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    initialize()
    LoopExecution(0.001; shutdown = false)(givre)()
  end
  monitor_children()
end

function initialize_components()
  # Required because `WidgetComponent` is a Union, so `typeof(value)` at first insertion will be too narrow.
  givre.ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()

  # TODO: Use a `Widget` for this.
  texture = new_entity!()
  set_location(texture, P2(-0.5, 0))
  set_geometry(texture, Box(P2(0.5, 0.5)))
  image = image_resource(givre.systems.rendering.renderer.device, RGBA.(rand(AGray{Float32}, 512, 512)))
  set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image)))

  settings_background = Rectangle(Box(P2(0.4, 0.9)), RGB(0.01, 0.01, 0.01))
  model_text = Text("Model")
  path_text = Text("Path")
  box = get_geometry(model_text)
  dropdown_bg = Rectangle(box, RGB(0.3, 0.2, 0.9))
  put_behind(dropdown_bg, model_text)

  checkbox = Checkbox(identity, false, Box(P2(0.02, 0.02)))
  button = Button(Box(P2(0.15, 0.05)); text = Text("Save")) do
    button.background_color = rand(RGB{Float32})
  end

  on_input = let threshold = Ref((0.0, 0.0)), origin = Ref{P2}()
    function (input::Input)
      if input.type === BUTTON_PRESSED
        threshold[] = (0.0, 0.0)
        origin[] = get_location(texture)
        dropdown_bg.color = rand(RGB{Float32})
      elseif input.type === DRAG
        target, event = input.dragged
        drag_amount = event.location .- input.source.event.location
        set_location(texture, origin[] .+ drag_amount)
        if sqrt(sum((drag_amount .- threshold[]) .^ 2)) > 0.5
          threshold[] = drag_amount
          renderable = get_render(texture)
          set_render(texture, @set renderable.vertex_data = fill(Vec3(rand(3)), 4))
        end
      end
    end
  end
  insert!(givre.ecs, texture, INPUT_COMPONENT_ID, InputComponent(on_input, BUTTON_PRESSED, DRAG))

  vline_left = at(at(settings_background, :edge, :left), P2(0.2, 0))
  vline_right = at(vline_left, P2(0.05, 0))
  vspacing = 0.1

  add_constraint(attach(at(at(settings_background, :center), P2(-0.4, 0.0)), at(at(texture, :center), P2(0.5, 0.0))))

  add_constraint(align(at.([model_text, path_text], :edge, :right), :vertical, vline_left))
  add_constraint(align(at.([checkbox, dropdown_bg], :edge, :left), :vertical, vline_right))
  left_column = EntityID[model_text, path_text]
  right_column = EntityID[checkbox, dropdown_bg]

  for column in (left_column, right_column)
    add_constraint(distribute(column, :vertical, vspacing, :point))
  end

  add_constraint(attach(button, at(checkbox, P2(0.0, -0.2))))
end
