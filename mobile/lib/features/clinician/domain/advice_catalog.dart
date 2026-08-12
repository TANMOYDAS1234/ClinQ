/// Common lifestyle-advice snippets a diabetes doctor writes repeatedly. The
/// consult shows these as tappable chips (like the lab-test catalog); tapping
/// one appends it to the general-advice text, so the doctor rarely has to type.
///
/// These are plain patient-facing sentences — kept short so several combine into
/// a natural block of advice.
class AdviceSnippet {
  const AdviceSnippet({required this.text, required this.category});

  /// The full sentence appended to the advice.
  final String text;

  /// Grouping for the sectioned picker.
  final String category;
}

const List<AdviceSnippet> kAdviceCatalog = [
  // Diet
  AdviceSnippet(text: 'Reduce refined sugar and sweets', category: 'Diet'),
  AdviceSnippet(text: 'Avoid fried and oily food', category: 'Diet'),
  AdviceSnippet(text: 'Eat more vegetables and fibre', category: 'Diet'),
  AdviceSnippet(text: 'Take smaller, frequent meals', category: 'Diet'),
  AdviceSnippet(text: 'Limit rice and refined carbohydrates', category: 'Diet'),

  // Activity
  AdviceSnippet(text: 'Walk at least 30 minutes daily', category: 'Activity'),
  AdviceSnippet(text: 'Exercise regularly', category: 'Activity'),
  AdviceSnippet(text: 'Avoid prolonged sitting', category: 'Activity'),

  // Monitoring
  AdviceSnippet(text: 'Monitor fasting blood sugar every morning', category: 'Monitoring'),
  AdviceSnippet(text: 'Maintain a blood-sugar log', category: 'Monitoring'),
  AdviceSnippet(text: 'Take medicines regularly as prescribed', category: 'Monitoring'),

  // Foot & precautions
  AdviceSnippet(text: 'Daily foot care and inspection', category: 'Precautions'),
  AdviceSnippet(text: 'Wear proper, well-fitting footwear', category: 'Precautions'),
  AdviceSnippet(text: 'Report any wound or infection immediately', category: 'Precautions'),

  // Lifestyle
  AdviceSnippet(text: 'Drink adequate water', category: 'Lifestyle'),
  AdviceSnippet(text: 'Get adequate sleep', category: 'Lifestyle'),
  AdviceSnippet(text: 'Avoid smoking and alcohol', category: 'Lifestyle'),
];

/// The snippets grouped by category, in catalog order — for a sectioned picker.
Map<String, List<AdviceSnippet>> adviceByCategory() {
  final out = <String, List<AdviceSnippet>>{};
  for (final a in kAdviceCatalog) {
    (out[a.category] ??= []).add(a);
  }
  return out;
}
