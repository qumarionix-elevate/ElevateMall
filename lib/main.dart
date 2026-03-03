import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'save_report.dart';

void main() {
  runApp(const RetailIntelligenceApp());
}

// --- API config ---
const _baseUrl = 'https://api.giva.co';

// --- Brand (mall brand with logo/color; 100+ stores across brands) ---
class MallBrand {
  final String id;
  final String name;
  final Color accentColor;
  /// Optional: set when you have logo assets (e.g. assets/brands/allen_solly.png) or CDN URL
  final String? logoUrl;

  const MallBrand({
    required this.id,
    required this.name,
    required this.accentColor,
    this.logoUrl,
  });
}

// --- Store (belongs to a brand) ---
class Store {
  final String id;
  final String name;
  final String brandId;
  final String? location;

  const Store({
    required this.id,
    required this.name,
    required this.brandId,
    this.location,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Store && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// Mall brands – replace with API when available
final List<MallBrand> kBrands = [
  const MallBrand(id: 'giva', name: 'Giva', accentColor: Color(0xFFD4A853)),
  const MallBrand(id: 'allen_solly', name: 'Allen Solly', accentColor: Color(0xFF2D5A3D)),
  const MallBrand(id: 'lp', name: 'LP', accentColor: Color(0xFF1E3A5F)),
  const MallBrand(id: 'starbucks', name: 'Starbucks', accentColor: Color(0xFF00704A)),
  const MallBrand(id: 'van_heusen', name: 'Van Heusen', accentColor: Color(0xFF1A1A1A)),
  const MallBrand(id: 'decathlon', name: 'Decathlon', accentColor: Color(0xFF0066B3)),
];

// Stores per brand – in production load from API (100+ stores)
final List<Store> kStores = [
  const Store(id: '75949441186', name: 'Giva Main', brandId: 'giva', location: 'Ground Floor'),
  const Store(id: '75949441187', name: 'Giva West', brandId: 'giva', location: 'West Wing'),
  const Store(id: 'as_01', name: 'Allen Solly Store 1', brandId: 'allen_solly', location: 'Level 1'),
  const Store(id: 'as_02', name: 'Allen Solly Store 2', brandId: 'allen_solly', location: 'Level 2'),
  const Store(id: 'lp_01', name: 'LP Store', brandId: 'lp', location: 'Level 1'),
  const Store(id: 'sb_01', name: 'Starbucks Café', brandId: 'starbucks', location: 'Food Court'),
  const Store(id: 'sb_02', name: 'Starbucks Kiosk', brandId: 'starbucks', location: 'Atrium'),
  const Store(id: 'vh_01', name: 'Van Heusen', brandId: 'van_heusen', location: 'Level 1'),
  const Store(id: 'dec_01', name: 'Decathlon', brandId: 'decathlon', location: 'Annex'),
];

List<Store> storesForBrand(String brandId) =>
    kStores.where((s) => s.brandId == brandId).toList();

MallBrand? brandById(String brandId) {
  for (final b in kBrands) if (b.id == brandId) return b;
  return null;
}

// --- API models (posTransactionsWithGoldBreakdown response) ---

class ItemDetail {
  final String? sku;
  final String? skuTitle;
  final String? skuMetal;
  final String? skuCategory;

  ItemDetail({
    this.sku,
    this.skuTitle,
    this.skuMetal,
    this.skuCategory,
  });

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    return ItemDetail(
      sku: json['sku'] as String?,
      skuTitle: json['sku_title'] as String?,
      skuMetal: json['sku_metal'] as String?,
      skuCategory: json['sku_category'] as String?,
    );
  }
}

class PosTransaction {
  final int? storeId;
  final dynamic tillId;
  final String? name;
  final int? invoiceNo;
  final String? invoiceDate;
  final String? transactionType;
  final String? type;
  final int? quantity;
  final num? grossAmount;
  final num? totalTaxAmount;
  final num? netAmount;
  final num? discount;
  final bool? multiple;
  final List<ItemDetail> itemDetails;

  PosTransaction({
    this.storeId,
    this.tillId,
    this.name,
    this.invoiceNo,
    this.invoiceDate,
    this.transactionType,
    this.type,
    this.quantity,
    this.grossAmount,
    this.totalTaxAmount,
    this.netAmount,
    this.discount,
    this.multiple,
    this.itemDetails = const [],
  });

  factory PosTransaction.fromJson(Map<String, dynamic> json) {
    final itemDetailsJson = json['item_details'] as List<dynamic>? ?? [];
    return PosTransaction(
      storeId: json['store_id'] as int?,
      tillId: json['till_id'],
      name: json['name'] as String?,
      invoiceNo: json['invoice_no'] as int?,
      invoiceDate: json['invoice_date'] as String?,
      transactionType: json['transaction_type'] as String?,
      type: json['type'] as String?,
      quantity: json['quantity'] as int?,
      grossAmount: (json['gross_amount'] as num?)?.toDouble(),
      totalTaxAmount: (json['total_tax_amount'] as num?)?.toDouble(),
      netAmount: (json['net_amount'] as num?)?.toDouble(),
      discount: (json['discount'] as num?)?.toDouble(),
      multiple: json['multiple'] as bool?,
      itemDetails: itemDetailsJson
          .map((e) => ItemDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// --- API service ---

Future<List<PosTransaction>> fetchPosTransactions({
  required String storeId,
  required int fromMs,
  required int toMs,
}) async {
  final uri = Uri.parse(
    '$_baseUrl/pos/posTransactionsWithGoldBreakdown?from=$fromMs&to=$toMs',
  );
  final response = await http.get(
    uri,
    headers: {'storeid': storeId},
  );
  if (response.statusCode != 200) {
    throw Exception('API error: ${response.statusCode} ${response.body}');
  }
  final list = jsonDecode(response.body) as List<dynamic>;
  return list
      .map((e) => PosTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
}

// --- Design tokens (rich, modern jewellery-inspired palette) ---
abstract class AppColors {
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceElevated = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const borderLight = Color(0xFF484F58);
  static const gold = Color(0xFFD4A853);
  static const goldMuted = Color(0xFFB8860B);
  static const emerald = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const textPrimary = Color(0xFFF0F6FC);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF6E7681);
}

class RetailIntelligenceApp extends StatelessWidget {
  const RetailIntelligenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elevate Mall · Intelligence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.gold,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          outline: AppColors.border,
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.dark().textTheme,
        ).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 24),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceElevated,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const IntelligenceDashboard(),
    );
  }
}

// --- Display models for dashboard (derived from API) ---

class AggregatedInsight {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const AggregatedInsight({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });
}

// --- Pulse effect loader (center position) ---
class _PulseLoader extends StatefulWidget {
  final String label;
  final String subtitle;

  const _PulseLoader({required this.label, required this.subtitle});

  @override
  State<_PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<_PulseLoader> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1.0 - _pulseAnimation.value) * 0.5,
                  child: Container(
                    width: 80 + (_pulseAnimation.value * 40),
                    height: 80 + (_pulseAnimation.value * 40),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: (1.0 - _pulseAnimation.value * 0.6) * 0.7,
                  child: Container(
                    width: 56 + (_pulseAnimation.value * 24),
                    height: 56 + (_pulseAnimation.value * 24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.8),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withOpacity(0.2),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.gold,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          widget.label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// --- Period filter (All / Day / Week / Month) ---
enum PeriodFilter { all, day, week, month }

extension PeriodFilterExt on PeriodFilter {
  String get label {
    switch (this) {
      case PeriodFilter.all: return 'All';
      case PeriodFilter.day: return 'Day';
      case PeriodFilter.week: return 'Week';
      case PeriodFilter.month: return 'Month';
    }
  }

  String get subtitle {
    switch (this) {
      case PeriodFilter.all: return 'All transactions';
      case PeriodFilter.day: return 'Today';
      case PeriodFilter.week: return 'Last 7 days';
      case PeriodFilter.month: return 'This month';
    }
  }
}

// --- Dashboard ---

class IntelligenceDashboard extends StatefulWidget {
  const IntelligenceDashboard({super.key});

  @override
  State<IntelligenceDashboard> createState() => _IntelligenceDashboardState();
}

class _IntelligenceDashboardState extends State<IntelligenceDashboard> {
  final ScrollController _scrollController = ScrollController();
  MallBrand? _selectedBrand = kBrands.first;
  Store? _selectedStore = kStores.first;
  PeriodFilter _periodFilter = PeriodFilter.week;
  List<PosTransaction> _transactions = [];
  bool _loading = true;
  String? _error;

  int get _fromMs {
    final now = DateTime.now();
    switch (_periodFilter) {
      case PeriodFilter.all:
        return DateTime(now.year - 2, 1, 1).millisecondsSinceEpoch;
      case PeriodFilter.day:
        final start = DateTime(now.year, now.month, now.day);
        return start.millisecondsSinceEpoch;
      case PeriodFilter.week:
        final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        return start.millisecondsSinceEpoch;
      case PeriodFilter.month:
        final start = DateTime(now.year, now.month, 1);
        return start.millisecondsSinceEpoch;
    }
  }

  int get _toMs {
    final now = DateTime.now();
    switch (_periodFilter) {
      case PeriodFilter.all:
        final endOfToday = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return endOfToday.millisecondsSinceEpoch;
      case PeriodFilter.day:
        final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return end.millisecondsSinceEpoch;
      case PeriodFilter.week:
      case PeriodFilter.month:
        final endOfToday = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        if (_periodFilter == PeriodFilter.week) return endOfToday.millisecondsSinceEpoch;
        final lastDay = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return lastDay.millisecondsSinceEpoch;
    }
  }

  List<Store> get _storesForSelectedBrand =>
      _selectedBrand != null ? storesForBrand(_selectedBrand!.id) : <Store>[];

  /// 0 = All transactions, 1 = Refunds only
  int _transactionListTab = 0;

  List<PosTransaction> get _refundTransactions =>
      _transactions.where((t) => (t.transactionType ?? '').toUpperCase() == 'REFUND').toList();

  List<PosTransaction> get _displayedTransactions =>
      _transactionListTab == 1 ? _refundTransactions : _transactions;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    if (_selectedStore == null) {
      setState(() { _loading = false; _transactions = []; _error = null; });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await fetchPosTransactions(
        storeId: _selectedStore!.id,
        fromMs: _fromMs,
        toMs: _toMs,
      );
      if (mounted) {
        setState(() {
          _transactions = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _transactions = [];
          _loading = false;
        });
      }
    }
  }

  void _onBrandChanged(MallBrand brand) {
    if (brand == _selectedBrand) return;
    final stores = storesForBrand(brand.id);
    setState(() {
      _selectedBrand = brand;
      _selectedStore = stores.isNotEmpty ? stores.first : null;
    });
    _loadTransactions();
  }

  void _onStoreChanged(Store store) {
    if (store == _selectedStore) return;
    setState(() => _selectedStore = store);
    _loadTransactions();
  }

  Future<void> _downloadReportExcel() async {
    final excel = Excel.createExcel();
    final sheetName = excel.sheets.keys.isNotEmpty ? excel.sheets.keys.first : 'Sheet1';
    final sheet = excel[sheetName];
    final storeName = _selectedStore?.name ?? 'Store';
    final period = _periodFilter.subtitle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Report: $storeName · $period');
    final headers = ['Invoice', 'Date', 'Type', 'Category', 'Qty', 'Net (₹)', 'Tax (₹)', 'Items'];
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2)).value = TextCellValue(headers[c]);
    }
    for (var i = 0; i < _transactions.length; i++) {
      final t = _transactions[i];
      final row = 3 + i;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(t.invoiceNo?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(t.invoiceDate ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(t.transactionType ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(t.type ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = IntCellValue(t.quantity ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = DoubleCellValue((t.netAmount ?? 0).toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = DoubleCellValue((t.totalTaxAmount ?? 0).toDouble());
      final items = t.itemDetails.map((d) => d.skuTitle ?? d.sku ?? '').join('; ');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = TextCellValue(items);
    }
    final bytes = excel.encode();
    if (bytes == null || bytes.isEmpty) return;
    final filename = 'elevate_mall_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await saveReport(bytes, filename);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $filename'), backgroundColor: AppColors.emerald));
  }

  Future<void> _downloadReportPdf() async {
    final pdf = pw.Document();
    final storeName = _selectedStore?.name ?? 'Store';
    final period = _periodFilter.subtitle;
    pdf.addPage(
      pw.MultiPage(
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text('Elevate Mall · $storeName · $period', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        build: (ctx) => [
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: ['Invoice', 'Date', 'Type', 'Category', 'Qty', 'Net (₹)', 'Tax (₹)']
                    .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)))).toList(),
              ),
              ..._transactions.map((t) => pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.invoiceNo?.toString() ?? '', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.invoiceDate ?? '', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.transactionType ?? '', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.type ?? '', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${t.quantity ?? 0}', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text((t.netAmount ?? 0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text((t.totalTaxAmount ?? 0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8))),
                ],
              )),
            ],
          ),
        ],
      ),
    );
    final bytes = await pdf.save();
    final filename = 'elevate_mall_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await saveReport(bytes, filename);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $filename'), backgroundColor: AppColors.emerald));
  }

  List<AggregatedInsight> get _aggregatedInsights {
    if (_transactions.isEmpty) return [];
    final netTotal = _transactions.fold<double>(
      0, (sum, t) => sum + ((t.netAmount ?? 0).toDouble()),
    );
    final taxTotal = _transactions.fold<double>(
      0, (sum, t) => sum + ((t.totalTaxAmount ?? 0).toDouble()),
    );
    final saleCount = _transactions.where((t) => t.transactionType == 'SALE').length;
    final refundCount = _transactions.where((t) => t.transactionType == 'REFUND').length;
    final byType = <String, int>{};
    for (final t in _transactions) {
      final type = t.type ?? 'Other';
      byType[type] = (byType[type] ?? 0) + 1;
    }
    final topTypes = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTypesStr = topTypes.take(3).map((e) => e.key).join(', ');
    return [
      AggregatedInsight(
        title: 'Total Net Amount',
        value: '₹ ${_formatAmount(netTotal)}',
        subtitle: '${_transactions.length} line items',
        icon: Icons.account_balance_outlined,
      ),
      AggregatedInsight(
        title: 'Total Tax',
        value: '₹ ${_formatAmount(taxTotal)}',
        subtitle: 'GST in period',
        icon: Icons.receipt_long_outlined,
      ),
      AggregatedInsight(
        title: 'Transactions',
        value: '$saleCount sales, $refundCount refunds',
        subtitle: topTypesStr.isNotEmpty ? 'By type: $topTypesStr' : '',
        icon: Icons.shopping_bag_outlined,
      ),
    ];
  }

  static String _formatAmount(num n) {
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) return 12;
    if (w < 400) return 16;
    return 20;
  }

  static bool _isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 400;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF131920),
              Color(0xFF0D1117),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadTransactions,
            color: AppColors.gold,
            backgroundColor: AppColors.surfaceElevated,
            child: _loading && _transactions.isEmpty && _selectedStore != null
                ? _buildLoadingState()
                : _error != null && _transactions.isEmpty && _selectedStore != null
                    ? _buildErrorState(context)
                    : CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          _buildAppBar(context),
                          SliverToBoxAdapter(child: _buildBrandSelector(context)),
                          SliverToBoxAdapter(child: _buildStoreSelector(context)),
                          SliverToBoxAdapter(child: _buildPeriodFilter(context)),
                          if (_selectedStore != null) ...[
                            SliverToBoxAdapter(child: _buildStoreHeroCard(context)),
                            SliverToBoxAdapter(child: _buildStatsGrid(context)),
                            SliverToBoxAdapter(child: _buildLineCharts(context)),
                            SliverToBoxAdapter(child: _buildSectionHeader(context, 'Transactions · ${_selectedStore!.name} · ${_periodFilter.subtitle}')),
                            if (_transactions.isEmpty && !_loading)
                              SliverToBoxAdapter(child: _buildRichEmptyState(context))
                            else ...[
                              SliverToBoxAdapter(child: _buildTransactionListTabs(context)),
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(_horizontalPadding(context), 0, _horizontalPadding(context), 48),
                                sliver: _displayedTransactions.isEmpty
                                    ? SliverToBoxAdapter(child: _buildRefundsEmptyState(context))
                                    : SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: _buildTransactionCard(context, _displayedTransactions[index]),
                                          ),
                                          childCount: _displayedTransactions.length,
                                        ),
                                      ),
                              ),
                            ],
                          ] else
                            SliverToBoxAdapter(child: _buildSelectStorePrompt(context)),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final narrow = _isNarrow(context);
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(narrow ? 6 : 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.storefront_rounded, color: AppColors.gold, size: narrow ? 20 : 24),
          ),
          SizedBox(width: narrow ? 8 : 12),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Elevate Mall',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: narrow ? 17 : 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(width: narrow ? 4 : 6),
                Text(
                  '${kStores.length}+ stores',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: narrow ? 10 : 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Download report',
          onSelected: (value) async {
            if (value == 'xlsx') await _downloadReportExcel();
            if (value == 'pdf') await _downloadReportPdf();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'xlsx', child: Row(children: [Icon(Icons.table_chart_rounded, size: 20), SizedBox(width: 12), Text('Download as Excel (XL)')])),
            const PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_rounded, size: 20), SizedBox(width: 12), Text('Download as PDF')])),
          ],
        ),
        IconButton(
          onPressed: _loading ? null : _loadTransactions,
          icon: _loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                )
              : const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBrandSelector(BuildContext context) {
    final hp = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 16, hp, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Brand',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kBrands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final brand = kBrands[index];
                final isSelected = brand == _selectedBrand;
                return _buildBrandChip(brand, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandChip(MallBrand brand, bool isSelected) {
    final initial = brand.name.isNotEmpty ? brand.name[0].toUpperCase() : '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onBrandChanged(brand),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? brand.accentColor.withOpacity(0.2)
                : AppColors.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? brand.accentColor : AppColors.border,
              width: isSelected ? 1.5 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: brand.accentColor.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBrandLogo(brand, isSelected, initial),
              const SizedBox(width: 10),
              Text(
                brand.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandLogo(MallBrand brand, bool selected, String initial) {
    if (brand.logoUrl != null && brand.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          brand.logoUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _brandLogoPlaceholder(brand, initial),
        ),
      );
    }
    return _brandLogoPlaceholder(brand, initial);
  }

  Widget _brandLogoPlaceholder(MallBrand brand, String initial) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.accentColor.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: brand.accentColor.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        initial,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: brand.accentColor,
        ),
      ),
    );
  }

  Widget _buildStoreSelector(BuildContext context) {
    final stores = _storesForSelectedBrand;
    if (stores.isEmpty) return const SizedBox.shrink();
    final hp = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 0, hp, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Store · ${_selectedBrand?.name ?? "—"}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stores.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final store = stores[index];
                final isSelected = store == _selectedStore;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onStoreChanged(store),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (_selectedBrand?.accentColor ?? AppColors.gold).withOpacity(0.2)
                            : AppColors.surface.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? (_selectedBrand?.accentColor ?? AppColors.gold) : AppColors.border,
                          width: isSelected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.store_rounded,
                              size: 18,
                              color: isSelected ? (_selectedBrand?.accentColor ?? AppColors.gold) : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              store.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodFilter(BuildContext context) {
    final hp = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 0, hp, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Period',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: PeriodFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final period = PeriodFilter.values[index];
                return _buildPeriodChip(context, period);
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _periodFilter.subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(BuildContext context, PeriodFilter period) {
    final isSelected = period == _periodFilter;
    final narrow = _isNarrow(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (period == _periodFilter) return;
          setState(() {
            _periodFilter = period;
          });
          _loadTransactions();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: narrow ? 8 : 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.2)
                : AppColors.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.gold : AppColors.border,
              width: isSelected ? 1.5 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                period == PeriodFilter.all
                    ? Icons.all_inclusive_rounded
                    : period == PeriodFilter.day
                        ? Icons.today_rounded
                        : period == PeriodFilter.week
                            ? Icons.date_range_rounded
                            : Icons.calendar_month_rounded,
                size: narrow ? 16 : 18,
                color: isSelected ? AppColors.gold : AppColors.textSecondary,
              ),
              SizedBox(width: narrow ? 6 : 8),
              Text(
                period.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: narrow ? 13 : 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreHeroCard(BuildContext context) {
    if (_selectedStore == null) return const SizedBox.shrink();
    final store = _selectedStore!;
    final brand = brandById(store.brandId);
    final accent = brand?.accentColor ?? AppColors.gold;
    final initial = brand != null && brand.name.isNotEmpty ? brand.name[0].toUpperCase() : '?';
    final hp = _horizontalPadding(context);
    final narrow = _isNarrow(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 0, hp, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withOpacity(0.9),
                  AppColors.surfaceElevated.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border.withOpacity(0.6), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: brand != null
                          ? _brandLogoPlaceholder(brand, initial)
                          : Icon(Icons.storefront_rounded, color: AppColors.gold, size: narrow ? 24 : 28),
                    ),
                    SizedBox(width: narrow ? 12 : 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (brand != null)
                            Text(
                              brand.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          Text(
                            store.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: narrow ? 17 : 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID · ${store.id}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (store.location != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              store.location!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_transactions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    height: 1,
                    color: AppColors.border.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 280) {
                        return Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildHeroStat('Line items', '${_transactions.length}', Icons.receipt_long_rounded),
                            _buildHeroStat('Invoices', '${_transactions.map((t) => t.invoiceNo).toSet().length}', Icons.description_rounded),
                            _buildHeroStat('Categories', '${_transactions.map((t) => t.type).whereType<String>().toSet().length}', Icons.category_rounded),
                          ],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildHeroStat('Line items', '${_transactions.length}', Icons.receipt_long_rounded),
                          _buildHeroStat('Invoices', '${_transactions.map((t) => t.invoiceNo).toSet().length}', Icons.description_rounded),
                          _buildHeroStat('Categories', '${_transactions.map((t) => t.type).whereType<String>().toSet().length}', Icons.category_rounded),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.gold.withOpacity(0.9)),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildRichEmptyState(BuildContext context) {
    final store = _selectedStore!;
    final brand = brandById(store.brandId);
    final accent = brand?.accentColor ?? AppColors.gold;
    final hp = _horizontalPadding(context);
    final narrow = _isNarrow(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 28, vertical: 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withOpacity(0.85),
                  AppColors.surfaceElevated.withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border.withOpacity(0.6), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: 48,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No transactions yet',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  '${store.name} has no POS data for this period.\nTry another store or date range.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      icon: const Icon(Icons.store_rounded, size: 20),
                      label: const Text('Change store'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.background,
                        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loadTransactions,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.6)),
                        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectStorePrompt(BuildContext context) {
    final hp = _horizontalPadding(context);
    final narrow = _isNarrow(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 24, hp, 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 28, vertical: 48),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withOpacity(0.9),
                  AppColors.surfaceElevated.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border.withOpacity(0.6), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.1),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(narrow ? 20 : 28),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 56,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Select a store',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose a brand above, then pick a store to view transactions and metrics.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: narrow ? 14 : 15,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '${kBrands.length} brands · ${kStores.length} stores',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    if (_aggregatedInsights.isEmpty) {
      return const SizedBox.shrink();
    }
    final hp = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key metrics',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'For ${_selectedStore?.name ?? "—"}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 460;
          return isWide
              ? Row(
                  children: [
                    Expanded(child: _buildStatCard(_aggregatedInsights[0])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(_aggregatedInsights[1])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(_aggregatedInsights[2])),
                  ],
                )
              : Column(
                  children: [
                    _buildStatCard(_aggregatedInsights[0]),
                    const SizedBox(height: 12),
                    _buildStatCard(_aggregatedInsights[1]),
                    const SizedBox(height: 12),
                    _buildStatCard(_aggregatedInsights[2]),
                  ],
                );
        },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(AggregatedInsight insight) {
    final colors = [
      (AppColors.gold, Icons.account_balance_wallet_rounded),
      (AppColors.emerald, Icons.receipt_long_rounded),
      (AppColors.amber, Icons.shopping_bag_rounded),
    ];
    final idx = _aggregatedInsights.indexOf(insight).clamp(0, colors.length - 1);
    final accent = colors[idx].$1;
    final iconData = colors[idx].$2;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconData, color: accent, size: 22),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  insight.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            insight.value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (insight.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              insight.subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static DateTime? _parseDate(String? s) {
    if (s == null || s.length < 10) return null;
    try {
      return DateTime.tryParse(s.substring(0, 10));
    } catch (_) {
      return null;
    }
  }

  /// Bucket key for aggregation: by day, week (Monday start), or month depending on period.
  DateTime _bucketKey(DateTime d) {
    switch (_periodFilter) {
      case PeriodFilter.all:
      case PeriodFilter.month:
        return DateTime(d.year, d.month, 1);
      case PeriodFilter.week:
        final weekday = d.weekday;
        final monday = d.subtract(Duration(days: weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case PeriodFilter.day:
        return DateTime(d.year, d.month, d.day);
    }
  }

  String _bucketLabel(DateTime key, int index) {
    switch (_periodFilter) {
      case PeriodFilter.all:
      case PeriodFilter.month:
        return '${key.month}/${key.year}';
      case PeriodFilter.week:
        return 'W${key.month}.${key.day}';
      case PeriodFilter.day:
        return key.day.toString();
    }
  }

  Widget _buildLineCharts(BuildContext context) {
    if (_transactions.isEmpty) return const SizedBox.shrink();
    final hp = _horizontalPadding(context);
    final narrow = _isNarrow(context);
    final byBucket = <DateTime, ({double netAmount, double tax})>{};
    for (final t in _transactions) {
      final d = _parseDate(t.invoiceDate);
      if (d == null) continue;
      final key = _bucketKey(d);
      final cur = byBucket[key] ?? (netAmount: 0.0, tax: 0.0);
      byBucket[key] = (
        netAmount: cur.netAmount + (t.netAmount ?? 0).toDouble(),
        tax: cur.tax + (t.totalTaxAmount ?? 0).toDouble(),
      );
    }
    final sortedKeys = byBucket.keys.toList()..sort();
    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    final netSpots = <FlSpot>[];
    final taxSpots = <FlSpot>[];
    double maxY = 1;
    for (var i = 0; i < sortedKeys.length; i++) {
      final v = byBucket[sortedKeys[i]]!;
      netSpots.add(FlSpot(i.toDouble(), v.netAmount));
      taxSpots.add(FlSpot(i.toDouble(), v.tax));
      if (v.netAmount > maxY) maxY = v.netAmount;
      if (v.tax > maxY) maxY = v.tax;
    }
    maxY = maxY > 0 ? maxY * 1.15 : 1;

    final lineBarsData = [
      LineChartBarData(
        spots: netSpots,
        isCurved: true,
        color: AppColors.gold,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true, color: AppColors.gold.withOpacity(0.12)),
      ),
      LineChartBarData(
        spots: taxSpots,
        isCurved: true,
        color: AppColors.emerald,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true, color: AppColors.emerald.withOpacity(0.12)),
      ),
    ];
    final sides = sortedKeys.length;
    final interval = sides > 8 ? (sides / 6).ceil() : 1;
    final showIndices = List.generate(sides, (i) => i).where((i) => i % interval == 0 || i == sides - 1).toSet();

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total transaction amount · ${_periodFilter.subtitle}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 3, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('Net amount (₹)', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 3, decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('Tax (₹)', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: narrow ? 180 : 200,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (sortedKeys.length - 1).clamp(0, double.infinity).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      lineBarsData: lineBarsData,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border.withOpacity(0.3), strokeWidth: 0.5),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i >= 0 && i < sortedKeys.length && showIndices.contains(i)) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _bucketLabel(sortedKeys[i], i),
                                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                    duration: const Duration(milliseconds: 250),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionListTabs(BuildContext context) {
    final hp = _horizontalPadding(context);
    final narrow = _isNarrow(context);
    final refundCount = _refundTransactions.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 16),
      child: Row(
        children: [
          _buildTransactionTab(
            context: context,
            label: 'All',
            count: _transactions.length,
            isSelected: _transactionListTab == 0,
            onTap: () => setState(() => _transactionListTab = 0),
          ),
          SizedBox(width: narrow ? 8 : 12),
          _buildTransactionTab(
            context: context,
            label: 'Refunds',
            count: refundCount,
            isSelected: _transactionListTab == 1,
            onTap: () => setState(() => _transactionListTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTab({
    required BuildContext context,
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final narrow = _isNarrow(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 14 : 18,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.amber.withOpacity(0.2)
                : AppColors.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.amber : AppColors.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                label == 'Refunds' ? Icons.reply_rounded : Icons.receipt_long_rounded,
                size: narrow ? 18 : 20,
                color: isSelected ? AppColors.amber : AppColors.textSecondary,
              ),
              SizedBox(width: narrow ? 6 : 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: narrow ? 13 : 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              if (count > 0) ...[
                SizedBox(width: narrow ? 4 : 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.amber.withOpacity(0.3) : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppColors.amber : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefundsEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.reply_rounded, size: 40, color: AppColors.amber),
            ),
            const SizedBox(height: 16),
            Text(
              'No refunds in this period',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Refund transactions will appear here when available.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final hp = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 28, hp, 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(BuildContext context, PosTransaction item) {
    final isRefund = item.transactionType == 'REFUND';
    final accent = isRefund ? AppColors.amber : AppColors.emerald;
    final itemsSummary = item.itemDetails.isNotEmpty
        ? item.itemDetails.map((d) => d.skuTitle ?? d.sku ?? '-').join(', ')
        : '—';
    final summaryShort = itemsSummary.length > 60 ? '${itemsSummary.substring(0, 60)}…' : itemsSummary;
    final narrow = _isNarrow(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.name ?? '#${item.invoiceNo ?? '—'}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: narrow ? 14 : 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.transactionType ?? '—',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.invoiceDate ?? '—',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.storeId != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Store ${item.storeId}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.type ?? '—',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          summaryShort,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Qty: ${item.quantity ?? 0}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Text(
                              '₹ ${item.netAmount?.toStringAsFixed(2) ?? '—'}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isRefund ? AppColors.amber : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: _PulseLoader(
        label: 'Loading ${_selectedStore?.name ?? "store"}…',
        subtitle: 'POS transactions & gold breakdown',
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final narrow = _isNarrow(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(narrow ? 20 : 24),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: narrow ? 40 : 48, color: AppColors.amber),
            ),
            const SizedBox(height: 24),
            Text(
              'Couldn’t load store data',
              style: GoogleFonts.plusJakartaSans(
                fontSize: narrow ? 18 : 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _selectedStore?.name ?? 'Store',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadTransactions,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
