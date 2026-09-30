import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum StockFilter { all, low, out }

enum _StockStatus { inStock, low, out }

_StockStatus _statusForStock(int stock) {
  if (stock <= 0) {
    return _StockStatus.out;
  }
  if (stock <= 10) {
    return _StockStatus.low;
  }
  return _StockStatus.inStock;
}

String _statusLabel(_StockStatus status) {
  switch (status) {
    case _StockStatus.inStock:
      return 'In Stock';
    case _StockStatus.low:
      return 'Low Stock';
    case _StockStatus.out:
      return 'Out of Stock';
  }
}

Color _statusColor(_StockStatus status) {
  switch (status) {
    case _StockStatus.inStock:
      return Colors.green;
    case _StockStatus.low:
      return Colors.orange;
    case _StockStatus.out:
      return Colors.red;
  }
}

int stockValueOf(dynamic value) {
  if (value is int) {
    return value < 0 ? 0 : value;
  }
  if (value is num) {
    final rounded = value.round();
    return rounded < 0 ? 0 : rounded;
  }
  final parsed = int.tryParse(value?.toString().trim() ?? '') ?? 0;
  return parsed < 0 ? 0 : parsed;
}

class StockManagementPage extends StatefulWidget {
  const StockManagementPage({super.key});

  @override
  State<StockManagementPage> createState() => _StockManagementPageState();
}

class _StockManagementPageState extends State<StockManagementPage> {
  final CollectionReference<Map<String, dynamic>> _productsRef =
      FirebaseFirestore.instance.collection('products');
  final Set<String> _updatingIds = <String>{};
  StockFilter _filter = StockFilter.all;
  String _searchQuery = '';

  Future<int?> _askQuantity({
    required String title,
    required String label,
    int? initialValue,
  }) async {
    final controller = TextEditingController(
      text: initialValue?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: label),
              validator: (value) {
                final quantity = int.tryParse(value?.trim() ?? '');
                if (quantity == null || quantity < 0) {
                  return 'Enter a whole number of 0 or more';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(
                    dialogContext,
                    int.parse(controller.text.trim()),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<bool> _confirmLargeChange(int currentStock, int newStock) async {
    if ((newStock - currentStock).abs() < 100) {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm stock change'),
          content: Text('Change stock from $currentStock to $newStock?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _applyStock(
    DocumentReference<Map<String, dynamic>> reference,
    int currentStock,
    int newStock,
  ) async {
    final safeStock = newStock < 0 ? 0 : newStock;
    if (safeStock == currentStock) {
      return;
    }

    if (!await _confirmLargeChange(currentStock, safeStock) || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updatingIds.add(reference.id));

    try {
      await reference.update({'stock': safeStock});
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Stock updated to $safeStock.')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to update stock.')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingIds.remove(reference.id));
      }
    }
  }

  Future<void> _increaseStock(
    DocumentReference<Map<String, dynamic>> reference,
    int currentStock,
  ) async {
    final quantity = await _askQuantity(
      title: 'Increase Stock',
      label: 'Quantity to add',
    );
    if (quantity == null || quantity == 0) {
      return;
    }
    await _applyStock(reference, currentStock, currentStock + quantity);
  }

  Future<void> _decreaseStock(
    DocumentReference<Map<String, dynamic>> reference,
    int currentStock,
  ) async {
    final quantity = await _askQuantity(
      title: 'Decrease Stock',
      label: 'Quantity to remove',
    );
    if (quantity == null || quantity == 0) {
      return;
    }

    if (quantity > currentStock) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot remove $quantity, only $currentStock in stock.',
          ),
        ),
      );
      return;
    }

    await _applyStock(reference, currentStock, currentStock - quantity);
  }

  Future<void> _editStock(
    DocumentReference<Map<String, dynamic>> reference,
    int currentStock,
  ) async {
    final newStock = await _askQuantity(
      title: 'Edit Stock',
      label: 'New stock quantity',
      initialValue: currentStock,
    );
    if (newStock == null) {
      return;
    }
    await _applyStock(reference, currentStock, newStock);
  }

  bool _matchesFilter(int stock) {
    switch (_filter) {
      case StockFilter.all:
        return true;
      case StockFilter.low:
        return stock > 0 && stock <= 10;
      case StockFilter.out:
        return stock == 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Management')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load products.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = [...(snapshot.data?.docs ?? [])]
            ..sort((a, b) {
              final aName = a.data()['name']?.toString().toLowerCase() ?? '';
              final bName = b.data()['name']?.toString().toLowerCase() ?? '';
              return aName.compareTo(bName);
            });

          var inStockCount = 0;
          var lowStockCount = 0;
          var outOfStockCount = 0;
          for (final doc in products) {
            switch (_statusForStock(stockValueOf(doc.data()['stock']))) {
              case _StockStatus.inStock:
                inStockCount++;
              case _StockStatus.low:
                lowStockCount++;
              case _StockStatus.out:
                outOfStockCount++;
            }
          }

          final visibleProducts = products.where((doc) {
            final data = doc.data();
            if (!_matchesFilter(stockValueOf(data['stock']))) {
              return false;
            }
            if (_searchQuery.isEmpty) {
              return true;
            }
            final haystack = [
              data['name'],
              data['category'],
              data['subcategory'],
            ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
            return haystack.contains(_searchQuery);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search by name, category or subcategory',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in <StockFilter, String>{
                      StockFilter.all: 'All Products (${products.length})',
                      StockFilter.low: 'Low Stock ($lowStockCount)',
                      StockFilter.out: 'Out of Stock ($outOfStockCount)',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected: (_) {
                          setState(() => _filter = entry.key);
                        },
                      ),
                    Chip(
                      avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: Text('In Stock $inStockCount'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visibleProducts.isEmpty
                    ? Center(
                        child: Text(
                          'No products found.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: visibleProducts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = visibleProducts[index];
                          final data = doc.data();
                          final stock = stockValueOf(data['stock']);
                          final status = _statusForStock(stock);
                          final statusColor = _statusColor(status);
                          final imageUrl =
                              data['imageUrl']?.toString().trim() ?? '';
                          final isUpdating = _updatingIds.contains(doc.id);

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: imageUrl.isEmpty
                                        ? Container(
                                            width: 56,
                                            height: 56,
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                            child: const Icon(
                                              Icons.image_outlined,
                                            ),
                                          )
                                        : Image.network(
                                            imageUrl,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                Container(
                                                  width: 56,
                                                  height: 56,
                                                  color: colorScheme
                                                      .surfaceContainerHighest,
                                                  child: const Icon(
                                                    Icons.broken_image_outlined,
                                                  ),
                                                ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['name']?.toString() ??
                                              'Unnamed Product',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${data['category']?.toString() ?? 'General'}'
                                          '${(data['subcategory']?.toString().trim() ?? '').isEmpty ? '' : ' • ${data['subcategory']}'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              'Stock: $stock',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Chip(
                                              label: Text(_statusLabel(status)),
                                              backgroundColor: statusColor
                                                  .withValues(alpha: 0.12),
                                              side: BorderSide(
                                                color: statusColor.withValues(
                                                  alpha: 0.22,
                                                ),
                                              ),
                                              labelStyle: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isUpdating)
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  else
                                    Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: 'Increase stock',
                                          onPressed: () => _increaseStock(
                                            doc.reference,
                                            stock,
                                          ),
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Decrease stock',
                                          onPressed: stock == 0
                                              ? null
                                              : () => _decreaseStock(
                                                  doc.reference,
                                                  stock,
                                                ),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit stock',
                                          onPressed: () =>
                                              _editStock(doc.reference, stock),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
