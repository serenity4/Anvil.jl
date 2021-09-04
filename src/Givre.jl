module Givre

using Vulkan
using XCB
using MLStyle
using UnPack
using AbstractGUI
using ColorTypes
using ProceduralNoise
using GeometryExperiments
using Accessors
using TimerOutputs
using Memoization: @memoize
using LRUCache: LRU
using Dictionaries
using Rhyolite

import AbstractGUI: callbacks

const to = Rhyolite.to

const Point2f = Point{2,Float32}
const Optional{T} = Union{T,Nothing}

include("utils.jl")
include("widgets.jl")
include("guirenderer.jl")
include("app.jl")
include("noise.jl")
include("render.jl")
include("vertex.jl")

export Application, ApplicationState


end
