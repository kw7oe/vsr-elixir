defmodule Vsr.Message do
  def to_message(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.join(",")
  end

  def request(op, c, s) do
    "request,#{op},#{c},#{s}"
  end

  def reply(v, s, x) do
    "reply,#{v},#{s},#{x}"
  end

  def prepare(v, m, n, k) do
    "prepare\t#{v}\t#{m}\t#{n}\t#{k}"
  end

  def prepare_ok(v, n, i) do
    "prepare_ok,#{v},#{n},#{i}"
  end

  def commit(v, k) do
    "commit,#{v},#{k}"
  end

  def parse(string) do
    splitted =
      if String.starts_with?(string, "prepare\t") do
        String.split(string, "\t")
      else
        String.split(string, ",")
      end

    do_parse(splitted)
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
