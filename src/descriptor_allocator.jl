struct DescriptorPoolState
    allocated::Dictionary{DescriptorType,Int}
    limits::Dictionary{DescriptorType,Int}
    max::Int
end

"""
Entity which manages descriptor pools and descriptor sets.
"""
struct DescriptorAllocator
    device::Device
    pools::Dictionary{Created{DescriptorPool,DescriptorPoolCreateInfo},DescriptorPoolState}
end

DescriptorAllocator(device::Device) = DescriptorAllocator(device, Dictionary())

"""
Free descriptor sets from a descriptor allocator.

!!! warning
    All descriptor sets must have been allocated with the same pool, through the same descriptor allocator.
    They may, however, have been allocated in several times.
"""
function free_descriptor_sets!(da::DescriptorAllocator, sets::Vector{Created{DescriptorSet,DescriptorSetAllocateInfo}})
    pool = unique!(getproperty.(info.(sets), :descriptor_pool))
    length(pool) == 1 || error("The descriptor sets were allocated via different descriptor pools.")
    allocations = compute_allocations(da, sets)
    da.pools[pool].allocated .-= allocations
    free_descriptor_sets(da.device, pool, sets)
end

function new_pool!(da::DescriptorAllocator, allocations::Dictionary{DescriptorType,Int}; next=C_NULL, flags=0)
    limits = [DescriptorPoolSize(t, max(allocations[t], 20)) for t in keys(allocations)]
    maxsize = max(sum(allocations), 50)
    create_info = DescriptorPoolCreateInfo(limits, maxsize; next, flags)
    new = Created(DescriptorPool(da.device, create_info), create_info)
    insert!(da, new, DescriptorPoolState(Dictionary(), limits, maxsize))
    new
end

function compute_allocations(da::DescriptorAllocator, layouts::AbstractVector{Created{DescriptorSetLayout, DescriptorSetLayoutCreateInfo}})
    allocations = Dictionary{DescriptorType,Int}()
    for layout in layouts
        for binding in layout.info.bindings
            allocations[binding.descriptor_type] = get(allocations, binding.descriptor_type, 0) + binding.descriptor_count
        end
    end
    allocations
end

function compute_allocations(da::DescriptorAllocator, sets::AbstractVector{Created{DescriptorSet,DescriptorSetAllocateInfo}})
    merge!(+, compute_allocations.(getproperty.(unique!(info.(sets)), :set_layouts))...)
end

function find_pool!(da::DescriptorAllocator, layouts)
    find_pool!(da, compute_allocations(da, layouts))
end

function find_pool!(da::DescriptorAllocator, allocations::Dictionary{DescriptorType,Int})
    for (pool, state) in zip(keys(da.pools), da.pools)
        n = 0
        has_room = sum(allocations) < sum(state.max) && all(keys(state.allocated)) do t
            state.allocated[t] + allocations[t] < state.limits[t]
        end
        if has_room
            return pool
        end
    end

    # no pool could be reused
    new_pool!(da, allocations)
end

function allocate_descriptor_sets!(da::DescriptorAllocator, layouts::Vector{Created{DescriptorSetLayout,DescriptorSetLayoutCreateInfo}}; next=C_NULL, flags=0)
    pool = find_pool!(da, layouts)
    info = DescriptorSetAllocateInfo(pool, layouts; next, flags)
    allocate_descriptor_sets!(da, pool, info)
end

function allocate_descriptor_sets!(da::DescriptorAllocator, pool::CommandPool, info::DescriptorSetAllocateInfo)
    pool in handle.(keys(da.pools)) || error("Pool $pool was not created with the provided allocator $da.")
    allocations = compute_allocations(da, info.set_layouts)
    merge!(pool.allocated, allocations)
    sets = unwrap(allocate_descriptor_sets(da.device, info))
    Created.(sets, info)
end
