---
name: stock-price-enricher
description: Detects company names mentioned in a user's message, fetches their current stock prices, and appends the results to the agent's final response.
---
# Stock Price Enricher Skill: 

# Triggers
This skill activates whenever the user message contains any token that could be interpreted as a company name.

triggers:
  - type: message
    pattern: ".*"   # Always run; filtering happens in logic

# Runtime Requirements

requirements:
  python: ">=3.10"
  packages:
    - yfinance
    - fuzzywuzzy
    - python-Levenshtein

# Skill Logic
entrypoint: main.py