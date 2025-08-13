When a user asks references a GitHub issue or PR, use the GitHub MCP to access the issue. When the MCP tool fails or does not support the request, use the GitHub CLI tools to access the issue or PR.

When the user asks you to address an issue:

You MUST first determine whether you are in the correct repository. If not, inform the user and STOP.

If you are in the correct repository, follow these steps:

If a branch does not already exist for the issue or PR: {
  1. Check out the base branch (usually main or dev).
  2. Pull
  3. Create a new branch with the name of the issue or PR.
  4. Push
}

If a branch already exists for the issue or PR:{
  If you are not in that branch: {
    Check out that branch.
  }
  Pull.
}

Edit files locally and commit your changes.
