const List<String> grocerySubcategories = [
  'Atta, Rice & Dal',
  'Oil, Ghee & Masala',
  'Dairy & Eggs',
  'Bakery & Biscuits',
  'Dry Fruits & Cereals',
  'Chicken, Meat & Fish',
  'Kitchenware',
  'Chips & Namkeen',
  'Sweets & Chocolates',
  'Drinks & Juices',
  'Tea, Coffee & Milk',
  'Instant Food',
  'Sauces & Spreads',
  'Ice Creams',
];

const List<String> vegetableSubcategories = [
  'Fresh Vegetables',
  'Leafy Greens',
  'Cut & Packed',
];

const List<String> fruitSubcategories = [
  'Fresh Fruits',
  'Cut & Packed',
];

const List<String> foodSubcategories = [
  'Pizza',
  'Burger',
  'Biryani',
  'Chinese',
  'Rolls',
  'Beverages',
];

const List<String> giftSubcategories = [
  'Birthday',
  'Anniversary',
  'Flowers',
  'Teddy',
  'Cakes',
  'Chocolates',
  'Surprise Box',
];

const List<String> beautySubcategories = [
  'Bath & Body',
  'Hair Care',
  'Skin Care',
  'Cosmetics',
  'Baby Care',
  'Health',
];

const List<String> electronicsSubcategories = [
  'Mobile Accessories',
  'Chargers',
  'Earphones',
  'Power Banks',
  'Smart Gadgets',
];

const List<String> householdSubcategories = [
  'Cleaning & Laundry',
  'Kitchen Essentials',
  'Bathroom Essentials',
  'Storage & Organizers',
  'Cleaning Tools',
  'Tissue & Paper Products',
  'Garbage Bags',
  'Mosquito & Pest Control',
  'Home Utility',
];

const List<String> petSubcategories = [
  'Food',
  'Toys',
  'Grooming',
  'Healthcare',
  'Accessories',
];

const List<String> partySubcategories = [
  'Decor',
  'Candles',
  'Balloons',
  'Tableware',
  'Cake Accessories',
];

const List<String> printSubcategories = [
  'Documents',
  'Photos',
  'Cards',
  'Stickers',
  'Banners',
];

const List<String> pujaSubcategories = [
  'Puja Essentials',
  'Incense & Dhoop',
  'Diyas & Candles',
  'Puja Flowers',
  'Puja Utensils',
  'Prasad & Bhog Items',
  'Festival Specials',
];

const List<String> fishAndMeatSubcategories = [
  'Fish',
  'Chicken',
];

const Map<String, List<String>> categorySubcategoryMap = {
  'Grocery': grocerySubcategories,
  'Vegetables': vegetableSubcategories,
  'Fruits': fruitSubcategories,
  'Food': foodSubcategories,
  'Gifts': giftSubcategories,
  'Gifts & Surprises': ['Surprise your loved ones'],
  'Cosmetics': beautySubcategories,
  'Electronics': electronicsSubcategories,
  'Household Essentials': householdSubcategories,
  'Puja Items': pujaSubcategories,
  'Fish & Meat': fishAndMeatSubcategories,
};

const Map<String, List<String>> subcategoryChildCategoryMap = {
  'Atta, Rice & Dal': [
    'Atta',
    'Rice',
    'Dal',
    'Flours',
  ],
  'Oil, Ghee & Masala': [
    'Cooking Oils',
    'Ghee',
    'Whole Spices',
    'Blended Masala',
  ],
  'Fruits & Vegetables': [
    'Fresh Fruits',
    'Fresh Vegetables',
    'Leafy Greens',
    'Cut & Packed',
  ],
  'Fresh Vegetables': [
    'Root Vegetables',
    'Green Vegetables',
    'Seasonal Vegetables',
    'Other Vegetables',
  ],
  'Leafy Greens': [
    'Spinach',
    'Coriander',
    'Fenugreek',
    'Other Leafy Greens',
  ],
  'Fresh Fruits': [
    'Seasonal Fruits',
    'Citrus Fruits',
    'Tropical Fruits',
    'Other Fruits',
  ],
  'Cut & Packed': [
    'Cut Fruits',
    'Cut Vegetables',
    'Mixed Packs',
  ],
  'Dairy, Bread & Eggs': [
    'Milk',
    'Bread & Pav',
    'Eggs',
    'Curd & Yogurt',
    'Cheese & Butter',
    'Batter',
    'Paneer & Tofu',
    'Soy Milk & More',
    'Lassi & Milkshakes',
    'Cream & Whitener',
  ],
  'Dairy & Eggs': [
    'Milk',
    'Bread & Pav',
    'Eggs',
    'Curd & Yogurt',
    'Cheese & Butter',
    'Batter',
    'Paneer & Tofu',
    'Soy Milk & More',
    'Lassi & Milkshakes',
    'Cream & Whitener',
  ],
  'Bakery & Biscuits': [
    'Biscuits',
    'Cookies',
    'Cakes & Pastries',
    'Breads',
  ],
  'Dry Fruits & Cereals': [
    'Dry Fruits',
    'Nuts & Seeds',
    'Breakfast Cereals',
    'Muesli & Oats',
  ],
  'Chicken, Meat & Fish': [
    'Chicken',
    'Mutton',
    'Fish',
    'Ready to Cook',
  ],
  'Kitchenware': [
    'Cookware',
    'Storage Containers',
    'Utensils',
    'Cleaning Tools',
  ],
  'Chips & Namkeen': [
    'Potato Chips',
    'Namkeen Mixes',
    'Bhujia & Sev',
    'Roasted Snacks',
  ],
  'Sweets & Chocolates': [
    'Indian Sweets',
    'Chocolate Bars',
    'Gift Packs',
    'Sugar-Free Sweets',
  ],
  'Drinks & Juices': [
    'Fruit Juices',
    'Soft Drinks',
    'Energy Drinks',
    'Flavored Water',
  ],
  'Tea, Coffee & Milk': [
    'Tea',
    'Coffee',
    'Milk Drinks',
    'Premixes',
  ],
  'Instant Food': [
    'Noodles & Pasta',
    'Ready Meals',
    'Soup Mixes',
    'Frozen Snacks',
  ],
  'Sauces & Spreads': [
    'Ketchup & Sauces',
    'Mayonnaise',
    'Jams & Spreads',
    'Dips',
  ],
  'Ice Creams': [
    'Cups & Cones',
    'Family Packs',
    'Kulfi',
    'Frozen Desserts',
  ],
  'Restaurant Food': [
    'North Indian',
    'South Indian',
    'Combo Meals',
    'Thali',
  ],
  'Fast Food': [
    'Burgers',
    'Fries',
    'Sandwiches',
    'Wraps',
  ],
  'Pizza': [
    'Veg Pizza',
    'Non-Veg Pizza',
    'Cheese Burst',
    'Pizza Combos',
  ],
  'Burger': [
    'Veg Burger',
    'Chicken Burger',
    'Double Patty',
    'Burger Combos',
  ],
  'Biryani': [
    'Chicken Biryani',
    'Mutton Biryani',
    'Veg Biryani',
    'Family Packs',
  ],
  'Chinese': [
    'Noodles',
    'Fried Rice',
    'Manchurian',
    'Combo Boxes',
  ],
  'Rolls': [
    'Egg Rolls',
    'Chicken Rolls',
    'Paneer Rolls',
    'Kathi Rolls',
  ],
  'Beverages': [
    'Cold Beverages',
    'Hot Beverages',
    'Shakes',
    'Mocktails',
  ],
  'Sweets': [
    'Rasgulla',
    'Gulab Jamun',
    'Kheer',
    'Halwa',
  ],
  'Birthday': [
    'Birthday Cakes',
    'Birthday Flowers',
    'Birthday Hampers',
    'Personalized Gifts',
  ],
  'Anniversary': [
    'Anniversary Cakes',
    'Bouquets',
    'Romantic Gift Sets',
    'Custom Keepsakes',
  ],
  'Flowers': [
    'Roses',
    'Mixed Bouquets',
    'Orchids',
    'Flower Baskets',
  ],
  'Teddy': [
    'Small Teddy',
    'Medium Teddy',
    'Large Teddy',
    'Teddy Combos',
  ],
  'Cakes': [
    'Eggless Cakes',
    'Chocolate Cakes',
    'Designer Cakes',
    'Photo Cakes',
  ],
  'Chocolates': [
    'Chocolate Boxes',
    'Premium Chocolates',
    'Assorted Packs',
    'Chocolate Bouquets',
  ],
  'Surprise Box': [
    'Mini Surprise Box',
    'Premium Surprise Box',
    'Custom Surprise Box',
    'Couple Surprise Box',
  ],
  'Soft Toys': [
    'Small Soft Toys',
    'Character Toys',
    'Heart Cushions',
    'Combo Packs',
  ],
  'Gift Combos': [
    'Cake + Flowers',
    'Chocolate + Teddy',
    'Perfume + Card',
    'Custom Combo',
  ],
  'Surprise your loved ones': [
    'Midnight Surprise',
    'Romantic Surprise',
    'Birthday Surprise',
    'Custom Surprise',
  ],
  'Bath & Body': [
    'Body Wash',
    'Soaps',
    'Body Lotion',
    'Body Scrub',
  ],
  'Hair Care': [
    'Shampoo',
    'Conditioner',
    'Hair Oil',
    'Hair Serum',
  ],
  'Skin Care': [
    'Face Wash',
    'Moisturizer',
    'Sunscreen',
    'Face Masks',
  ],
  'Cosmetics': [
    'Lipsticks',
    'Foundations',
    'Kajal & Eyeliner',
    'Makeup Kits',
  ],
  'Beauty Products': [
    'Makeup',
    'Skincare Essentials',
    'Fragrances',
    'Nail Care',
  ],
  'Baby Care': [
    'Baby Lotion',
    'Baby Powder',
    'Baby Wipes',
    'Baby Shampoo',
  ],
  'Health': [
    'Supplements',
    'First Aid',
    'Personal Hygiene',
    'Wellness Products',
  ],
  'Mobile Accessories': [
    'Mobile Covers',
    'Screen Guards',
    'Holders & Mounts',
    'Data Cables',
  ],
  'Chargers': [
    'Fast Chargers',
    'Type-C Chargers',
    'Wireless Chargers',
    'Car Chargers',
  ],
  'Earphones': [
    'Wired Earphones',
    'Bluetooth Earbuds',
    'Neckbands',
    'Gaming Earphones',
  ],
  'Power Banks': [
    '10000 mAh',
    '20000 mAh',
    'Fast Charge Power Banks',
    'Compact Power Banks',
  ],
  'Smart Gadgets': [
    'Smart Watches',
    'Smart Bulbs',
    'Tracking Devices',
    'Portable Speakers',
  ],
  'Home Cleaning': [
    'Deep Cleaning',
    'Kitchen Cleaning',
    'Bathroom Cleaning',
    'Sofa Cleaning',
  ],
  'Electrician': [
    'Wiring Repair',
    'Switch Board Fix',
    'Appliance Installation',
    'Lighting Setup',
  ],
  'Plumber': [
    'Leak Repair',
    'Tap Installation',
    'Drain Cleaning',
    'Pipe Fitting',
  ],
  'AC Service': [
    'AC Installation',
    'AC Gas Refill',
    'AC Repair',
    'AC Maintenance',
  ],
  'Salon at Home': [
    'Hair Styling',
    'Facial',
    'Manicure & Pedicure',
    'Bridal Services',
  ],
  'Document Delivery': [
    'Office Documents',
    'Legal Documents',
    'Educational Documents',
    'Urgent File Delivery',
  ],
  'Fragile Items': [
    'Glass Items',
    'Electronic Items',
    'Decor Items',
    'Secure Packed Items',
  ],
  'Gift Delivery': [
    'Birthday Gift Delivery',
    'Anniversary Gift Delivery',
    'Festival Gift Delivery',
    'Surprise Gift Delivery',
  ],
};

String canonicalCategory(String raw) {
  final normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'grocery':
    case 'groceries':
      return 'Grocery';
    case 'vegetable':
    case 'vegetables':
      return 'Vegetables';
    case 'fruit':
    case 'fruits':
      return 'Fruits';
    case 'food':
    case 'foods':
      return 'Food';
    case 'gift':
    case 'gifts':
      return 'Gifts';
    case 'beauty & personal care':
    case 'beauty':
    case 'personal care':
    case 'cosmetic':
    case 'cosmetics':
      return 'Cosmetics';
    case 'electronic':
    case 'electronics':
    case 'electric':
    case 'electrics':
      return 'Electronics';
    case 'household essentials':
    case 'household':
    case 'essentials':
      return 'Household Essentials';
    case 'pet':
    case 'pets':
    case 'pet store':
      return 'Pet Store';
    case 'party':
    case 'party store':
      return 'Party Store';
    case 'print':
    case 'print store':
    case 'printing':
      return 'Print Store';
    default:
      return raw.trim().isEmpty ? 'General' : raw.trim();
  }
}

List<String> buildSubcategoryOptions(String category) {
  final canonical = canonicalCategory(category);
  return categorySubcategoryMap[canonical]?.toList() ?? const [];
}

List<String> buildChildCategoryOptions(String? subcategory) {
  if (subcategory == null || subcategory.trim().isEmpty) {
    return const [];
  }

  return subcategoryChildCategoryMap[subcategory.trim()]?.toList() ?? const [];
}
