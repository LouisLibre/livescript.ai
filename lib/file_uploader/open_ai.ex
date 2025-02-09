# {:ok, %{body: response}} = FileUploader.OpenAI.chat_completion(%{ model: "gpt-3.5-turbo", messages: [%{role: "user", content: "Hello 3.5!"}] })
# FileUploader.OpenAI.chat_completion(%{ model: "gpt-3.5-turbo", stream: true, messages: [%{role: "user", content: "Hello 3.5!"}]},&IO.puts/1)
defmodule FileUploader.OpenAI do
  @chat_completions_url "https://api.openai.com/v1/chat/completions"

  def one_shot_prompt_template(user_transcript) do
    system_prompt = """
    Act as a professional video/podcast editor. Your task is to create timestamps and titles from a transcript. Follow ALL rules strictly.
    You must not add any explanations, apologies, or any text other than the exact required segment list.
    If you have any uncertainty, reflect that in the titles or the segmentation, but do not produce extra commentary.

    Rules for Timestamps:
    - Convert [HH:MM:SS] → [MM:SS].
    """

    user_prompt = """
    I have a video transcript covering the time range [00:00:00–00:10:00].

    **Your Tasks**:
    1. Identify the logical segments within this transcript (ideally 3-5 segments).
      - If fewer than 5 segments are present, output only the available segments.
      - If more than 5 segments are evident, choose the five most significant based on topic changes.

    2. For each segment, provide:
      - The exact timestamp from the transcript.
      - A concise title (3–8 words max).
      - Format: [MM:SS] Title.

    3. Output ONLY the formatted list of segments. NO extra text.

    **Rules**:
    - Use ONLY the timestamps that appear exactly in the transcript; do not approximate.
    - Split segments at topic shifts, speaker changes, or explicit breaks.
    - No commentary, no additional explanations.

    --
    **Example user input transcript chunk**:
    [00:00:00] "Now, let’s dive into case studies of AI bias..."
    [00:08:45] "Here’s an example from healthcare..."
    [... rest of chunk ...]
    --

    --
    **Example of the desired output**:
    [00:00] Case Studies of AI Bias
    [03:15] Ad Break
    [08:45] Healthcare Examples
    --

    **User Transcript (00:00–10:00)**:
    #{user_transcript}
    """

    {system_prompt, user_prompt}
  end

  def first_transcript_prompt_template(user_transcript, first_hh_mm_ss, last_hh_mm_ss) do
    system_prompt = """
    Act as a professional video/podcast editor. Your task is to create timestamps and titles for transcript chunks. Follow ALL rules strictly.
    You must not add any explanations, apologies, or any text other than the exact required segment list.
    If you have any uncertainty, reflect that in the titles or the segmentation, but do not produce extra commentary.

    Rules for Timestamps:
    - If HH = 0, convert [HH:MM:SS] → [MM:SS].
    - If HH > 0, preserve [HH:MM:SS].
    """

    user_prompt = """
    I have a video transcript chunk covering the time range [#{first_hh_mm_ss}–#{last_hh_mm_ss}].

    **Your Tasks**:
    1. Identify the logical segments within this transcript chunk (ideally 3–5 segments).
       - If fewer than 3 segments are present, output only the available segments.
       - If more than 5 segments are evident, choose the five most significant based on topic changes.

    2. For each segment, provide:
       - The exact timestamp from the transcript.
       - A concise title (3–8 words max).
       - Format: [MM:SS] Title  (or [HH:MM:SS] Title if hour > 0).

    3. Output ONLY the formatted list of segments. NO extra text.

    **Rules**:
    - Use ONLY the timestamps that appear exactly in the transcript; do not approximate.
    - Split segments at topic shifts, speaker changes, or explicit breaks.
    - No commentary, no additional explanations.

    **Example user input transcript chunk**:
    [00:00:00] "Now, let’s dive into case studies of AI bias..."
    [... rest of chunk ...]
    [00:03:15] "And now, a word from our sponsors..."
    [... rest of chunk ...]
    [00:08:45] "Here’s an example from healthcare..."
    [... rest of chunk ...]

    **Example of the desired output**:
    [00:00] Case Studies of AI Bias
    [03:15] Ad Break
    [08:45] Healthcare Examples

    **User Transcript Chunk (00:00–10:00)**:
    #{user_transcript}
    """

    {system_prompt, user_prompt}
  end

  def nth_transcript_prompt_template(user_transcript, first_hh_mm_ss, last_hh_mm_ss) do
    system_prompt = """
    Act as a professional video/podcast editor. Your task is to create timestamps and titles for transcript chunks. Follow ALL rules strictly.
    You must not add any explanations, apologies, or any text other than the exact required segment list.
    If you have any uncertainty, reflect that in the titles or the segmentation, but do not produce extra commentary.

    Rules for Timestamps:
    - If HH = 0, convert [HH:MM:SS] → [MM:SS].
    - If HH > 0, preserve [HH:MM:SS].
    """

    user_prompt = """
    Now, for your task I have a **new transcript chunk** covering the time range [#{first_hh_mm_ss}-#{last_hh_mm_ss}].

    **Task**:
    1. Identify logical segments within this **new transcript chunk** (ideally 3–5 segments).
      - If fewer than 3 segments are present, output only the available segments.
      - If more than 5 are evident, choose the five most significant based on topic changes.

    2. For each segment, provide:
      - The exact timestamp from the transcript.
      - A concise title (3–8 words max).
      - Format: [MM:SS] Title (or [HH:MM:SS] Title if hour > 0).

    3. **Rules**:
      - Use ONLY timestamps that appear exactly IN THIS TRANSCRIPT CHUNK; do not approximate or invent.
      - Split segments at topic shifts, speaker changes, or explicit breaks.
      - Output ONLY the formatted list of this chunk segments. NO extra text.

    ---

    **User Transcript Chunk [#{first_hh_mm_ss}-#{last_hh_mm_ss}]**:
    #{user_transcript}
    """

    {system_prompt, user_prompt}
  end

  def chat_completion(request) do
    Req.post(@chat_completions_url,
      json: request,
      auth: {:bearer, api_key()}
    )
  end

  def stream_chat_completion(request, callback) do
    Req.post(@chat_completions_url,
      json: request,
      auth: {:bearer, api_key()},
      into: fn {:data, data}, context ->
        callback.(data)
        {:cont, context}
      end
    )
  end

  defp api_key() do
    Application.get_env(:file_uploader, :openai)[:api_key]
  end

  merge_prompt = """
  system_prompt:
  Act as a professional video/podcast editor. Your task is to merge previously generated timestamps/titles from multiple transcript chunks into a single cohesive list. Follow ALL rules strictly.
  You must not add any explanations, apologies, or any text other than the exact required segment list.
  If you have any uncertainty, reflect that in the titles or segmentation, but do not produce extra commentary.

  Rules for Timestamps:
  - If HH = 0, convert [HH:MM:SS] → [MM:SS].
  - If HH > 0, preserve [HH:MM:SS].

  user_prompt:
  You have timestamps and titles from several transcript chunks. Merge them into one final timeline of segments. The final output should:

  1. **Combine** all segments from the chunks **in chronological order**, covering the full range from the first chunk's start time to the final chunk's end time.

  2. **Detect continuity**:
    - If a segment from one chunk directly continues in the next chunk (e.g., same topic, labeled "Part 2"), either merge them or clearly label them to reflect the continuation (e.g., "Healthcare Examples (Part 2)").

  3. **Resolve any overlaps or inconsistencies.**:
    - If two segments share nearly the same timestamps/titles, merge or remove duplicates so the final list has no redundancy.

  4. **Aim for a reasonable total number of segments** (around 6–12):
    - If there are many short segments with similar or related topics, combine them into broader chapters.

  5. **Maintain format**:
    - For each final segment, use `[MM:SS] Title` (or `[HH:MM:SS] Title` if hour > 0).
    - Do **not** invent or approximate timestamps; use only those given.

  6. **Output ONLY** the merged list of segments (no extra text).

  ---
  ### Example

  #### Example Input
  ```
  Previously Generated Segments:
  Chunk 1 ([00:00–10:00]):
  [00:00] Introduction to AI Bias
  [03:12] Early Healthcare Examples
  [07:50] Modern Healthcare Examples

  Chunk 2 ([10:00–20:00]):
  [10:00] Modern Healthcare Examples (Part 2)
  [14:20] New Speaker’s Perspective
  [18:05] Ad Break
  ```

  #### Example Output
  ```
  [00:00] Introduction to AI Bias
  [03:12] Early Healthcare Examples
  [07:50] Modern Healthcare Examples
  [14:20] New Speaker’s Perspective
  [18:05] Ad Break
  ```

  (Notice how the segments are merged chronologically, no duplicates are created, and continuation is handled appropriately)
  ---

  Now, below is the list of actual segments that need to be merged. Remember, the final output should follow the same format:

  All Previously Generated Segments:
  [PASTE_ALL_SEGMENT_LISTS_HERE]
  """


end
