struct Application{WH<:AbstractWindowHandler}
    """
    Window manager. Only XCB is supported for now.
    """
    wm::WH
end
