"""
    @record command_buffer [create_info] commands

Convenience macro for recording a sequence of API commands into a command buffer `cbuff`.
All API commands have `cbuff` inserted as their first argument, and are wrapped inside
`begin_command_buffer(cbuff, info)` and `end_command_buffer(cbuff)`.

The two-argument version of this macro simply passes in a default `CommandBufferBeginInfo()`.
"""
macro record(cbuff, info, cmds)
    cmds = @match cmds begin
        Expr(:block, args...) => args
        _ => [cmds]
    end
    _cbuff, _info = esc(cbuff), esc(info)
    api_calls = map(filter(x -> !isa(x, LineNumberNode), cmds)) do cmd
        @match cmd begin
            :($f($(args...))) => :($f($_cbuff, $(esc.(args)...)))
            :($f($(args...); $(kwargs...))) => :($f($_cbuff, $(esc.(args)...); $(esc.(kwargs)...)))
            _ => error("Expected API call, got $cmd")
        end
    end
    esc(quote
        begin_command_buffer($_cbuff, $_info)
        $(api_calls...)
        end_command_buffer($_cbuff)
    end)
end

macro record(cbuff, cmds)
    :(@record $cbuff CommandBufferBeginInfo() $cmds)
end
