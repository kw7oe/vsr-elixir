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
        message = Vsr.Message.parse(String.trim(data))
        state = handle_message(socket, state, message)
        serve(socket, state)

      _ ->
        Logger.debug("connection closed")
    end

    state
  end

  defp handle_message(socket, state, {:request, op, client_id, request_number}) do
    Logger.info("state: #{inspect(state)}")

    client_info =
      Map.get(state.client_table, client_id, %Vsr.VRState.ClientInfo{})
      |> IO.inspect()

    # Step 2
    state =
      if request_number < client_info.last_request_number do
        {last_request_number, result} = client_info.last_result

        if last_request_number == request_number do
          write_line(socket, result)
        else
          write_line(socket, "drop")
        end

        state
      else
        # Step 3
        result = "result#{request_number}"

        Map.put(state.client_table, client_id, %Vsr.VRState.ClientInfo{
          last_request_number: request_number,
          last_result: {request_number, result}
        })

        write_line(socket, result)

        %{state | op_number: state.op_number + 1}
      end

    state
  end

  defp handle_message(socket, _state, _) do
    write_line(socket, "unsupported message type")
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(socket, message) do
    :gen_tcp.send(socket, message <> "\n")
  end
end
