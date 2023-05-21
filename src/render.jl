# Called by the application thread.
function frame_nodes(givre::GivreApplication, target::Resource)
  nodes = RenderNode[]
  (; program_cache) = givre.rdr

  grad = Gradient(target)
  rect = Rectangle((0.5, 0.5), (-0.4, -0.4), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
  push!(nodes, RenderNode(Command(program_cache, grad, Primitive(rect))))

  nodes
end
