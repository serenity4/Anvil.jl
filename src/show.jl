function Base.show(io::IO, renderer::Renderer)
  device = Vk.get_physical_device_properties(renderer.device.handle.physical_device)
  print(io, typeof(renderer), '(', device, ", ", length(renderer.cycles), " frames in flight maximum, ", length(renderer.program_cache.programs), " programs in cache, ", renderer.task, ')')
end

function Base.show(io::IO, rendering::RenderingSystem)
  print(io, typeof(rendering), '(', length(rendering.passes), " passes, ", rendering.renderer, ')')
end

function Base.show(io::IO, ::MIME"text/plain", frame::FrameData)
  print(io, "Frame at index ", frame.index, ':')
  print(io, "\n  ", styled"{yellow:entity changes}: ", frame.entity_changes)
  print(io, "\n  ", styled"{yellow:command changes}: ", frame.command_changes)
  print(io, "\n  ", styled"{yellow:passes}: ", frame.command_changes)
  for pass in keys(frame.command_changes)
    nentities = 0
    ncommands = sum(frame.entity_command_lists) do list
      commands = get(list.changes, pass, nothing)
      commands === nothing && return 0
      nentities += 1
      length(commands)
    end
    print(io, "\n    $pass: $nentities entities for $ncommands commands")
  end
end

function Base.show(io::IO, diff::AbstractDiff)
  print(io, nameof(typeof(diff)), '(')
  first = true
  !isempty(diff.additions) && (first = false; print(io, length(diff.additions), " additions"))
  !isempty(diff.deletions) && print(io, first ? "" : ", ", length(diff.deletions), " deletions")
  print(io, ')')
end
