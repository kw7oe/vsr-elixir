defmodule Vsr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
     port = String.to_integer(System.fetch_env!("PORT"))

    children = [
      {Task.Supervisor, name: Vsr.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> Vsr.Server.accept(port) end}, restart: :permanent)
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Vsr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
