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
  givre.systems.synchronization(givre)
  givre.systems.drawing_order(givre.ecs)
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
  layout = ECSLayoutEngine{P2, Box{2,Float64}, LocationComponent, GeometryComponent}(givre.ecs)

  texture = new_entity!(givre)
  set_location!(givre, texture, P2(-0.4, -0.4))
  set_geometry!(givre, texture, Box(P2(0.5, 0.5)))
  image = image_resource(givre.systems.rendering.renderer.device, rand(RGBA{Float32}, 512, 512))
  set_render!(givre, texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image)))

  model_text = Text(givre, "Model")
  box = get_geometry(givre, model_text)
  dropdown_bg = Rectangle(givre, box, RGB(0.3, 0.2, 0.9))
  put_behind!(givre, dropdown_bg, model_text)

  checkbox = Checkbox(identity, givre, false, Box(P2(0.02, 0.02)))

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

  compute_layout!(layout, [texture, dropdown_bg, model_text], [
    attach(dropdown_bg, at(at(texture, :corner, CORNER_TOP_RIGHT), Point(0.2, -0.1))),
    attach(at(model_text, :center), dropdown_bg),
    attach(checkbox, at(at(model_text, :center), P2(0.2, 0.0))),
  ])
end
