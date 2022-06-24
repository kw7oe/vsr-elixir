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

  def initiate_view_change() do
    "initiate_view_change"
  end

  def start_view_change(v, i) do
    "start_view_change,#{v},#{i}"
  end

  def do_view_change(v, vprime, n, k, i, log) do
    log = Enum.join(log, "\t")
    "do_view_change,#{v},#{vprime},#{n},#{k},#{i}-#{log}"
  end

  def start_view(v, n, k, log) do
    log = Enum.join(log, "\t")
    "start_view,#{v},#{n},#{k}-#{log}"
  end

  def parse(string) do
    splitted =
      case string do
        "prepare\t" <> _ ->
          String.split(string, "\t")

        "do_view_change," <> _ ->
          [head, tail] = String.split(string, "-")
          String.split(head, ",") ++ [tail]

        "start_view," <> _ ->
          [head, tail] = String.split(string, "-")
          String.split(head, ",") ++ [tail]

        _ ->
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

  defp do_parse(["initiate_view_change"]) do
    {:initiate_view_change}
  end

  defp do_parse(["start_view_change", v, i]) do
    {:start_view_change, String.to_integer(v), String.to_integer(i)}
  end

  defp do_parse(["do_view_change", v, vprime, n, k, i, log]) do
    {:do_view_change, String.to_integer(v), String.to_integer(vprime), String.to_integer(n),
     String.to_integer(k), String.to_integer(i), String.split(log, "\t")}
  end

  defp do_parse(["start_view", v, n, k, log]) do
    {:start_view, String.to_integer(v), String.to_integer(n), String.to_integer(k),
     String.split(log, "\t")}
  end
end
