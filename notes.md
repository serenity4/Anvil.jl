# Refactoring notes

Managing application resources may require a custom logic. Something like "compute on CPU + upload to GPU". But best is not to worry too much about architecture here; this functionality is likely to not be so used in the future due to performance issues.
It should make use of Vulkan abstractions where it makes sense.
