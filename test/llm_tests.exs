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

user_prompt = """
[00:00] Introduction of Sheel
[01:00] Sheel's Business Achievements
[02:00] Wedding in the Metaverse
[03:00] Newsletter Ventures
[04:00] iPod Mini Hustle Story
[10:00] Domain Auctions Overview
[10:43] Meeting the Co-Founder
[11:58] The Concept of Dot Collecting
[12:52] Living on a Dollar a Day in India
[19:50] Balancing Focus and Exploration [20:00] Startup Philosophy and Food Business
[21:00] Origin of Local Food Delivery
[23:00] Subscription Model for Food Delivery
[24:00] Expansion and Celebrity Endorsements
[28:00] Opportunities in Retirement Communities
[30:00] Business Opportunities in Senior Care
[31:22] Concerns About Nursing Home Costs
[33:00] Cultural Perspectives on Elder Care
[34:34] Idea for Yelp-Style Professional Services
[39:40] Concept for Simplified Dental Services
[40:00] Dental Whitening Business Model
[41:00] Pizza Concept for Hotels
[43:00] Challenges of High-Quality Ingredients
[45:00] Great Goose Vodka Story
[48:00] AI Tools Education Franchise Idea  [50:00] Weekly Coaching Sessions
[50:40] Organizational Coach Experience
[52:30] Discussion on Frugality
[55:28] Credit Card Strategies
[58:59] Stance on Bitcoin and Crypto  [01:00:00] Investment Perspectives on Stablecoins
[01:01:20] Discussion on Cash Transactions and Taxes
[01:03:00] Negotiation Tips for Discounts
[01:06:25] Personal Stories of Sales Experience
[01:09:24] Cruise Experience with Family[01:10:00] Episode Recommendation
[01:10:40] Couch Discussion
[01:11:27] Closing Remarks
"""

llm_messages = [
  %{role: "system", content: system_prompt},
  %{role: "user", content: user_prompt}
]

{:ok, %{body: llm_response}} =
  FileUploader.OpenAI.chat_completion(%{
    model: "gpt-4o-mini",
    messages: llm_messages
})

IO.inspect(llm_messages)
IO.inspect(llm_response, limit: :infinity)
