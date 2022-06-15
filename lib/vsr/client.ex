defmodule Vsr.Client do
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: :"client-#{config.client_id}")
  end

  def init(config) do
    {:ok, sock} =
      :gen_tcp.connect('localhost', config.port, [:binary, packet: :line, active: false])

    state =
      Map.merge(config, %{
        conn: sock,
        request_number: 0
      })

    {:ok, state}
  end

  # Client to Server only
  def request(client, op) do
    GenServer.call(client, {:request, op})
  end

  # Server to Replica only

  # Send by primary to replica upon receiving a request.
  def prepare(client, view_number, message, op_number, commit_number) do
    GenServer.call(client, {:prepare, view_number, message, op_number, commit_number})
  end

  # Send by replica i to primary, to reply to the prepare message from primary.
  def prepare_ok(client, view_number, op_number, i) do
    GenServer.call(client, {:prepare_ok, view_number, op_number, i})
  end

  # Send by primary to replica.
  def commit(client, view_number, commit_number) do
    GenServer.call(client, {:commit, view_number, commit_number})
  end

  def handle_call({:request, op}, _from, state) do
    s = state.request_number
    c = state.client_id
    Logger.info("client #{c}: request op=\"#{op}\" c=#{c} s=#{s}")

    resp = tcp_send(state.conn, "request,#{op},#{c},#{s}")
    {:reply, resp, %{state | request_number: s + 1}}
  end

  def handle_call({:prepare, v, m, o, c}, _from, state) do
    id = state.client_id
    Logger.info("client #{id}: prepare v=#{v} m=\"#{m}\" o=#{o} c=#{c}")

    resp = tcp_send(state.conn, "prepare,#{v},#{m},#{o},#{c}")
    {:reply, resp, state}
  end

  def handle_call({:prepare_ok, v, n, i}, _from, state) do
    id = state.client_id
    Logger.info("client #{id}: prepare_ok v=#{v} n=\"#{n}\" i=#{i}")

    resp = tcp_send(state.conn, "prepare_ok,#{v},#{n},#{i}")
    {:reply, resp, state}
  end

  def handle_call({:commit, v, k}, _from, state) do
    id = state.client_id
    Logger.info("client #{id}: commit v=#{v} k=#{k}")

    resp = tcp_send(state.conn, "commit,#{v},#{k}")
    {:reply, resp, state}
  end

  def tcp_send(conn, data) do
    :gen_tcp.send(conn, data <> "\n")
    {:ok, resp} = :gen_tcp.recv(conn, 0)
    resp
  end
end
