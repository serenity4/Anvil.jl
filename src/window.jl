function on_key_pressed(details::EventDetails)
    @unpack win, data = details
    @unpack key_name, key, input, modifiers = data
    kc = KeyCombination(key, modifiers)
    if kc ∈ [key"q", key"ctrl+q"]
        println("Bye!")
        throw(CloseWindow(win, ""))
    end
end

function Application()
    connection = Connection()
    setup = Setup(connection)
    iter = XCB.xcb_setup_roots_iterator(setup)
    screen = unsafe_load(iter.data)

    win = XCBWindow(connection, screen; x=0, y=1000, border_width=50, window_title="Givre", icon_title="Givre", attributes=[XCB.XCB_CW_BACK_PIXEL], values=[screen.black_pixel])
    println("Window ID: ", win.id)

    wh = XWindowHandler(connection, [win])

    set_callbacks!(wh, win, WindowCallbacks(;
        on_key_pressed
    ))

    Application(wh)
end
