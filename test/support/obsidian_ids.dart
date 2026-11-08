/// Deterministic UUIDs keep source fixtures in the production identity format.
String obsidianId(int value) =>
    '^daymark-obsidian-00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';
