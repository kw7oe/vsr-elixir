defmodule State do
   use Agent

  def start_link(state) do
    Agent.start_link(fn -> state end, name: __MODULE__)
  end


  def put(new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)
  end

  def get() do
    Agent.get(__MODULE__, fn state -> state end)
  end
end
