walk(ex::Expr, inner, outer) = outer(Expr(ex.head, map(inner, ex.args)...))
walk(ex, inner, outer) = outer(ex)

postwalk(f, ex) = walk(ex, x -> postwalk(f, x), f)
prewalk(f, ex) = walk(f(ex), x -> prewalk(f, x), identity)

"""
    @record command_buffer [create_info] commands

Convenience macro for recording a sequence of API commands into a command buffer `cbuff`.
All calls to API commands have `cbuff` inserted as their first argument, and are wrapped inside
`begin_command_buffer(cbuff, info)` and `end_command_buffer(cbuff)`.

!!! warning
    An expression is assumed to be an API command if it begins with `cmd_`.
    Make sure that all functions that you call satisfy this assumption.

The two-argument version of this macro simply passes in a default `CommandBufferBeginInfo()`.
"""
macro record(cbuff, info, cmds)
    cmds = @match cmds begin
        Expr(:block, args...) => args
        _ => [cmds]
    end
    _cbuff, _info = esc(cbuff), esc(info)
    api_calls = map(cmds) do cmd
        postwalk(cmd) do ex
            @match ex begin
                :($f($(args...))) => startswith(string(f), "cmd_") ? :($(esc(f))($_cbuff, $(esc.(args)...))) : ex
                :($f($(args...); $(kwargs...))) => startswith(string(f), "cmd_") ? :($(esc(f))($_cbuff, $(esc.(args)...); $(esc.(kwargs)...))) : ex
                _ => ex
            end
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
