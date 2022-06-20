defmodule Vsr.Server do
  require Logger

  def accept(port, replica_number) do
    state = %Vsr.VRState{replica_number: replica_number}
    Logger.info("Starting server with state: #{inspect(state)}...")

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Accepting connections on port #{port}")

    replicas =
      Application.get_env(:vsr, :ports, [])
      |> Enum.reject(fn p -> p == port end)

    loop_acceptor(socket, %{state | replicas: replicas})
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
    client_info = Map.get(state.client_table, client_id, %Vsr.VRState.ClientInfo{})
    Logger.info(%{state: state, client_info: client_info})

    # Step 2
    state =
      if request_number <= client_info.last_request_number do
        {last_request_number, result} = client_info.last_result

        if last_request_number == request_number do
          write_line(socket, result)
        else
          write_line(socket, "drop")
        end

        state
      else
        # Step 3
        op_number = state.op_number + 1
        log = [op | state.log]

        # This might be wrong:
        commit_number = state.commit_number + 1

        # Send <Prepare v, m, n, k> to other replicas
        for port <- state.replicas do
          Vsr.ReplicaClient.send_message(
            port,
            Vsr.Message.prepare(state.view_number, op, op_number, commit_number)
          )
        end

        # Compute result
        result = "result#{request_number}"

        client_table =
          Map.put(state.client_table, client_id, %Vsr.VRState.ClientInfo{
            last_request_number: request_number,
            last_result: {request_number, result}
          })

        write_line(socket, result)

        # Update
        %{state | client_table: client_table, op_number: op_number, log: log}
      end

    state
  end

  defp handle_message(socket, _state, message) do
    Logger.info("receive unsupported message: #{inspect(message)}")
    write_line(socket, "unsupported message type")
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(socket, message) do
    :gen_tcp.send(socket, message <> "\n")
  end
end
