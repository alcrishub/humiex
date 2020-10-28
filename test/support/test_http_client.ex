defmodule HumiexTest.TestHTTPClient do
  @moduledoc """
  Implements a HTTP Clients for tests that conform to the behaviour Humiex.Runner.Streamer uses

  * setup/1 allows to specify the response sent.
  """
  @behaviour Humiex.HTTPAsyncBehaviour
  require Logger
  alias Humiex.{State, Client}
  alias HumiexTest.TestResponse

  def setup(%TestResponse{} = response) do
    response_list = [
      status: response.status,
      headers: response.headers,
      chunks: response.chunks,
      response_end: response.response_end
    ]
    {:ok, pid} = Agent.start(fn -> response_list end)

    get_next(pid)
    %State{
      client: Client.new("mock", "test", "my_token"),
      http_client: __MODULE__,
      resp: pid
    }
  end

  def get_next(pid) do
    msg = Agent.get_and_update(pid, fn
      [{:status, _code} = msg | rest] ->
        {msg, rest}
      [{:headers, _headers} = msg | rest] -> {msg, rest}
      [{:chunks, [chunk | []]} | rest ] -> {{:chunk, chunk}, rest}
      [{:chunks, [chunk | rest_chunks]} | rest ] -> {{:chunk, chunk}, [{:chunks, rest_chunks} | rest]}
      [{:response_end, :response_end}] -> {:response_end, []}
    end)

    send(self(), msg)
  end

  @impl true
  def start(%State{} = state) do
    fn ->
      state
    end
  end

  @impl true
  def next(%State{resp: resp} = state) do
    receive do
      {:status, code} ->
        Logger.debug("STATUS: #{code}")
        get_next(resp)
        {[], state}

      {:headers, headers} ->
        Logger.debug("RESPONSE HEADERS: #{inspect(headers)}")
        get_next(resp)
        {[], state}

      {:chunk, chunk} ->
        get_next(resp)
        new_state = %State{state | chunk: chunk}
        {[new_state], new_state}

      :response_end ->
        {:halt, state}
    end
  end

  @impl true
  def stop(%State{resp: resp} = state) do
    Agent.stop(resp)
    {:ok, state}
  end
end