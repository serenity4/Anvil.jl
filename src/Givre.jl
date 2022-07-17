module Givre

using Reexport
@reexport using Diatone
using Dictionaries
using Accessors: @set
@reexport using GeometryExperiments
using UUIDs: uuid4, UUID

uuid() = uuid4()

const Optional{T} = Union{T,Nothing}

include("utils.jl")
include("keybindings.jl")
include("render.jl")
include("rectangle.jl")
include("main.jl")

export main, Rectangle, render_to_array


end
