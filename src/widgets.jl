const WidgetID = EntityID

"""
A widget is a user-interface element rendered on screen that a user may or may not interact with.

Common examples include clickable buttons, static text displays, checkboxes, dropdowns, and more.
"""
abstract type Widget end

function synchronize!(widget::Widget)
  synchronize(widget)
  widget.modified = false
end
synchronize(::Widget) = nothing

Base.convert(::Type{WidgetID}, widget::Widget) = widget.id

function Base.setproperty!(widget::Widget, name::Symbol, value)
  (name === :modified || name === :id || name === :disabled) && return setfield!(widget, name, value)
  prev = getproperty(widget, name)
  prev === value && return value
  widget.modified = true
  setfield!(widget, name, value)
  synchronize(widget)
  value
end

function new_widget(::Type{T}, args...) where {T<:Widget}
  entity = new_entity()
  set_location(entity, zero(LocationComponent))
  widget = T(entity, args...)
  set_widget(entity, widget)
  synchronize!(widget)
  widget
end

disable!(widget::WidgetID) = disable!(get_widget(widget))
function disable!(widget::Widget)
  for part in constituents(widget)
    disable!(part)
  end
  unset_render(widget)
  unset_input_handler(widget)
  remove_constraints(widget)
  widget.disabled = true
  widget
end

enable!(widget::WidgetID) = enable!(get_widget(widget))
function enable!(widget::Widget)
  for part in constituents(widget)
    enable!(part)
  end
  synchronize(widget)
  widget.disabled = false
  widget
end

function set_name(widget::Widget, name::Symbol)
  set_name(widget.id, name)
  parts = constituents(widget)
  for (i, part) in enumerate(parts)
    part = isa(part, WidgetID) ? get_widget(part) : part
    set_name(part, Symbol(name, :_, i))
  end
end

"""
    @widget struct Rectangle
      geometry::Box2
      color::RGB{Float32}
    end

Turn a `struct` declaration into a mutable `Widget` subtype,
with two additional fields:
- `const id::WidgetID` to identify the widget.
- `modified::Bool` to keep track of changes made to the widget.

A constructor is furthermore added which receives all arguments except `modified` and sets `modified` to `true`.

Any `Widget` subtype should be declared in a way that is compatible to the above.
"""
macro widget(ex)
  @match ex begin
    Expr(:struct, mutable, name, block) => begin
      ex.args[1] = true # force mutability
      fields = map(x -> Meta.isexpr(x, :const) ? x.args[1] : x, filter(x -> Meta.isexpr(x, (:const, :(::))), block.args))
      new = @match name begin
        :($_{$Ts...}) => :(new{$(Ts...)})
        _ => :new
      end
      !Meta.isexpr(name, :(<:)) && (ex.args[2] = Expr(:(<:), ex.args[2], Widget)) # force subtyping `Widget`.
      pushfirst!(block.args, Expr(:const, :(id::$WidgetID)), :(modified::Bool), :(disabled::Bool))
      push!(block.args, :($name(id::$WidgetID, args...) = $new(id, false, false, args...)))
    end
    _ => error("Expected a struct declaration, got `$ex`")
  end
  esc(ex)
end

constituents(widget::Widget) = Widget[]

@widget struct Rectangle
  geometry::Box2
  color::RGB{Float32}
end

Rectangle((width, height)::Tuple, color) = Rectangle(geometry(width, height), color)
Rectangle(geometry::Box, color) = new_widget(Rectangle, geometry, color)

function synchronize(rect::Rectangle)
  (; r, g, b) = rect.color
  vertex_data = [Vec3(r, g, b) for _ in 1:4]
  set_geometry(rect, rect.geometry)
  set_render(rect, RenderComponent(RENDER_OBJECT_RECTANGLE, vertex_data, Gradient(); is_opaque = true))
end

@widget struct Image
  geometry::GeometryComponent
  texture::Texture
  is_opaque::Bool
end

Image(geometry::GeometryComponent, texture::Texture, is_opaque::Bool) = new_widget(Image, geometry, texture, is_opaque)
Image((width, height)::Tuple, texture::Texture, is_opaque::Bool) = Image(geometry(width, height), texture, is_opaque)
Image(geometry, data; is_opaque::Bool = false) = Image(geometry, texture(data), is_opaque)

function Image(data, scale::Real = 1; is_opaque::Bool = false)
  data = texture(data)
  width, height = dimensions(data.image) .* scale * 0.001
  Image((width, height), data, is_opaque)
end

texture(data::Texture) = data
texture(data::AbstractMatrix) = load_texture(data)

function Base.setproperty!(image::Image, name::Symbol, value)
  name === :texture && (value = texture(value))
  @invoke setproperty!(image::Widget, name::Symbol, value)
end

function synchronize(image::Image)
  set_geometry(image, image.geometry)
  set_render(image, RenderComponent(RENDER_OBJECT_IMAGE, nothing, Sprite(image.texture); image.is_opaque))
end

@widget struct Text
  text::Base.AnnotatedString{String}
  size::Float64
  font::String
  script::Tag4
  language::Tag4
end

function line_center(text::Text)
  shader = get_render(text).primitive_data::ShaderLibrary.Text
  (; ascender, descender) = shader.font.hhea
  offset = (ascender + descender) / 2shader.font.units_per_em * text.size
  P2(0, offset)
end

function synchronize(text::Text)
  font_options = FontOptions(ShapingOptions(text.script, text.language), text.size)
  options = TextOptions()
  shader = ShaderLibrary.Text(OpenType.Text(text.text, options), get_font(text.font), font_options)
  text_span = boundingelement(shader)
  geometry = text_span - centroid(text_span)
  set_geometry(text, geometry)
  set_render(text, RenderComponent(RENDER_OBJECT_TEXT, nothing, shader))
end

function Text(text::AbstractString; font = "arial", size = TEXT_SIZE_MEDIUM, script = tag4"latn", language = tag4"en  ")
  new_widget(Text, text, size, font, script, language)
end

function unset_shortcut((; text)::Text, shortcut::Char)
  for i in eachindex(text)
    char = text[i]
    if lowercase(char) == shortcut
      range = i:(nextind(text, i) - 1)
      prev = annotations(text, range)
      j = findfirst(prev) do (_, (label, value))
        label === :face && in(value, (:application_shortcut_show, :application_shortcut_hide))
      end
      isnothing(j) && return false
      region = prev[j][1]
      faces = findall(prev) do (_region, (label, value))
        label === :face && _region == region
      end
      if length(faces) == 1
        annotate!(text, region, :face => nothing)
      else
        annotate!(text, region, :face => nothing)
        for face in faces
          face == j && continue
          annotate!(text, region, :face => prev[face][2][2])
        end
      end
      return true
    end
  end
end

function set_shortcut((; text)::Text, shortcut::Char)
  for i in eachindex(text)
    char = text[i]
    if lowercase(char) == shortcut
      range = i:(nextind(text, i) - 1)
      prev = annotations(text, range)
      any(prev) do (range, (label, value))
        label === :face && in(value, (:application_shortcut_show, :application_shortcut_hide))
      end && return true
      annotation = ifelse(app.show_shortcuts, :application_shortcut_show, :application_shortcut_hide)
      annotate!(text, range, :face => annotation)
      return true
    end
  end
  false
end

@widget struct Button
  on_input::Function
  background::Rectangle
  text::Optional{Text}
end

constituents(button::Button) = [button.background, button.text]

function set_name(button::Button, name::Symbol)
  set_name(button.id, name)
  set_name(button.background, Symbol(name, :_background))
end

Button(on_click, (width, height)::Tuple; background_color = BUTTON_BACKGROUND_COLOR, text = nothing) = Button(on_click, geometry(width, height); background_color, text)
Button(on_click, geometry::Box{2}; background_color = BUTTON_BACKGROUND_COLOR, text = nothing) = Button(on_click, Rectangle(geometry, background_color); text)
function Button(on_click, background::Rectangle; text = nothing)
  on_input = function (input::Input)
    is_left_click(input) && on_click()
  end
  new_widget(Button, on_input, background, text)
end

function synchronize(button::Button)
  set_input_handler(button, InputComponent(input -> is_left_click(input) && button.on_input(input), BUTTON_PRESSED, NO_ACTION))
  isnothing(button.text) && return
  put_behind(button.background, button.text)
  set_geometry(button, get_geometry(button.background))
  add_constraint(attach(button.background, button))
  add_constraint(attach(button.text, button))
end

function put_behind(button::Button, of)
  put_behind(button.text, of)
  put_behind(button.id, button.text)
end

@widget struct Checkbox
  on_toggle::Function
  value::Bool
  background::Rectangle
  active_color::RGB{Float32}
  inactive_color::RGB{Float32}
end

constituents(checkbox::Checkbox) = [checkbox.background]

function set_name(checkbox::Checkbox, name::Symbol)
  set_name(checkbox.id, name)
  set_name(checkbox.background, Symbol(name, :_background))
end

function Checkbox(on_toggle, value::Bool = false; size::Float64 = CHECKBOX_SIZE, active_color = CHECKBOX_ACTIVE_COLOR, inactive_color = CHECKBOX_INACTIVE_COLOR)
  geometry = Box(Point2(0.5size, 0.5size))
  background = Rectangle(geometry, inactive_color)
  checkbox = new_widget(Checkbox, identity, value, background, active_color, inactive_color)
  checkbox.on_toggle = function (input::Input)
    if is_left_click(input)
      checkbox.value = !checkbox.value
      on_toggle(checkbox.value)
    end
  end
  checkbox
end

function synchronize(checkbox::Checkbox)
  set_geometry(checkbox, get_geometry(checkbox.background))
  add_constraint(attach(checkbox.background, checkbox))
  set_input_handler(checkbox, InputComponent(input -> is_left_click(input) && checkbox.on_toggle(input), BUTTON_PRESSED, NO_ACTION))
  checkbox.background.color = checkbox.value ? checkbox.active_color : checkbox.inactive_color
end

@widget mutable struct MenuItem
  const on_selected::Function
  const background::Rectangle
  const text::Text
  # Whether the item is currently active in navigation (pointer actively over it, navigation via keyboard)
  active::Bool
  shortcut::Char
end

constituents(item::MenuItem) = [item.background, item.text]

function set_name(item::MenuItem, name::Symbol)
  set_name(item.id, name)
  set_name(item.background, Symbol(name, :_background))
end

set_active(item::MenuItem) = (item.active = true)
set_inactive(item::MenuItem) = (item.active = false)
isactive(item::MenuItem) = item.active

function MenuItem(on_selected, text, geometry, shortcut = lowercase(first(text.text)))
  background = Rectangle(geometry, MENU_ITEM_COLOR)
  new_widget(MenuItem, on_selected, background, text, false, shortcut)
end

function synchronize(item::MenuItem)
  set_geometry(item, item.background.geometry)
  put_behind(item.text, item)
  put_behind(item.background, item.text)
  add_constraint(attach(item.background, item))
  add_constraint(attach(at(item.text, :center), item))
  color = ifelse(item.active, MENU_ITEM_ACTIVE_COLOR, MENU_ITEM_COLOR)
  item.background.color = color
end

@widget struct Menu
  on_input::Function
  head::WidgetID
  items::Vector{MenuItem}
  direction::Direction
  expanded::Bool
  overlay::EntityID # entity that overlays the whole window on menu expand
  shortcuts::Union{Nothing, KeyBindingsToken}
  shortcut::Char
end

constituents(menu::Menu) = [menu.head; menu.items]

function set_name(menu::Menu, name::Symbol)
  set_name(menu.id, name)
  set_name(menu.head, Symbol(name, :_head))
  for (i, item) in enumerate(menu.items)
    set_name(item, Symbol(name, :_item_, i))
  end
end

function active_item(menu::Menu)
  i = findfirst(isactive, menu.items)
  isnothing(i) && return
  menu.items[i]
end

function select_item(menu::Menu, item::MenuItem)
  set_inactive(item)
  item.on_selected()
  collapse!(menu)
end

function Menu(head, items::Vector{MenuItem}, shortcut::Char, direction::Direction = DIRECTION_VERTICAL)
  menu = new_widget(Menu, identity, head, items, direction, false, new_entity(), 0, lowercase(shortcut))
  menu.on_input = function (input::Input)
    # Expand the menu if the head is left-clicked (only the head is reachable if collapsed).
    is_left_click(input) && !menu.expanded && return expand!(menu)

    # Propagate the event to menu items, triggering the selection of the target item.
    subareas = InputArea[]
    push!(subareas, app.systems.event.ui.areas[menu.head])
    append!(subareas, app.systems.event.ui.areas[item.id] for item in menu.items)
    propagate!(input, subareas) && is_left_click(input) && collapse!(menu)
  end
  menu
end

function select_active_item(menu::Menu)
  item = active_item(menu)
  !isnothing(item) && select_item(menu, item)
end

function navigate_to_next_item(menu::Menu, direction, items = menu.items)
  i = findfirst(isactive, items)
  next = !isnothing(i) ? mod1(i + direction, length(items)) : ifelse(direction == 1, 1, lastindex(items))
  !isnothing(i) && set_inactive(items[i])
  set_active(items[next])
end

function set_active(menu::Menu, item::MenuItem)
  prev = active_item(menu)
  !isnothing(prev) && set_inactive(prev)
  set_active(item)
end

function expand!(menu::Menu)
  menu.expanded && return false
  register_shortcuts!(menu)
  menu.expanded = true
end

function collapse!(menu::Menu)
  foreach(set_inactive, menu.items)
  unregister_shortcuts!(menu)
  menu.expanded = false
end

function register_shortcuts!(menu::Menu)
  menu.shortcuts === nothing || unbind(menu.shortcuts)
  shortcuts = [item.shortcut for item in menu.items]
  bindings = Pair{KeyCombination, Callable}[]
  for (item, shortcut) in zip(menu.items, shortcuts)
    set_shortcut(item.text, shortcut)
    indices = findall(==(shortcut), shortcuts)
    key = KeyCombination(shortcut)
    if length(indices) == 1
      push!(bindings, key => let item = item
        () -> select_item(menu, item)
      end)
    else
      push!(bindings, key => let items = menu.items[indices]
        () -> navigate_to_next_item(menu, 1, items)
      end)
    end
  end
  push!(bindings, key"enter" => () -> select_active_item(menu))
  push!(bindings, key"up" => () -> navigate_to_next_item(menu, -1))
  push!(bindings, key"down" => () -> navigate_to_next_item(menu, 1))
  menu.shortcuts = bind(bindings)
end

function unregister_shortcuts!(menu::Menu)
  menu.shortcuts === nothing && return
  unbind(menu.shortcuts)
  for item in menu.items
    unset_shortcut(item.text, item.shortcut)
  end
  menu.shortcuts = nothing
end

function synchronize(menu::Menu)
  if menu.expanded
    for item in menu.items
      enable!(item)
      set_input_handler(item, InputComponent(BUTTON_PRESSED | POINTER_ENTERED | POINTER_EXITED, NO_ACTION) do input::Input
        is_left_click(input) && item.on_selected()
        input.type === POINTER_ENTERED && set_active(menu, item)
        input.type === POINTER_EXITED && set_inactive(item)
      end)
    end
    window = app.windows[app.window]
    set_location(menu.overlay, get_location(window))
    set_geometry(menu.overlay, get_geometry(window))
    set_z(menu.overlay, 100)
    set_input_handler(menu.overlay, InputComponent(BUTTON_PRESSED, NO_ACTION) do input::Input
      propagate!(input, app.systems.event.ui.areas[menu.id]) && return
      click = input.event.mouse_event.button
      !in(click, (BUTTON_SCROLL_UP, BUTTON_SCROLL_DOWN)) && return collapse!(menu)
      navigate_to_next_item(menu, ifelse(click == BUTTON_SCROLL_UP, -1, 1))
    end)
  else
    foreach(disable!, menu.items)
    unset_input_handler(menu.overlay)
  end
  set_geometry(menu, menu_geometry(menu))
  place_items(menu)
  set_input_handler(menu, InputComponent(menu.on_input, BUTTON_PRESSED, NO_ACTION))
end

function menu_geometry(menu::Menu)
  box = get_geometry(menu.head)
  !menu.expanded && return box
  bottom_left = box.bottom_left .- @SVector [0.0, sum(item -> get_geometry(item).height, menu.items; init = 0.0)]
  Box(bottom_left, box.top_right)
end

function place_items(menu::Menu)
  menu.direction === DIRECTION_VERTICAL || error("Unsupported direction $direction")
  add_constraint(attach(menu.head, menu))
  prev_item = menu.head
  for item in menu.items
    constraint = attach(at(item, :corner, :top_left), at(prev_item, :corner, :bottom_left))
    add_constraint(constraint)
    prev_item = item
  end

  for part in constituents(menu)
    put_behind(get_widget(part), menu)
  end
end

attach(object::Widget, onto::Widget) = attach(object.id, onto.id)
attach(object, onto::Widget) = attach(object, onto.id)
attach(object::Widget, onto) = attach(object.id, onto)
at(object::Widget, location::FeatureLocation, args...) = at(object.id, location, args...)
at(object::Widget, location::Symbol, args...) = at(object.id, location, args...)

const WidgetComponent = Union{subtypes(Widget)...}
