import yfinance as yf
from fuzzywuzzy import process

# A minimal mapping of common company names to tickers.
# In production, replace with a richer database or API.
COMPANY_TICKERS = {
    "apple": "AAPL",
    "microsoft": "MSFT",
    "google": "GOOGL",
    "alphabet": "GOOGL",
    "amazon": "AMZN",
    "meta": "META",
    "facebook": "META",
    "tesla": "TSLA",
    "netflix": "NFLX",
    "nvidia": "NVDA",
    "intel": "INTC",
    "amd": "AMD",
}

def detect_companies(text: str):
    words = text.lower().split()
    detected = set()

    for word in words:
        match, score = process.extractOne(word, COMPANY_TICKERS.keys())
        if score >= 85:  # high-confidence fuzzy match
            detected.add(match)

    return list(detected)

def fetch_prices(companies):
    results = {}
    for name in companies:
        ticker = COMPANY_TICKERS[name]
        try:
            data = yf.Ticker(ticker).history(period="1d")
            price = round(float(data["Close"].iloc[-1]), 2)
            results[name] = {"ticker": ticker, "price": price}
        except Exception:
            results[name] = {"ticker": ticker, "price": None}
    return results

def on_message(context, message):
    user_text = message["content"]
    companies = detect_companies(user_text)

    if not companies:
        return None  # Skill does not modify the response

    prices = fetch_prices(companies)

    # Append stock info to the agent’s final response
    enrichment = "\n\n📈 **Stock Prices for Mentioned Companies:**\n"
    for name, info in prices.items():
        if info["price"] is None:
            enrichment += f"- {name.title()} ({info['ticker']}): unavailable\n"
        else:
            enrichment += f"- {name.title()} ({info['ticker']}): ${info['price']}\n"

    return {
        "append_response": enrichment
    }

def main():
    return {
        "on_message": on_message
    }
