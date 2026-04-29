# Adapter Testkit

`Inference.Testkit.AdapterCase` provides small conformance helpers for adapter
tests.

The helpers are normal library functions. They do not require ExUnit at runtime
and can be called from ExUnit tests in adapter-owning projects.

Example:

```elixir
defmodule MyAdapterTest do
  use ExUnit.Case, async: true

  alias Inference.Testkit.AdapterCase

  test "adapter returns text" do
    response =
      AdapterCase.assert_text_completion(MyAdapter,
        adapter_opts: [fake_backend: MyFakeBackend]
      )

    assert response.text != ""
  end
end
```

The testkit covers:

- successful text completion;
- provider error normalization;
- unsupported stream behavior;
- metadata redaction;
- trace metadata redaction.

Default tests should use fake provider modules. Live provider tests belong in
explicitly gated examples or smoke-test suites.
