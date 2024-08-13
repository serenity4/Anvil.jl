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
  set_geometry(rect.id, rect.geometry)
  set_render(rect.id, RenderComponent(RENDER_OBJECT_RECTANGLE, vertex_data, Gradient()))
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
  box = boundingelement(text)
  set_geometry(id, box)
  set_render(id, RenderComponent(RENDER_OBJECT_TEXT, nothing, text))
end

function Text(text::AbstractString; font = "arial", size = TEXT_SIZE_MEDIUM, script = tag4"latn", language = tag4"en  ")
  new_widget(Text, text, size, font, script, language)
end

@widget struct Button
  on_input::Function
  geometry::Box2
  background_color::RGB{Float32}
  text::Optional{Text}
end

constituents(button::Button) = [button.text]

function Button(on_click, geometry::Box{2}; background_color = BUTTON_BACKGROUND_COLOR, text = nothing)
  on_input = function (input::Input)
    input.type === BUTTON_PRESSED && on_click()
  end
  new_widget(Button, on_input, geometry, background_color, text)
end

function synchronize(button::Button)
  rect = Rectangle(button.id, button.geometry, button.background_color)
  synchronize(rect)
  set_input_handler(button, InputComponent(button.on_input, BUTTON_PRESSED, NO_ACTION))
  isnothing(button.text) && return
  synchronize(button.text)
  put_behind(rect, button.text)
  add_constraint(attach(at(button.text, :center), at(button, :center)))
end

function put_behind(button::Button, of)
  put_behind(button.text, of)
  put_behind(button.id, button.text)
end

@widget struct Checkbox
  on_toggle::Function
  value::Bool
  geometry::Box2
  active_color::RGB{Float32}
  inactive_color::RGB{Float32}
end

function Checkbox(on_toggle, value::Bool, geometry::Box{2}; active_color = CHECKBOX_ACTIVE_COLOR, inactive_color = CHECKBOX_INACTIVE_COLOR)
  checkbox = new_widget(Checkbox, identity, value, geometry, active_color, inactive_color)
  checkbox.on_toggle = function (input::Input)
    if input.type == BUTTON_PRESSED
      checkbox.value = !checkbox.value
      on_toggle(checkbox.value)
    end
  end
  checkbox
end

function synchronize(checkbox::Checkbox)
  set_input_handler(checkbox, InputComponent(checkbox.on_toggle, BUTTON_PRESSED, NO_ACTION))
  rect = Rectangle(checkbox.id, checkbox.geometry, checkbox.value ? checkbox.active_color : checkbox.inactive_color)
  synchronize(rect)
end

@widget struct Menu
  on_input::Function
  head::WidgetID
  items::Vector{WidgetID}
  direction::Direction
  expanded::Bool
end

constituents(menu::Menu) = [menu.head; menu.items]

Menu(head, items, direction::Direction = DIRECTION_VERTICAL) = Menu(head, convert(Vector{WidgetID}, items), direction)
function Menu(head, items::Vector{WidgetID}, direction::Direction = DIRECTION_VERTICAL)
  menu = new_widget(Menu, identity, head, items, direction, false)
  menu.on_input = function (input::Input)
    !menu.expanded && return input.type === BUTTON_PRESSED && expand!(menu)
    propagate!(input, [app.systems.event.ui.areas[item] for item in [menu.head; menu.items]]) || return
    input.type === BUTTON_PRESSED && collapse!(menu)
  end
  menu
end

function expand!(menu::Menu)
  ret = menu.expanded ≠ (menu.expanded = true)
  ret && synchronize!(menu)
  ret
end
function collapse!(menu::Menu)
  ret = menu.expanded ≠ (menu.expanded = false)
  ret && synchronize!(menu)
  ret
end

function synchronize(menu::Menu)
  foreach(menu.expanded ? enable! : disable!, menu.items)
  set_geometry(menu, menu_geometry(menu))
  place_items(menu)
  # Capture all events because we don't know what the menu items will react to.
  set_input_handler(menu, InputComponent(menu.on_input, ALL_EVENTS, NO_ACTION))
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

@widget struct Dropdown
  background::Rectangle
  choices::Vector{Text}
end

constituents(dropdown::Dropdown) = dropdown.choices

function Dropdown(box::Box{2}; background_color = DROPDOWN_BACKGROUND_COLOR, choices = Text[])
  background = Rectangle(box, background_color)
  # TODO
  # on_input = function (input::Input)
  #   if input.type === BUTTON_PRESSED
  #
  #   end
  # end
  Dropdown(background)
end

attach(object::Widget, onto::Widget) = attach(object.id, onto.id)
attach(object, onto::Widget) = attach(object, onto.id)
attach(object::Widget, onto) = attach(object.id, onto)
at(object::Widget, location::FeatureLocation, args...) = at(object.id, location, args...)
at(object::Widget, location::Symbol, args...) = at(object.id, location, args...)

const WidgetComponent = Union{subtypes(Widget)...}
