font_file(name) = joinpath(ASSET_DIRECTORY, "fonts", name * ".ttf")
get_font(name::AbstractString) = get!(() -> OpenTypeFont(font_file(name)), app.fonts, name)

texture_file(name) = joinpath(ASSET_DIRECTORY, "textures", name)
get_texture(name) = get!(() -> load_texture(texture_file(name)), app.textures, name)

load_texture(filename) = load_texture(read_image(filename))
function load_texture(data::AbstractMatrix)
  data = convert(Matrix{RGBA{N0f8}}, data)
  resource = Lava.image_resource(app.systems.rendering.renderer.device, data; format = Vk.FORMAT_R8G8B8A8_SRGB)
  Lava.Texture(resource)
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
