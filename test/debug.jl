using Anvil
using Anvil: get_name, set_name, get_widget, initialize, Rectangle
using Test

@testset "Debug utilities" begin
  initialize()
  @set_name widget = Rectangle((3, 3), RGB(1, 1, 1))
  @test get_name(widget.id) === :widget
  set_name(widget, :rectangle)
  @test get_name(widget.id) === :rectangle
  @test get_widget(:rectangle) === widget
  @set_name "under" "some" "path" widget = widget
  @test get_name(widget.id) === Symbol("under/some/path/widget")
  @test_throws "No widget exists with the name" get_widget(:rectangle)
  namespace = "under/some/other_path"
  @set_name namespace widget = widget
  @test get_name(widget.id) === Symbol("under/some/other_path/widget")
end;
