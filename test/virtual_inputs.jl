CURSOR = Ref((0.5, 0.5))
BUTTON_STATE = Ref(BUTTON_NONE)
MODIFIER_STATE = Ref(NO_MODIFIERS)

function send(event_type, data = nothing; location = CURSOR[], time = time())
  event = Event(event_type, data, location, time, app.window)
  @match event.type begin
    &BUTTON_PRESSED => (BUTTON_STATE[] |= event.mouse_event.button)
    &BUTTON_RELEASED => (BUTTON_STATE[] = BUTTON_STATE[] & ~event.mouse_event.button)
    &KEY_PRESSED || &KEY_RELEASED => begin
      modifier = ModifierState(event.key_event.key)
      event.type == KEY_PRESSED ? (MODIFIER_STATE[] |= modifier) : (MODIFIER_STATE[] &= ~modifier)
    end
  end
  send_event(app.wm, event)
  # Let some time for the X server to process the event and send it to the application.
  sleep(0.01)
end

function press_button(button; release = true)
  send(BUTTON_PRESSED, MouseEvent(button, BUTTON_STATE[]); location = CURSOR[])
  release && send(BUTTON_RELEASED, MouseEvent(button, BUTTON_STATE[]); location = CURSOR[])
  nothing
end

function press_key(key; modifiers = NO_MODIFIERS, release = true)
  send(KEY_PRESSED, KeyEvent(app.wm.keymap, PhysicalKey(app.wm.keymap, key), modifiers))
  release && release_key(key; modifiers)
  nothing
end

function release_key(key; modifiers = NO_MODIFIERS)
  send(KEY_RELEASED, KeyEvent(app.wm.keymap, PhysicalKey(app.wm.keymap, key), modifiers))
  nothing
end

left_click() = press_button(BUTTON_LEFT)
scroll_up(n = 1) = foreach(_ -> press_button(BUTTON_SCROLL_UP), 1:n)
scroll_down(n = 1) = foreach(_ -> press_button(BUTTON_SCROLL_DOWN), 1:n)

function drag(to)
  send(BUTTON_PRESSED, MouseEvent(BUTTON_LEFT, BUTTON_STATE[]); location = CURSOR[])
  move_cursor(to)
end
drop() = send(BUTTON_RELEASED, MouseEvent(BUTTON_LEFT, BUTTON_STATE[]); location = CURSOR[])

move_cursor(widget::Widget; spatial_resolution = 0.01) = move_cursor(get_location(widget); spatial_resolution)
move_cursor(entity::EntityID; spatial_resolution = 0.01) = move_cursor(get_location(entity); spatial_resolution)

function move_cursor(location; spatial_resolution = 0.01)
  from = CURSOR[]
  to = to_window_coordinate_system(location, app.window)
  from == to && return
  CURSOR[] = to
  points = linear_path(from, to, spatial_resolution)
  for point in points
    send_event(app.wm, app.window, POINTER_MOVED, PointerState(BUTTON_STATE[], MODIFIER_STATE[]); location = point)
  end
  sleep(0.01)
end

function linear_path(from::NTuple{2}, to::NTuple{2}, spatial_resolution::Real)
  diag = to .- from
  steps = collect(0.0:spatial_resolution:1.0)
  !in(1.0, steps) && push!(steps, 1.0)
  popfirst!(steps) # remove `from`
  unique!([from .+ step .* diag for step in steps])
end
