defmodule Vsr.ReplicaClient do
  use GenServer
  require Logger

  @max_retry 5

  def send_message(port, message, retry \\ 0) do
    # TODO: Check if a race condition is possible.

    # This might not be a good pattern to lazily initiate a connection.
    # Might considering looking into other existing connection pool like
    # implementation.
    case Process.whereis(:"replica-client-#{port}") do
      nil ->
        # Logger.info("replica client for port #{port} not started yet, starting it now...")
        DynamicSupervisor.start_child(Vsr.DynamicSupervisor, {__MODULE__, %{port: port}})

        # Exponential backoff before retry
        base_ms = 100
        duration = base_ms * 2 ** retry
        Process.sleep(duration)

        if retry == @max_retry do
          {:error, :replica_offline}
        else
          send_message(port, message, retry + 1)
        end

      pid ->
        {:ok, GenServer.call(pid, {:send, message})}
    end
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: :"replica-client-#{config.port}")
  end

  def init(config) do
    {:ok, sock} =
      :gen_tcp.connect('localhost', config.port, [:binary, packet: :line, active: false])

    state = Map.merge(config, %{port: config.port, conn: sock})

    {:ok, state}
  end

  # Send by primary to replica upon receiving a request.
  def prepare(client, view_number, message, op_number, commit_number) do
    GenServer.call(
      client,
      {:send, Vsr.Message.prepare(view_number, message, op_number, commit_number)}
    )
  end

  # Send by replica i to primary, to reply to the prepare message from primary.
  def prepare_ok(client, view_number, op_number, i) do
    GenServer.call(client, {:send, Vsr.Message.prepare_ok(view_number, op_number, i)})
  end

  # Send by primary to replica.
  def commit(client, view_number, commit_number) do
    GenServer.call(client, {:send, Vsr.Message.commit(view_number, commit_number)})
  end

  def handle_call({:send, message}, _from, state) do
    id = state.port
    Logger.info("client #{id}: #{message}")
    resp = tcp_send(state.conn, message)
    {:reply, resp, state}
  end

  def tcp_send(conn, data) do
    :gen_tcp.send(conn, data <> "\n")
    {:ok, resp} = :gen_tcp.recv(conn, 0)
    resp
  end
end
