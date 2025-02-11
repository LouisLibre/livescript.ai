defmodule FileUploaderWeb.UploadLive do
  use FileUploaderWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(message: "", count: 0)
     |> assign(:transcript_segments, [])
     |> assign(:visible_transcript_segments, [])
     |> assign(:visible_timestamps, [])
     |> assign(:active_tab, "overview")
     |> assign(:milestones_printed, 0) # Tracks how many 10-min milestones we have already flushed
     |> assign(:last_flushed_time, 0)  # The highest second mark (e.g. 125 seconds) we have flushed up to
     |> allow_upload(:file,
       accept: :any,
       max_file_size: 524_288_000,
       # 256kb
       chunk_size: 262_144,
       writer: fn _name, _entry, _socket ->
        IO.inspect("FileUploaderWeb.CustomUploadWriter writer called")
        {FileUploaderWeb.CustomUploadWriter, caller: self()}
       end,
       auto_upload: true  # Add this line
     )}
  end

  # transcript_generator.ex def handle_info({:DOWN,..
  @impl true
  def handle_info({_ref, :ok, total_count}, socket) do
    consume_uploaded_entries(socket, :file, fn meta, _entry -> {:ok, meta} end)
    {:noreply,
    socket
    |>assign(message: "FINISHED uploading/transcoding #{total_count} segments!", count: total_count)
    }
  end


  @impl true
  def handle_info({:transcript, tokens, segment_number}, socket) do
    IO.inspect("FileUploaderWeb.UploadLive handle_info {:transcript, tokens, segment_number: #{segment_number}")

    # The incoming tokens may be empty, but we need at least one token to start the process
    # and not break the logic for consecutive segments.
    # TODO: Fix the results of this on the UI, just don't show empty text segments.
    tokens_with_placeholder =
      case tokens do
        [] -> [%{text: "", start_timestamp_seconds: 0.0}]
        _  -> tokens
      end

    socket = Enum.reduce(tokens_with_placeholder, socket, fn token, acc_socket ->
      %{text: text, start_timestamp_seconds: start_timestamp_seconds} = token
      add_segment(acc_socket, segment_number, text, start_timestamp_seconds)
    end)
    #socket = add_segment(socket, segment_number, text)

    socket = if socket.assigns.count > 0 and
             max_chunk_id(socket.assigns.transcript_segments) == socket.assigns.count - 1 do
      socket = flush_final_chunk(socket)
      # Possibly log or set some final state:
      IO.puts("ALL segments have been received and flushed!")
      socket
    else
      socket
    end

    if segment_number == 0 do
      {:noreply,
       socket
       |> push_event("play-video", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply,
     socket
     |> stream(:transcript_segments, [], reset: true)
     |> assign(show_stream: false)
     |> assign(:active_tab, "transcript")
     |> assign(count: 0, message: "Uploading/Transcoding/Transcribing video...")}
     #     |> assign(active_tab: "transcript") # In case we want to switch to transcript tab immediately
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

    # Catch any other messages to prevent crashes
  @impl true
  def handle_info(msg, socket) do
    IO.inspect("FileUploaderWeb.UploadLive handle_info fallback")
    IO.inspect(msg)
    {:noreply, socket}
  end

  defp max_chunk_id(segments) do
    case segments do
      [] -> 0
      segs -> segs |> Enum.map(& &1.chunk_id) |> Enum.max()
    end
  end

  def parse_timestamp(time_str) do
    [minutes, seconds] = String.split(time_str, ":")
    String.to_integer(minutes) * 60 + String.to_integer(seconds)
  end

  @impl true
  def render(assigns) do
    ~H"""
        <div class="min-h-screen bg-gray-100 text-gray-800 p-4 flex items-start justify-center font-mono">
        <div class="grid lg:grid-cols-[6fr_5fr] gap-4 max-w-[1600px] w-full h-[calc(100vh-2rem)]">
          <div class="space-y-4 flex flex-col max-h-full left-sidebar">

                <div id="left_sidebar" phx-update="ignore"  class="relative bg-white rounded-lg border border-gray-200 shadow-sm">
                <div class="initial-state flex flex-col items-center justify-center pt-12 pb-24">
                  <div class="orb-container flex items-center justify-center">
                    <div class="orb"></div>
                  </div>
                  <div class="orb-copy font-mono">

                  </div>
                  </div>
                </div>
                <div class="border border-gray-200 rounded-lg space-y-4 bg-white shadow-sm h-[calc(100vh-24rem-2rem)] flex flex-col">
                <div class="w-full bg-gray-100 border-b border-gray-200 flex bg-gray-50">
                  <button class=' py-2 px-4 text-sm font-medium bg-gray-50'>
                    Summary
                  </button>
                </div>
                  <skeleton-loader class="px-3 w-1/2" height="24px"></skeleton-loader>
                  <skeleton-loader class="px-3 pr-6" count="3"></skeleton-loader>

                </div>
          </div>

          <div class="border border-gray-300 rounded-lg bg-white shadow-md overflow-hidden flex flex-col h-full">
            <div class="w-full bg-gray-100 border-b border-gray-200 flex">
              <button
                phx-click="set_tab"
                phx-value-tab="overview"
                class={"flex-1 py-2 px-4 text-sm font-medium " <>
                if @active_tab == "overview", do: "bg-white", else: ""}>
                Overview
              </button>
              <button
              phx-click="set_tab"
              phx-value-tab="transcript"
              class={"flex-1 py-2 px-4 text-sm font-medium " <>
              if @active_tab == "transcript", do: "bg-white", else: ""}>
                Transcript
              </button>

              <button
              phx-click="set_tab"
              phx-value-tab="timestamps"
              class={"flex-1 py-2 px-4 text-sm font-medium " <>
              if @active_tab == "timestamps", do: "bg-white", else: ""}>
              Timestamps
              </button>
            </div>

            <div class="flex-1 overflow-hidden flex flex-col">



              <div class="flex-1 overflow-y-auto p-4">

            <!-- (2) OVERVIEW TAB PANEL (always rendered, just hidden if inactive) -->
            <div class={if @active_tab == "overview", do: "block", else: "hidden"}>
              <div class="space-y-4">
                <h2 class="text-xl font-semibold">Welcome!</h2>
                <ul class="list-disc list-inside space-y-1 text-gray-700">
                  <li>Step 1: Choose a video file to upload.</li>
                  <li>Step 2: Pay on-demand invoice.</li>
                  <li>Step 3: Real-time stream transcript begins.</li>
                  <li>Step 4: Summary & Timestamps at end.</li>
                </ul>

                <.form for={%{}} phx-change="validate" phx-submit="save">
                  <div id="live-file-input-parent" phx-hook="UploadParentDiv">
                    <.live_file_input upload={@uploads.file} />
                  </div>
                  <div :for={entry <- @uploads.file.entries}>
                    <div class="w-full bg-gray-200 rounded-full h-2.5 mb-2">
                      <div class="bg-blue-600 h-2.5 rounded-full"
                            style={"width: #{entry.progress}%"}></div>
                    </div>
                  </div>
                  <p class="mt-2"><%= @message %></p>

                </.form>
              </div>
            </div>

            <div class={if @active_tab == "timestamps", do: "block", else: "hidden"}>
              <div class="space-y-6">
                <div
                  id="timestamps-skeleton"
                  class="space-y-2"
                >
                  <%= for timestamp_group <- @visible_timestamps do %>
                    <div class="space-y-2">
                      <%= for entry <- String.split(timestamp_group, "\n") do %>
                        <%= if Regex.match?(~r/\[([\d:]+)\](.+)/, entry) do %>
                          <% [_, time, text] = Regex.run(~r/\[([\d:]+)\](.+)/, entry) %>
                          <div class="group flex gap-2">
                            <button class="text-sm text-gray-500 hover:text-gray-700">
                              [<%= time %>]
                            </button>
                            <p
                              id={"text-#{parse_timestamp(time)}"}
                              phx-hook="SeekOnClick"
                              data-start-time={parse_timestamp(time)}
                              class="text-sm group-hover:text-gray-900 transition-colors hover:bg-yellow-100 hover:cursor-pointer"
                            >
                              <%= String.trim(text) %>
                            </p>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                  <skeleton-loader class={
                      if @count > 0 and max_chunk_id(@transcript_segments) == @count - 1,
                        do: "hidden",
                        else: "px-3"
                      } count="3"></skeleton-loader>
                </div>
              </div>
            </div>

            <div class={if @active_tab == "transcript", do: "block", else: "hidden"}>
                <div class="space-y-6">
                    <div class="space-y-2" :for={seg <- @visible_transcript_segments}>
                      <div data-id={"#{seg.chunk_id}"} class={"group flex gap-2 #{if seg.text == "", do: "hidden", else: ""}"}>
                        <button
                          class="text-sm text-gray-500 hover:text-gray-700"
                        >
                          {seg.text_start_time_formatted}
                        </button>
                        <p
                          id={"text-#{seg.chunk_id}"}
                          phx-hook="SeekOnClick"
                          data-start-time={seg.text_start_time}
                          class="text-sm group-hover:text-gray-900 transition-colors hover:bg-yellow-100 hover:cursor-pointer"
                        >
                          { seg.text}
                        </p>
                      </div>
                    </div>
                    <div
                      id="timescript-skeleton"
                      data-length={length(@transcript_segments)}
                      data-count={@count}
                      class={
                      if @count > 0 and max_chunk_id(@transcript_segments) == @count - 1,
                        do: "hidden",
                        else: "space-y-2"
                      }
                      >
                      <skeleton-loader class="px-3" count="3"></skeleton-loader>
                    </div>
                </div>
              </div>
              </div>
            </div>

          </div>
          </div>
        </div>
    """
  end

  defp add_segment(socket, index, text, text_start_time) do
    # 1) Build the new segment
    text_start_time = trunc(text_start_time + (index * 20))

    new_segment = %{
      chunk_id: index,
      text: text,
      text_start_time: text_start_time,
      text_start_time_formatted: TimeFormatter.format_seconds_web(text_start_time)
    }

    # 2) Add the new segment to the list, ( and remove duplicates ( maybe not needed ) )
    all_segments = socket.assigns.transcript_segments
    updated = [new_segment | all_segments]
    |> Enum.uniq_by(& &1.text_start_time)

    # 2) Sort by index
    sorted = Enum.sort_by(updated, & &1.text_start_time)

    # 3) Keep only contiguous from chunk_id=0..N
    max_consecutive =
      sorted
      |> Enum.map(& &1.chunk_id)
      |> largest_consecutive_seq()

    visible = Enum.filter(sorted, &(&1.chunk_id <= max_consecutive))

    # 4) Flush every 10 minutes
    socket =
      case List.last(visible) do
        nil -> socket
        last_segment -> maybe_flush(socket, visible, last_segment.text_start_time)
      end

    socket
    |> assign(:transcript_segments, sorted)
    |> assign(:visible_transcript_segments, visible)
  end

  defp maybe_flush(socket, visible_segments, last_visible_time) do
    IO.puts("maybe_flush: last_visible_time: #{last_visible_time}")
    old_milestones = socket.assigns.milestones_printed
    new_milestones = div(last_visible_time, 600)

    if new_milestones > old_milestones do
      milestone_range = (old_milestones + 1)..new_milestones

      updated_socket =
        Enum.reduce(milestone_range, socket, fn milestone, acc_socket ->
          boundary = milestone * 600
          chunk_string = process_transcript_chunk(acc_socket, visible_segments, acc_socket.assigns.last_flushed_time, boundary, false)

          if is_binary(chunk_string) do
            current_visible_timestamps = acc_socket.assigns[:visible_timestamps] || []
            new_visible_timestamps = current_visible_timestamps ++ [chunk_string]

            acc_socket
            |> assign(:visible_timestamps, new_visible_timestamps)
            |> assign(:last_flushed_time, boundary)
          else
            acc_socket
          end
        end)

      updated_socket
      |> assign(:milestones_printed, new_milestones)
    else
      socket
    end

  end

  defp flush_final_chunk(socket) do
    IO.puts("flush_final_chunk")
    final_time =
      socket.assigns.transcript_segments
      |> Enum.map(& &1.text_start_time)
      |> Enum.max(fn -> 0 end)  # fallback to 0 if no segments

    last_flushed_time = socket.assigns.last_flushed_time

    if final_time > last_flushed_time do
      # TODO: let process_transcript_chunk know this is the final chunk
      timestamps = process_transcript_chunk(socket, socket.assigns.transcript_segments, last_flushed_time, final_time, true)
      IO.puts("Flushed final chunk from ~#{last_flushed_time} to ~#{final_time} seconds.")
      IO.inspect(timestamps)

      current_visible_timestamps = socket.assigns[:visible_timestamps] || []
      new_visible_timestamps = current_visible_timestamps ++ [timestamps]

      socket
      |> assign(:last_flushed_time, final_time)
      |> assign(:visible_timestamps, new_visible_timestamps)
    else
      socket
    end
  end

  # This one will be called for one-shotting the timestamps
  # It pattern matches when the chunk is the final one and  0 milestone were flushed
  defp process_transcript_chunk(
       %{assigns: %{milestones_printed: milestones}} = socket,
       segments,
       from_seconds,
       to_seconds,
       is_final
     ) do
    IO.puts("process_transcript_chunk called: from #{from_seconds} to #{to_seconds} (final? #{is_final})")

    # 1. Decide which segments to include.
    chunk_segments =
      cond do
        is_final and milestones == 0 ->
          # "First and final" scenario: take them all
          segments

        true ->
          # Otherwise, standard chunking by from/to
          Enum.filter(segments, fn seg ->
            seg.text_start_time >= from_seconds and seg.text_start_time <= to_seconds
          end)
      end

    # 2. Handle a possible empty chunk.
    if chunk_segments == [] do
      IO.puts("No segments found in this chunk. Skipping processing...")
      # Return the socket unchanged in this example
      socket
    else
      # 3. Build the final text output that we'll feed to the prompt.
      output =
        chunk_segments
        |> Enum.map_join("\n", fn seg ->
          "[#{TimeFormatter.format_seconds_llm(seg.text_start_time)}] #{seg.text}"
        end)

      # 4. Choose which prompt template to use.
      {system_prompt, user_prompt} =
        case {milestones, is_final} do
          {0, true} ->
            IO.puts("About to process first AND final transcript chunk.")
            FileUploader.OpenAI.one_shot_prompt_template(output)

          {0, false} ->
            IO.puts("Processing first chunk of the transcript.")
            first_start = TimeFormatter.format_seconds_llm(List.first(chunk_segments).text_start_time, false)
            last_start  = TimeFormatter.format_seconds_llm(List.last(chunk_segments).text_start_time, false)
            FileUploader.OpenAI.first_transcript_prompt_template(output, first_start, last_start)

          {_, _} ->
            IO.puts("Processing nth chunk of the transcript.")
            first_start = TimeFormatter.format_seconds_llm(List.first(chunk_segments).text_start_time, false)
            last_start  = TimeFormatter.format_seconds_llm(List.last(chunk_segments).text_start_time, false)
            FileUploader.OpenAI.nth_transcript_prompt_template(output, first_start, last_start)
        end

      # 5. Send to the LLM.
      llm_messages = [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_prompt}
      ]

      {:ok, %{body: llm_response}} =
        FileUploader.OpenAI.chat_completion(%{
          model: "gpt-4o-mini",
          messages: llm_messages
        })

      %{
        "choices" => [
          %{"message" => %{"content" => content}}
        ]
      } = llm_response

      # 6. Log the final result
      IO.puts("Received content: #{content}")
      IO.puts("FLUSHING transcript (from=#{from_seconds}, to=#{to_seconds}, final?=#{is_final}):")
      IO.inspect(llm_messages)
      IO.inspect(llm_response)

      # 7. Update the socket, appending the LLM content to `:visible_timestamps`.
      #
      #    If you prefer to *prepend*, you can do `[content | &1]` instead.
      content
    end
  end


   # Given a list of indexes (already sorted), find the largest consecutive run
  # starting at 1. For example:
  #
  #   [1,2,3] => 3
  #   [1,2,4,6,7] => 2 (since 3 is missing)
  #   [2,3,4,5] => 0 (since 1 is missing, no consecutive run from 1)
  #
  defp largest_consecutive_seq(indexes) do
    indexes
    |> Enum.reduce_while(1, fn
      x, expected when x == expected -> {:cont, expected + 1}
      x, expected when x > expected  -> {:halt, expected}
      _, expected                   -> {:cont, expected}
    end)
    |> then(&(&1 - 1))
  end


  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "Unacceptable file type"
end
