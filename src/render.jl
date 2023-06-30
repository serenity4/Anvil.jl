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
  for (object, location) in components(givre.ecs, (RENDER_COMPONENT_ID, LOCATION_COMPONENT_ID), Tuple{RenderObject,Point2})
    command = @match object.type begin
      &RENDER_OBJECT_RECTANGLE => begin
        primitive = object.data::Primitive
        z = 1.0 # TODO: Use the ECS for that, as we likely want the z-index to be consistent with that of the `InputArea`.
        Command(program_cache, Gradient(target), @set primitive.transform.translation = (location..., z))
      end
    end
    push!(commands, command)
  end
  commands
end
