using OpenType
using GeometryExperiments

function intensity(curve_points, pixel_per_em)
    @assert length(curve_points) == 3
    res = 0.
    for coord in 1:2
        (x̄₁, x̄₂, x̄₃) = getindex.(curve_points, 3 - coord)
        if maximum(getindex.(curve_points, coord)) * pixel_per_em ≤ -0.5
            continue
        end
        rshift = sum(((i, x̄),) -> x̄ > 0 ? (1 << i) : 0, enumerate((x̄₁, x̄₂, x̄₃)))
        code = (0x2e74 >> rshift) & 0x0003
        if code ≠ 0
            a = x̄₁ - 2x̄₂ + x̄₃
            b = x̄₁ - x̄₂
            c = x̄₁
            if isapprox(a, 0, atol=1e-7)
                t₁ = t₂ = c / 2b
            else
                Δ = b ^ 2 - a * c
                if Δ < 0
                    # in classes C and F, only x̄₂ is of the opposite sign
                    # and there may be no real roots.
                    continue
                end
                δ = sqrt(Δ)
                t₁ = (b - δ) / a
                t₂ = (b + δ) / a
            end
            bezier = BezierCurve()
            if code & 0x0001 == 0x0001
                val = clamp(pixel_per_em * bezier(t₁, curve_points)[coord] + 0.5, 0, 1)
            end
            if code > 0x0001
                val = -clamp(pixel_per_em * bezier(t₂, curve_points)[coord] + 0.5, 0, 1)
            end
            res += val * (coord == 1 ? 1 : -1)
        end
    end
    res
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

    contour_indices = [0; data.contour_indices]
    ranges = map(zip(contour_indices[begin:end-1], contour_indices[begin+1:end])) do (i, j)
        (i+1):j
    end

    contour_points = Vector{Point{2,Float64}}[]
    for data_points in map(Base.Fix1(getindex, data.points), ranges)
        points = Point{2,Float64}[]

        # make sure data points define a closed contour
        while !(first(data_points).on_curve)
            push!(data_points, popfirst!(data_points))
        end
        if last(data_points) ≠ first(data_points)
            # terminate with a linear segment
            push!(data_points, first(data_points))
        end

        # gather contour points including implicit ones
        on_curve = false
        for point in data_points
            coords = Point(point.coords)
            if !on_curve && !point.on_curve || on_curve && point.on_curve
                # there is an implicit on-curve point halfway
                push!(points, (coords + points[end]) / 2)
            end
            push!(points, coords)
            on_curve = point.on_curve
        end

        @assert isodd(length(points)) "Expected an odd number of curve points."
        @assert first(points) == last(points) points
        push!(contour_points, points)
        on_curve = true
    end

    # rescale to [0., 1.]
    min = Point(glyph.header.xmin, glyph.header.ymin)
    max = Point(glyph.header.xmax, glyph.header.ymax)
    sc = inv(Scaling(max - min))
    transf = sc ∘ Translation(-min)
    contour_points = map(contour_points) do points
        @assert all(min[1] ≤ minimum(getindex.(points, 1)))
        @assert all(min[2] ≤ minimum(getindex.(points, 2)))
        @assert all(max[1] ≥ maximum(getindex.(points, 1)))
        @assert all(max[2] ≥ maximum(getindex.(points, 2)))
        res = transf.(points)
        @assert all(p -> all(0 .≤ p .≤ 1), res)
        res
    end

    contour_points
end

function curves(glyph::OpenType.Glyph)
    contour_points = uncompress(glyph)
    patch = Patch(BezierCurve(), 3)

    [map(Base.Fix2(split, patch), contour_points)...;]
end

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

function render_glyph(font, glyph, font_size)
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

    is = map(grid) do p
        try
            intensity(p, glyph, font.head.units_per_em; font_size)
        catch e
            if e isa DomainError
                NaN
            else
                rethrow(e)
            end
        end
    end
    @assert !all(iszero, is)

    p = heatmap(is)
    xticks!(p, 1:n ÷ 10:n, string.(xs[1:n ÷ 10:n]))
    yticks!(p, 1:n ÷ 10:n, string.(ys[1:n ÷ 10:n]))
end

using Plots

const BezierCurve = GeometryExperiments.BezierCurve

font = OpenTypeFont(joinpath(dirname(@__DIR__), "shaders", "JuliaMono-Regular.ttf"))

glyph = font.glyphs[64]
plot_outline(glyph)
render_glyph(font, glyph, 12)

glyph = font.glyphs[75]
plot_outline(glyph)
render_glyph(font, glyph, 12)

glyph = font.glyphs[350]
plot_outline(glyph)
render_glyph(font, glyph, 12)

glyph = font.glyphs[13]
plot_outline(glyph)
render_glyph(font, glyph, 12)
