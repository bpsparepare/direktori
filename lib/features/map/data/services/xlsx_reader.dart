import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Pembaca .xlsx minimal: cukup untuk mengekstrak isi sheet pertama sebagai
/// grid teks per baris/kolom. Tidak menangani formula, style, atau merge cell
/// -- cukup untuk file export data (mis. Fasih) yang isinya teks/nomor polos.
class XlsxReader {
  static List<List<String>> readFirstSheet(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final sharedStrings = _readSharedStrings(archive);
    final sheetFile = _findFirstSheet(archive);
    if (sheetFile == null) return [];

    final doc = XmlDocument.parse(utf8.decode(sheetFile.content));
    final sheetData = _firstElement(doc.findAllElements('sheetData'));
    if (sheetData == null) return [];

    final rows = <List<String>>[];
    for (final rowEl in sheetData.findElements('row')) {
      final cells = <int, String>{};
      var maxCol = -1;

      for (final cellEl in rowEl.findElements('c')) {
        final ref = cellEl.getAttribute('r') ?? '';
        final col = _columnIndexFromRef(ref);
        if (col < 0) continue;

        final type = cellEl.getAttribute('t');
        var value = '';

        if (type == 'inlineStr') {
          final isEl = _firstElement(cellEl.findElements('is'));
          if (isEl != null) {
            value = isEl.findAllElements('t').map((t) => t.innerText).join();
          }
        } else {
          final vEl = _firstElement(cellEl.findElements('v'));
          final raw = vEl?.innerText ?? '';
          if (type == 's') {
            final idx = int.tryParse(raw);
            value = (idx != null && idx >= 0 && idx < sharedStrings.length)
                ? sharedStrings[idx]
                : '';
          } else {
            value = raw;
          }
        }

        cells[col] = value;
        if (col > maxCol) maxCol = col;
      }

      final row = List<String>.filled(maxCol + 1, '');
      cells.forEach((col, value) => row[col] = value);
      rows.add(row);
    }
    return rows;
  }

  static List<String> _readSharedStrings(Archive archive) {
    ArchiveFile? file;
    for (final f in archive.files) {
      if (f.name == 'xl/sharedStrings.xml') {
        file = f;
        break;
      }
    }
    if (file == null) return [];

    final doc = XmlDocument.parse(utf8.decode(file.content));
    return doc.findAllElements('si').map((si) {
      return si.findAllElements('t').map((t) => t.innerText).join();
    }).toList();
  }

  static ArchiveFile? _findFirstSheet(Archive archive) {
    for (final f in archive.files) {
      if (f.name == 'xl/worksheets/sheet1.xml') return f;
    }
    final candidates = archive.files
        .where(
          (f) =>
              f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return candidates.isEmpty ? null : candidates.first;
  }

  static XmlElement? _firstElement(Iterable<XmlElement> elements) {
    for (final e in elements) {
      return e;
    }
    return null;
  }

  /// Konversi referensi sel excel (mis. "AB12") jadi indeks kolom 0-based.
  static int _columnIndexFromRef(String ref) {
    var col = 0;
    for (final codeUnit in ref.codeUnits) {
      if (codeUnit >= 65 && codeUnit <= 90) {
        col = col * 26 + (codeUnit - 64);
      } else {
        break;
      }
    }
    return col - 1;
  }
}
