using Givre, Test
using FileIO
using ImageIO

instance, device = init();

@testset "Givre.jl" begin
  @testset "Rendering" begin
    rect = Rectangle(Point2f(-1.0, -1.0), Point2f(1.0, 1.0), RGBA(1.0, 0.3, 0.3, 1.0))
    prog = Givre.program(device, rect)
    @test isa(prog, Program)
    data = render_to_array(device, rect)
    save(joinpath(pkgdir(Givre), "test", "renders", "rectangle.png"), data)
    @test all(≈(RGBA(1.0, 0.3, 0.3, 1.0)), data)
  end
end
