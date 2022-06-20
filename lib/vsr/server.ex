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

        # Send <Prepare v, m, n, k> to other replicas
        #
        # This should be asynchronous and fault tolerant.
        #
        # Failure to send to one replicae shouldn't cause
        # the whole thing to failed.
        for port <- state.replicas do
          reply =
            Vsr.ReplicaClient.send_message(
              port,
              Vsr.Message.prepare(
                state.view_number,
                {:request, op, client_id, request_number} |> :erlang.term_to_binary(),
                op_number,
                state.commit_number
              )
            )

          Logger.info("received reply from replica #{port}: #{reply}")
        end

        # Compute result
        result = "result#{request_number}"

        # Commit number is increment after primary excutes the operation
        # by calling the service code.
        commit_number = state.commit_number + 1

        # Send <Reply v, s, x> to client
        write_line(socket, Vsr.Message.reply(state.view_number, request_number, result))

        client_table =
          Map.put(state.client_table, client_id, %Vsr.VRState.ClientInfo{
            last_request_number: request_number,
            last_result: {request_number, result}
          })

        # Update
        %{
          state
          | client_table: client_table,
            op_number: op_number,
            commit_number: commit_number,
            log: log
        }
      end

    state
  end

  # Commit number is included in prepare message to inform replica about
  # the previous commit.
  #
  # If primary does not receive any client request in a timely way,
  # it will instead inform the replica by sending a <Commit v, k> message.
  defp handle_message(socket, state, {:prepare, view_number, message, _op_number, _commit_number}) do
    # TODO:Check if log contain request up to op_number

    op_number = state.op_number + 1
    log = [message | state.log]

    # Assuming, message is always <Request>
    {_, _, client_id, request_number} = :erlang.binary_to_term(message)

    client_table =
      Map.put(state.client_table, client_id, %Vsr.VRState.ClientInfo{
        last_request_number: request_number
      })

    # Send primary <PrepareOK, v, n, i>
    message = Vsr.Message.prepare_ok(view_number, op_number, state.replica_number)
    write_line(socket, message)

    %{state | client_table: client_table, op_number: op_number, log: log}
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
