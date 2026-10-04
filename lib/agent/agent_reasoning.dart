/// How much the model should think before it answers.
///
/// The choice is sent as the OpenAI-compatible `reasoning_effort` field, which
/// OpenAI, DeepSeek and OpenRouter all read under that name. It is not a
/// capability every model advertises — a model handed an effort it does not
/// know refuses the turn in its own words — so [modelDefault], the untouched
/// state, leaves the request without one.
///
/// The composer's pill offers the three levels a reader can hold in mind;
/// tapping the lit one again returns to [modelDefault], so the untouched state
/// is never lost once the pill has been touched.
enum AgentReasoning {
  modelDefault('agentReasoningModelDefault', null),
  low('agentReasoningLow', 'low'),
  medium('agentReasoningMedium', 'medium'),
  high('agentReasoningHigh', 'high');

  const AgentReasoning(this.labelKey, this.effort);

  /// Key of the name this level is shown under.
  final String labelKey;

  /// The `reasoning_effort` a turn is sent with, or null to send none.
  final String? effort;

  /// Reads a stored level back, treating anything unrecognized — including a
  /// level a newer build knows and this one does not — as the model default.
  static AgentReasoning fromName(String? name) =>
      values.asNameMap()[name] ?? modelDefault;
}
