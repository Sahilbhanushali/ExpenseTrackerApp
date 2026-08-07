"""
parser.py — turns a free-text message like "1.5k myntra shirt" into a
structured transaction dict: {amount, category, note, type}.

Everything that's meant to be tweaked lives in the CATEGORY_KEYWORDS,
INCOME_KEYWORDS and FILLER_WORDS tables below — edit those, nothing else,
to teach the parser new merchants or a new currency's income words.
"""

import re
from datetime import date, timedelta

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

# Money that leaves/enters your pocket but isn't really spent/earned — it's
# expected back (or owed back). Checked before INCOME_KEYWORDS so "lent 500
# to a friend" doesn't get swept up by an unrelated income word.
LEND_KEYWORDS = ["lent", "loaned", "loan to", "lending"]
BORROW_KEYWORDS = ["borrowed", "took a loan", "loan from", "borrowing"]

# Words stripped out of the note after the amount is removed. Keep this
# list lowercase; matching is case-insensitive.
FILLER_WORDS = {
    "spent", "spend", "on", "for", "rs", "rupees", "rupee", "inr", "paid",
    "pay", "got", "of", "at", "the", "a", "an", "in", "to", "from",
    "lent", "loaned", "borrowed",
}

DEFAULT_CATEGORY = "other"

# ---------------------------------------------------------------------------
# Amount extraction
# ---------------------------------------------------------------------------

# Matches things like: 500  1,250  1.5k  2l  2.5L  rs 500  ₹500  500rs
# Captures: currency-ish prefix, the numeric part, and a k/l suffix.
# k/l each get their own (?![a-zA-Z]) so they don't eat the first letter of
# the next word — without it, "450 lunch" reads the "l" off "lunch" as a
# lakh multiplier and turns ₹450 into ₹4.5 crore. The lookahead is scoped to
# just those two single-letter alternatives (not the whole suffix group) so
# it doesn't also block a real currency suffix like "500rs".
_AMOUNT_RE = re.compile(
    r"""
    (?:rs\.?|inr|₹)?\s*          # optional currency prefix
    (?P<num>\d[\d,]*(?:\.\d+)?)  # the number itself, with optional commas/decimal
    \s*
    (?P<suffix>lakhs|lakh|lacs|lac|k(?![a-zA-Z])|l(?![a-zA-Z]))?  # optional magnitude suffix, not mid-word
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
# Retroactive dates — "yesterday 500 taxi", "780 groceries on 3rd aug"
# ---------------------------------------------------------------------------

_MONTH_NAMES = {
    "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
    "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
    "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10,
    "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
}
_MONTH_ALT = "|".join(sorted(_MONTH_NAMES, key=len, reverse=True))

_RELATIVE_DATE_RE = re.compile(
    r"\b(day before yesterday|yesterday|today)\b", re.IGNORECASE
)
_DAYS_AGO_RE = re.compile(r"\b(\d+)\s+days?\s+ago\b", re.IGNORECASE)
_ABS_DATE_RE = re.compile(
    rf"\bon\s+(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MONTH_ALT})\s*(\d{{4}})?\b",
    re.IGNORECASE,
)


def _find_date(message: str):
    """
    Returns (date_str: 'YYYY-MM-DD', span: (start, end)) for the first
    date phrase found — "on 3rd aug 2026", "5 days ago", "yesterday", "day
    before yesterday", "today" — checked in that priority order (explicit
    beats relative). Returns (None, None) if the message doesn't mention a
    date at all, so the caller should default to today.
    """
    m = _ABS_DATE_RE.search(message)
    if m:
        day = int(m.group(1))
        month = _MONTH_NAMES[m.group(2).lower()]
        year = int(m.group(3)) if m.group(3) else date.today().year
        try:
            return date(year, month, day).isoformat(), m.span()
        except ValueError:
            return None, None

    m = _DAYS_AGO_RE.search(message)
    if m:
        return (date.today() - timedelta(days=int(m.group(1)))).isoformat(), m.span()

    m = _RELATIVE_DATE_RE.search(message)
    if m:
        word = m.group(1).lower()
        offset = {"today": 0, "yesterday": 1, "day before yesterday": 2}[word]
        return (date.today() - timedelta(days=offset)).isoformat(), m.span()

    return None, None


def _remove_span(text: str, span) -> str:
    if not span:
        return text
    start, end = span
    return text[:start] + " " + text[end:]


# ---------------------------------------------------------------------------
# Category + type detection
# ---------------------------------------------------------------------------

# Plain "kw in message_lower" substring checks match inside unrelated words
# — "rd" (recurring deposit) matches inside "card", "rent" matches inside
# "different"/"parent"/"current", "bus" matches inside "business". \b keeps
# the match to whole words (or whole phrases, for multi-word keywords).
def _keyword_in(text_lower: str, keyword: str) -> bool:
    return re.search(r"\b" + re.escape(keyword.lower()) + r"\b", text_lower) is not None


def _detect_type(message_lower: str) -> str:
    for kw in LEND_KEYWORDS:
        if _keyword_in(message_lower, kw):
            return "lent"
    for kw in BORROW_KEYWORDS:
        if _keyword_in(message_lower, kw):
            return "borrowed"
    for kw in INCOME_KEYWORDS:
        if _keyword_in(message_lower, kw):
            return "income"
    return "expense"


# Picks up "...to <Name>" or "...from <Name>" so a lent/borrowed entry can
# be tied to a person without requiring the /lend /borrow commands. Best
# effort only — a plain name after to/from, not general NER.
_COUNTERPARTY_RE = re.compile(r"\b(?:to|from)\s+([A-Za-z][A-Za-z]*)")


def _extract_counterparty(message: str):
    m = _COUNTERPARTY_RE.search(message)
    return m.group(1).title() if m else None


def _detect_category(message_lower: str, extra_categories: dict = None) -> str:
    # User-defined categories/keywords are checked first, so /addcategory can
    # override a default classification (e.g. "vet" pulled into "pets"
    # instead of the default "health").
    if extra_categories:
        for category, keywords in extra_categories.items():
            for kw in keywords:
                if _keyword_in(message_lower, kw):
                    return category
    for category, keywords in CATEGORY_KEYWORDS.items():
        for kw in keywords:
            if _keyword_in(message_lower, kw):
                return category
    return DEFAULT_CATEGORY


def _build_note(message: str, amount_span) -> str:
    text = _remove_span(message, amount_span)

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
        {"amount": float | None, "category": str, "note": str, "type": str,
         "counterparty": str | None, "date": str}

    amount is None if no amount could be found at all (caller should treat
    this as "could not parse" and ask the user to rephrase).

    type is one of "expense", "income", "lent" (you gave money, expect it
    back) or "borrowed" (you received money, owe it back). counterparty is
    a best-effort "to/from <Name>" guess, only meaningful for lent/borrowed.

    date is 'YYYY-MM-DD' — today, unless the message names a date, e.g.
    "yesterday 500 taxi", "3 days ago 200 chai", "780 groceries on 3rd aug".

    extra_categories: optional {category: [keyword, ...]} to merge in on top
    of CATEGORY_KEYWORDS at call time — lets callers (bot.py) add user-defined
    categories/keywords from config.json without editing this file.
    """
    message = (message or "").strip()

    txn_date, date_span = _find_date(message)
    text = _remove_span(message, date_span)
    text_lower = text.lower()

    amount, span = _find_amount(text)
    category = _detect_category(text_lower, extra_categories)
    txn_type = _detect_type(text_lower)
    note = _build_note(text, span)

    if txn_type in ("lent", "borrowed"):
        out_category = "lending"
        counterparty = _extract_counterparty(text)
    else:
        out_category = category if txn_type == "expense" else "income"
        counterparty = None

    return {
        "amount": round(amount, 2) if amount is not None else None,
        "category": out_category,
        "note": note,
        "type": txn_type,
        "counterparty": counterparty,
        "date": txn_date or date.today().isoformat(),
    }


# Splits a message into multiple transactions when it's clearly listing more
# than one, e.g. "450 lunch and 200 auto". Not a comma, since commas are
# also thousands separators inside an amount ("1,250") — splitting on those
# would mangle the number. "and"/";"/newline don't have that ambiguity.
_SPLIT_RE = re.compile(r"\s*(?:\band\b|;|\n)\s*", re.IGNORECASE)


def parse_multi(message: str, extra_categories: dict = None) -> list:
    """
    Like parse_message, but returns a list of transaction dicts — more than
    one if the message looks like it's logging several things at once.

    Splits on "and"/";"/newline, then parses each piece. Only actually
    returns multiple entries if at least two pieces each had their own
    amount; otherwise (e.g. "coffee and snacks 300", where "and" is just
    part of one purchase's description, not a separator between two) it
    falls back to parsing the whole message as a single transaction, so a
    stray "and" in a note doesn't silently drop half of it.
    """
    message = (message or "").strip()
    parts = [p.strip() for p in _SPLIT_RE.split(message) if p.strip()]
    if len(parts) <= 1:
        return [parse_message(message, extra_categories)]

    parsed = [parse_message(p, extra_categories) for p in parts]
    valid = [p for p in parsed if p["amount"] is not None]
    if len(valid) < 2:
        return [parse_message(message, extra_categories)]
    return valid


# Best-effort extraction of "emi 10000 per month for 6 months" style
# phrasing, used only to point the user at /emi with a prefilled suggestion
# — never to auto-log. A normal parse_message on an EMI-worded message
# would grab the total purchase price (the first/only large number) and log
# it as this month's full expense, which is wrong: only one installment
# happened this month, not the whole purchase.
_EMI_RE = re.compile(
    r"emi.*?(?P<amt>[\d,]+(?:\.\d+)?)\s*(?:per\s*month|/\s*month|pm|monthly)?"
    r".*?(?P<months>\d+)\s*months?",
    re.IGNORECASE | re.DOTALL,
)


def detect_emi(message: str):
    """
    None if the message doesn't mention "emi" at all. Otherwise a dict —
    {"monthly_amount": float | None, "months": int | None} — with whatever
    could be pulled out of the phrasing, so the caller can prefill a
    suggested /emi command even from a partial match.
    """
    if not _keyword_in(message.lower(), "emi"):
        return None
    m = _EMI_RE.search(message)
    if not m:
        return {"monthly_amount": None, "months": None}
    return {
        "monthly_amount": float(m.group("amt").replace(",", "")),
        "months": int(m.group("months")),
    }


_TOTAL_LINE_RE = re.compile(r"\btotal\b", re.IGNORECASE)
_SUBTOTAL_LINE_RE = re.compile(r"\bsub[\s-]?total\b", re.IGNORECASE)


def parse_receipt_text(text: str, extra_categories: dict = None) -> dict:
    """
    Best-effort parse of OCR'd receipt text into the same shape as
    parse_message. Receipts usually list several numbers (subtotal, tax,
    total) — this prefers a line that says "total" but not "subtotal", and
    falls back to the largest number on the receipt (which is almost always
    the final total, since line items and tax are each smaller pieces of it).

    Always returns type "expense" and date today — OCR text has no notion
    of income vs. expense or a stated date, so those aren't guessed.
    """
    lines = [l.strip() for l in (text or "").splitlines() if l.strip()]

    amount = None
    for line in lines:
        if _TOTAL_LINE_RE.search(line) and not _SUBTOTAL_LINE_RE.search(line):
            amt, _ = _find_amount(line)
            if amt is not None:
                amount = amt
                break

    if amount is None:
        candidates = [a for a, _ in (_find_amount(l) for l in lines) if a is not None]
        if candidates:
            amount = max(candidates)

    full_text_lower = "\n".join(lines).lower()
    category = _detect_category(full_text_lower, extra_categories)
    note = lines[0][:40] if lines else ""

    return {
        "amount": round(amount, 2) if amount is not None else None,
        "category": category,
        "note": note,
        "type": "expense",
        "counterparty": None,
        "date": date.today().isoformat(),
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
