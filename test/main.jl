using Anvil: Text, MENU_ITEM_COLOR, MENU_ITEM_ACTIVE_COLOR, exit
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
  info::Dict{Symbol, Any}
  ApplicationState() = new(random_image(), 0, Dict())
end

function generate_user_interface(state::ApplicationState)
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
  add_callback(on_input, image, BUTTON_PRESSED, DRAG)

  # File menu.
  file_menu_head = Rectangle((3, 1), MENU_ITEM_COLOR)
  file_menu_head_text = Text("File")
  file_menu = Menu(file_menu_head, 'F'; on_expand = menu -> generate_file_menu!(menu, state), on_collapse = close!)
  place(file_menu_head |> at(:top_left), app.windows[app.window] |> at(:top_left))
  place(at(file_menu_head_text, :center), at(file_menu_head, :center))
  state.info[:file_menu] = file_menu

  # Edit menu.
  edit_menu_head = Rectangle((3, 1), MENU_ITEM_COLOR)
  edit_menu_text = Text("Edit")
  edit_menu = Menu(edit_menu_head, 'E'; on_expand = menu -> generate_edit_menu!(menu, state), on_collapse = close!)
  place(edit_menu_head |> at(:top_left), file_menu_head |> at(:top_right))
  place(at(edit_menu_text, :center), at(edit_menu_head, :center))
  state.info[:edit_menu] = edit_menu

  vline_left = side_panel |> at(:left) |> at(3.0)
  vline_right = vline_left |> at(1.5)
  vspacing = 1.0

  place(side_panel |> at(:left), image |> at(:right))

  @set_name node_name_text = Text("Name")
  @set_name node_name_value = Text("Value"; editable = true)
  @set_name node_color_text = Text("Color")
  @set_name node_color_value = Rectangle((1.0, 0.4), RGBA(0.3, 0.2, 0.9, 0.2))
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

on_active(widget) = active -> widget.color = ifelse(active, MENU_ITEM_ACTIVE_COLOR, MENU_ITEM_COLOR)

generate_menu_item(f, text::AbstractString, dimensions; shortcut = nothing) = generate_menu_item(f, Text(text), dimensions; shortcut)

function generate_menu_item(f, text::Text, dimensions; shortcut = nothing)
  background = Rectangle(dimensions, MENU_ITEM_COLOR)
  place(at(text, :left), at(background, :left) |> at(0.2, 0.0))
  MenuItem(f, background; text, on_active = on_active(background), shortcut)
end

function generate_file_menu!(menu::Menu, state::ApplicationState)
  dimensions = (3, 1)
  items = MenuItem[]

  push!(items, generate_menu_item("New file", dimensions) do
    @get_widget save_button
    save_button.background.color = RGB{Float32}(0.1, 0.3, 0.2)
  end)

  push!(items, generate_menu_item("Open...", dimensions) do
    @get_widget save_button
    save_button.background.color = RGB{Float32}(0.3, 0.2, 0.1)
  end)

  push!(items, generate_menu_item(exit, "Exit", dimensions; shortcut = 'x'))

  align([at(item.widget, :left) for item in items], :vertical, at(menu.head, :left))
  distribute([menu.head; [item.widget for item in items]], :vertical, 0.0, :geometry)
  add_menu_items!(menu, items)
end

function generate_edit_menu!(menu::Menu, state::ApplicationState)
  dimensions = (3, 1)
  items = MenuItem[]

  push!(items, generate_menu_item("Regenerate", dimensions) do
    regenerate_image(state)
  end)

  align([at(item.widget, :left) for item in items], :vertical, at(menu.head, :left))
  distribute([menu.head; [item.widget for item in items]], :vertical, 0.0, :geometry)
  add_menu_items!(menu, items)
end

main(state = ApplicationState(); async = false, record_events = false) = Anvil.main(() -> generate_user_interface(state); async, record_events)
