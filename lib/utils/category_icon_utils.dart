String normalizeCategoryKey(String? categoryName) {
  return (categoryName ?? '').trim().toLowerCase();
}

const Map<String, String> kDefaultCategoryIcons = {
  'food': '🍔',
  'groceries': '🛒',
  'transport': '🚌',
  'accommodation': '🏠',
  'accomodation': '🏠',
  'entertainment': '🎬',
  'furniture': '🛋️',
  'cleaning & hygiene': '🧹',
  'water': '💧',
  'shopping': '🛍',
  'restaurants': '🍝',
  'restaurant': '🍝',
  'rent': '🏡',
  'transfer': '💸',
  'transfered': '💸',
  'other': '🧾',
  'salary': '💰',
  'freelance': '💻',
  'investment': '📈',
  'refund': '🔄',
  'gift': '🎁',
};

String categoryIconForName(String? categoryName) {
  // Intentionally hard-coded by category name.
  final key = normalizeCategoryKey(categoryName);
  return kDefaultCategoryIcons[key] ?? '🧾';
}
