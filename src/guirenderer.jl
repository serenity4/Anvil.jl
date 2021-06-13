"""
Describes how the pipeline needs to be bound.
"""
struct BindState
    vbuffer::VertexBuffer
    ibuffer::Union{Nothing,IndexBuffer}
    descriptors::DescriptorSetVector
    pipeline::GPUResource{Pipeline,Nothing,GraphicsPipelineCreateInfo}
end

"""
Describes data that an object needs to be drawn, but without having a pipeline created yet.
"""
struct PreRenderInfo
    vbuffer::VertexBuffer
    ibuffer::Union{Nothing,IndexBuffer}
    descriptors::DescriptorSetVector
end

"""
Describes how to generate rendering commands.
"""
struct RenderInfo
    bind_state::BindState
    draw_args::NTuple{4,Int}
end

struct ShaderInfo
    vertex::Shader
    fragment::Shader
end

"""
Make the link between a description of widgets and rendering.
"""
struct GUIRenderer <: AbstractRenderer
    rdr::BasicRenderer
    prerender_infos::Dict{Symbol,PreRenderInfo}
    pipelines::Dict{Symbol,GPUResource{Pipeline}}
    resources::Dict{Symbol,Tuple}
    shaders::Dict{Symbol,ShaderInfo}
    update_resources::Dict{Symbol,Tuple{Function,Function}}
end

GUIRenderer(rdr::BasicRenderer) = GUIRenderer(rdr, Dict(), Dict(), Dict(), Dict(), Dict())

function Base.delete!(gr::GUIRenderer, wname::Symbol)
    delete!(gr.pipelines, wname)
    delete!(gr.prerender_infos, wname)
end

function BindState(gr::GUIRenderer, wname::Symbol)
    @unpack vbuffer, ibuffer, descriptors = gr.prerender_infos[wname]
    BindState(vbuffer, ibuffer, descriptors, gr.pipelines[wname])
end

RenderInfo(gr::GUIRenderer, wname::Symbol, w::Widget) = RenderInfo(BindState(gr, wname), (nvertices(w), 1, 0, 0))

function Vulkan.DescriptorPoolCreateInfo(shaders::ShaderInfo)
    descriptors = Dict{DescriptorType,Int}()
    for shader in (shaders.vertex, shaders.fragment)
        for binding in shader.bindings
            dtype = binding.descriptor_type
            if haskey(descriptors, dtype)
                descriptors[dtype] += 1
            else
                descriptors[dtype] = 1
            end
        end
    end
    DescriptorPoolCreateInfo(sum(values(descriptors)), [DescriptorPoolSize(dtype, n) for (dtype, n) in descriptors])
end

function find_descriptor_pool!(rdr::BasicRenderer, wname::Symbol, shaders::ShaderInfo)
    if haskey(rdr.gpu.descriptor_pools, wname)
        rdr.gpu.descriptor_pools[wname]
    else
        info = DescriptorPoolCreateInfo(shaders)
        pool = unwrap(create_descriptor_pool(rdr.device, info))
        resource = GPUResource(pool, nothing, info)
        rdr.gpu.descriptor_pools[wname] = resource
        resource
    end
end

function add_widget!(gr::GUIRenderer, wname::Symbol, w::Widget, shaders::ShaderInfo, update_resources, resources::Tuple)
    pool = find_descriptor_pool!(gr.rdr, wname, shaders)
    gr.prerender_infos[wname] = PreRenderInfo(gr.rdr.gpu.buffers[vertex_buffer_symbol(wname)], nothing, DescriptorSetVector(gr.rdr.device, pool, shaders))
    check_resources(w, resources)
    gr.resources[wname] = resources
    gr.shaders[wname] = shaders
    gr.update_resources[wname] = update_resources
    update_descriptor_sets(gr, wname)
end

add_widget!(gr::GUIRenderer, wname::Symbol, w::Widget, shaders::ShaderInfo, update_resources, resources...) =
    add_widget!(gr, wname, w, shaders, update_resources, tuple(resources...))

function check_resources(w, resources)
    @assert Set(map(typeof, resources)) == Set(resource_types(w)) "Shader resources do not match the widget type $(typeof(w))"
end

function Vulkan.WriteDescriptorSet(gr::GUIRenderer, wname::Symbol, resource::SampledImage)
    WriteDescriptorSet(
        gr.prerender_infos[wname].descriptors.resource[1],
        1,
        0,
        DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        [DescriptorImageInfo(resource.sampler, resource.view.resource, IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)],
        [],
        [],
    )
end

function Vulkan.update_descriptor_sets(gr::GUIRenderer, wname::Symbol)
    update_descriptor_sets(
        gr.rdr.device,
        collect(map(gr.resources[wname]) do resource
            WriteDescriptorSet(gr, wname, resource)
        end),
        [],
    )
end

function recreate_pipelines!(gr::GUIRenderer, gm::GUIManager, rstate::RenderState)
    device = gr.rdr.device
    infos = map(collect(gm.widgets)) do (wname, w)
        GraphicsPipelineCreateInfo(gr.rdr, gr.shaders[wname], vertex_data_type(w), rstate.render_pass, extent(main_window(gm.wm)), gr.prerender_infos[wname].descriptors)
    end
    pipelines, _ = unwrap(create_graphics_pipelines(device, infos))
    map(enumerate(keys(gm.widgets))) do (i, wname)
        gr.pipelines[wname] = GPUResource(pipelines[i], nothing, infos[i])
    end
end

function needs_resource_update(gr::GUIRenderer)
    any(gr.update_resources) do pair
        (wname, (needs_update, _)) = pair
        needs_update(gr.resources[wname]...)
    end
end

function update_resources(gr::GUIRenderer)
    for (wname, (needs_update, update)) in gr.update_resources
        resources = gr.resources[wname]
        if needs_update(resources...)
            gr.resources[wname] = update(resources...)
        end
        update_descriptor_sets(gr, wname)
    end
end
