using OpenType
using GeometryExperiments

function intensity(curve_points, pixel_per_em)
    @assert length(curve_points) == 3
    (y₁, y₂, y₃) = getindex.(curve_points, 2)
    rshift = sum(((i, y),) -> y ≥ 0 ? (1 << i) : 0, enumerate((y₁, y₂, y₃)))
    code = (0x2e74 >> rshift) & 0x0003
    res = 0.
    if code ≠ 0
        a = y₁ - 2y₂ + y₃
        b = y₁ - y₂
        c = y₁
        if a ≈ 0
            t₁ = t₂ = c / 2b
        else
            δ = sqrt(b ^ 2 - a * c)
            t₁ = (b - δ) / a
            t₂ = (b + δ) / a
        end
        bezier = BezierCurve()
        if code & 0x0001 == 0x0001
            res += clamp(pixel_per_em * bezier(t₁, curve_points)[1] + 0.5, 0, 1)
        end
        if code > 0x0001
            res -= clamp(pixel_per_em * bezier(t₂, curve_points)[1] + 0.5, 0, 1)
        end
    end
    res
end

function intensity2(point, glyph::OpenType.Glyph)
    ranges, points = uncompress(glyph)
    # get nearest two points
    points_on_curve = [(points[r][1:2:end] for r in ranges)...;]
    (a, b) = sort_nearest(PointSet(points_on_curve), point)[1:2]
    (idx_a, idx_b) = (findfirst(==(a), points_on_curve), findfirst(==(b), points_on_curve))
    @assert idx_b ≠ idx_a

    # get patch
    patch_idx_a = findfirst(Base.Fix1(in, idx_a), ranges)
    patch_idx_b = findfirst(Base.Fix1(in, idx_b), ranges)
    if patch_idx_a ≠ patch_idx_b
        
    end
    range = ranges[patch_idx_a]

    # get curve on patch
    idx_a_rel = idx_a - (range.start - 1)
    idx_b_rel = idx_b - (range.start - 1)
    patch_points = CircularVector(points[range])
    if isodd(idx_a_rel) # a is on-curve
        if isodd(idx_b_rel) # b is on-curve
            if abs(idx_a_rel - idx_b_rel) == 2
                curve = getindex.(Ref(patch_points), min(idx_a_rel, idx_b_rel):max(idx_a_rel, idx_b_rel))
            end
        end
    end
end

function intensity(point, glyph::OpenType.Glyph, units_per_em; font_size=12)
    res = sum(curves(glyph)) do p
        poffset = map(Translation(-point), p)
        intensity(poffset, font_size)
    end
    sqrt(abs(res))
end

function uncompress(glyph::OpenType.Glyph)
    data = glyph.data
    ranges = UnitRange{Int}[]
    points = Point{2,Float64}[]

    start = 1
    prev_end = 1
    for contour in data.contour_indices
        data_points = copy(data.points)
        while !(first(data_points).on_curve) || !(last(data_points).on_curve)
            push!(data_points, popfirst!(data_points))
        end
        if last(data_points) ≠ first(data_points)
            # terminate with a linear segment
            push!(data_points, last(data_points), first(data_points))
            contour += 2
        end
        on_curve = false
        for point in data_points[start:contour]
            coords = Point(point.coords)
            if !on_curve && !point.on_curve || on_curve && point.on_curve
                # there is an implicit on-curve point halfway
                push!(points, (coords + points[end]) / 2)
            end
            push!(points, coords)
            on_curve = point.on_curve
        end

        start = contour + 1
        range = prev_end:length(points)
        prev_end = length(points) + 1
        npoints = 1 + range.stop - range.start
        @assert isodd(npoints) "Expected an odd number of curve points."
        push!(ranges, range)
        on_curve = true
    end

    # rescale to [0., 1.]
    min = Point(glyph.header.xmin, glyph.header.ymin)
    max = Point(glyph.header.xmax, glyph.header.ymax)
    sc = inv(Scaling(max - min))
    transf = sc ∘ Translation(-min)
    ranges, transf.(points)
end

function curves(glyph::OpenType.Glyph)
    ranges, points = uncompress(glyph)
    patch = Patch(BezierCurve(), 3)
    points_per_patch = map(ranges) do range
        points[range]
    end

    [map(Base.Fix2(split, patch), points_per_patch)...;]
end

font = OpenTypeFont(joinpath(dirname(@__DIR__), "shaders", "JuliaMono-Regular.ttf"))

glyph = font.glyphs[64] # should be a C

intensity(Point(0.3, 0.4), glyph, font.head.units_per_em)

function plot_outline(glyph)
    cs = curves(glyph)
    p = plot()
    for (i, curve) in enumerate(cs)
        for (i, point) in enumerate(curve)
            color = i == 1 ? :blue : i == 2 ? :cyan : :green
            scatter!(p, [point[1]], [point[2]], legend=false, color=color)
        end
        points = BezierCurve().(0:0.1:1, Ref(curve))
        curve_color = UInt8[255 - Int(floor(i / length(cs) * 255)), 40, 40]
        plot!(p, first.(points), last.(points), color=string('#', bytes2hex(curve_color)))
    end
    p
end

function render_glyph(font, glyph)
    step = 0.01
    n = Int(inv(step))
    xs = 0:step:1
    ys = 0:step:1

    grid = map(xs) do x
        map(ys) do y
            Point(x, y)
        end
    end

    grid = hcat(grid...)

    is = intensity.(grid, Ref(glyph), font.head.units_per_em)
    @assert !all(iszero, is)

    p = heatmap(is)
    xticks!(p, 1:n ÷ 10:n, string.(xs[1:n ÷ 10:n]))
    yticks!(p, 1:n ÷ 10:n, string.(ys[1:n ÷ 10:n]))
end

using Plots

plot_outline(glyph)
render_glyph(font, glyph)
