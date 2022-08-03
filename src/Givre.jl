module Givre

using Reexport
using Diatone
using Lava
using Dictionaries
using Accessors: @set
using GeometryExperiments
using UUIDs: uuid1, UUID
using Accessors

uuid() = uuid1()

const Optional{T} = Union{T,Nothing}

include("utils.jl")
include("keybindings.jl")
include("render.jl")
include("rectangle.jl")
include("main.jl")

export main


end
