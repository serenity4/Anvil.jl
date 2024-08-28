using Givre: bind!, unbind!, KeyBindings, KeyBindingsToken, Callable, execute_binding
using WindowAbstractions: @key_str, KeyEvent, KeyCombination
using XCB: Keymap, Connection, PhysicalKey
using Test

km = Keymap(Connection())

key_event(key::Symbol) = KeyEvent(km, PhysicalKey(km, key))

@testset "Key bindings" begin
  kb = KeyBindings()
  @test isempty(kb)
  value = Ref{Any}()
  set(x) = () -> (value[] = x)

  token = bind!(kb, key"f" => set(1))
  @test token == 1
  @test length(kb.active) == 1
  @test length(kb.inactive) == 0
  @test length(kb.bindings) == 1
  execute_binding(kb, key_event(:AC04))
  @test value[] == 1

  unbind!(kb, token)
  value[] = 0
  execute_binding(kb, key_event(:AC04))
  @test value[] == 0
  @test isempty(kb)

  bind!(kb, key"f" => key -> (value[] = key)) do
    execute_binding(kb, key_event(:AC04))
    @test isa(value[], KeyCombination)
  end
  @test isempty(kb)

  token = bind!(kb, key"f" => set(2), [key"g", key")"] => set(3))
  token2 = bind!(kb, key"g" => set(4))
  execute_binding(kb, key_event(:AC04))
  @test value[] == 2
  execute_binding(kb, key_event(:AC05))
  @test value[] == 4
  execute_binding(kb, key_event(:AE11))
  @test value[] == 3

  unbind!(kb, token)
  value[] = 0
  execute_binding(kb, key_event(:AC04))
  @test value[] == 0
  execute_binding(kb, key_event(:AC05))
  @test value[] == 3

  unbind!(kb, token2)
  @test isempty(kb)
end;
