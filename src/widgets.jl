const WidgetID = EntityID

abstract type Widget end

Base.convert(::Type{WidgetID}, widget::Widget) = widget.id

function Base.setproperty!(widget::Widget, name::Symbol, value)
  (name === :modified || name === :id) && return setfield!(widget, name, value)
  prev = getproperty(widget, name)
  prev === value && return value
  widget.modified = true
  setfield!(widget, name, value)
end

function new_widget(::Type{T}, args...) where {T<:Widget}
  entity = new_entity!()
  set_location(entity, zero(LocationComponent))
  widget = T(entity, args...)
  synchronize(widget)
  givre.ecs[entity, WIDGET_COMPONENT_ID] = widget
  widget
end

(T::Type{<:Widget})(args...) = new_widget(T, args...)

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
      pushfirst!(block.args, Expr(:const, :(id::$WidgetID)), :(modified::Bool))
      push!(block.args, :($name(id::$WidgetID, args...) = $new(id, true, args...)))
    end
    _ => error("Expected a struct declaration, got `$ex`")
  end
  esc(ex)
end

@widget struct Rectangle
  geometry::Box2
  color::RGB{Float32}
end

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
  Text(text, size, font, script, language)
end

@widget struct Button
  on_input::Function
  geometry::Box2
  background_color::RGB{Float32}
  text::Optional{Text}
end

function Button(on_click, geometry::Box{2}; background_color = BUTTON_BACKGROUND_COLOR, text = nothing)
  on_input = function (input::Input)
    input.type === BUTTON_PRESSED && on_click()
  end
  widget = new_widget(Button, on_input, geometry, background_color, text)
  !isnothing(text) && add_constraint(attach(at(text, :center), at(widget, :center)))
  widget
end

function synchronize(button::Button)
  rect = Rectangle(button.id, button.geometry, button.background_color)
  synchronize(rect)
  givre.ecs[button, INPUT_COMPONENT_ID] = InputComponent(button.on_input, BUTTON_PRESSED, NO_ACTION)
  isnothing(button.text) && return
  synchronize(button.text)
  put_behind(rect, button.text)
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
  givre.ecs[checkbox, INPUT_COMPONENT_ID] = InputComponent(checkbox.on_toggle, BUTTON_PRESSED, NO_ACTION)
  rect = Rectangle(checkbox.id, checkbox.geometry, checkbox.value ? checkbox.active_color : checkbox.inactive_color)
  synchronize(rect)
end

@widget struct Dropdown
  background::Rectangle
  choices::Vector{Text}
end

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

Base.getindex(ecs::ECSDatabase, widget::Widget, args...) = getindex(ecs, widget.id, args...)
Base.setindex!(ecs::ECSDatabase, value, widget::Widget, args...) = setindex!(ecs, value, widget.id, args...)

attach(object::Widget, onto::Widget) = attach(object.id, onto.id)
attach(object, onto::Widget) = attach(object, onto.id)
attach(object::Widget, onto) = attach(object.id, onto)
at(object::Widget, location::FeatureLocation, args...) = at(object.id, location, args...)

const WidgetComponent = Union{subtypes(Widget)...}
