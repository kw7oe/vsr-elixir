defmodule Vsr.Server do
  require Logger

  def accept(port, replica_number) do
    state = %Vsr.VRState{replica_number: replica_number}
    Logger.info("Starting server with state: #{inspect(state)}...")

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Accepting connections on port #{port}")

    loop_acceptor(socket, state)
  end

  defp loop_acceptor(socket, state) do
    {:ok, client} = :gen_tcp.accept(socket)
    # {:ok, pid} = Task.Supervisor.start_child(Vsr.TaskSupervisor, fn -> serve(client) end)
    # :ok = :gen_tcp.controlling_process(client, pid)
    state = serve(client, state)
    loop_acceptor(socket, state)
  end

  defp serve(socket, state) do
    case read_line(socket) do
      {:ok, data} ->
        write_line(data, socket)
        serve(socket, state)

      _ ->
        Logger.debug("connection closed")
    end

    state
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
