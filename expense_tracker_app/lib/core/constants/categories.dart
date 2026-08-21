/// Port of expense_bot/parser.py's CATEGORY_KEYWORDS/INCOME_KEYWORDS/etc.
/// Edit these tables to teach the parser new merchants — nothing else.
const Map<String, List<String>> kCategoryKeywords = {
  'travel': [
    'ola', 'uber', 'rapido', 'metro', 'petrol', 'diesel', 'fuel',
    'cab', 'taxi', 'auto', 'bus', 'train', 'irctc', 'flight',
    'indigo', 'toll', 'fastag', 'parking',
  ],
  'food': [
    'swiggy', 'zomato', 'chai', 'coffee', 'restaurant', 'dinner',
    'lunch', 'breakfast', 'starbucks', 'dominos', 'pizza', 'burger',
    'cafe', 'eatsure', 'food', 'snacks', 'tea',
  ],
  'groceries': [
    'blinkit', 'zepto', 'instamart', 'bigbasket', 'grocery',
    'groceries', 'dmart', 'vegetables', 'milk', 'kirana',
  ],
  'clothes': [
    'myntra', 'ajio', 'shirt', 'tshirt', 't-shirt', 'jeans', 'shoes',
    'footwear', 'dress', 'clothes', 'clothing', 'apparel', 'zara', 'h&m',
  ],
  'rent': ['rent', 'landlord', 'maintenance', 'society maintenance'],
  'bills': [
    'electricity', 'wifi', 'broadband', 'recharge', 'mobile bill',
    'water bill', 'gas bill', 'dth', 'internet', 'phone bill',
    'postpaid', 'prepaid',
  ],
  'luxuries': [
    'netflix', 'hotstar', 'prime video', 'movie', 'bookmyshow',
    'spotify', 'pvr', 'inox', 'party', 'bar', 'pub', 'alcohol', 'shopping',
  ],
  'fitness': [
    'gym', 'gym membership', 'fitness', 'yoga', 'workout', 'trainer',
    'protein', 'supplements', 'cult.fit', 'cultfit', 'swimming', 'badminton', 'sports',
  ],
  'investments': [
    'sip', 'etf', 'stocks', 'mutual fund', 'mf', 'zerodha', 'groww',
    'invest', 'investment', 'nps', 'ppf', 'rd', 'fd',
  ],
  'health': [
    'medicine', 'pharmacy', 'doctor', 'hospital', 'clinic', 'medical',
    'apollo', 'diagnostic', 'checkup', 'dentist',
  ],
  'education': ['course', 'udemy', 'coursera', 'book', 'books', 'tuition', 'fees', 'school', 'college', 'exam'],
};

const List<String> kIncomeKeywords = [
  'salary', 'salaried', 'refund', 'cashback',
  'received', 'receive', 'recieved', 'recieve', 'recevied',
  'credited', 'credit', 'bonus', 'reimbursement', 'reimbursed',
  'payout', 'income', 'interest', 'dividend', 'sold', 'sale',
  'got paid', 'earned', 'earning',
];

const List<String> kLendKeywords = ['lent', 'loaned', 'loan to', 'lending'];
const List<String> kBorrowKeywords = ['borrowed', 'took a loan', 'loan from', 'borrowing'];

const Set<String> kFillerWords = {
  'spent', 'spend', 'on', 'for', 'rs', 'rupees', 'rupee', 'inr', 'paid',
  'pay', 'got', 'of', 'at', 'the', 'a', 'an', 'in', 'to', 'from',
  'lent', 'loaned', 'borrowed',
};

const String kDefaultCategory = 'other';

/// A rule-of-thumb monthly split — needs/wealth/wants — port of bot.py's
/// RECOMMENDED_ALLOCATION. (category -> (bucket, fraction of budget))
const Map<String, (String, double)> kRecommendedAllocation = {
  'rent': ('needs', 0.28),
  'bills': ('needs', 0.05),
  'groceries': ('needs', 0.10),
  'health': ('needs', 0.04),
  'travel': ('needs', 0.05),
  'investments': ('wealth', 0.20),
  'food': ('wants', 0.08),
  'fitness': ('wants', 0.05),
  'clothes': ('wants', 0.04),
  'luxuries': ('wants', 0.06),
  'education': ('wants', 0.03),
  'other': ('wants', 0.02),
};

const Map<String, String> kBucketTitle = {
  'needs': 'Needs (essentials)',
  'wealth': 'Wealth-building',
  'wants': 'Wants (life you love)',
};
