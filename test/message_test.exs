defmodule Vsr.MessageTest do
  use ExUnit.Case

  test "parse/1" do
    assert {:request, "op", 0, 1} = Vsr.Message.parse("request,op,0,1")
    assert {:reply, 0, 1, "result"} = Vsr.Message.parse("reply,0,1,result")
    assert {:prepare, 0, "op", 0, 0} = Vsr.Message.parse("prepare,0,op,0,0")
    assert {:prepare_ok, 0, 1, 0} = Vsr.Message.parse("prepare_ok,0,1,0")
    assert {:commit, 0, 1} = Vsr.Message.parse("commit,0,1")
  end
end
