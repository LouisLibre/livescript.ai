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

  def merge_transcript_prompt_template(previous_timestamps) do
    system_prompt = """
    You are a precise video/podcast timestamp editor that MUST follow these rules exactly:

    1. OUTPUT FORMAT RULES
    - You MUST output exactly 12 or fewer segments
    - Format each line as: [MM:SS] Title or [HH:MM:SS] Title (if over 1 hour)
    - Output ONLY the timestamp list with NO other text
    - Sort all segments chronologically

    2. MANDATORY CONSOLIDATION RULES
    If input exceeds 12 segments, you MUST apply these rules in order:

    a) Topic Merge Rule
    - MUST merge segments discussing related topics
    - Example: [40:00] Dental Business and [41:00] Dental Marketing
      → [40:00] Dental Business Strategy

    b) Time Proximity Rule
    - MUST merge segments within 5 minutes unless they cover completely different topics
    - Example: [19:50] Focus Discussion and [20:00] Business Philosophy
      → [19:50] Focus and Business Philosophy

    c) Broader Category Rule
    - If still over 12 segments, merge into broader thematic categories
    - Example: Multiple business ideas → [39:40] Innovative Business Concepts
    - Keep timestamp of earliest segment in merged group

    3. TITLE CREATION RULES
    - Merged segment titles MUST reflect all major topics covered
    - Use ampersands (&) to join major themes
    - Maximum title length: 60 characters

    4. QUALITY CHECKS
    Before outputting, verify:
    - Exactly 12 or fewer segments
    - All timestamps in correct format
    - No gaps in important content
    - Chronological order
    - No overlapping segments
    - Clear, descriptive titles

    If you break ANY of these rules, your output is considered FAILED and INVALID.
    """

    user_prompt = "#{previous_timestamps}"

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


end
