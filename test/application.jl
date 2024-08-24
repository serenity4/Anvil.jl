using Givre
using Givre: EntityID, get_widget, get_entity, get_location, synchronize, Widget, to_rendering_coordinate_system, to_window_coordinate_system
using CooperativeTasks: execute
using LinearAlgebra: norm
using XCB
using WindowAbstractions
using Test
using Logging: Logging
using MLStyle: @match

Logging.disable_logging(Logging.Info)
ENV["GIVRE_LOG_FRAMECOUNT"] = false

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
  release && send(KEY_RELEASED, KeyEvent(app.wm.keymap, PhysicalKey(app.wm.keymap, key), modifiers))
  nothing
end

left_click() = press_button(BUTTON_LEFT)
scroll_up(n = 1) = foreach(_ -> press_button(BUTTON_SCROLL_UP), 1:n)
scroll_down(n = 1) = foreach(_ -> press_button(BUTTON_SCROLL_UP), 1:n)

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

@testset "Application" begin
  @testset "Application start/exit" begin
    GC.gc()
    @test isa(sprint(show, Givre.app), String)
    main(async = true)
    synchronize()
    @test isa(sprint(show, app), String)
    @test app.ecs[app.windows[app.window], Givre.WINDOW_COMPONENT_ID] == app.window

    @testset "Location mapping" begin
      for location in [(0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 1.0), (0.5, 0.5), (0.4, 0.6)]
        location_2 = to_rendering_coordinate_system(location, app.window)
        @test collect(to_window_coordinate_system(location_2, app.window)) == collect(location)
      end
    end

    press_key(:AC01; modifiers = CTRL_MODIFIER)
    wait(app)
    @test istaskdone(app.task)
  end

  @testset "Interactions" begin
    GC.gc()
    CURSOR[] = (0.5, 0.5)
    main(async = true)
    synchronize()
    sleep(0.1)
    synchronize()

    # Menu.

    file_menu = get_widget(:file_menu)
    @test !file_menu.expanded

    move_cursor(file_menu)
    left_click()
    synchronize()
    @test file_menu.expanded
    @test Givre.active_item(file_menu) === nothing

    left_click()
    synchronize()
    @test !file_menu.expanded
    @test Givre.active_item(file_menu) === nothing

    left_click()
    synchronize()
    @test file_menu.expanded

    item_1 = get_widget(:file_menu_item_1)
    move_cursor(item_1)
    synchronize()
    @test Givre.active_item(file_menu) === item_1

    item_2 = get_widget(:file_menu_item_2)
    move_cursor(item_2)
    synchronize()
    @test Givre.active_item(file_menu) === item_2

    left_click()
    synchronize()
    @test !file_menu.expanded
    @test Givre.active_item(file_menu) === nothing

    ## Key-based navigation.
    move_cursor(file_menu)
    left_click()
    press_key(:UP)
    synchronize()
    @test Givre.active_item(file_menu) === item_2
    press_key(:RTRN)
    synchronize()
    @test Givre.active_item(file_menu) === nothing
    @test !file_menu.expanded

    left_click()
    press_key(:UP)
    press_key(:UP)
    synchronize()
    @test count(Givre.isactive, file_menu.items) == 1
    @test Givre.active_item(file_menu) === item_1
    press_key(:DOWN)
    synchronize()
    @test count(Givre.isactive, file_menu.items) == 1
    @test Givre.active_item(file_menu) === item_2
    move_cursor(item_1)
    synchronize()
    @test count(Givre.isactive, file_menu.items) == 1
    @test Givre.active_item(file_menu) === item_1
    press_key(:RTRN)
    synchronize()
    @test Givre.active_item(file_menu) === nothing
    @test !file_menu.expanded

    ## Wheel-based navigation.
    move_cursor(file_menu)
    left_click()
    scroll_up()
    synchronize()
    @test Givre.active_item(file_menu) === item_2
    scroll_down()
    synchronize()
    @test Givre.active_item(file_menu) === item_1
    press_key(:RTRN)
    synchronize()
    @test Givre.active_item(file_menu) === nothing
    @test !file_menu.expanded

    # Checkbox.

    checkbox = get_widget(:checkbox)
    @test !checkbox.value

    move_cursor(checkbox)
    left_click()
    synchronize()
    @test checkbox.value

    left_click()
    synchronize()
    @test !checkbox.value

    # Dragging.

    texture = get_entity(:texture)
    from = get_location(texture)
    move_cursor(texture)
    drag(from .+ 0.5)
    @test BUTTON_STATE[] == BUTTON_LEFT
    drop()
    @test BUTTON_STATE[] == BUTTON_NONE
    synchronize()
    to = get_location(texture)
    @test to - from ≈ [0.5, 0.5] atol=0.02

    @test quit()
    @test istaskdone(app.task)
  end
end;
