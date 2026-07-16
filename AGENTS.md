# Agent Guidance

Follow and embody the principles of the [suckless.org philosophy](https://suckless.org/philosophy/) in all work on this project. Write simple, clear, minimal, and usable code; avoid unnecessary complexity, features, abstractions, dependencies, and lines of code.

Keep Nauvis small enough to understand completely, while making its few parts flexible and useful for many real workflows.

Nauvis is dogfooded: agent requests to modify Nauvis are sent from a running Nauvis instance. When debugging or testing, do not terminate, relaunch, or close the Nauvis process or window that started the agent session, as doing so can interrupt the session and cause issues. Use a separate Nauvis process or window for tests that require lifecycle changes.
