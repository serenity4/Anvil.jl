font_file(name) = joinpath(ASSET_DIRECTORY, "fonts", name * ".ttf")
get_font(name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), app.fonts, name)

texture_file(name) = joinpath(ASSET_DIRECTORY, "textures", name)
get_texture(name) = get!(() -> load_texture(texture_file(name)), app.textures, name)

load_texture(filename) = load_texture(read_image(filename))
function load_texture(data::AbstractMatrix; generate_mip_levels = true)
  (; device, program_cache) = app.systems.rendering.renderer
  data = convert(Matrix{RGBA{N0f8}}, data)
  dims = size(data)
  mip_levels = maximum_mip_level(dims)

  if generate_mip_levels
    resource = image_resource(device, nothing; dims, format = Vk.FORMAT_R8G8B8A8_SRGB, mip_levels, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT, flags = Vk.IMAGE_CREATE_EXTENDED_USAGE_BIT | Vk.IMAGE_CREATE_MUTABLE_FORMAT_BIT, name = :loaded_texture_image)
    copyto!(resource, data, device; mip_level = 1)
    generate_mipmaps(resource, device; cache = program_cache)
    image_view = image_view_resource(resource; usage = Vk.IMAGE_USAGE_SAMPLED_BIT, name = :loaded_texture_image_view)
  else
    image_view = image_view_resource(device, data; format = Vk.FORMAT_R8G8B8A8_SRGB, name = :loaded_texture_image_view)
  end

  # For best results, use -1.0 without fragment supersampling, or -2.0 with fragment supersampling.
  sampling = @set DEFAULT_SAMPLING.mip_lod_bias = -2.0
  Texture(image_view, sampling)
end

read_transposed(::Type{T}, file) where {T} = convert(Matrix{T}, permutedims(FileIO.load(file), (2, 1)))
read_transposed(file) = read_transposed(RGBA{N0f8}, file)
read_png(::Type{T}, file) where {T} = read_transposed(T, file)
read_png(file) = read_png(RGBA{N0f8}, file)
read_jpeg(file) = read_transposed(file)
function read_image(filename)
  ext = last(splitext(filename))
  ext == ".png" && return read_png(filename)
  (ext == ".jpeg" || ext == ".jpg") && return read_jpeg(filename)
  error("Unsupported file extension '$ext' for image $filename")
end
