defmodule Vsr.Message do
  def request(op, c, s) do
    "request,#{op},#{c},#{s}"
  end

  def reply(v, s, x) do
    "reply,#{v},#{s},#{x}"
  end

  def prepare(v, m, n, k) do
    "prepare,#{v},#{m},#{n},#{k}"
  end

  def prepare_ok(v, n, i) do
    "prepare_ok,#{v},#{n},#{i}"
  end

  def commit(v, k) do
    "commit,#{v},#{k}"
  end

  def parse(string) do
    string
    |> String.split(",")
    |> do_parse()
  end

  defp do_parse(["request", op, c, s]) do
    {:request, op, String.to_integer(c), String.to_integer(s)}
  end

  defp do_parse(["reply", v, s, x]) do
    {:reply, String.to_integer(v), String.to_integer(s), x}
  end

  defp do_parse(["prepare", v, m, n, k]) do
    {:prepare, String.to_integer(v), m, String.to_integer(n), String.to_integer(k)}
  end

  defp do_parse(["prepare_ok", v, n, i]) do
    {:prepare_ok, String.to_integer(v), String.to_integer(n), String.to_integer(i)}
  end

  defp do_parse(["commit", v, k]) do
    {:commit, String.to_integer(v), String.to_integer(k)}
  end
end
