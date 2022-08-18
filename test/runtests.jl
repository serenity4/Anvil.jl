using Givre, Test
using GeometryExperiments
using Givre: program_invocation, render_to_array, Rectangle
using ColorTypes
using Lava: init
using FileIO
using ImageIO

instance, device = init();

@testset "Givre.jl" begin
  @testset "Rendering" begin
    rect = Rectangle(Point2f(-1.0, -1.0), Point2f(1.0, 1.0), RGBA(1.0, 0.3, 0.3, 1.0))
    invocation = program_invocation(device, rect)
    data = render_to_array(device, invocation)
    save(joinpath(pkgdir(Givre), "test", "renders", "rectangle.png"), data)
    @test all(≈(RGBA(1.0, 0.3, 0.3, 1.0)), data)
  end
end;
