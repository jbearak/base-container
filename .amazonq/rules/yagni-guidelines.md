Implement only the exact requirements specified. Do not add:

- Configuration options not explicitly requested
- Generic frameworks or abstractions beyond current needs
- 'Future-proofing' features or extensibility hooks
- Error handling for scenarios not mentioned in requirements

Default to the simplest working solution. Before adding complexity, require explicit justification that addresses a concrete, stated need.

Avoid creating:

- Classes when functions suffice for the current use case
- Interfaces with single implementations unless polymorphism is required
- Plugin architectures for single-purpose tools
- Configuration files for hardcoded values that aren't specified as configurable
- Abstract base classes for concrete, single-use functionality

When choosing between multiple approaches:

Start with the most direct solution
- Only increase complexity if the requirements explicitly demand it
- If you're tempted to add flexibility 'just in case,' don't
- Comment your reasoning when deliberately choosing simplicity over extensibility

Focus on readability and correctness over architectural elegance. Prefer obvious code over clever abstractions.

