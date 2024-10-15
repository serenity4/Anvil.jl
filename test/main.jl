using Anvil: Text
using Lava: image_resource
using ShaderLibrary: Sprite
using LinearAlgebra: norm

function start_app()
  # TODO: Use a `Widget` for this.
  @set_name texture = new_entity()
  set_location(texture, P2(-0.5, 0))
  set_geometry(texture, Box(P2(0.5, 0.5)))
  random_image() = image_resource(app.systems.rendering.renderer.device, RGBA.(rand(AGray{Float32}, 512, 512)))
  image = random_image()
  set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image)))

  @set_name side_panel = Rectangle((0.8, 1.8), RGB(0.01, 0.01, 0.01))

  @set_name save_button = Button((0.3, 0.1); text = Text("Save")) do
    save_button.background.color = rand(RGB{Float32})
  end

  on_input = let origin = Ref(zero(P2)), last_displacement = Ref(zero(P2)), total_drag = Ref(zero(P2))
    function (input::Input)
      if is_left_click(input)
        origin[] = get_location(texture)
        last_displacement[] = origin[]
        node_color_value.color = rand(RGB{Float32})
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
  file_menu_head = Button(() -> collapse!(file_menu), (0.3, 0.1); text = Text("File"))
  file_menu_item_1 = MenuItem(Text("New file"), (0.3, 0.1)) do
    save_button.background.color = RGB{Float32}(0.1, 0.3, 0.2)
  end
  file_menu_item_2 = MenuItem(Text("Open..."), (0.3, 0.1)) do
    save_button.background.color = RGB{Float32}(0.3, 0.2, 0.1)
  end
  file_menu_item_3 = MenuItem(exit, Text("Exit"), (0.3, 0.1), 'x')
  @set_name file_menu = Menu(file_menu_head, [file_menu_item_1, file_menu_item_2, file_menu_item_3], 'F')
  add_constraint(attach(at(file_menu, :corner, :top_left), at(app.windows[app.window], :corner, :top_left)))

  # Edit menu.
  edit_menu_head = Button(() -> collapse!(edit_menu), (0.3, 0.1); text = Text("Edit"))
  edit_menu_item_1 = MenuItem(Text("Regenerate"), (0.3, 0.1)) do
    new_image = fetch(execute(random_image, app.systems.rendering.renderer.task))
    set_render(texture, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(new_image)))
  end
  @set_name edit_menu = Menu(edit_menu_head, [edit_menu_item_1], 'E')
  add_constraint(attach(at(edit_menu, :corner, :top_left), at(file_menu, :corner, :top_right)))

  vline_left = at(at(side_panel, :edge, :left), 0.2)
  vline_right = at(vline_left, 0.05)
  vspacing = 0.1

  add_constraint(attach(at(at(side_panel, :center), P2(-0.4, 0.0)), at(at(texture, :center), P2(0.5, 0.0))))

  @set_name node_name_text = Text("Name")
  @set_name node_name_value = Rectangle((0.1, 0.04), RGB(0.2, 0.2, 0.2))
  @set_name node_color_text = Text("Color")
  @set_name node_color_value = Rectangle((0.1, 0.04), RGB(0.3, 0.2, 0.9))
  @set_name node_hide_text = Text("Hide")
  @set_name node_hide_value = Checkbox(_ -> nothing)
  left_column = EntityID[
    node_name_text,
    node_color_text,
    node_hide_text,
  ]
  right_column = EntityID[
    node_name_value,
    node_color_value,
    node_hide_value,
  ]
  add_constraint(align(at.(left_column, :edge, :right), :vertical, vline_left))
  add_constraint(align(at.(right_column, :edge, :left), :vertical, vline_right))

  for column in (left_column, right_column)
    add_constraint(distribute(column, :vertical, vspacing, :point))
  end

  add_constraint(attach(save_button, at(left_column[end], P2(0.2, -0.2))))
end

main(; async = false) = Anvil.main(start_app; async)
