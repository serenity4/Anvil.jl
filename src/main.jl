struct Exit
  code::Int
end

function exit(code::Int)
  shutdown(app)
  close(app.wm, app.window)
  @debug "Exiting application" * (!iszero(code) ? "(exit code: $(code))" : "")
  Exit(code)
end

function (app::Application)()
  # Make sure that the drawing order (which also defines interaction order)
  # has been resolved prior to resolving which object receives which event based on that order.
  run_systems()
  code = app.systems.event(app.ecs)
  if isa(code, Int)
    exit(code)
    schedule_shutdown()
  end
end

function main(; async = false)
  nthreads() ≥ 3 || error("Three threads or more are required to execute the application.")
  reset_mpi_state()
  app.task = spawn(SpawnOptions(start_threadid = APPLICATION_THREADID, allow_task_migration = false)) do
    initialize()
    LoopExecution(0.001; shutdown = false)(app)()
  end
  async && return false
  wait(app)
end

synchronize() = fetch(execute(() -> (app(); true), app.task))

function initialize_components()
  # Required because `WidgetComponent` is a Union, so `typeof(value)` at first insertion will be too narrow.
  app.ecs.components[WIDGET_COMPONENT_ID] = ComponentStorage{WidgetComponent}()

  # TODO: Use a `Widget` for this.
  texture = new_entity()
  set_location(texture, P2(-0.5, 0))
  set_geometry(texture, Box(P2(0.5, 0.5)))
  random_image() = image_resource(app.systems.rendering.renderer.device, RGBA.(rand(AGray{Float32}, 512, 512)))
  image = random_image()
  set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image)))
  @set_name texture

  settings_background = Rectangle(Box(P2(0.4, 0.9)), RGB(0.01, 0.01, 0.01))
  model_text = Text("Model")
  path_text = Text("Path")
  box = get_geometry(model_text)
  dropdown_bg = Rectangle(box, RGB(0.3, 0.2, 0.9))
  put_behind(dropdown_bg, model_text)

  checkbox = Checkbox(identity, false, Box(P2(0.02, 0.02)))
  button = Button(Box(P2(0.15, 0.05)); text = Text("Save")) do
    button.background.color = rand(RGB{Float32})
  end
  @set_name checkbox button

  on_input = let origin = Ref(zero(P2)), last_displacement = Ref(zero(P2)), total_drag = Ref(zero(P2))
    function (input::Input)
      if is_left_click(input)
        origin[] = get_location(texture)
        last_displacement[] = origin[]
        dropdown_bg.color = rand(RGB{Float32})
      elseif input.type === DRAG
        target, event = input.drag
        displacement = event.location .- input.source.event.location
        segment = displacement .- last_displacement[]
        last_displacement[] = SVector(displacement)
        total_drag[] = total_drag[] .+ abs.(segment)
        set_location(texture, origin[] .+ displacement)
        if norm(total_drag) > 1.0
          total_drag[] = (0.0, 0.0)
          renderable = get_render(texture)
          new_image = fetch(execute(random_image, app.systems.rendering.renderer.task))
          set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(new_image)))
        end
      end
    end
  end
  set_input_handler(texture, InputComponent(on_input, BUTTON_PRESSED, DRAG))

  # File menu.
  file_menu_head = Button(() -> collapse!(file_menu), Box(P2(0.15, 0.05)); text = Text("File"))
  file_menu_item_1 = MenuItem(Text("New file"), Box(P2(0.15, 0.05))) do
    button.background.color = RGB{Float32}(0.1, 0.3, 0.2)
  end
  file_menu_item_2 = MenuItem(Text("Open..."), Box(P2(0.15, 0.05))) do
    button.background.color = RGB{Float32}(0.3, 0.2, 0.1)
  end
  file_menu = Menu(file_menu_head, [file_menu_item_1, file_menu_item_2])
  add_constraint(attach(at(file_menu, :corner, :top_left), at(app.windows[app.window], :corner, :top_left)))
  @set_name file_menu

  # Edit menu.
  edit_menu_head = Button(() -> collapse!(edit_menu), Box(P2(0.15, 0.05)); text = Text("Edit"))
  edit_menu_item_1 = MenuItem(Text("Regenerate"), Box(P2(0.15, 0.05))) do
    new_image = fetch(execute(random_image, app.systems.rendering.renderer.task))
    set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(new_image)))
  end
  edit_menu = Menu(edit_menu_head, [edit_menu_item_1])
  add_constraint(attach(at(edit_menu, :corner, :top_left), at(file_menu, :corner, :top_right)))
  @set_name edit_menu

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
