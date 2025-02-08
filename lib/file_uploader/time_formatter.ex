defmodule TimeFormatter do
  def format_seconds_llm(total_seconds) do
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    "[#{pad(hours)}:#{pad(minutes)}:#{pad(seconds)}]"
  end

  def format_seconds_web(total_seconds) do
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    if hours > 0 do
      "(#{pad(hours)}:#{pad(minutes)}:#{pad(seconds)})"
    else
      "(#{pad(minutes)}:#{pad(seconds)})"
    end
  end

  defp pad(number) when number < 10 do
    "0#{number}"
  end

  defp pad(number) do
    "#{number}"
  end
end
