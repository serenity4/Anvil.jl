struct Exit
  code::Int
end

function Base.exit(givre::GivreApplication, code::Int)
  @debug "Shutting down renderer"
  shutdown(givre)
  close(givre.wm, givre.window)
  @debug "Exiting application" * (!iszero(code) ? "(exit code: $(code))" : "")
  Exit(code)
end

function (givre::GivreApplication)()
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
    LoopExecution(0.000; shutdown = false)(givre)()
  end
  monitor_children()
end

function initialize!(givre::GivreApplication)
  layout = ECSLayoutEngine{Point2, Box{2,Float64}, Point2, GeometryComponent}(givre.ecs)

  texture = new_entity!(givre)
  set_location!(givre, texture, Point2(-0.4, -0.4))
  set_geometry!(givre, texture, GeometryComponent(Box(Point2(0.5, 0.5)), 1.0))
  set_render!(givre, texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, image_resource(givre.systems.rendering.renderer.device, rand(RGBA{Float32}, 512, 512))))
  on_input = let threshold = Ref((0.0, 0.0)), origin = Ref{Point2}()
    function (input::Input)
      if input.type === BUTTON_PRESSED
        threshold[] = (0.0, 0.0)
        origin[] = givre.ecs[texture, LOCATION_COMPONENT_ID]::Point2
      elseif input.type === DRAG
        target, event = input.dragged
        drag_amount = event.location .- input.source.event.location
        set_location!(givre, texture, origin[] .+ drag_amount)
        if sqrt(sum((drag_amount .- threshold[]) .^ 2)) > 0.5
          threshold[] = drag_amount
          renderable = givre.ecs[texture, RENDER_COMPONENT_ID]::RenderComponent
          set_render!(givre, texture, @set renderable.vertex_data = fill(Vec3(rand(3)), 4))
        end
      end
    end
  end
  insert!(givre.ecs, texture, INPUT_COMPONENT_ID, InputComponent(texture, on_input, BUTTON_PRESSED, DRAG))

  button_bg = new_entity!(givre)
  set_location!(givre, button_bg, Point2(0, 0))
  set_geometry!(givre, button_bg, GeometryComponent(Box(Point2(0.1, 0.05)), 2.0))
  set_render!(givre, button_bg, RenderComponent(RENDER_OBJECT_RECTANGLE, repeat([Vec3(0.3, 0.2, 0.9)], 4), nothing))

  options = FontOptions(ShapingOptions(tag"latn", tag"fra "), 1/10)
  model_text = new!(givre, Text("juliamono-regular", OpenType.Text("Model", TextOptions()), options))
  set_location!(givre, model_text, zero(LocationComponent))

  compute_layout!(layout, [texture, button_bg, model_text], [
    attach(at(texture, FEATURE_LOCATION_CENTER), at(button_bg, Point(-1.0, 0.0))),
    attach(button_bg, model_text),
  ])
end
