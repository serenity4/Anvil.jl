"""
Describes data that an object needs to be drawn, but without having a pipeline created yet.
"""
struct ShaderDependencies
    vertex_buffer::VertexBuffer
    index_buffer::Optional{IndexBuffer}
    descriptor_sets::Vector{Created{DescriptorSet,DescriptorSetAllocateInfo}}
end

"""
Binding state that must be set in order for
drawing commands to render correctly.
"""
struct BindRequirements
    dependencies::ShaderDependencies
    push_data::Any
    pipeline::Created{Pipeline,GraphicsPipelineCreateInfo}
end

"""
Describes the current binding state.
"""
struct BindState
    vertex_buffer::Optional{VertexBuffer}
    index_buffer::Optional{IndexBuffer}
    descriptor_sets::Vector{Created{DescriptorSet,DescriptorSetAllocateInfo}}
    push_data::Any
    pipeline::Optional{Created{Pipeline,GraphicsPipelineCreateInfo}}
end

function Base.bind(cbuffer::CommandBuffer, reqs::BindRequirements, state::BindState)
    @unpack vertex_buffer, index_buffer, descriptor_sets = reqs.dependencies
    @unpack push_data, pipeline = reqs

    pipeline ≠ state.pipeline && cmd_bind_pipeline(cbuffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline)
    vertex_buffer ≠ state.vertex_buffer && cmd_bind_vertex_buffers(cbuffer, [vertex_buffer], [0])

    if !isnothing(index_buffer) && index_buffer ≠ state.index_buffer
        cmd_bind_index_buffer(cbuffer, index_buffer, 0, INDEX_TYPE_UINT32)
    end

    if !isempty(descriptor_sets) && descriptor_sets ≠ state.descriptor_sets
        cmd_bind_descriptor_sets(cbuffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline.info.layout, 0, handle.(descriptor_sets), [])
    end

    if !isnothing(push_data) && push_data ≠ state.push_data
        cmd_push_constants(cbuffer, pipeline.info.layout, SHADER_STAGE_VERTEX_BIT, 1, Ref(push_data), sizeof(push_data))
    end

    BindState(vertex_buffer, index_buffer, descriptor_sets, push_data, pipeline)
end

"""
Describes how to generate rendering commands.
"""
struct RenderInfo
    bind_requirements::BindRequirements
    draw_args::NTuple{4,Int}
end

struct ShaderInfo
    vertex::Shader
    fragment::Shader
    specialization_constants::Vector{SpecializationInfo}
    push_ranges::Vector{PushConstantRange}
end

ShaderInfo(vertex, fragment) = ShaderInfo(vertex, fragment, [], [])

struct ResourceManagement
    "External resources used by one or more shaders for a given widget."
    resources::Vector{Any}
    "Whether resources needs an update."
    needs_update::Function
    "Function that updates resources."
    update_resources::Function
end

struct WidgetDependencies
    shaders::ShaderInfo
    resource_management::Optional{ResourceManagement}
end

WidgetDependencies(shaders::ShaderInfo) = WidgetDependencies(shaders, nothing)

"""
Make the link between a description of widgets and rendering.
"""
struct GUIRenderer <: AbstractRenderer
    rdr::BasicRenderer
    descriptor_allocator::DescriptorAllocator
    widget_dependencies::Dictionary{Symbol,WidgetDependencies}
    shader_dependencies::Dictionary{Symbol,ShaderDependencies}
    push_data::Dictionary{Symbol,Any}
end

device(gr::GUIRenderer) = device(gr.rdr)

GUIRenderer(rdr::BasicRenderer) = GUIRenderer(rdr, DescriptorAllocator(device(rdr)), Dictionary(), Dictionary(), Dictionary())

function Base.delete!(gr::GUIRenderer, wname::Symbol)
    delete!(gr.widget_dependencies, wname)
    free_descriptor_sets!(gr.descriptor_allocator, gr.shader_dependencies[wname].descriptors)
    delete!(gr.shader_dependencies, wname)
end

function BindRequirements(gr::GUIRenderer, wname::Symbol)
    BindRequirements(gr.shader_dependencies[wname], get(gr.push_data, nothing))
end

RenderInfo(gr::GUIRenderer, wname::Symbol, w::Widget) = RenderInfo(BindRequirements(gr, wname), (nvertices(w), 1, 0, 0))

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

function add_widget!(gr::GUIRenderer, wname::Symbol, w::Widget, widget_dependencies::WidgetDependencies, shader_dependencies::ShaderDependencies)
    dset_layouts = create_descriptor_set_layouts(widget_dependencies.shaders)
    dsets = allocate_descriptor_sets!(gr.descriptor_allocator, dset_layouts)
    append!(shader_dependencies.descriptor_sets, dsets)
    gr.shader_dependencies[wname] = shader_dependencies
    gr.widget_dependencies[wname] = widget_dependencies
    resources = widget_dependencies.resource_management.resources
    !isempty(resources) && update_descriptor_sets(device(gr), resources)
    nothing
end

function Vulkan.WriteDescriptorSet(shader_dependencies::ShaderDependencies, resource::SampledImage)
    WriteDescriptorSet(
        first(shader_dependencies.descriptors.resource),
        1,
        0,
        DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        [DescriptorImageInfo(resource.sampler, resource.view.resource, IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)],
        [],
        [],
    )
end

function Vulkan.update_descriptor_sets(device::Device, shader_dependencies::ShaderDependencies, resources)
    update_descriptor_sets(
        device,
        map(Base.Fix1(WriteDescriptorSet, shader_dependencies), resources),
        [],
    )
end

function recreate_pipelines!(gr::GUIRenderer, gm::GUIManager, rstate::RenderState)
    infos = map(collect(gm.widgets)) do (wname, w)
        GraphicsPipelineCreateInfo(device(gr), gr.widget_dependencies[wname].shaders, mesh_encoding_type(w), rstate.render_pass, extent(main_window(gm.wm)), gr.shader_dependencies[wname])
    end
    pipelines, _ = unwrap(create_graphics_pipelines(device(gr), infos))
    map(enumerate(keys(gm.widgets))) do (i, wname)
        gr.pipelines[wname] = GPUResource(pipelines[i], nothing, infos[i])
    end
end

function needs_resource_update(gr::GUIRenderer)
    any(gr.widget_dependencies) do deps
        isnothing(deps.resource_management) && return false
        rm = deps.resource_management
        rm.needs_update(rm.resources...)
    end
end

function update_resources(gr::GUIRenderer)
    foreach(zip(gr.shader_dependencies, gr.widget_dependencies)) do (sdeps, wdeps)
        !isnothing(wdeps.resource_management) || return
        rm = wdeps.resource_management
        if rm.needs_update(resources...)
            rm.resources .= rm.update(resources...)
        end
        update_descriptor_sets(device(gr), sdeps)
    end
end
