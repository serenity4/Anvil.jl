using Givre
using Givre: app, get_widget, get_location, synchronize, Widget, exit, to_rendering_coordinate_system, to_window_coordinate_system
using LinearAlgebra: norm
using XCB
using WindowAbstractions
using Test
using Logging: Logging

Logging.disable_logging(Logging.Info)
ENV["GIVRE_LOG_FRAMECOUNT"] = false

CURSOR = Ref((0.5, 0.5))
send(args...; kwargs...) = send_event(app.wm, app.window, args...; location = CURSOR[], kwargs...)
press_key(key; modifiers = NO_MODIFIERS) = send(KEY_PRESSED, KeyEvent(app.wm.keymap, PhysicalKey(app.wm.keymap, key), modifiers))
function left_click(; state = BUTTON_NONE)
  send(BUTTON_PRESSED, MouseEvent(BUTTON_LEFT, state))
  send(BUTTON_RELEASED, MouseEvent(BUTTON_LEFT, state))
end

move_cursor(widget::Widget; spatial_resolution = 0.01) = move_cursor(get_location(widget); spatial_resolution)

function move_cursor(location; spatial_resolution = 0.01)
  from = CURSOR[]
  to = to_window_coordinate_system(location, app.window)
  from == to && return
  CURSOR[] = to
  points = linear_path(from, to, spatial_resolution)
  for point in points
    # XXX: Set the correct `PointerState` for e.g. dragging operations.
    send_event(app.wm, app.window, POINTER_MOVED, PointerState(BUTTON_NONE, NO_MODIFIERS); location = point)
  end
end

function linear_path(from::NTuple{2}, to::NTuple{2}, spatial_resolution::Real)
  diag = to .- from
  steps = collect(0.0:spatial_resolution:1.0)
  !in(1.0, steps) && push!(steps, 1.0)
  unique!([from .+ step .* diag for step in steps])
end

@testset "Application setup" begin
  GC.gc()
  @test isa(sprint(show, Givre.app), String)
  main(async = true)
  synchronize()
  @test isa(sprint(show, app), String)
  @test app.ecs[app.windows[app.window], Givre.WINDOW_COMPONENT_ID] == app.window

  for location in [(0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 1.0), (0.5, 0.5), (0.4, 0.6)]
    location_2 = to_rendering_coordinate_system(location, app.window)
    @test collect(to_window_coordinate_system(location_2, app.window)) == collect(location)
  end

  press_key(:AC01; modifiers = CTRL_MODIFIER)
  wait(app)
  @test istaskdone(app.task)

  # XXX: These tests seem to have race conditions, probably due to
  # whether events are processed in a batch or whether the application
  # has time to synchronize its widgets after modification.
  GC.gc()
  main(async = true)
  synchronize()
  sleep(0.1)
  file_menu = get_widget(:file_menu)
  @test !file_menu.expanded
  CURSOR[] = (0.5, 0.5)
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
  item_1 = get_widget(:file_menu_2)
  move_cursor(item_1)
  synchronize()
  @test Givre.active_item(file_menu) === item_1
  item_2 = get_widget(:file_menu_3)
  move_cursor(item_2)
  synchronize()
  @test Givre.active_item(file_menu) === item_2
  left_click()
  synchronize()
  @test !file_menu.expanded
  @test Givre.active_item(file_menu) === nothing
  exit(0)
end;
