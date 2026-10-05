import 'package:flutter/material.dart';

class SePdrbComparisonPage extends StatefulWidget {
  const SePdrbComparisonPage({super.key});

  @override
  State<SePdrbComparisonPage> createState() => _SePdrbComparisonPageState();
}

class _SePdrbComparisonPageState extends State<SePdrbComparisonPage> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F6FB),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            children: [
              _buildHero(),
              const SizedBox(height: 16),
              _buildPlaceholderInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1D8F5A), Color(0xFF27AE60), Color(0xFF58D68D)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D8F5A).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.compare_rounded, color: Colors.white, size: 32),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perbandingan SE & PDRB',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Perbandingan data Sensus Ekonomi (SE) 2026 dengan Produk Domestik Regional Bruto (PDRB) 2025',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderInfo() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.table_chart_rounded,
                  color: Color(0xFF1D8F5A),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Siap untuk diisi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2544),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tabel data SE 2026 dan PDRB 2025 akan ditampilkan di sini',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFE5E7EB)),
          const SizedBox(height: 20),
          const Text(
            'Yang akan ditampilkan di halaman ini:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2544),
            ),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.dataset_rounded,
            title: 'Tabel SE 2026',
            subtitle: 'Data Sensus Ekonomi 2026 per wilayah dan kategori',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            icon: Icons.show_chart_rounded,
            title: 'Tabel PDRB 2025',
            subtitle: 'Data Produk Domestik Regional Bruto tahun 2025',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            icon: Icons.swap_horiz_rounded,
            title: 'Perbandingan Data',
            subtitle: 'Analisis perbandingan antara SE 2026 dan PDRB 2025',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            icon: Icons.bar_chart_rounded,
            title: 'Visualisasi Grafis',
            subtitle: 'Grafik dan diagram perbandingan antar wilayah',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Silakan siapkan tabel data SE 2026 dan PDRB 2025 terlebih dahulu. Setelah data tersedia, halaman ini akan menampilkan perbandingan kedua sumber data tersebut secara interaktif.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF1D8F5A), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2544),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
