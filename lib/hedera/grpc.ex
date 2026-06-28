defmodule Hedera.Grpc do
  @moduledoc """
  A minimal gRPC unary client over HTTP/2 (via Mint), speaking the cleartext
  (h2c) protocol Hedera consensus nodes serve on port 50211. Handles the 5-byte
  gRPC length-prefixed framing and the `grpc-status` trailer; enough for the
  single-request/single-response calls this SDK makes.
  """

  @doc """
  Make a unary gRPC call: send `message` (raw protobuf bytes) to `path` on
  `host:port`, return `{:ok, response_bytes}` or `{:error, reason}`.
  """
  @spec unary(binary(), :inet.port_number(), binary(), binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def unary(host, port, path, message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    with {:ok, conn} <-
           Mint.HTTP.connect(:http, host, port,
             protocols: [:http2],
             transport_opts: [timeout: timeout]
           ) do
      try do
        do_call(conn, path, message, timeout)
      after
        Mint.HTTP.close(conn)
      end
    end
  end

  defp do_call(conn, path, message, timeout) do
    headers = [
      {"content-type", "application/grpc+proto"},
      {"te", "trailers"},
      {"grpc-accept-encoding", "identity"}
    ]

    frame = <<0::8, byte_size(message)::unsigned-32>> <> message

    with {:ok, conn, ref} <- Mint.HTTP.request(conn, "POST", path, headers, frame) do
      collect(conn, ref, timeout, %{status: nil, data: <<>>, grpc_status: nil, grpc_message: nil})
    end
  end

  defp collect(conn, ref, timeout, acc) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            acc = Enum.reduce(responses, acc, &handle(&1, ref, &2))

            if done?(responses, ref) do
              finish(acc)
            else
              collect(conn, ref, timeout, acc)
            end

          {:error, _conn, reason, _responses} ->
            {:error, {:http2, reason}}
        end
    after
      timeout -> {:error, :timeout}
    end
  end

  defp handle({:status, ref, status}, ref, acc), do: %{acc | status: status}
  defp handle({:data, ref, data}, ref, acc), do: %{acc | data: acc.data <> data}

  defp handle({:headers, ref, headers}, ref, acc) do
    %{
      acc
      | grpc_status: header(headers, "grpc-status", acc.grpc_status),
        grpc_message: header(headers, "grpc-message", acc.grpc_message)
    }
  end

  defp handle(_other, _ref, acc), do: acc

  defp done?(responses, ref), do: Enum.any?(responses, &match?({:done, ^ref}, &1))

  defp header(headers, name, default) do
    case List.keyfind(headers, name, 0) do
      {^name, value} -> value
      nil -> default
    end
  end

  defp finish(%{status: status}) when status not in [200, nil],
    do: {:error, {:http_status, status}}

  defp finish(%{grpc_status: s}) when s not in [nil, "0"], do: {:error, {:grpc_status, s}}

  defp finish(%{data: <<_flag::8, len::unsigned-32, rest::binary>>})
       when byte_size(rest) >= len do
    <<message::binary-size(^len), _::binary>> = rest
    {:ok, message}
  end

  defp finish(%{data: <<>>}), do: {:ok, <<>>}
  defp finish(_), do: {:error, :malformed_response}
end
