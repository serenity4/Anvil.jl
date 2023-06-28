@enum RenderObjectType begin
  RENDER_OBJECT_RECTANGLE = 1
end

struct RenderObject
  type::RenderObjectType
  data::Any
end

# Called by the application thread.
function frame_nodes(givre::GivreApplication, target::Resource)
  nodes = RenderNode[]
  commands = materialize_render_commands(givre, target)
  push!(nodes, RenderNode(commands))
  nodes
end

function materialize_render_commands(givre::GivreApplication, target::Resource)
  (; program_cache) = givre.rdr
  commands = Command[]
  for object in components(givre.ecs, RENDER_COMPONENT_ID, RenderObject)
    command = @match object.type begin
      &RENDER_OBJECT_RECTANGLE => Command(program_cache, Gradient(target), object.data::Primitive)
    end
    push!(commands, command)
  end
  commands
end

function initialize_render_commands!(givre::GivreApplication)
  geometry = Rectangle((0.5, 0.5), (-0.4, -0.4), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
  rect = RenderObject(RENDER_OBJECT_RECTANGLE, Primitive(geometry))
  insert!(givre.ecs, Entities.new!(givre.entity_pool), RENDER_COMPONENT_ID, rect)
end
