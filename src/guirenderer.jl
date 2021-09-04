struct ResourceManagement
    "External resources used by one or more shaders for a given widget."
    resources::Vector{Any}
    "Whether resources needs an update."
    needs_update::Function
    "Function that updates resources."
    update_resources::Function
end

struct WidgetDependencies
    shaders::Vector{ShaderSpecification}
    resource_management::Optional{ResourceManagement}
end

WidgetDependencies(shaders) = WidgetDependencies(shaders, nothing)

"""
Make the link between a description of widgets and rendering.
"""
struct GUIRenderer
    device::Created{Device,DeviceCreateInfo}
    disp::QueueDispatch
    swapchain_info::SwapchainCreateInfoKHR
    descriptor_allocator::DescriptorAllocator
    command_pools::ThreadedCommandPool
    shader_cache::ShaderCache
    descriptor_set_layout_cache::DescriptorSetLayoutCache
    pipeline_layout_cache::PipelineLayoutCache
    render_set::RenderSet
end

device(gr::GUIRenderer) = handle(gr.device)

function GUIRenderer(device, disp::QueueDispatch)
    GUIRenderer(
        device,
        disp,
        DescriptorAllocator(device),
        ThreadedCommandPool(device, disp, dictionary([1 => QUEUE_COMPUTE_BIT | QUEUE_GRAPHICS_BIT])),
        ShaderCache(device),
        DescriptorSetLayoutCache(device),
        PipelineLayoutCache(device),
        RenderSet(device),
    )
end

function add_widget!(gr::GUIRenderer, w::Widget, widget_dependencies::WidgetDependencies)
    dset_layouts = get!(gr.descriptor_set_layout_cache, widget_dependencies.shaders)
    dsets = allocate_descriptor_sets!(gr.descriptor_allocator, dset_layouts)
    append!(shader_dependencies.descriptor_sets, dsets)
    insert!(gr.render_set, w, RenderInfo(shader_dependencies, (nvertices(w),1,0,0); push_data = push_data(w)))
    resources = widget_dependencies.resource_management.resources
    !isempty(resources) && update_descriptor_sets(device(gr), resources)
    nothing
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
