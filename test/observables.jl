using Anvil: @observable, @bind, observe!, OBSERVABLE_DELETE_CALLBACK
using Test

@observable mutable struct TestObservable
  x::Int
end

@testset "Observables" begin
  x = TestObservable(1)
  observe!(x, :x) do old, new
    @test old == 1
    @test new == 2
    OBSERVABLE_DELETE_CALLBACK
  end
  @test !isempty(x.field_callbacks)
  x.x = 2
  @test isempty(x.field_callbacks)

  y = TestObservable(2)
  @bind y.x => x.x
  x.x = 3
  @test y.x == 3
end;
