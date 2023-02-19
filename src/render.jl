# Called by the application thread.
function frame_nodes(givre::GivreApplication, target::Resource)
  nodes = RenderNode[]
  (; rdr) = givre

  # Add all things we want to render.
  # `target` will be displayed as a result, which should have dimensions equal to the window extent.
  rect = Rectangle(Point2f(-1.0, -1.0), Point2f(1.0, 1.0), RGBA(1.0, 0.3, 0.3, 1.0))
  push!(nodes, draw(rdr, rect, target))

  nodes
end

function compile_programs(device)
  Dict(
    :rectangle => program(device, Rectangle),
  )
end
