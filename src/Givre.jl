module Givre

using Vulkan
using VulkanShaders
using XCB
using MLStyle
using UnPack
using AbstractGUI
using ColorTypes
using ProceduralNoise
using GeometryExperiments
using Setfield
using TimerOutputs
using Memoization: @memoize
using LRUCache: LRU
using Dictionaries

import AbstractGUI: callbacks

const to = TimerOutput()

const Point2f = Point{2,Float32}
const Optional{T} = Union{T,Nothing}

include("gpu/GPU.jl")
using .GPU

include("render/Render.jl")
using .Render

include("utils.jl")
include("widgets.jl")
include("guirenderer.jl")
include("app.jl")
include("noise.jl")
include("render.jl")

export Application, ApplicationState


end
