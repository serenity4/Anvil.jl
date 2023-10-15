abstract type Widget end

convert(::Type{EntityID}, widget::Widget) = widget.id

struct Rectangle <: Widget
  id::EntityID
  geometry::Box2
  color::RGB{Float32}
end

function Rectangle(givre::GivreApplication, box::Box{2}, color::RGB)
  entity = new_entity!(givre)
  set_geometry!(givre, entity, box)
  set_location!(givre, entity, zero(LocationComponent))
  vertex_data = [Vec3(color.r, color.g, color.b) for _ in 1:4]
  set_render!(givre, entity, RenderComponent(RENDER_OBJECT_RECTANGLE, vertex_data, Gradient()))
  Rectangle(entity, box, color)
end

struct Text <: Widget
  id::EntityID
  text::String
  size::Float64
  font::String
  script::Tag4
  language::Tag4
end

function new!(givre::GivreApplication, text::ShaderLibrary.Text)
  entity = new_entity!(givre)
  box = boundingelement(text)
  set_geometry!(givre, entity, box)
  set_location!(givre, entity, zero(LocationComponent))
  set_render!(givre, entity, RenderComponent(RENDER_OBJECT_TEXT, nothing, text))
  entity
end

function Text(givre::GivreApplication, text::AbstractString; font = "arial", size = TEXT_SIZE_MEDIUM, script = tag4"latn", language = tag4"en  ")
  font_options = FontOptions(ShapingOptions(script, language), size)
  options = TextOptions()
  id = new!(givre, ShaderLibrary.Text(OpenType.Text(text, options), get_font(givre, font), font_options))
  Text(id, text, size, font, script, language)
end

struct Dropdown <: Widget
  id::EntityID
  background::Rectangle
  choices::Vector{Text}
end

function Dropdown(givre::GivreApplication, box::Box{2}; background_color = DROPDOWN_BACKGROUND_COLOR, choices = Text[])
  background = Rectangle(givre, box, background_color)
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
