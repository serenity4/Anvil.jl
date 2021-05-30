"""
Application-owned resource hosted in-memory on the GPU.
"""
mutable struct GPUResource{R<:Handle,I}
    resource::R
    memory::DeviceMemory
    info::I
end

Base.@kwdef struct GPUState
    images::Dict{Symbol,GPUResource{Image}} = Dict()
    buffers::Dict{Symbol,GPUResource{Buffer}} = Dict()
    semaphores::Dict{Symbol,Semaphore} = Dict()
    fences::Dict{Symbol,Fence} = Dict()
end
