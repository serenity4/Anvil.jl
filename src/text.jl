font_file(font_name) = joinpath(pkgdir(Givre), "assets", "fonts", font_name * ".ttf")
OpenType.OpenTypeFont(givre::GivreApplication, font_name::AbstractString) = OpenTypeFont(font_file(font_name))

struct Text
  font_name::String
  text::OpenType.Text
  options::FontOptions
end

function new!(givre::GivreApplication, text::Text)
  entity = new_entity!(givre)
  font = OpenTypeFont(givre, text.font_name)
  geometry = GeometryComponent(Box(Point2(0.1, 0.1)), 3.0) # dummy geometry component for now
  set_geometry!(givre, entity, geometry)
  set_render!(givre, entity, RenderComponent(RENDER_OBJECT_TEXT, nothing, (text.text, font, text.options)))
  entity
end
