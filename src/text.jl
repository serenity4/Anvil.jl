font_file(font_name) = joinpath(pkgdir(Givre), "assets", "fonts", font_name * ".ttf")
OpenType.OpenTypeFont(givre::GivreApplication, font_name::AbstractString) = OpenTypeFont(font_file(font_name))
font(givre, name::AbstractString) = get!(() -> OpenTypeFont(givre, name), givre.fonts, name)


function new!(givre::GivreApplication, text::Text)
  entity = new_entity!(givre)
  box = boundingelement(text)
  geometry = GeometryComponent(box, 10.0) # dummy z-index for now
  set_geometry!(givre, entity, geometry)
  set_render!(givre, entity, RenderComponent(RENDER_OBJECT_TEXT, nothing, text))
  entity
end
