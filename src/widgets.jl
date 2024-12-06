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
Base.:(==)(widget::Widget, id::WidgetID) = widget.id == id

function Base.setproperty!(widget::Widget, name::Symbol, value)
  (name === :modified || name === :id || name === :disabled) && return setfield!(widget, name, value)
  prev = getproperty(widget, name)
  prev === value && return value
  widget.modified = true
  setfield!(widget, name, convert(fieldtype(typeof(widget), name), value))
  synchronize(widget)
  value
end

function new_widget(::Type{T}, args...) where {T<:Widget}
  entity = new_entity()
  set_location(entity, zero(LocationComponent))
  set_geometry(entity, Box2(zero(P2)))
  set_z(entity, 0)
  widget = T(entity, args...)
  set = INTERACTION_SET[]
  !isnothing(set) && push!(set, widget)
  set_widget(entity, widget)
  synchronize!(widget)
  widget
end

# XXX: Use `EntityID` or `Widget` iterators to recursively get widget constituents,
# instead of performing the recursion manually.

function disable!(widget::WidgetID)
  unset_render(widget)
  unoverlay(widget)
  remove_layout_operations(widget)
end

function disable!(widget::Widget)
  disable!(widget.id)
  for part in constituents(widget)
    has_widget(part) || continue
    disable!(get_widget(part))
  end
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

function unset_widget(widget::Widget)
  for part in constituents(widget)
    unset_widget(part)
  end
end

function delete_widget(widget)
  disable!(widget)
  unset_z(widget)
  unset_location(widget)
  unset_geometry(widget)
  unset_widget(widget)
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
  geometry::GeometryComponent
  visual::Union{ImageVisual, RectangleVisual}
end

Rectangle(geometry::GeometryComponent, visual::Union{ImageVisual, RectangleVisual}) = new_widget(Rectangle, geometry, visual)
Rectangle((width, height)::Tuple, args...) = Rectangle(geometry(width, height), args...)

Rectangle(geometry::GeometryComponent, color::Colorant) = Rectangle(geometry, RectangleVisual(color))
Rectangle(geometry::GeometryComponent, image::Texture, parameters::ImageParameters = ImageParameters()) = Rectangle(geometry, ImageVisual(image, parameters))
Rectangle(geometry::GeometryComponent, data::Union{AbstractMatrix, AbstractString}, parameters::ImageParameters = ImageParameters()) = Rectangle(geometry, texture(data), parameters)
Rectangle(data::Union{AbstractMatrix, AbstractString}, parameters::ImageParameters = ImageParameters(); scale = 1.0) = Rectangle(texture(data), parameters; scale)
function Rectangle(image::Texture, parameters::ImageParameters = ImageParameters(); scale = 1.0)
  width, height = dimensions(image) .* scale .* 0.001
  Rectangle((width, height), image, parameters)
end

texture(data::Texture) = data
texture(data::AbstractMatrix) = fetch(execute(load_texture, app.systems.rendering.renderer.task, data))
texture(filename::String) = get_texture(filename)

function Base.setproperty!(rect::Rectangle, name::Symbol, value)
  if name === :texture
    visual = rect.visual::ImageVisual
    return rect.visual = ImageVisual(texture(value), visual.parameters)
  elseif name === :color
    visual = RectangleVisual(value)
    isa(value, AbstractRGB) && @reset visual.color.alpha = rect.visual.color.alpha
    return rect.visual = visual
  end
  @invoke setproperty!(rect::Widget, name::Symbol, value)
end

function synchronize(rect::Rectangle)
  set_geometry(rect, rect.geometry)
  set_render(rect, RenderComponent(rect.visual))
end

@widget struct Text
  value::Base.AnnotatedString{String}
  lines::Vector{OpenType.Line}
  size::Float64
  font::String
  script::Tag4
  language::Tag4
  editable::Bool
  edit::Any # ::TextEditState
end

function Text(value::AbstractString; font = "arial", size = TEXT_SIZE_MEDIUM, script = tag4"latn", language = tag4"en  ", editable = false, on_edit = nothing)
  text = new_widget(Text, value, OpenType.Line[], size, font, script, language, editable, nothing)
  editable && (text.edit = TextEditState(on_edit, text))
  text
end

function line_center(text::Text)
  shader = get_render(text).primitive_data::ShaderLibrary.Text
  (; ascender, descender) = shader.font.hhea
  offset = (ascender + descender) / 2shader.font.units_per_em * text.size
  P2(0, offset)
end

function synchronize(text::Text)
  options = TextOptions()
  font = get_font(text.font)
  font_options = FontOptions(ShapingOptions(text.script, text.language), text.size)
  string = text.editable && isa(text.edit, TextEditState) ? something(text.edit.buffer, text.value) : text.value
  if !isempty(string)
    text_ot = OpenType.Text(string, options)
    lines = OpenType.lines(text_ot, [font => font_options])
    setfield!(text, :lines, lines)
    shader = ShaderLibrary.Text(lines)
    set_geometry(text, text_geometry(text_ot, lines))
    set_render(text, RenderComponent(RENDER_OBJECT_TEXT, nothing, shader))
  else
    set_geometry(text, geometry(0, 0))
    unset_render(text)
  end
end

function unset_shortcut(text::Text, shortcut::Char)
  text = text.value
  for i in eachindex(text)
    char = text[i]
    if lowercase(char) == shortcut
      range = i:(nextind(text, i) - 1)
      prev = annotations(text, range)
      j = findfirst(prev) do (_, label, value)
        label === :face && in(value, (:application_shortcut_show, :application_shortcut_hide))
      end
      isnothing(j) && return false
      region = prev[j][1]
      faces = findall(prev) do (_region, label, value)
        label === :face && _region == region
      end
      if length(faces) == 1
        annotate!(text, region, :face, nothing)
      else
        annotate!(text, region, :face, nothing)
        for face in faces
          face == j && continue
          annotate!(text, region, :face, prev[face][2][2])
        end
      end
      return true
    end
  end
end

function set_shortcut(text::Text, shortcut::Char)
  text = text.value
  for i in eachindex(text)
    char = text[i]
    if lowercase(char) == shortcut
      range = i:(nextind(text, i) - 1)
      prev = annotations(text, range)
      any(prev) do (range, label, value)
        label === :face && in(value, (:application_shortcut_show, :application_shortcut_hide))
      end && return true
      annotation = ifelse(app.show_shortcuts, :application_shortcut_show, :application_shortcut_hide)
      annotate!(text, range, :face, annotation)
      return true
    end
  end
  false
end

mutable struct TextEditState
  text::Text
  on_edit::Any # user-provided

  # Interaction state.
  pending::Bool
  buffer::Optional{Base.AnnotatedString{String}}
  selection::UnitRange{Int64}
  cursor::Rectangle
  cursor_index::Int64

  # Interaction functionality.
  edit_on_select::InputCallback
  select_cursor::InputCallback
  character_input::InputCallback
  shortcuts::Optional{KeyBindingsToken}
  typing_overlay::EntityID # overlay that allows typing from anywhere on the screen
  function TextEditState(on_edit, text::Text)
    cursor = Rectangle(Box2(zero(P2), zero(P2)), RGB(0.2, 0.2, 0.9))
    unset_render(cursor)

    edit = new()
    edit.text = text
    edit.on_edit = on_edit
    edit.pending = false
    edit.buffer = nothing
    edit.selection = 1:0
    edit.cursor = cursor
    edit.cursor_index = 0

    edit.edit_on_select = add_callback(edit.text, BUTTON_PRESSED) do input
      start_editing!(edit)
      select_text!(edit)
    end

    edit.select_cursor = InputCallback(BUTTON_PRESSED, DOUBLE_CLICK | TRIPLE_CLICK | DRAG) do input
      input.type === DOUBLE_CLICK && return select_word!(edit, input.event.location)
      input.type === TRIPLE_CLICK && return select_text!(edit)
      input.type === DRAG && return select_at_selection!(edit, input)
      select_at_cursor!(edit, input)
    end

    edit.character_input = InputCallback(KEY_PRESSED) do input
      (; event) = input
      char = event.key_event.input
      isprint(char) || return propagate!(input)
      isempty(edit.selection) ? insert_after!(edit, char) : edit_selection!(edit, char)
    end

    edit.shortcuts = nothing
    edit.typing_overlay = new_entity()

    edit
  end
end

function start_editing!(edit::TextEditState)
  edit.buffer = deepcopy(edit.text.value)
  register_shortcuts!(edit)
  set_location(edit.typing_overlay, (0, 0))
  set_geometry(edit.typing_overlay, (Inf, Inf))
  set_z(edit.typing_overlay, Inf)
  remove_callback(edit.text, edit.edit_on_select)
  add_callback(edit.text, edit.select_cursor; drag_threshold = 0.1)
  set_cursor!(edit, length(edit.buffer))
  edit.pending = true
end

function stop_editing!(edit::TextEditState)
  unregister_shortcuts!(edit)
  unset_location(edit.typing_overlay)
  unset_geometry(edit.typing_overlay)
  unset_z(edit.typing_overlay)
  add_callback(edit.text, edit.edit_on_select)
  remove_callback(edit.text, edit.select_cursor)
  unset_cursor!(edit)
  edit.buffer = nothing
  edit.pending = false
  synchronize!(edit.text)
end

function select_at_cursor!(edit::TextEditState, input::Input)
  location = get_location(edit.text)
  geometry = get_geometry(edit.text)
  origin = geometry.bottom_left .+ location
  i = cursor_index(edit.buffer, edit.text.lines, input.event.location .- origin)
  clear_selection!(edit)
  set_cursor!(edit, i)
end

function select_at_selection!(edit::TextEditState, input::Input)
  location = get_location(edit.text)
  geometry = get_geometry(edit.text)
  origin = geometry.bottom_left .+ location
  area, event = input.drag
  i = cursor_index(edit.buffer, edit.text.lines, input.source.event.location .- origin)
  j = cursor_index(edit.buffer, edit.text.lines, event.location .- origin)
  j == edit.cursor_index && return
  if j > edit.cursor_index
    navigate_and_select_next!(edit -> set_cursor!(edit, j), edit)
  else
    navigate_and_select_previous!(edit -> set_cursor!(edit, j), edit)
  end
end

is_cursor_active(edit::TextEditState) = edit.cursor_index ≥ 0

function add_selection_background!(edit::TextEditState)
  isempty(edit.selection) && return
  remove_selection_background!(edit)
  annotate!(edit.buffer, edit.selection, :background, RGBA(0.3, 0.1, 0.1, 1))
end

function remove_selection_background!(edit::TextEditState)
  for (range, label, _) in annotations(edit.buffer)
    label == :background && annotate!(edit.buffer, range, :background, nothing)
  end
end

function register_shortcuts!(edit::TextEditState)
  edit.shortcuts === nothing || unbind(edit.shortcuts)
  bindings = Pair{KeyCombination, Callable}[]
  push!(bindings, key"left" => () -> navigate_previous!(edit))
  push!(bindings, key"right" => () -> navigate_next!(edit))
  push!(bindings, key"ctrl+left" => () -> navigate_previous_word!(edit))
  push!(bindings, key"ctrl+right" => () -> navigate_next_word!(edit))
  push!(bindings, key"shift+left" => () -> select_previous!(edit))
  push!(bindings, key"shift+right" => () -> select_next!(edit))
  push!(bindings, key"ctrl+shift+left" => () -> select_previous_word!(edit))
  push!(bindings, key"ctrl+shift+right" => () -> select_next_word!(edit))
  append!(bindings, (key"home", key"kp_home") .=> () -> navigate_start!(edit))
  append!(bindings, (key"end", key"kp_end") .=> () -> navigate_end!(edit))
  append!(bindings, (key"shift+home", key"shift+kp_home") .=> () -> select_start!(edit))
  append!(bindings, (key"shift+end", key"shift+kp_end") .=> () -> select_end!(edit))
  push!(bindings, key"ctrl+a" => () -> select_text!(edit))
  push!(bindings, key"backspace" => () -> begin
    isempty(edit.selection) ? delete_previous!(edit) : delete_selection!(edit)
  end)
  push!(bindings, key"delete" => () -> begin
    isempty(edit.selection) ? delete_next!(edit) : delete_selection!(edit)
  end)
  push!(bindings, key"enter" => () -> commit_modifications!(edit))
  push!(bindings, key"escape" => () -> clear_modifications!(edit))
  edit.shortcuts = bind(bindings)
end

function unregister_shortcuts!(edit::TextEditState)
  edit.shortcuts === nothing && return
  unbind(edit.shortcuts)
  edit.shortcuts = nothing
end

function clear_modifications!(edit::TextEditState)
  clear_selection!(edit)
  stop_editing!(edit)
end

function clear_selection!(edit::TextEditState)
  edit.selection = 1:0
  remove_selection_background!(edit)
  synchronize!(edit.text)
end

function set_cursor!(edit::TextEditState, i)
  edit.cursor_index = clamp(i, 0, length(edit.buffer))
  add_callback(edit.typing_overlay, edit.character_input)
  display_cursor!(edit)
end

function unset_cursor!(edit::TextEditState)
  edit.cursor_index = -1
  remove_callback(edit.typing_overlay, edit.character_input)
  unset_render(edit.cursor)
end

function display_cursor!(edit::TextEditState)
  # TODO: Implement a substitution-aware mapping.
  glyph_index = edit.cursor_index
  location = get_location(edit.text)
  geometry = get_geometry(edit.text)
  origin = geometry.bottom_left .+ location
  # XXX: Remove this visual hack and actually address the vertical position issue.
  origin = origin .+ P2(0, 0.15)
  set_location(edit.cursor, origin .+ cursor_location(edit.text.lines, glyph_index))
  edit.cursor.geometry = cursor_geometry(edit.text.lines, glyph_index)
  synchronize!(edit.cursor)
end

function cursor_index(text::AbstractString, lines::Vector{OpenType.Line}, (x, y))
  # TODO: Support glyph substitutions and BiDi.
  length(lines) == 1 || error("Multi-line text is not supported yet")
  line = lines[1]
  offset = P2(0, 0)
  for (i, advance) in enumerate(line.advances)
    midpoint = offset .+ 0.5 .* advance
    midpoint[1] > x && return i - 1
    offset = offset .+ line.advances[i]
  end
  length(text)
end

function cursor_location(lines::Vector{OpenType.Line}, glyph_index)
  line = only(lines)
  sum(@view line.advances[1:glyph_index])
end

function cursor_geometry(lines::Vector{OpenType.Line}, glyph_index)
  line = only(lines)
  if glyph_index == 0
    segment = line.segments[1]
  else
    i = findfirst(x -> in(glyph_index, x.indices), line.segments)
    isnothing(i) && return Box2(zero(P2), zero(P2))
    segment = line.segments[i]
  end
  width = 0.1
  height = 1.2segment_height(segment)
  geometry(width, height)
end

function commit_modifications!(edit::TextEditState)
  edit.text.value = edit.buffer
  clear_modifications!(edit)
  edit.on_edit === nothing && return
  edit.on_edit(edit.text.value)
end

function insert_after!(edit::TextEditState, value)
  edit_buffer!(edit, (edit.cursor_index + 1, edit.cursor_index), value)
  set_cursor!(edit, edit.cursor_index + 1)
end

function delete_previous!(edit::TextEditState)
  edit.cursor_index == 0 && return
  edit_buffer!(edit, (edit.cursor_index, edit.cursor_index), "")
  set_cursor!(edit, edit.cursor_index - 1)
end

function delete_next!(edit::TextEditState)
  edit.cursor_index == length(edit.buffer) && return
  edit_buffer!(edit, (edit.cursor_index + 1, edit.cursor_index + 1), "")
end

function delete_selection!(edit::TextEditState)
  @assert !isempty(edit.selection)
  edit_buffer!(edit, edit.selection, "")
  set_cursor!(edit, edit.cursor_index - length(edit.selection))
  clear_selection!(edit)
end

function edit_selection!(edit::TextEditState, replacement)
  @assert !isempty(edit.selection)
  edit_buffer!(edit, edit.selection, replacement)
  set_cursor!(edit, first(edit.selection) + length(replacement) - 1)
  clear_selection!(edit)
end

edit_buffer!(edit::TextEditState, range::UnitRange, replacement) = edit_buffer!(edit, (first(range), last(range)), replacement)

function edit_buffer!(edit::TextEditState, (start, stop), replacement)
  isa(replacement, AnnotatedString) || (replacement = inherit_style(replacement, edit.buffer, (start, stop)))
  i = byte_index(edit.buffer, start - 1)
  j = byte_index(edit.buffer, stop + 1)
  new = annotatedstring(@view(edit.buffer[1:i]), replacement, @view(edit.buffer[j:end]))
  # Compact identically-styled regions to avoid accumulating too many of them.
  annotatedstring_optimize!(new)
  edit.buffer = new
  synchronize!(edit.text)
end

function inherit_style(str, buffer, (start, stop))
  n = length(buffer)
  reference_index = start > n ? n : stop < 1 ? 1 : start
  i = byte_index(buffer, reference_index)
  str = annotatedstring(str)
  for (_, label, value) in annotations(buffer, i:i)
    annotate!(str, label, value)
  end
  str
end

function navigate_previous!(edit::TextEditState)
  isempty(edit.selection) && return set_cursor!(edit, edit.cursor_index - 1)
  set_cursor!(edit, first(edit.selection) - 1)
  clear_selection!(edit)
end

function navigate_next!(edit::TextEditState)
  isempty(edit.selection) && return set_cursor!(edit, edit.cursor_index + 1)
  set_cursor!(edit, last(edit.selection))
  clear_selection!(edit)
end

function navigate_previous_word!(edit::TextEditState)
  j = edit.cursor_index
  buffer = reverse(edit.buffer[begin:byte_index(edit.buffer, j)])
  m = match(r"(?<=\S)[\b\s+][^$]", buffer)
  index = !isnothing(m) ? length(buffer) - (character_index(buffer, m.offset) - 1) : 0
  set_cursor!(edit, index)
  clear_selection!(edit)
end

function navigate_next_word!(edit::TextEditState)
  i = edit.cursor_index + 1
  buffer = String(edit.buffer[byte_index(edit.buffer, i):end])
  m = match(r"(?<=\S)[\b\s+]", buffer)
  index = !isnothing(m) ? i - 1 + character_index(buffer, m.offset) - 1 : length(edit.buffer)
  set_cursor!(edit, index)
  clear_selection!(edit)
end

function select_previous!(edit::TextEditState)
  (; selection, cursor_index) = edit
  if isempty(selection)
    start = stop = cursor_index
  elseif first(selection) == cursor_index + 1
    start = first(selection) - 1
    stop = last(selection)
  elseif last(selection) == cursor_index
    start = first(selection)
    stop = last(selection) - 1
  end
  set_cursor!(edit, cursor_index - 1)
  select_text!(edit, (start, stop); set_cursor = false)
end

function select_next!(edit::TextEditState)
  (; selection, cursor_index) = edit
  if isempty(selection)
    start = stop = cursor_index + 1
  elseif first(selection) == cursor_index + 1
    start = first(selection) + 1
    stop = last(selection)
  elseif last(selection) == cursor_index
    start = first(selection)
    stop = last(selection) + 1
  end
  set_cursor!(edit, cursor_index + 1)
  select_text!(edit, (start, stop); set_cursor = false)
end

select_previous_word!(edit::TextEditState) = navigate_and_select_previous!(navigate_previous_word!, edit)

function navigate_and_select_previous!(navigate!, edit::TextEditState)
  previous_selection = edit.selection
  previous_cursor_index = edit.cursor_index
  (; selection, cursor_index) = edit
  navigate!(edit)
  if isempty(previous_selection)
    start = edit.cursor_index + 1
    stop = previous_cursor_index
  elseif first(previous_selection) == previous_cursor_index + 1
    # Expand selection toward the left.
    start = edit.cursor_index + 1
    stop = last(previous_selection)
  elseif last(previous_selection) == previous_cursor_index
    # Select toward the left (shrinking or starting a new selection).
    start = first(previous_selection)
    stop = edit.cursor_index
    start > stop && ((start, stop) = (stop + 1, start - 1))
  end
  select_text!(edit, (start, stop); set_cursor = false)
end

select_next_word!(edit::TextEditState) = navigate_and_select_next!(navigate_next_word!, edit)

function navigate_and_select_next!(navigate!, edit::TextEditState)
  previous_selection = edit.selection
  previous_cursor_index = edit.cursor_index
  (; selection, cursor_index) = edit
  navigate!(edit)
  if isempty(previous_selection)
    start = previous_cursor_index + 1
    stop = edit.cursor_index
  elseif first(previous_selection) == previous_cursor_index + 1
    # Select toward the right (shrinking or starting a new selection).
    start = edit.cursor_index + 1
    stop = last(previous_selection)
    start > stop && ((start, stop) = (stop + 1, start - 1))
  elseif last(previous_selection) == previous_cursor_index
    # Expand selection toward the right.
    start = first(previous_selection)
    stop = edit.cursor_index
  end
  select_text!(edit, (start, stop); set_cursor = false)
end

function navigate_start!(edit::TextEditState)
  set_cursor!(edit, 0)
  clear_selection!(edit)
end

function navigate_end!(edit::TextEditState)
  set_cursor!(edit, length(edit.buffer))
  clear_selection!(edit)
end

select_start!(edit::TextEditState) = navigate_and_select_previous!(navigate_start!, edit)
select_end!(edit::TextEditState) = navigate_and_select_next!(navigate_end!, edit)

"""
Return the index of the byte that points to the `i`th character in `str`.

Performs the inverse operation of `character_index`.
"""
function byte_index(str::AbstractString, i)
  i < 0 && throw(ArgumentError("Expected positive index, got $i"))
  i == 0 && return 0
  i == 1 && return 1
  n = length(str)
  next = 1
  for j in 1:n
    i == j && return next
    _, next = iterate(str, next)
  end
  next - 1 + (i - n)
end

"""
Return the index of the character that uses the `i`th byte in `str`.

Performs the inverse operation of `byte_index`.

!!! warning
    This function scales as O(length(str)).
"""
character_index(str::AbstractString, byte_index) = findlast(≤(byte_index), collect(keys(str)))

function select_text!(edit::TextEditState, (start, stop) = (1, length(edit.buffer)); set_cursor = true)
  start = max(1, start)
  stop = min(length(edit.buffer), stop)
  set_cursor && set_cursor!(edit, stop)
  range = start:stop
  isempty(range) && return clear_selection!(edit)
  edit.selection = range
  add_selection_background!(edit)
  synchronize!(edit.text)
end

function select_word!(edit::TextEditState, (x, _); set_cursor = true)
  cx, _ = get_location(edit.cursor)
  click = edit.cursor_index + (x > cx)
  for (; match, offset) in eachmatch(r"\w+|[^\w\s]+|\s+", edit.buffer)
    start = character_index(edit.buffer, offset)
    stop = start + length(match) - 1
    start - 1 ≤ click ≤ stop || continue
    return select_text!(edit, (start, stop); set_cursor)
  end
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
  add_callback(input -> is_left_click(input) && button.on_input(input), button, BUTTON_PRESSED)
  isnothing(button.text) && return
  put_behind(button.background, button.text)
  set_geometry(button, get_geometry(button.background))
  place(button.background, button)
  place(button.text |> at(:center) |> at(0.0, -0.08), button)
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
  place(checkbox.background, checkbox)
  add_callback(input -> is_left_click(input) && checkbox.on_toggle(input), checkbox, BUTTON_PRESSED)
  checkbox.background.color = checkbox.value ? checkbox.active_color : checkbox.inactive_color
end

mutable struct MenuItem
  const widget::WidgetID
  # Whether the item is currently active in navigation (pointer actively over it, navigation via keyboard)
  active::Bool
  const on_selected::Any
  const on_active::Any
  const text::Optional{Text}
  const shortcut::Optional{Char}
end

function set_active(item::MenuItem)
  item.active && return
  item.active = true
  item.on_active === nothing && return
  item.on_active(true)
end

function set_inactive(item::MenuItem)
  !item.active && return
  item.active = false
  item.on_active === nothing && return
  item.on_active(false)
end

isactive(item::MenuItem) = item.active

function MenuItem(on_selected, widget; text = nothing, shortcut = nothing, on_active = nothing)
  !isnothing(text) && isnothing(shortcut) && (shortcut = lowercase(first(text.value)))
  MenuItem(widget, false, on_selected, on_active, text, shortcut)
end

function disable!(item::MenuItem)
  disable!(item.widget)
  isnothing(item.text) && return
  disable!(item.text)
end

function enable!(item::MenuItem)
  enable!(item.widget)
  isnothing(item.text) && return
  enable!(item.text)
end

mutable struct Menu
  const on_expand::Any
  const on_collapse::Any
  const head::WidgetID
  const items::Vector{MenuItem}
  const set::InteractionSet
  expanded::Bool
  const overlay::EntityID # entity that overlays the whole window on menu expand to allow scrolling outside the menu area
  shortcuts::Union{Nothing, KeyBindingsToken}
  const shortcut::Char
end

add_menu_item!(menu::Menu, item::MenuItem) = push!(menu.items, item)
add_menu_items!(menu::Menu, items) = append!(menu.items, items)

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

function Menu(head, shortcut::Char; set = InteractionSet(), on_expand = nothing, on_collapse = nothing)
  menu = Menu(on_expand, on_collapse, head, WidgetID[], set, false, new_entity(), 0, lowercase(shortcut))
  add_callback(menu.head, BUTTON_PRESSED) do input::Input
    is_left_click(input) && !menu.expanded && return expand!(menu)
    is_left_click(input) && menu.expanded && return collapse!(menu)
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
  menu.expanded = true
  create_window_overlay!(menu)

  menu.on_expand !== nothing && use_interaction_set(() -> menu.on_expand(menu), menu.set)

  register_shortcuts!(menu)
  for item in menu.items
    add_callback(item.widget, BUTTON_PRESSED | POINTER_ENTERED | POINTER_EXITED) do input::Input
      if is_left_click(input)
        item.on_selected()
        collapse!(menu)
      end
      input.type === POINTER_ENTERED && set_active(menu, item)
      input.type === POINTER_EXITED && set_inactive(item)
    end
  end

  true
end

function collapse!(menu::Menu)
  menu.expanded || return false
  menu.expanded = false
  foreach(set_inactive, menu.items)
  unregister_shortcuts!(menu)
  delete_widget(menu.overlay)
  menu.on_collapse !== nothing && use_interaction_set(() -> menu.on_collapse(menu), menu.set)
  false
end

function close!(menu::Menu)
  wipe!(menu.set)
  empty!(menu.items)
end

function create_window_overlay!(menu::Menu)
  window = app.windows[app.window]
  set_location(menu.overlay, get_location(window))
  set_geometry(menu.overlay, get_geometry(window))
  set_z(menu.overlay, Inf)
  add_callback(menu.overlay, BUTTON_PRESSED) do input::Input
    propagate!(input) do propagated
      propagated && return
      click = input.event.mouse_event.button
      !in(click, (BUTTON_SCROLL_UP, BUTTON_SCROLL_DOWN)) && return collapse!(menu)
      navigate_to_next_item(menu, ifelse(click == BUTTON_SCROLL_UP, -1, 1))
    end
  end
end

function register_shortcuts!(menu::Menu)
  menu.shortcuts === nothing || unbind(menu.shortcuts)
  shortcuts = [item.shortcut for item in menu.items]
  bindings = Pair{KeyCombination, Callable}[]
  for (item, shortcut) in zip(menu.items, shortcuts)
    isnothing(shortcut) && continue
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

at(arg, args...) = Layout.at(app.systems.layout.engine, arg, args...)

width() = Layout.width_of
height() = Layout.height_of

const WidgetComponent = Union{subtypes(Widget)...}
