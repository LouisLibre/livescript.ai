defmodule FileUploader.Whisper do
  def speech_to_text(path, caller, segment_number) do
    IO.puts("Whisper speech_to_text: #{inspect(path)}")
    output = Nx.Serving.batched_run(WhisperServing, {:file, path})

    #=> %{
    #=>   chunks: [
    #=>     %{
    #=>       text: " There is a cat outside the window.",
    #=>       start_timestamp_seconds: nil,
    #=>       end_timestamp_seconds: nil
    #=>     }
    #=>   ]
    #=> }

    text = output.chunks |> Enum.map_join(& &1.text) |> String.trim()
    #=> "There is a cat outside the window."

    send(caller, {:transcript, text, segment_number})


  end
end
