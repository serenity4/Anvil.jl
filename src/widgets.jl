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

Rectangle(geometry, color) = new_widget(Rectangle, geometry, color)

function synchronize(rect::Rectangle)
  (; r, g, b) = rect.color
  vertex_data = [Vec3(r, g, b) for _ in 1:4]
  set_geometry(rect, rect.geometry)
  set_render(rect, RenderComponent(RENDER_OBJECT_RECTANGLE, vertex_data, Gradient()))
end

@widget struct Text
  text::String
  size::Float64
  font::String
  script::Tag4
  language::Tag4
end

function synchronize(text::Text)
  (; id) = text
  font_options = FontOptions(ShapingOptions(text.script, text.language), text.size)
  options = TextOptions()
  text = ShaderLibrary.Text(OpenType.Text(text.text, options), get_font(text.font), font_options)
  geometry = boundingelement(text, extent(app.window))
  set_geometry(id, geometry)
  set_render(id, RenderComponent(RENDER_OBJECT_TEXT, nothing, text))
end

function Text(text::AbstractString; font = "arial", size = TEXT_SIZE_MEDIUM, script = tag4"latn", language = tag4"en  ")
  new_widget(Text, text, size, font, script, language)
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
  add_constraint(attach(at(button.text, :center), button))
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

function Checkbox(on_toggle, value::Bool, geometry::Box{2}; active_color = CHECKBOX_ACTIVE_COLOR, inactive_color = CHECKBOX_INACTIVE_COLOR)
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
end

constituents(item::MenuItem) = [item.background, item.text]

function set_name(item::MenuItem, name::Symbol)
  set_name(item.id, name)
  set_name(item.background, Symbol(name, :_background))
end

set_active(item::MenuItem) = (item.active = true)
set_inactive(item::MenuItem) = (item.active = false)
isactive(item::MenuItem) = item.active

function MenuItem(on_selected, text, geometry)
  background = Rectangle(geometry, MENU_ITEM_COLOR)
  new_widget(MenuItem, on_selected, background, text, false)
end

function synchronize(item::MenuItem)
  set_input_handler(item, InputComponent(BUTTON_PRESSED | POINTER_ENTERED | POINTER_EXITED, NO_ACTION) do input::Input
    is_left_click(input) && item.on_selected()
    input.type === POINTER_ENTERED && set_active(item)
    input.type === POINTER_EXITED && set_inactive(item)
  end)
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

function Menu(head, items::Vector{MenuItem}, direction::Direction = DIRECTION_VERTICAL)
  menu = new_widget(Menu, identity, head, items, direction, false)
  menu.on_input = function (input::Input)
    if menu.expanded
      matches(key"enter", input.event) && return select_active_item(menu)
      if matches(key"up", input.event) || matches(key"down", input.event)
        navigate_to_next_item(menu, ifelse(matches(key"up", input.event), -1, 1))
      end
    end

    input.type === BUTTON_PRESSED || return

    click = input.event.mouse_event.button
    if in(click, (BUTTON_SCROLL_UP, BUTTON_SCROLL_DOWN))
      navigate_to_next_item(menu, ifelse(click == BUTTON_SCROLL_UP, -1, 1))
    end

    # Expand the menu if the head is left-clicked (only the head is reachable if collapsed).
    is_left_click(input) && !menu.expanded && return expand!(menu)

    # Propagate the event to menu items, triggering the selection of the target item
    # and allowing the detection of pointer enters/exits for pointer-based activation.
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

function navigate_to_next_item(menu::Menu, direction)
  i = findfirst(isactive, menu.items)
  next = !isnothing(i) ? mod1(i + direction, length(menu.items)) : ifelse(direction == 1, 1, lastindex(menu.items))
  !isnothing(i) && set_inactive(menu.items[i])
  set_active(menu.items[next])
end

function expand!(menu::Menu)
  menu.expanded = true
end
function collapse!(menu::Menu)
  foreach(set_inactive, menu.items)
  menu.expanded = false
end

function synchronize(menu::Menu)
  foreach(menu.expanded ? enable! : disable!, menu.items)
  set_geometry(menu, menu_geometry(menu))
  place_items(menu)
  set_input_handler(menu, InputComponent(menu.on_input, BUTTON_PRESSED | KEY_PRESSED, NO_ACTION))
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
