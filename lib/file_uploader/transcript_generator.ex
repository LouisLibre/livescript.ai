defmodule FileUploader.TranscriptGenerator do
  use GenServer

  require Logger

  alias FileUploader.TranscriptGenerator

  # caller is the live_view pid

  defstruct ref: nil, exec_pid: nil, caller: nil, pid: nil, watcher_pid: nil, output_dir: nil, processed_segments: MapSet.new()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stream_chunk!(%TranscriptGenerator{} = gen, chunk) do
    each_part(chunk, 60_000, fn part -> :ok = exec_send(gen, part) end)
  end

  defp each_part(binary, max_size, func) when is_binary(binary) and is_integer(max_size) do
    case binary do
      <<>> ->
        :ok

      part when byte_size(part) <= max_size ->
        func.(part)

      <<part::binary-size(max_size), rest::binary>> ->
        func.(part)
        each_part(rest, max_size, func)
    end
  end

  defp exec_send(%TranscriptGenerator{pid: pid, ref: ref}, data) do
    if node(pid) === node() do
      :exec.send(ref, data)
    else
      GenServer.call(pid, {:exec_send, data})
    end
  end

  def close(%TranscriptGenerator{} = gen) do
    GenServer.call(gen.pid, :close)
  end

  def open(opts \\ []) do
    Keyword.validate!(opts, [:timeout, :caller])
    timeout = Keyword.get(opts, :timeout, 5_000)
    caller = Keyword.get(opts, :caller, self())
    parent_ref = make_ref()
    parent = self()

    spec = %{
      id: parent_ref,
      start: {__MODULE__, :start_link, [{caller, parent_ref, parent, opts}]},
      restart: :temporary
    }

    {:ok, pid} = DynamicSupervisor.start_child(FileUploader.DynSup, spec)

    receive do
      {^parent_ref, %TranscriptGenerator{} = gen} ->
        %TranscriptGenerator{gen | pid: pid}
    after
      timeout -> exit(:timeout)
    end
  end

  @impl true
  def init({caller, parent_ref, parent, opts}) do
    segment_time = Keyword.get(opts, :segment_time, 20)


    unique_id = make_ref() |> :erlang.phash2() |> Integer.to_string()
    output_dir = Path.join(System.tmp_dir!(), "segments_#{unique_id}")

    File.mkdir_p!(output_dir)
    output_pattern = Path.join(output_dir, "segment_%03d.wav")

    #ffmpeg -i file.mp4 -ac 1 -ar 16k -f f32le -ss 0 -t 20 -v quiet -
    # cat file.mp4 | ffmpeg -i pipe:0 -f segment -segment_time 20 -segment_format wav -c:a pcm_f32le -ac 1 -ar 16000 segment_%03d.wav

    cmd =
      "ffmpeg -i pipe:0 -f segment -segment_time #{segment_time} -segment_format wav -c:a pcm_f32le -ac 1 -ar 16000 #{output_pattern}"

    IO.inspect(cmd)

    case exec(cmd) do
      {:ok, exec_pid, ref} ->
        # Start watching the folder for new files
        {:ok, watcher_pid} = FileSystem.start_link(dirs: [output_dir])
        FileSystem.subscribe(watcher_pid)

        gen = %TranscriptGenerator{ref: ref, exec_pid: exec_pid, pid: self(), caller: caller, watcher_pid: watcher_pid, output_dir: output_dir}
        send(parent, {parent_ref, gen})
        Process.monitor(caller)
        {:ok, %{gen: gen, count: 0, ffmpeg_finished: false, processed_segments: MapSet.new()}}

      other ->
        exit(other)
    end
  end

  @impl true
  def handle_call({:exec_send, data}, _from, state) do
    %TranscriptGenerator{ref: ref} = state.gen
    :exec.send(ref, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:close, _from, state) do
    %TranscriptGenerator{ref: ref} = state.gen
    :exec.send(ref, :eof)
    {:reply, :ok, state}
  end

  # TODO: possibly remove this for a catch-all
  @impl true
  def handle_info({:stderr, _ref, _msg}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, state) do
    %TranscriptGenerator{watcher_pid: ^watcher_pid, caller: caller, ref: ref} = state.gen

    Logger.info("File event: #{inspect(path)}")
    Logger.info("File event: #{inspect(events)}")

    cond do
      MapSet.member?(state.processed_segments, path) ->
        {:noreply, state}

      :created in events and Path.extname(path) == ".wav" ->
        count = state.count + 1
        processed_segments = MapSet.put(state.processed_segments, path)

        segment_number = path
        |> Path.basename
        |> String.split("_")
        |> List.last
        |> String.replace(".wav", "")
        |> String.to_integer()

        Logger.info("WAV segment created: #{inspect(path)}")
        spawn(fn ->
          # Instead of calling Nx.Serving directly, do:
          user_id = caller  # or some unique user token
          FileUploader.InterleavedTranscriber.transcribe(path, caller, segment_number, user_id)
        end)

        new_state = %{state | count: count, processed_segments: processed_segments}

        if state.ffmpeg_finished and check_completion(state.gen, processed_segments, count) do
          {:stop, :normal, new_state}
        else
          {:noreply, new_state}
        end

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    %{gen: %TranscriptGenerator{ref: gen_ref, caller: caller, watcher_pid: watcher_pid, output_dir: output_dir}} = state

    cond do
      pid === caller ->
        # triggered by Process.monitor(caller)
        IO.inspect("Caller #{inspect(pid)} went away: #{inspect(reason)}")
        # TODO: Handle case where ffmpeg dies before completion, there should be a conflict here
        #if Process.alive?(watcher_pid), do: GenServer.stop(watcher_pid)
        # TODO: remove the comment once verified it works
        # File.rm_rf(output_dir)
        {:stop, {:shutdown, reason}, state}

      ref === gen_ref ->
        # triggered by     :exec.run(cmd, [_, _, _, :MONITOR])
        IO.inspect("TranscriptGenerator process went away: #{inspect(reason)}")
        new_state = %{state | ffmpeg_finished: true}
        check_completion(state.gen, state.processed_segments, state.count)
        {:noreply, new_state}
        # TODO: remove the comment once verified it works, prolly similar existance check
        # File.rm_rf(output_dir)
        #send(caller, {gen_ref, :ok, state.count})
        #{:stop, :normal, state}
    end
  end

  def handle_info(msg, state) do
    # Handle any unexpected exits
    Logger.info("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end


  defp check_completion(gen, processed_segments, count) do
    # Get list of all WAV files in output directory
    wav_files = Path.wildcard(Path.join(gen.output_dir, "*.wav"))

    if length(wav_files) == MapSet.size(processed_segments) do
      Logger.info("All segments processed. Total count: #{count}")
      send(gen.caller, {gen.ref, :ok, count})
      if Process.alive?(gen.watcher_pid), do: GenServer.stop(gen.watcher_pid)
      true
    else
      false
    end
  end


  defp exec(cmd) do
    :exec.run(cmd, [:stdin, :stdout, :stderr, :monitor])
  end


end
