defmodule Vsr.Server do
  require Logger
  alias State

  def accept(port, replica_number) do
    state = %Vsr.VRState{replica_number: replica_number}
    Logger.info("Starting server with state: #{inspect(state)}...")

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Accepting connections on port #{port}")

    replicas =
      Application.get_env(:vsr, :ports, [])
      # The first port is always the primary port. So
      # we can drop it.
      |> Enum.drop(1)
      |> Enum.reject(fn p -> p == port end)

    state = %{state | replicas: replicas}

    State.put(state)
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Vsr.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    case read_line(socket) do
      {:ok, data} ->
        message = Vsr.Message.parse(String.trim(data))
        handle_message(socket, message)
        serve(socket)

      _ ->
        Logger.debug("connection closed")
    end
  end

  defp handle_message(socket, {:request, _op, client_id, request_number} = request) do
    state = State.get()
    client_info = Map.get(state.client_table, client_id, %Vsr.VRState.ClientInfo{})
    Logger.info(%{state: state, client_info: client_info})

    # Step 2
    #
    # When the primary receives the request, it compares the request-number in the request
    # with the information in the client table. If the request-number s isn’t bigger than
    # the information in the table it drops the request, but it will re-send the response if
    # the request is the most recent one from this client and it has already been executed.

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
        #
        # The primary advances op-number, adds the request to the end of the log, and updates
        # the information for this client in the client-table to contain the new
        # request number, s. Then it sends a ⟨PREPARE v, m, n, k⟩ message to the other replicas,
        # where v is the current view-number, m is the message it received from the client,
        # n is the op-number it assigned to the request, and k is the commit-number.

        op_number = state.op_number + 1
        message = Vsr.Message.to_message(request)
        log = [to_log(op_number, message) | state.log]

        # Skip update client-table... since if we failed, the state won't be
        # stored as well.

        # To fix this, we need to store our state on a long running process.
        # Our current implementation pass the state around...

        # port is 2f + 1, so we can calculate f through this formula
        f = (length(state.replicas) - 1) / 2

        # Send <Prepare v, m, n, k> to other replicas
        #
        # This should be asynchronous and fault tolerant.
        #
        # Failure to send to one replicae shouldn't cause
        # the whole thing to failed.
        #
        # Hence, we spawn a task with async_nolink:
        tasks =
          Enum.map(state.replicas, fn port ->
            Task.Supervisor.async_nolink(Vsr.TaskSupervisor, fn ->
              reply =
                Vsr.ReplicaClient.send_message(
                  port,
                  Vsr.Message.prepare(
                    state.view_number,
                    message,
                    op_number,
                    state.commit_number
                  )
                )

              Logger.info("received reply from replica #{port}: #{inspect(reply)}")
              reply
            end)
          end)

        # We repeatly called yield with a timeout of 100 ms
        # until we collected at least f results.
        #
        # TODO: Shutdown tasks that are not completed when
        # we collected enough of f.
        yield_many_until = fn tasks, count, results, func ->
          results =
            Task.yield_many(tasks, 100)
            |> Enum.filter(fn {_, res} -> res end)
            |> Enum.reduce(results, fn {_, {s1, {s2, res}}}, results ->
              if s1 == :ok && s2 == :ok do
                [res | results]
              else
                results
              end
            end)

          if length(results) < f do
            func.(tasks, count + 1, results, func)
          else
            {count + 1, results}
          end
        end

        # We probably need to check the results:
        #
        # we are curently assuming that all of the successful results
        # return prepareok correctly.
        {_count, _results} = yield_many_until.(tasks, 0, [], yield_many_until)

        # Step 5:
        #
        # The primary waits for f PREPAREOK messages from different backups;
        # at this point it considers the operation (and all earlier ones) to be committed.
        # Then, after it has executed all earlier operations (those assigned smaller op-numbers),
        # the primary executes the operation by making an up-call to the service code, and
        # increments its commit-number. Then it sends a ⟨REPLY v, s, x⟩ message to the client;
        # here v is the view-number, s is the number the client provided in the request, and
        # x is the result of the up-call. The primary also updates the client’s entry in the
        # client-table to contain the result.

        # TODO: wait for f PrepareOk message.  Current implmentation wait for all request.

        # Performing upcall to service code and increment commit number
        result = upcall(request_number)
        commit_number = state.commit_number + 1

        # Send <Reply v, s, x> to client
        write_line(socket, Vsr.Message.reply(state.view_number, request_number, result))

        # Update client table:
        client_table =
          Map.put(state.client_table, client_id, %Vsr.VRState.ClientInfo{
            last_request_number: request_number,
            last_result: {request_number, result}
          })

        # Update state
        state = %{
          state
          | client_table: client_table,
            op_number: op_number,
            commit_number: commit_number,
            log: log
        }
        State.put(state)
      end
  end

  # Commit number is included in prepare message to inform replica about
  # the previous commit.
  #
  # If primary does not receive any client request in a timely way,
  # it will instead inform the replica by sending a <Commit v, k> message.
  defp handle_message(socket, {:prepare, view_number, message, op_number, commit_number}) do
    state = State.get()
    Logger.info(%{state: state, op_number: op_number, commit_number: commit_number})

    # Commit
    inspect_logs(state.log)
    {commit_number, client_table} = commit(state, commit_number)

    # Step 4:
    #
    # Backups process PREPARE messages in order: a backup won’t accept a prepare with op-number n
    # until it has entries for all earlier requests in its log. When a backup i receives a
    # PREPARE message, it waits until it has entries in its log for all earlier re- quests
    # (doing state transfer if necessary to get the missing information).
    #
    # Then it increments its op-number, adds the request to the end of its log, updates the
    # client’s information in the client-table, and sends a ⟨PREPAREOK v, n, i⟩ message to the
    # primary to indicate that this operation and all earlier ones have prepared locally.

    # Not sure if checking op number with commmit number is enough to ensure
    # the following property:
    #
    #   > a backup won’t accept a prepare with op-number n until it
    #     has entries for all earlier requests in its log.
    if op_number - 1 != commit_number do
      Logger.warn("does not contain all the earlier opereations yet...")

      # TODO: Perform a state transfer or wait until earlier operations reach.
    end

    op_number = state.op_number + 1
    log = [to_log(op_number, message) | state.log]

    # We are assuming, message is always <Request>
    request = Vsr.Message.parse(message)
    {_, _, client_id, request_number} = request

    client_table =
      Map.update(
        client_table,
        client_id,
        %Vsr.VRState.ClientInfo{
          last_request_number: request_number
        },
        fn existing_client_info ->
          %{existing_client_info | last_request_number: request_number}
        end
      )

    # Send primary <PrepareOK, v, n, i>
    message = Vsr.Message.prepare_ok(view_number, op_number, state.replica_number)
    write_line(socket, message)

    state = %{
      state
      | client_table: client_table,
        op_number: op_number,
        commit_number: commit_number,
        log: log
    }
    State.put(state)
  end

  defp handle_message(socket, {:initiate_view_change}) do
    state = State.get()
    # Write to socket immediately to prevent the sender getting
    # stuck and timeout
    write_line(socket, "ok")

    # View Change Step 1:
    #
    # A replica i that notices the need for a view change advances
    # its view-number, sets its status to view- change, and sends
    # a ⟨STARTVIEWCHANGE v, i⟩ message to the all other replicas,
    # where v iden- tifies the new view. A replica notices the
    # need for a view change either based on its own timer, or
    # because it receives a STARTVIEWCHANGE or DOVIEWCHANGE
    # message for a view with a larger number than its own
    # view-number.
    view_number = state.view_number + 1
    i = state.replica_number
    message = Vsr.Message.start_view_change(view_number, i)

    for port <- state.replicas do
      Logger.info("sending to #{port}")
      reply = Vsr.ReplicaClient.send_message(port, message)
      Logger.info("receive reply from replica: #{inspect(reply)}")
    end

    # View Change Step 3:
    #
    # When the new primary receives f + 1 DOVIEWCHANGE messages from different replicas
    # (including itself), it sets its view-number to that in the messages and selects
    # as the new log the one contained in the message with the largest v′; if several
    # messages have the same v′ it selects the one among them with the largest n. It
    # sets its op-number to that of the topmost entry in the new log, sets its commit-number
    # to the largest such number it received in the DOVIEWCHANGE mes- sages, changes its
    # status to normal, and informs the other replicas of the completion of the view change by
    # sending ⟨STARTVIEW v, l, n, k⟩ messages to the other replicas, where l is the new log,
    # n is the op-number, and k is the commit-number.

    # View Change Step 4:
    #
    # The new primary starts accepting client requests. It also executes (in order)
    # any committed operations that it hadn’t executed previously, updates its client
    # table, and sends the replies to the clients

    State.put(%{state | status: :view_change, view_number: view_number})
  end

  defp handle_message(socket, {:start_view_change, v, i}) do
    state = State.get()
    Logger.info("start view change requested from replica #{i}")
    # View Change Step 2:
    #
    # When replica i receives STARTVIEWCHANGE messages for its view-number
    # from f other replicas, it sends a ⟨DOVIEWCHANGE v, l, v’, n, k, i⟩ message
    # to the node that will be the primary in the new view. Here v is its view-number,
    # l is its log, v′ is the view number of the latest view in which its status was
    # normal, n is the op-number, and k is the commit- number.
    message =
      Vsr.Message.do_view_change(
        v,
        state.view_number,
        state.op_number,
        state.commit_number,
        state.replica_number,
        state.log
      )

    Logger.info("send do view change: #{inspect(message)}")
    write_line(socket, "ok")
  end

  defp handle_message(socket, {:start_view, v, n, k, log}) do
    state = State.get()
    # View Change Step 5:
    #
    # When other replicas receive the STARTVIEW message, they replace their
    # log with the one in the mes- sage, set their op-number to that of the
    # latest entry in the log, set their view-number to the view num- ber in the
    # message, change their status to normal, and update the information in their
    # client-table. If there are non-committed operations in the log, they send
    # a ⟨PREPAREOK v, n, i⟩ message to the primary; here n is the op-number. Then
    # they execute all op- erations known to be committed that they haven’t executed
    # previously, advance their commit-number, and update the information in their
    # client-table.

    write_line(socket, "noop")
  end

  defp handle_message(socket, _state, message) do
    Logger.warn("receive unsupported message: #{inspect(message)}")
    write_line(socket, "unsupported message type")
  end

  # Step 7:
  #
  # When a backup learns of a commit, it waits until it has the request in its log
  # (which may require state transfer) and until it has executed all earlier operations.
  # Then it executes the operation by performing the up-call to the service code,
  # increments its commit-number, updates the client’s entry in the client-table,
  # but does not send the reply to the client.
  defp commit(state, commit_number) do
    # Receive instruction to commit commit_number, check if we have commited up
    # to commit_number - 1:
    if commit_number != 0 && state.commit_number != commit_number - 1 do
      Logger.warn("commit: does not contain all the earlier operations...")
    end

    # We might need to commit more than one message in our logs...
    message_to_commit =
      Enum.find_value(state.log, fn log ->
        [op_number, message] = String.split(log, ":")

        if String.to_integer(op_number) == commit_number do
          message
        else
          false
        end
      end)

    if message_to_commit do
      Logger.info("committing #{commit_number}: #{message_to_commit}...")
      {_, _, client_id, request_number} = Vsr.Message.parse(message_to_commit)

      # Performing up-call to the service code
      result = upcall(request_number)
      commit_number = state.commit_number + 1

      client_table =
        Map.update(
          state.client_table,
          client_id,
          %Vsr.VRState.ClientInfo{
            last_result: {request_number, result},
            last_request_number: request_number
          },
          fn existing_client_info ->
            %{existing_client_info | last_result: {request_number, result}}
          end
        )

      {commit_number, client_table}
    else
      {state.commit_number, state.client_table}
    end
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(socket, message) do
    :gen_tcp.send(socket, message <> "\n")
  end

  defp to_log(op_number, message) do
    "#{op_number}:#{message}"
  end

  defp upcall(request_number) do
    "result#{request_number}"
  end

  defp inspect_logs(logs) do
    for l <- logs do
      [op_number, message] = String.split(l, ":")
      IO.inspect(%{op_number: op_number, message: message})
    end
  end
end
