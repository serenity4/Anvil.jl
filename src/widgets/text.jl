using OpenType

const FONT_LOAD_DIR = joinpath(dirname(dirname((@__DIR__))), "assets", "fonts")

@memoize LRU(maxsize=50) function load_font(font_name::AbstractString)
    for file in readdir(FONT_LOAD_DIR)
        if first(splitext(basename(file))) == font_name
            return OpenTypeFont(joinpath(FONT_LOAD_DIR, file))
        end
    end
    error("Could not find a font file for $font_name.")
end

abstract type TextWidget <: Widget end


struct GlyphCurveIndexing
    curves::Vector{Point{3, Point{2, Float32}}}
    curve_ranges::Vector{UnitRange{Int}}
end

function GlyphCurveIndexing(font::OpenTypeFont)
    ranges = UnitRange{Int}[]
    stop = 0
    cs = map(filter(!isnothing, font.glyphs)) do glyph
        glyph_curves = curves(glyph)
        start = stop + 1
        stop = start + 3 * length(glyph_curves)
        push!(ranges, start:stop)
        glyph_curves
    end
    GlyphCurveIndexing([cs...;], ranges)
end

struct TextRenderInfo
    color::RGBA
    size::Float64
end

struct TextProperties
    font::OpenTypeFont
    render_info::TextRenderInfo
    indexing::GlyphCurveIndexing
end

TextProperties(font::OpenTypeFont; render_info = TextRenderInfo(RGBA(1., 1., 1., 1.), 14.)) = TextProperties(font, render_info, GlyphCurveIndexing(font))

Base.@kwdef struct StaticText <: TextWidget
    text::String
    origin::Point2f
    properties::TextProperties = TextProperties(load_font("juliamono-regular"))
end

"""
Vertex data for a character to be rendered.
"""
struct CharData
    "Vertex position."
    position::Point2f
    "Character-dependent offset index within the vector of all concatenated glyph curves."
    offset::UInt32
    "Character-dependent number of curves."
    count::UInt32
end

vertex_data_type(::Type{StaticText}) = CharData
mesh_encoding_type(T::Type{StaticText}) = MeshVertexEncoding{TriangleList, vertex_data_type(T)}

function GeometryExperiments.PointSet(w::StaticText, char::Char)
    glyph = w.properties.font[char]
    if isnothing(glyph)
        PointSet(Point{2,Float64}[])
    else
        Translation(w.origin)(boundingelement(glyph))
    end
end

function GeometryExperiments.boundingelement(w::StaticText)
    points = [map(char -> PointSet(w, char).points, collect(w.text))...;]
    boundingelement(PointSet(points))
end

function GeometryExperiments.MeshVertexEncoding(w::StaticText)
    T = vertex_data_type(w)
    MT = mesh_encoding_type(w)
    mesh = MT(TriangleList{3,UInt32}([]), T[])

    foreach(enumerate(w.text)) do (i, char)
        glyph = w.properties.font[char]
        idx = findfirst(==(glyph), w.properties.font.glyphs)
        range = w.properties.indexing.curve_ranges[idx]
        offset = range.start - 1
        count = length(range)
        set = PointSet(w, char)
        append!(mesh.encoding.indices, collect(TriangleList(TriangleStrip(1 + 4 * (i - 1):4i))))
        append!(mesh.vertex_data, T.(set.points, offset, count))
    end
    mesh
end

resource_types(::Type{StaticText}) = (GPUResource{Buffer,DeviceMemory,Nothing},)
