# Refactoring notes

Now that GPUState was removed altogether, how do we manage application resources, notably the perlin texture resource and staging buffer?
Where do we get the command pool from? Should we define a CommandBufferAllocator?
Where should we store pipelines for widgets?
