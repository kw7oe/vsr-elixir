defmodule Vsr.MessageTest do
  use ExUnit.Case

  test "parse/1" do
    assert {:request, "op", 0, 1} = Vsr.Message.parse("request,op,0,1")
    assert {:reply, 0, 1, "result"} = Vsr.Message.parse("reply,0,1,result")
    assert {:prepare, 0, "op", 0, 0} = Vsr.Message.parse("prepare,0,op,0,0")
    assert {:prepare_ok, 0, 1, 0} = Vsr.Message.parse("prepare_ok,0,1,0")
    assert {:commit, 0, 1} = Vsr.Message.parse("commit,0,1")
  end

  test "parse prepare" do
    m = Vsr.Message.request("op", 0, 0)
    message = Vsr.Message.prepare(0, m, 0, 0)
    assert {:prepare, 0, "request,op,0,0", 0, 0} = Vsr.Message.parse(message)
  end

  test "parse do_view_change" do
    # Does not really represent the actual log
    log = [
      "1:request,op,0,1",
      "2:reply,0,1,result",
      "3:prepare,0,op,0,0",
      "4:prepare_ok,0,1,0",
      "5:commit,0,1"
    ]

    message = Vsr.Message.do_view_change(0, 1, 3, 3, 1, log)

    assert {:do_view_change, 0, 1, 3, 3, 1, ^log} = Vsr.Message.parse(message)
  end

  test "parse start_view" do
    # Does not really represent the actual log
    log = [
      "1:request,op,0,1",
      "2:reply,0,1,result",
      "3:prepare,0,op,0,0",
      "4:prepare_ok,0,1,0",
      "5:commit,0,1"
    ]

    message = Vsr.Message.start_view(1, 5, 5, log)
    assert {:start_view, 1, 5, 5, ^log} = Vsr.Message.parse(message)
  end
end
