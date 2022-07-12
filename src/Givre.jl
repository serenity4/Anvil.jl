module Givre

using Reexport
@reexport using Diatone
using Lava: DrawState
using Dictionaries
using Accessors: @set
@reexport using GeometryExperiments
using UUIDs: uuid4, UUID

uuid() = uuid4()

const Point2f = Point{2,Float32}
const Optional{T} = Union{T,Nothing}

include("utils.jl")
include("keybindings.jl")
include("render.jl")
include("rectangle.jl")
include("main.jl")

export main, Rectangle


end
