using Anvil: Text, @observable, @bind
using Lava: image_resource
using ShaderLibrary: Sprite
using LinearAlgebra: norm

function save(state)
  state.number_of_saves += 1
  println("Saved $(state.number_of_saves) times!")
end

function regenerate_image(state)
  state.image = random_image()
end

random_image() = RGBA.(rand(AGray{Float32}, 512, 512))

@observable mutable struct ApplicationState
  image::Matrix{RGBA{Float32}}
  number_of_saves::Int64
  ApplicationState() = new(random_image(), 0)
end

function generate_user_interface(state::ApplicationState = ApplicationState())
  @set_name image = Rectangle((10, 10), state.image)
  @bind image.texture => state.image
  set_location(image, P2(-5, 0))

  @set_name side_panel = Rectangle((12, 22), RGB(0.01, 0.01, 0.01))

  @set_name save_button = Button((3, 1); text = Text("Save")) do
    save(state)
    save_button.background.color = rand(RGB{Float32})
  end

  on_input = let origin = Ref(zero(P2)), last_displacement = Ref(zero(P2)), total_drag = Ref(zero(P2))
    function (input::Input)
      if is_left_click(input)
        origin[] = get_location(image)
        last_displacement[] = origin[]
        node_color_value.color = rand(RGB{Float32})
      elseif input.type === DRAG
        target, event = input.drag
        displacement = event.location .- input.source.event.location
        segment = displacement .- last_displacement[]
        last_displacement[] = SVector(displacement)
        total_drag[] = total_drag[] .+ abs.(segment)
        set_location(image, origin[] .+ displacement)
        if norm(total_drag) > 10
          total_drag[] = (0.0, 0.0)
          regenerate_image(state)
        end
      end
    end
  end
  intercept_inputs(on_input, image, BUTTON_PRESSED, DRAG)

  # File menu.
  file_menu_head = Button(() -> collapse!(file_menu), (3, 1); text = Text("File"))
  file_menu_item_1 = MenuItem(Text("New file"), (3, 1)) do
    save_button.background.color = RGB{Float32}(0.1, 0.3, 0.2)
  end
  file_menu_item_2 = MenuItem(Text("Open..."), (3, 1)) do
    save_button.background.color = RGB{Float32}(0.3, 0.2, 0.1)
  end
  file_menu_item_3 = MenuItem(exit, Text("Exit"), (3, 1), 'x')
  @set_name file_menu = Menu(file_menu_head, [file_menu_item_1, file_menu_item_2, file_menu_item_3], 'F')
  place(file_menu |> at(:top_left), app.windows[app.window] |> at(:top_left))

  # Edit menu.
  edit_menu_head = Button(() -> collapse!(edit_menu), (3, 1); text = Text("Edit"))
  edit_menu_item_1 = MenuItem(Text("Regenerate"), (3, 1)) do
    regenerate_image(state)
  end
  @set_name edit_menu = Menu(edit_menu_head, [edit_menu_item_1], 'E')
  place(edit_menu |> at(:top_left), file_menu |> at(:top_right))

  vline_left = side_panel |> at(:left) |> at(3.0)
  vline_right = vline_left |> at(1.5)
  vspacing = 1.0

  place(side_panel |> at(:left), image |> at(:right))

  @set_name node_name_text = Text("Name")
  @set_name node_name_value = Rectangle((1.0, 0.4), RGB(0.2, 0.2, 0.2))
  @set_name node_color_text = Text("Color")
  @set_name node_color_value = Rectangle((1.0, 0.4), RGB(0.3, 0.2, 0.9))
  @set_name node_hide_text = Text("Hide")
  @set_name node_hide_value = Checkbox(_ -> nothing)
  left_column = [node_name_text, node_color_text, node_hide_text]
  right_column = [node_name_value, node_color_value, node_hide_value]

  align(left_column .|> at(:right), :vertical, vline_left)
  align(right_column .|> at(:left), :vertical, vline_right)

  distribute(left_column, :vertical, vspacing, :point)
  for (left, right) in zip(left_column, right_column)
    align(right |> at(:bottom), :horizontal, left |> at(:bottom))
  end

  place(save_button, left_column[end] |> at(3.0, -2.0))
end

main(; async = false) = Anvil.main(generate_user_interface; async)
