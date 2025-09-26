function RenderingSystem(renderer::Renderer)
  passes = dictionary([
    :depth_mask_opaque => PassInfo(:depth_mask_opaque, NodeID(3)),
    :render_opaque => PassInfo(:render_opaque, NodeID(0)),
    :depth_mask_transparent => PassInfo(:depth_mask_transparent, NodeID(4)),
    :render_transparent_1 => PassInfo(:render_transparent_1, NodeID(1)),
    :render_transparent_2 => PassInfo(:render_transparent_2, NodeID(2)),
  ])
  RenderingSystem(renderer, FrameData[], passes, ReentrantLock())
end

# --- Renderer Interface ---

function initialize_frames_and_commands!()
  rendering = app.systems.rendering
  initialize_frames!(rendering)
  run_systems()
  for frame in rendering.frames
    generate_commands_for_frame!(frame, rendering, components(rendering))
  end
end

function synchronize_commands_for_cycle!(cycle::FrameCycleInfo)
  run_systems()
  synchronize_commands_for_cycle!(cycle, app.systems.rendering)
end

# --------------------------

Entities.components(::RenderingSystem) = components(app.ecs, (ENTITY_COMPONENT_ID, LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, RENDER_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID), Tuple{EntityID,P2,GeometryComponent,RenderComponent,ZCoordinateComponent})

function Entities.components(::RenderingSystem, entities)
  map(entities) do entity
    location = get_location(entity)
    geometry = get_geometry(entity)
    object = get_render(entity)
    z = get_z(entity)
    (entity, location, geometry, object, z)
  end
end

function initialize_frames!(rendering::RenderingSystem)
  (; renderer, frames) = rendering
  empty!(frames)
  for cycle in renderer.cycles
    color = cycle.target
    extent = dimensions(color.attachment)
    depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, extent; name = :depth, samples = RENDER_SAMPLE_COUNT)
    frame = FrameData(cycle.index, color, depth)
    push!(frames, frame)
    for pass in rendering.passes
      insert!(frame.command_changes, pass.name, DiffVector{Command}())
    end
    area = RenderArea(extent)
    nodes = initialize_passes!(rendering, frame, area)
    add_nodes!(cycle.render_graph, nodes)
  end
end

function initialize_passes!(rendering::RenderingSystem, frame::FrameData, area::RenderArea)
  # Create new `RenderNode`s and initialize `ShaderParameters`.
  nodes = RenderNode[]

  camera = camera_metric_to_viewport(area, rendering.renderer.frame_cycle.swapchain.surface.target)
  # Color and depth attachments will be set per frame before recording commands.
  parameters = ShaderParameters(; camera)

  push!(nodes, initialize_pass!(rendering.passes[:depth_mask_opaque], area, parameters))
  push!(nodes, initialize_pass!(rendering.passes[:render_opaque], area, parameters))
  push!(nodes, initialize_pass!(rendering.passes[:depth_mask_transparent], area, parameters))
  @reset parameters.render_state.enable_depth_write = false
  push!(nodes, initialize_pass!(rendering.passes[:render_transparent_1], area, parameters))
  push!(nodes, initialize_pass!(rendering.passes[:render_transparent_2], area, parameters))

  color_clear = ClearValue((BACKGROUND_COLOR.r, BACKGROUND_COLOR.g, BACKGROUND_COLOR.b, 1f0))
  depth_clear = ClearValue(1f0)
  start = nodes[1]
  insert!(start.clears, frame.color, color_clear)
  insert!(start.clears, frame.depth, depth_clear)

  nodes
end

function initialize_pass!(info::PassInfo, area::RenderArea, parameters::ShaderParameters)
  info.parameters = parameters
  RenderNode(info, area)
end

function Lava.RenderNode(info::PassInfo, area::RenderArea)
  RenderNode(; id = info.node, render_area = area, info.name)
end

function generate_commands_for_frame!(frame::FrameData, rendering::RenderingSystem, components)
  program_cache = rendering.renderer.program_cache # this cache is thread-safe
  for (entity, location, geometry, object, z) in components
    location = Point3f(location..., -1/z)
    list = get!(() -> EntityCommandList(entity), frame.entity_command_lists, entity)
    !STAGED_RENDERING[] && foreach(empty!, list.changes)

    parameters = pass_parameters(rendering.passes[ifelse(object.is_opaque, :depth_mask_opaque, :depth_mask_transparent)], frame)
    add_depth_mask_commands!(list, program_cache, object, location, geometry, parameters)

    parameters = pass_parameters(rendering.passes[ifelse(object.is_opaque, :render_opaque, :render_transparent_1)], frame)
    add_rendering_commands!(list, program_cache, object, location, geometry, parameters)

    for (pass, commands) in pairs(list.changes)
      append!(frame.command_changes[pass].additions, commands)
    end
  end
end

function pass_parameters(pass::PassInfo, frame::FrameData)
  setproperties(pass.parameters, (; color = [frame.color], frame.depth))
end

function stage_command_changes_for_frame!(frame::FrameData, rendering::RenderingSystem)
  isempty(frame.entity_changes) && STAGED_RENDERING[] && return nothing
  (; additions, deletions) = frame.entity_changes
  deletions = sort!(collect(deletions))
  additions = sort!(collect(additions))

  delete_entity_commands!(frame, deletions)
  delete_entity_commands!(frame, additions)
  empty!(frame.entity_changes)

  if STAGED_RENDERING[]
    itr = components(rendering, additions)
    generate_commands_for_frame!(frame, rendering, itr)
  else
    generate_commands_for_frame!(frame, rendering, components(rendering))
  end
end

function delete_entity_commands!(frame::FrameData, entities)
  for entity in entities
    list = get(frame.entity_command_lists, entity, nothing)
    list === nothing && continue
    for (pass, commands) in pairs(list.changes)
      append!(frame.command_changes[pass].deletions, commands)
    end
    delete!(frame.entity_command_lists, entity)
  end
end

function synchronize_commands_for_cycle!(cycle::FrameCycleInfo, rendering::RenderingSystem)
  frame = rendering.frames[cycle.index]
  stage_command_changes_for_frame!(frame, rendering)
  for pass in rendering.passes
    node = cycle.render_graph.nodes[pass.node]
    changes = frame.command_changes[pass.name]
    if STAGED_RENDERING[]
      update_commands!(node, changes.additions, changes.deletions)
    else
      empty!(node.commands)
      append!(node.commands, changes.additions)
    end
    empty!(changes)
  end
end

function add_rendering_commands!(list::EntityCommandList, program_cache::ProgramCache, component::RenderComponent, location, geometry::GeometryComponent, parameters::ShaderParameters)
  default_pass = component.is_opaque ? :render_opaque : :render_transparent_1
  @reset parameters.render_state.depth_compare_op = ifelse(geometry.type ≠ GEOMETRY_TYPE_RECTANGLE, Vk.COMPARE_OP_EQUAL, Vk.COMPARE_OP_LESS_OR_EQUAL)
  @switch component.type begin
    @case &RENDER_OBJECT_RECTANGLE
    rect = ShaderLibrary.Rectangle(geometry.aabb, component.vertex_data, nothing)
    gradient = component.primitive_data::Gradient
    primitive = Primitive(rect, location)
    command = Command(program_cache, gradient, parameters, primitive)
    add_command!(list, default_pass, command)

    @case &RENDER_OBJECT_IMAGE
    render = component.primitive_data::ImageVisual
    uvs = image_uvs(geometry.aabb, render)
    rect = ShaderLibrary.Rectangle(geometry.aabb, uvs, nothing)
    primitive = Primitive(rect, location)
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    command = Command(program_cache, render.sprite, parameters_ssaa, primitive)
    add_command!(list, default_pass, command)

    @case &RENDER_OBJECT_TEXT
    @assert !component.is_opaque
    text = component.primitive_data::ShaderLibrary.Text
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true
    @match renderables(program_cache, text, parameters_ssaa, location) begin
      commands::Vector{Command} => add_commands!(list, :render_transparent_1, commands)
      transparency_commands::Vector{Vector{Command}} => begin
        @assert length(transparency_commands) == 2
        # XXX: We may want to draw all opaque text backgrounds in the corresponding pass,
        # not in the transparency pass.
        add_commands!(list, :render_transparent_1, transparency_commands[1])
        add_commands!(list, :render_transparent_2, transparency_commands[2])
      end
    end

    @case &RENDER_OBJECT_USER_DEFINED
    (; create_renderables!) = component.primitive_data::UserDefinedRender
    create_renderables!(list, program_cache, location, geometry, parameters)
  end
end

function add_depth_mask_commands!(list, program_cache::ProgramCache, component::RenderComponent, location, geometry::GeometryComponent, parameters::ShaderParameters)
  geometry.type !== GEOMETRY_TYPE_RECTANGLE || return
  @reset parameters.render_state.enable_fragment_supersampling = true
  center = Point2f(location.x, location.y)
  pass = ifelse(component.is_opaque, :depth_mask_opaque, :depth_mask_transparent)
  @switch geometry.type begin
    @case &GEOMETRY_TYPE_FILLED_CIRCLE
    (; circle) = geometry
    shader = FragmentLocationTest(p -> in(p - center, circle))
    rect = ShaderLibrary.Rectangle(geometry.aabb, nothing, nothing)
    primitive = Primitive(rect, location)
    command = Command(program_cache, shader, parameters, primitive)
    add_command!(list, pass, command)

    @case &GEOMETRY_TYPE_USER_DEFINED
    shader = FragmentLocationTest(let test = geometry.in; p -> test(p - center); end)
    rect = ShaderLibrary.Rectangle(geometry.aabb, nothing, nothing)
    primitive = Primitive(rect, location)
    command = Command(program_cache, shader, parameters, primitive)
    add_command!(list, pass, command)
  end
end

function stage_for_render!(rendering::RenderingSystem, entity::EntityID)
  for frame in rendering.frames
    changes = frame.entity_changes
    push!(changes.additions, entity)
  end
end

function unstage_for_render!(rendering::RenderingSystem, entity::EntityID)
  for frame in rendering.frames
    changes = frame.entity_changes
    push!(changes.deletions, entity)
    in(entity, changes.additions) && delete!(changes.additions, entity)
  end
end
