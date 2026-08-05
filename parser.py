"""
parser.py — turns a free-text message like "1.5k myntra shirt" into a
structured transaction dict: {amount, category, note, type}.

Everything that's meant to be tweaked lives in the CATEGORY_KEYWORDS,
INCOME_KEYWORDS and FILLER_WORDS tables below — edit those, nothing else,
to teach the parser new merchants or a new currency's income words.
"""

import re

# ---------------------------------------------------------------------------
# Editable tables
# ---------------------------------------------------------------------------

# Category -> list of keywords (lowercase, no punctuation). Longest match
# order doesn't matter; first category with any keyword hit wins, checked
# in the order below, so put more specific categories first if two ever
# overlap.
CATEGORY_KEYWORDS = {
    "travel": [
        "ola", "uber", "rapido", "metro", "petrol", "diesel", "fuel",
        "cab", "taxi", "auto", "bus", "train", "irctc", "flight",
        "indigo", "toll", "fastag", "parking",
    ],
    "food": [
        "swiggy", "zomato", "chai", "coffee", "restaurant", "dinner",
        "lunch", "breakfast", "starbucks", "dominos", "pizza", "burger",
        "cafe", "eatsure", "food", "snacks", "tea",
    ],
    "groceries": [
        "blinkit", "zepto", "instamart", "bigbasket", "grocery",
        "groceries", "dmart", "vegetables", "milk", "kirana",
    ],
    "clothes": [
        "myntra", "ajio", "shirt", "tshirt", "t-shirt", "jeans", "shoes",
        "footwear", "dress", "clothes", "clothing", "apparel", "zara",
        "h&m",
    ],
    "rent": [
        "rent", "landlord", "maintenance", "society maintenance",
    ],
    "bills": [
        "electricity", "wifi", "broadband", "recharge", "mobile bill",
        "water bill", "gas bill", "dth", "internet", "phone bill",
        "postpaid", "prepaid",
    ],
    "luxuries": [
        "netflix", "hotstar", "prime video", "movie", "bookmyshow",
        "spotify", "pvr", "inox", "party", "bar", "pub", "alcohol",
        "shopping",
    ],
    "fitness": [
        "gym", "gym membership", "fitness", "yoga", "workout", "trainer",
        "protein", "supplements", "cult.fit", "cultfit", "swimming",
        "badminton", "sports",
    ],
    "investments": [
        "sip", "etf", "stocks", "mutual fund", "mf", "zerodha", "groww",
        "invest", "investment", "nps", "ppf", "rd", "fd",
    ],
    "health": [
        "medicine", "pharmacy", "doctor", "hospital", "clinic",
        "medical", "apollo", "diagnostic", "checkup", "dentist",
    ],
    "education": [
        "course", "udemy", "coursera", "book", "books", "tuition",
        "fees", "school", "college", "exam",
    ],
}

# Any of these words appearing in the message flips type -> "income"
INCOME_KEYWORDS = [
    "salary", "salaried", "refund", "cashback",
    "received", "receive", "recieved", "recieve", "recevied",
    "credited", "credit", "bonus", "reimbursement", "reimbursed",
    "payout", "income", "interest", "dividend", "sold", "sale",
    "got paid", "earned", "earning",
]

# Words stripped out of the note after the amount is removed. Keep this
# list lowercase; matching is case-insensitive.
FILLER_WORDS = {
    "spent", "spend", "on", "for", "rs", "rupees", "rupee", "inr", "paid",
    "pay", "got", "of", "at", "the", "a", "an", "in", "to", "from",
}

DEFAULT_CATEGORY = "other"

# ---------------------------------------------------------------------------
# Amount extraction
# ---------------------------------------------------------------------------

# Matches things like: 500  1,250  1.5k  2l  2.5L  rs 500  ₹500  500rs
# Captures: currency-ish prefix, the numeric part, and a k/l suffix.
_AMOUNT_RE = re.compile(
    r"""
    (?:rs\.?|inr|₹)?\s*          # optional currency prefix
    (?P<num>\d[\d,]*(?:\.\d+)?)  # the number itself, with optional commas/decimal
    \s*
    (?P<suffix>k|l|lac|lacs|lakh|lakhs)?  # optional magnitude suffix
    \s*
    (?:rs\.?|/-|₹)?              # optional currency suffix (500rs, 500/-)
    """,
    re.IGNORECASE | re.VERBOSE,
)

_SUFFIX_MULTIPLIER = {
    "k": 1_000,
    "l": 100_000,
    "lac": 100_000,
    "lacs": 100_000,
    "lakh": 100_000,
    "lakhs": 100_000,
}


def _find_amount(message: str):
    """
    Returns (amount: float, span: (start, end)) for the first plausible
    amount found in the message, or (None, None) if nothing looks like
    an amount.
    """
    best = None
    for m in _AMOUNT_RE.finditer(message):
        num_str = m.group("num")
        if not num_str:
            continue
        # Skip bare numbers with no digits before a decimal (defensive).
        try:
            value = float(num_str.replace(",", ""))
        except ValueError:
            continue

        suffix = (m.group("suffix") or "").lower()
        if suffix:
            value *= _SUFFIX_MULTIPLIER[suffix]

        # Prefer the first match that has some signal (currency prefix,
        # suffix, or at least 2+ digits) over stray single digits.
        span = m.span()
        matched_text = message[span[0]:span[1]]
        has_signal = bool(suffix) or "rs" in matched_text.lower() or \
            "₹" in matched_text or "inr" in matched_text.lower() or \
            len(num_str.replace(",", "")) >= 2

        if best is None:
            best = (value, span, has_signal)
        elif has_signal and not best[2]:
            best = (value, span, has_signal)
        else:
            # keep first found; don't overwrite once we have a good one
            if best[2]:
                break

    if best is None:
        return None, None
    return best[0], best[1]


# ---------------------------------------------------------------------------
# Category + type detection
# ---------------------------------------------------------------------------

def _detect_type(message_lower: str) -> str:
    for kw in INCOME_KEYWORDS:
        if kw in message_lower:
            return "income"
    return "expense"


def _detect_category(message_lower: str, extra_categories: dict = None) -> str:
    # User-defined categories/keywords are checked first, so /addcategory can
    # override a default classification (e.g. "vet" pulled into "pets"
    # instead of the default "health").
    if extra_categories:
        for category, keywords in extra_categories.items():
            for kw in keywords:
                if kw in message_lower:
                    return category
    for category, keywords in CATEGORY_KEYWORDS.items():
        for kw in keywords:
            if kw in message_lower:
                return category
    return DEFAULT_CATEGORY


def _build_note(message: str, amount_span) -> str:
    text = message
    if amount_span:
        start, end = amount_span
        text = text[:start] + " " + text[end:]

    # tokenize on whitespace, drop punctuation, drop filler words
    tokens = re.findall(r"[A-Za-z]+", text)
    kept = [t for t in tokens if t.lower() not in FILLER_WORDS]

    if not kept:
        return ""
    return " ".join(kept)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def parse_message(message: str, extra_categories: dict = None) -> dict:
    """
    Parse a free-text message into a transaction dict:
        {"amount": float | None, "category": str, "note": str, "type": str}

    amount is None if no amount could be found at all (caller should treat
    this as "could not parse" and ask the user to rephrase).

    extra_categories: optional {category: [keyword, ...]} to merge in on top
    of CATEGORY_KEYWORDS at call time — lets callers (bot.py) add user-defined
    categories/keywords from config.json without editing this file.
    """
    message = (message or "").strip()
    message_lower = message.lower()

    amount, span = _find_amount(message)
    category = _detect_category(message_lower, extra_categories)
    txn_type = _detect_type(message_lower)
    note = _build_note(message, span)

    return {
        "amount": round(amount, 2) if amount is not None else None,
        "category": category if txn_type == "expense" else "income",
        "note": note,
        "type": txn_type,
    }


if __name__ == "__main__":
    # quick manual smoke test when run directly
    samples = [
        "spent 500 on ola",
        "swiggy 420 dinner",
        "1.5k myntra shirt",
        "got salary 75000",
        "2l invested in mutual fund",
        "rs 200 chai",
        "₹1,250 blinkit groceries",
        "500rs netflix",
        "paid 300 electricity bill",
    ]
    for s in samples:
        print(f"{s!r:45} -> {parse_message(s)}")
