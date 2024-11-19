using Anvil: bind!, unbind!, KeyBindings, KeyBindingsToken, Callable, execute_binding
using XCB
using XCB: Connection
using Test

km = Keymap(Connection())

key_event(key::Symbol) = KeyEvent(km, PhysicalKey(km, key))

@testset "Key bindings" begin
  kb = KeyBindings()
  @test isempty(kb)
  placeholder() = () -> nothing

  token = bind!(kb, key"f" => placeholder)
  @test token == 1
  @test length(kb.active) == 1
  @test length(kb.inactive) == 0
  @test length(kb.bindings) == 1
  @test execute_binding(kb, key_event(:AC04))

  unbind!(kb, token)
  @test !execute_binding(kb, key_event(:AC04))
  @test isempty(kb)

  bind!(kb, key"f" => key -> key::KeyCombination) do
    @test execute_binding(kb, key_event(:AC04))
  end
  @test isempty(kb)

  token = bind!(kb, key"f" => placeholder, [key"g", key")"] => placeholder)
  token2 = bind!(kb, key"g" => placeholder)
  @test execute_binding(kb, key_event(:AC04))
  @test execute_binding(kb, key_event(:AC05))
  @test execute_binding(kb, key_event(:AE11))

  unbind!(kb, token)
  @test !execute_binding(kb, key_event(:AC04))
  @test execute_binding(kb, key_event(:AC05))

  unbind!(kb, token2)
  @test isempty(kb)

  token = bind!(kb, key"ctrl+q" => placeholder)
  @test execute_binding(kb, KeyEvent(:AC01, KeySymbol(:q), '\0', CTRL_MODIFIER))
  @test execute_binding(kb, KeyEvent(:AC01, KeySymbol(:q), '\0', CTRL_MODIFIER, MOD2_MODIFIER | LOCK_MODIFIER))
  @test !execute_binding(kb, KeyEvent(:AC01, KeySymbol(:q), '\0', CTRL_MODIFIER, CTRL_MODIFIER))
  @test execute_binding(kb, KeyEvent(:AC01, KeySymbol(:Q), '\0', LOCK_MODIFIER | CTRL_MODIFIER))
  @test !execute_binding(kb, KeyEvent(:AC01, KeySymbol(:Q), '\0', CTRL_MODIFIER | SHIFT_MODIFIER, CTRL_MODIFIER | SHIFT_MODIFIER))
  unbind!(kb, token)

  token = bind!(kb, key")" => placeholder)
  @test execute_binding(kb, KeyEvent(:AE11, KeySymbol(')'), ')'))
  @test !execute_binding(kb, KeyEvent(:AE11, KeySymbol(')'), ')', SHIFT_MODIFIER))
  @test execute_binding(kb, KeyEvent(:AE10, KeySymbol(')'), ')', SHIFT_MODIFIER, SHIFT_MODIFIER))
  unbind!(kb, token)

  token = bind!(kb, key"shift+)" => placeholder)
  @test !execute_binding(kb, KeyEvent(:AE11, KeySymbol(')'), ')'))
  @test execute_binding(kb, KeyEvent(:AE11, KeySymbol(')'), ')', SHIFT_MODIFIER))
  @test execute_binding(kb, KeyEvent(:AE10, KeySymbol(')'), ')', SHIFT_MODIFIER, SHIFT_MODIFIER))
  unbind!(kb, token)
end;
