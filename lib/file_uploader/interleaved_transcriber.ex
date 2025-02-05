defmodule FileUploader.InterleavedTranscriber do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def transcribe(path, caller, segment_number, user_id) do
    GenServer.cast(__MODULE__, {:transcribe, path, caller, segment_number, user_id})
  end

  def init(_opts) do
    # Keep track of:
    # :user_queues => user_id => queue of segments
    # :rr_order    => the round-robin list of user_ids
    # :processing  => false (not currently transcribing anything)
    {:ok, %{
      user_queues: %{},
      rr_order: [],
      processing: false
    }}
  end

  # ------------------------------------------------------------------------------
  # 1) Enqueue segments
  # ------------------------------------------------------------------------------
  def handle_cast({:transcribe, path, caller, seg_num, user_id}, state) do
    # Enqueue this user's segment
    user_queues =
      Map.update(state.user_queues, user_id, :queue.from_list([{path, caller, seg_num}]), fn q ->
        :queue.in({path, caller, seg_num}, q)
      end)

    # Ensure user_id is in round-robin
    rr_order =
      if user_id in state.rr_order do
        state.rr_order
      else
        state.rr_order ++ [user_id]
      end

    new_state = %{state | user_queues: user_queues, rr_order: rr_order}

    # If we're *not* currently processing any segment, schedule one now
    if not state.processing do
      # Do *not* set processing to true here;
      # let :process_next do that if/when it actually pulls a segment.
      Process.send(self(), :process_next, [])
    end

    {:noreply, new_state}
  end

  # ------------------------------------------------------------------------------
  # 2) The main loop to pick + process the next segment
  # ------------------------------------------------------------------------------
  def handle_info(:process_next, state) do
    do_process_next(state)
  end

  # This is where we either pick a segment (if any) and start a Task,
  # or go idle if no segments remain.
  defp do_process_next(%{user_queues: uq, rr_order: rr} = state) do
    if rr == [] do
      # No users => no work
      Logger.debug("No more segments to process. Going idle.")
      {:noreply, %{state | processing: false}}
    else
      [current_user | rest] = rr

      case Map.get(uq, current_user) do
        nil ->
          # That user has no queue => remove them from rr_order, continue
          new_uq = Map.delete(uq, current_user)
          new_state = %{state | user_queues: new_uq, rr_order: rest}
          # Try the next user
          Process.send(self(), :process_next, [])
          {:noreply, new_state}

        user_q ->
          case :queue.out(user_q) do
            {{:value, {path, caller, seg_num}}, new_user_q} ->
              # We found a single segment to process
              new_uq =
                if :queue.is_empty(new_user_q) do
                  # No more segments left for current_user
                  Map.delete(uq, current_user)
                else
                  Map.put(uq, current_user, new_user_q)
                end

              new_rr =
                if Map.has_key?(new_uq, current_user) do
                  rest ++ [current_user]
                else
                  rest
                end

              # Mark that we are processing a segment (so we won't pick another immediately)
              new_state = %{
                state
                | user_queues: new_uq,
                  rr_order: new_rr,
                  processing: true
              }

              # Spawn a Task for concurrency, but do NOT schedule the next segment
              # until we receive :done from this Task.
              # task.async_stream will default to # of cores... ( interesting )
              # Task.Supervisor.async_stream_nolink is the non liked alternative
              # Although here is not that important because we wait on :done to schedule the next
              # So the Task here is just to not block the GenServer
              Task.start(fn ->
                tokens = do_transcription(path)
                send(caller, {:transcript, tokens, seg_num})
                # After finishing, inform the GenServer
                GenServer.cast(__MODULE__, :done)
              end)

              # We do NOT call :process_next again right now; we wait for :done
              {:noreply, new_state}

            {:empty, _} ->
              # This user's queue is empty => remove them from round-robin
              new_uq = Map.delete(uq, current_user)
              new_state = %{state | user_queues: new_uq, rr_order: rest}
              Process.send(self(), :process_next, [])
              {:noreply, new_state}
          end
      end
    end
  end

  # ------------------------------------------------------------------------------
  # 3) When a Task finishes, it sends :done => schedule the next
  # ------------------------------------------------------------------------------
  def handle_cast(:done, state) do
    # The last transcription finished => mark not processing
    new_state = %{state | processing: false}
    # Kick off next segment
    Process.send(self(), :process_next, [])
    {:noreply, new_state}
  end

  # ------------------------------------------------------------------------------
  # Nx.Serving call
  # ------------------------------------------------------------------------------
  defp do_transcription(path) do
    result = Nx.Serving.batched_run(WhisperServing, {:file, path})
    IO.inspect(result)
    #Enum.map_join(result.chunks, & &1.text) |> String.trim()
    result.chunks
  end
end
