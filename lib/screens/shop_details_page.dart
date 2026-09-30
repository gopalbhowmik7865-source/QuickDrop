import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../category_routing.dart';
import '../category_theme.dart';
import '../main.dart';
import '../models/shop.dart';
import '../services/shop_service.dart';

class ShopDetailsPage extends StatefulWidget {
  const ShopDetailsPage({
    super.key,
    required this.shop,
    required this.cartNotifier,
  });

  final Shop shop;
  final ValueNotifier<List<CartItem>> cartNotifier;

  @override
  State<ShopDetailsPage> createState() => _ShopDetailsPageState();
}

class _ShopDetailsPageState extends State<ShopDetailsPage> {
  final ShopService _shopService = ShopService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  GroceryItem _productFromData(
    Map<String, dynamic> data,
    ShopInventoryItem inventory,
  ) {
    final category = data['category']?.toString() ?? 'General';
    final price = data['price'];
    final priceText = price is num
        ? '₹${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(2)}'
        : '₹${price ?? 0}';
    final oldPrice = data['oldPrice'];
    final oldPriceValue = oldPrice is num
        ? oldPrice.toDouble()
        : double.tryParse('$oldPrice');

    return GroceryItem(
      productId: inventory.productId,
      name: data['name']?.toString() ?? 'Product',
      price: priceText,
      unit: '1 item',
      emoji: '🛍️',
      tag: category,
      accent: categoryThemeFor(canonicalCategory(category)).primary,
      stock: inventory.stock,
      imageUrl: extractProductImageUrl(data),
      brand: data['brand']?.toString() ?? '',
      weight: data['weight']?.toString() ?? '',
      measureUnit: data['unit']?.toString() ?? '',
      oldPrice: oldPriceValue,
      discountPercent: (data['discount'] as num?)?.round() ?? 0,
      shortDescription: data['shortDescription']?.toString() ?? '',
      shopId: widget.shop.id,
      shopNameSnapshot: widget.shop.name,
      shopAddressSnapshot: widget.shop.displayAddress,
    );
  }

  bool _hasShopConflict(GroceryItem item) {
    final shopIds = widget.cartNotifier.value
        .map((entry) => entry.product.shopId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final hasGlobalItem = widget.cartNotifier.value.any(
      (entry) => entry.product.shopId == null,
    );
    return shopIds.any((id) => id != widget.shop.id) || hasGlobalItem;
  }

  void _addToCart(GroceryItem item) {
    if (_hasShopConflict(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your cart contains products from another shop. Complete or clear that cart first.',
          ),
        ),
      );
      return;
    }

    final updated = List<CartItem>.from(widget.cartNotifier.value);
    final index = updated.indexWhere(
      (entry) => entry.product.productId == item.productId,
    );
    if (index >= 0) {
      final nextQuantity = updated[index].quantity + 1;
      if (nextQuantity > item.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No more stock available at this shop.'),
          ),
        );
        return;
      }
      updated[index].quantity = nextQuantity;
    } else {
      updated.add(CartItem(product: item, quantity: 1));
    }
    widget.cartNotifier.value = updated;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.name} added to cart')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shop.name),
        backgroundColor: const Color(0xFFFAF7F2),
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.shop.displayAddress),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search shop products',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ShopInventoryItem>>(
              stream: _shopService.watchShopInventory(widget.shop.id),
              builder: (context, inventorySnapshot) {
                if (inventorySnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (inventorySnapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load shop products.'),
                  );
                }
                final inventory = inventorySnapshot.data ?? const [];
                return FutureBuilder<List<GroceryItem>>(
                  future: Future.wait(
                    inventory.map((item) async {
                      final data = await _shopService.getProduct(
                        item.productId,
                      );
                      return _productFromData(data ?? const {}, item);
                    }),
                  ),
                  builder: (context, productsSnapshot) {
                    if (productsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final products =
                        (productsSnapshot.data ?? const <GroceryItem>[])
                            .where(
                              (product) => product.name.toLowerCase().contains(
                                _searchQuery,
                              ),
                            )
                            .toList();
                    if (products.isEmpty) {
                      return const Center(
                        child: Text('No products available at this shop.'),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.68,
                          ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return _ShopProductCard(
                          product: product,
                          onAdd: () => _addToCart(product),
                          onOpen: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailsPage(
                                product: product,
                                sourceCollection: 'products',
                                cartNotifier: widget.cartNotifier,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopProductCard extends StatelessWidget {
  const _ShopProductCard({
    required this.product,
    required this.onAdd,
    required this.onOpen,
  });

  final GroceryItem product;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = categoryThemeFor(canonicalCategory(product.tag));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: product.imageUrl.isEmpty
                    ? ColoredBox(
                        color: theme.background,
                        child: Center(
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            color: theme.primary,
                            size: 34,
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: 360,
                        memCacheHeight: 280,
                        placeholder: (_, _) => Center(
                          child: CircularProgressIndicator(
                            color: theme.primary,
                          ),
                        ),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: theme.background,
                          child: Center(
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: theme.primary,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (product.weight.isNotEmpty || product.measureUnit.isNotEmpty)
                Text('${product.weight} ${product.measureUnit}'.trim()),
              Text(
                product.price,
                style: TextStyle(
                  color: theme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton(
                  onPressed: onAdd,
                  child: const Text('Add to Cart'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
