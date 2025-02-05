defmodule FileUploaderWeb.CustomUploadWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  require Logger

  alias FileUploader.TranscriptGenerator

  @impl true
  def init(opts) do
    generator = TranscriptGenerator.open(opts)
    {:ok, %{gen: generator}}
  end

  @impl true
  def write_chunk(data, state) do
    TranscriptGenerator.stream_chunk!(state.gen, data)
    {:ok, state}
  end

  @impl true
  def meta(state), do: %{gen: state.gen}

  @impl true
  def close(state, _reason) do
    TranscriptGenerator.close(state.gen)
    {:ok, state}
  end
end
