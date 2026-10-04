// Volunteer database entries that hold a Drug Facts panel instead of an ingredient list.
import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/services.dart';

void main() {
  test('a Drug Facts panel with no inactive list is not an ingredient list', () {
    // Open Products Facts' entry for a Crest mouthwash (barcode 037000811244), as served on 2026-10-04.
    const crest = 'cetylpyridinium chloride 0.1%..ntigingivitis/antiplaque purpose uses • helps control plaque bacteria '
        'that contribute to the development of gingivitis and bleeding gums • helps prevent and reduce plaque and '
        'gingivitis warnings ask a dentist if symptoms persist or condition worsens after regular use. keep out of '
        'reach of children under 12 years of age. if more than used for rinsing is accidentally swallowed, get medical '
        'help or contact a poison control center right away. • use after your normal brushing and flossing routine';
    expect(usableIngredients(crest), isNull);
  });

  test('a Drug Facts panel with marked sections keeps only the ingredients', () {
    const facts = 'Active ingredient (in each spray) Avobenzone 3% Purpose Sunscreen Uses helps prevent sunburn '
        'Warnings For external use only. Keep out of reach of children. Directions apply liberally. '
        'Inactive ingredients: Water, Glycerin, Fragrance, Tocopherol. Questions? 1-800-555-0100';
    expect(usableIngredients(facts), 'Avobenzone 3%, Water, Glycerin, Fragrance, Tocopherol');
  });

  test('plain ingredient lists pass through unchanged', () {
    expect(usableIngredients(' Water, Glycerin, Parfum, Linalool '), 'Water, Glycerin, Parfum, Linalool');
    expect(usableIngredients(''), isNull);
  });
}
