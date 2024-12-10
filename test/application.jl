using Anvil
using Anvil: EntityID, get_widget, get_entity, get_location, synchronize, Widget, to_metric_coordinate_system, to_window_coordinate_system, exit, has_render
using CooperativeTasks: execute
using LinearAlgebra: norm
using XCB
using Test
using Logging: Logging
using MLStyle: @match
using StyledStrings: annotations, getface
using GeometryExperiments: centroid

Logging.disable_logging(Logging.Info)
ENV["ANVIL_LOG_FRAMECOUNT"] = false

!@isdefined(CURSOR) && includet("virtual_inputs.jl")

# While executing this testset, do not provide any input of any sort to the windows that pop up.
# Otherwise, tests will fail due to unexpected interactions.

@testset "Application" begin
  @testset "Application start/exit" begin
    @test isa(sprint(show, Anvil.app), String)
    main(async = true)
    synchronize()
    @test isa(sprint(show, app), String)
    @test app.ecs[app.windows[app.window], Anvil.WINDOW_COMPONENT_ID] == app.window

    @testset "Location mapping" begin
      for location in [(0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 1.0), (0.5, 0.5), (0.4, 0.6)]
        location_2 = to_metric_coordinate_system(location, app.window)
        @test collect(to_window_coordinate_system(location_2, app.window)) == collect(location)
      end
    end

    press_key(:AC01; modifiers = CTRL_MODIFIER)
    wait(app)
    @test istaskdone(app.task)
  end

  @testset "Interactions" begin
    CURSOR[] = (0.5, 0.5)
    state = ApplicationState()
    main(state; async = true, record_events = true)
    synchronize()
    sleep(0.1)
    synchronize()

    # Menu.

    menu = state.info[:file_menu]::Menu
    @test !menu.expanded

    move_cursor(menu.head)
    left_click()
    synchronize()
    @test menu.expanded
    @test Anvil.active_item(menu) === nothing

    left_click()
    synchronize()
    @test !menu.expanded
    @test Anvil.active_item(menu) === nothing

    left_click()
    synchronize()
    @test menu.expanded

    item_1 = menu.items[1]
    move_cursor(item_1.widget)
    synchronize()
    @test Anvil.active_item(menu) === item_1

    item_2 = menu.items[2]
    move_cursor(item_2.widget)
    synchronize()
    @test Anvil.active_item(menu) === item_2

    left_click()
    synchronize()
    @test !menu.expanded
    @test Anvil.active_item(menu) === nothing

    ## Key-based navigation.
    move_cursor(menu.head)
    left_click()
    move_cursor(get_location(menu.head) .+ (10, 0))
    press_key(:UP)
    synchronize()
    @test Anvil.active_item(menu) === menu.items[end]
    press_key(:UP)
    press_key(:RTRN)
    synchronize()
    @test Anvil.active_item(menu) === nothing
    @test !menu.expanded

    move_cursor(menu.head)
    left_click()
    move_cursor(get_location(menu.head) .+ (10, 0))
    press_key(:UP)
    press_key(:UP)
    synchronize()
    @test count(Anvil.isactive, menu.items) == 1
    @test Anvil.active_item(menu) === menu.items[end - 1]
    press_key(:DOWN)
    synchronize()
    @test count(Anvil.isactive, menu.items) == 1
    @test Anvil.active_item(menu) === menu.items[end]
    move_cursor(menu.items[1].widget)
    synchronize()
    @test count(Anvil.isactive, menu.items) == 1
    @test Anvil.active_item(menu) == menu.items[1]
    press_key(:RTRN)
    synchronize()
    @test Anvil.active_item(menu) === nothing
    @test !menu.expanded

    ## Wheel-based navigation.
    move_cursor(menu.head)
    left_click()
    move_cursor(get_location(menu.head) .+ (10, 0))
    scroll_up()
    synchronize()
    @test Anvil.active_item(menu) === menu.items[end]
    scroll_down()
    synchronize()
    @test Anvil.active_item(menu) === menu.items[1]
    press_key(:RTRN)
    synchronize()
    @test Anvil.active_item(menu) === nothing
    @test !menu.expanded

    ## Shortcut navigation.
    move_cursor(menu.head)
    left_click()
    synchronize()
    @test menu.expanded
    press_key(:AB06)
    synchronize()
    @test !menu.expanded

    # Checkbox.

    checkbox = get_widget(:node_hide_value)
    @test !checkbox.value

    move_cursor(checkbox)
    left_click()
    synchronize()
    @test checkbox.value

    left_click()
    synchronize()
    @test !checkbox.value

    # Dragging.

    image = get_entity(:image)
    from = get_location(image)
    move_cursor(image)
    drag(from .+ 5)
    @test BUTTON_STATE[] == BUTTON_LEFT
    drop()
    @test BUTTON_STATE[] == BUTTON_NONE
    synchronize()
    to = get_location(image)
    @test to - from ≈ [5, 5] rtol=0.02

    # Shortcut display.

    move_cursor(menu.head)
    left_click()
    synchronize()
    text = menu.items[1].text.value
    @test annotations(text, 1) == [(region = 1:1, label = :face, value = :application_shortcut_hide)]
    press_key(:LALT)
    synchronize()
    @test annotations(text, 1) == [(region = 1:1, label = :face, value = :application_shortcut_show)]
    face = getface(last.(annotations(text)))
    @test face.underline === true
    press_key(:LALT)
    synchronize()
    @test annotations(text, 1) == [(region = 1:1, label = :face, value = :application_shortcut_hide)]
    face = getface(last.(annotations(text)))
    @test face.underline === false
    press_key(:LALT)
    synchronize()
    @test annotations(text, 1) == [(region = 1:1, label = :face, value = :application_shortcut_show)]
    face = getface(last.(annotations(text)))
    @test face.underline === true
    left_click() # close menu
    synchronize()
    @test annotations(text, 1) == []

    # Text editing.

    @testset "Text editing" begin
      text = get_widget(:node_name_value)
      @test text.value == "Value"
      move_cursor(get_location(text) .+ centroid(get_geometry(text)))

      @testset "Selection/deselection" begin
        left_click()
        synchronize()
        @test String(text.edit.buffer) == "Value"
        @test text.edit.cursor_index == length(text.value)
        @test text.edit.selection == 1:length(text.value)
        @test length(annotations(text.edit.buffer)) == 1
        (region, label, _) = annotations(text.edit.buffer)[1]
        @test region == 1:5 && label == :background
        @test has_render(text.edit.cursor)

        press_key(:ESC)
        synchronize()
        @test text.edit.buffer === nothing
        @test text.value == "Value"
        @test !has_render(text.edit.cursor)
      end

      @testset "Cursor selection" begin
        left_click()
        left_click()
        synchronize()
        @test isempty(text.edit.selection)
        @test isempty(annotations(text.edit.buffer))
        @test text.edit.cursor_index == 2
        press_key(:ESC)
      end

      @testset "Typing & cancelling" begin
        left_click()
        left_click()
        press_key(:AC02)
        synchronize()
        @test text.edit.buffer == "Vaslue"
        synchronize()
        @test isempty(text.edit.selection)
        @test isempty(annotations(text.edit.buffer))
        @test text.edit.cursor_index == 3
        press_key(:ESC)
        synchronize()
        @test text.edit.buffer === nothing
        @test text.value == "Value"
      end

      @testset "Keyboard navigation" begin
        left_click()
        left_click()
        synchronize()
        @test text.edit.cursor_index == 2
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 1
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 0
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 0
        press_key(:RGHT)
        synchronize()
        @test text.edit.cursor_index == 1
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 0
        press_key(:RGHT)
        synchronize()
        @test text.edit.cursor_index == 1
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:RGHT)
        synchronize()
        @test text.edit.cursor_index == 5
        press_key(:RGHT)
        synchronize()
        @test text.edit.cursor_index == 5
        press_key(:ESC)
      end

      @testset "Keyboard selection" begin
        left_click()
        left_click()
        synchronize()
        @test text.edit.cursor_index == 2
        @test isempty(text.edit.selection)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 1
        @test text.edit.selection == 2:2
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 0
        @test text.edit.selection == 1:2
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 0
        @test text.edit.selection == 1:2
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 1
        @test text.edit.selection == 2:2
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 2
        @test isempty(text.edit.selection)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 3
        @test text.edit.selection == 3:3
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 2
        @test isempty(text.edit.selection)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 5
        @test text.edit.selection == 3:5
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 5
        @test text.edit.selection == 3:5
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 2
        @test isempty(text.edit.selection)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 0
        @test text.edit.selection == 1:2
        press_key(:LEFT)
        synchronize()
        @test text.edit.cursor_index == 0
        @test isempty(text.edit.selection)
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        synchronize()
        @test text.edit.cursor_index == 0
        @test text.edit.selection == 1:2
        press_key(:RGHT)
        synchronize()
        @test text.edit.cursor_index == 2
        @test isempty(text.edit.selection)
        press_key(:ESC)
      end

      @testset "Editing" begin
        left_click()
        left_click()
        synchronize()
        @test text.edit.cursor_index == 2
        press_key(:AC01)
        press_key(:AC02)
        synchronize()
        @test text.edit.buffer == "Vaqslue"
        @test text.edit.cursor_index == 4
        press_key(:BKSP)
        synchronize()
        @test text.edit.buffer == "Vaqlue"
        press_key(:DELE)
        synchronize()
        @test text.edit.buffer == "Vaque"
        @test text.edit.cursor_index == 3
        press_key(:RTRN)
        synchronize()
        @test text.edit.buffer === nothing
        @test text.value == "Vaque"
        left_click()
        press_key(:BKSP)
        synchronize()
        @test text.edit.buffer == ""
        press_key(:AD09)
        press_key(:AD05)
        press_key(:AC06)
        press_key(:AD03)
        press_key(:AD04)
        synchronize()
        @test text.edit.buffer == "other"
        press_key(:RTRN)
        synchronize()
        @test text.edit.buffer === nothing
        @test text.value == "other"
        left_click()
        press_key(:DELE)
        synchronize()
        @test text.edit.buffer == ""
        press_key(:ESC)
        @test text.edit.buffer === nothing
        @test text.value == "other"
        left_click()
        press_key(:LEFT)
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        press_key(:RGHT; modifiers = SHIFT_MODIFIER)
        press_key(:AD07)
        synchronize()
        @test text.edit.buffer == "otur"
        @test isempty(text.edit.selection)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        press_key(:LEFT; modifiers = SHIFT_MODIFIER)
        press_key(:BKSP)
        synchronize()
        @test text.edit.buffer == "or"
        press_key(:AD09)
        press_key(:ESC)

        text.value = "testing something here"
        left_click()
        synchronize()
        press_key(:KP1)
        synchronize()
        @test text.edit.cursor_index == lastindex(text.edit.buffer)
        press_key(:BKSP; modifiers = CTRL_MODIFIER)
        synchronize()
        @test text.edit.buffer == "testing something "
        press_key(:KP7)
        synchronize()
        @test text.edit.cursor_index == 0
        press_key(:RGHT)
        press_key(:RGHT)
        synchronize()
        press_key(:BKSP; modifiers = CTRL_MODIFIER)
        synchronize()
        @test text.edit.buffer == "sting something "
        @test text.edit.cursor_index == 0
        press_key(:DELE; modifiers = CTRL_MODIFIER)
        synchronize()
        @test text.edit.buffer == " something "
        @test text.edit.cursor_index == 0
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:RGHT)
        press_key(:DELE; modifiers = CTRL_MODIFIER)
        synchronize()
        @test text.edit.buffer == " so "
        @test text.edit.cursor_index == 3

        press_key(:AD01; modifiers = CTRL_MODIFIER)
        press_key(:DELE)
        press_key(:AC02)
        press_key(:AD07)
        press_key(:AB03)
        press_key(:AB03)
        press_key(:AD03)
        press_key(:AC02)
        press_key(:AC02)
        press_key(:RTRN)
        synchronize()
        @test text.value == "success"
      end

      @testset "Text selection" begin
        press_key(:ESC)
        move_cursor(get_location(text) .+ (0.7, 0.1))
        left_click()
        left_click()
        synchronize()
        @test text.edit.cursor_index == 2
        move_cursor(get_location(text) .+ (1.4, 0.1))
        # XXX: Dynamically set a shorter double-click period to avoid having to wait here.
        sleep(0.5)
        left_click(release = false)
        synchronize()
        @test text.edit.cursor_index == 4
        move_cursor(get_location(text) .+ (0.7, 0.1))
        move_cursor(get_location(text) .+ (2.0, 0.1))
        synchronize()
        @test text.edit.cursor_index == 6
        @test text.edit.selection == 5:6
        move_cursor(get_location(text) .+ (4.0, 7.0))
        synchronize()
        @test text.edit.cursor_index == 7
        @test text.edit.selection == 5:7
        move_cursor(get_location(text) .+ (0.7, 0.1))
        synchronize()
        @test text.edit.cursor_index == 2
        @test text.edit.selection == 3:4

        press_key(:ESC)
        text.value = "Some text with words"
        move_cursor(get_location(text) .+ (3.5, 0.1))
        left_click()
        left_click()
        synchronize()
        @test text.edit.cursor_index == 12
        left_click()
        synchronize()
        @test text.edit.cursor_index == 14
        @test text.edit.selection == 11:14
        left_click()
        synchronize()
        @test text.edit.cursor_index == 20
        @test text.edit.selection == 1:20
        press_key(:ESC)
      end
    end

    # Exit.

    move_cursor(menu.head)
    left_click()
    press_key(:AB02) # 'x' to exit
    wait(app)
    @test istaskdone(app.task)

    @testset "Replaying events" begin
      events = save_events()
      main(; async = true)
      synchronize()
      replay_events(events; time_factor = 0.1)
    end
  end
end;
