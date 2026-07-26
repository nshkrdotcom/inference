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
- the response-format contract — for every member of the closed union the
  adapter must map it or refuse it with `:response_format_unsupported`;
- capability reporting — every reported `Inference.Capability` is well formed,
  names are unique, and `:require` names must be reported;
- unsupported stream behavior;
- metadata redaction;
- trace metadata redaction.

```elixir
AdapterCase.assert_response_format_contract(MyAdapter,
  adapter_opts: [fake_backend: MyFakeBackend]
)

AdapterCase.assert_capability_contract(MyAdapter,
  require: [:response_format_json_schema, :tools]
)
```

Default tests should use fake provider modules. Live provider tests belong in
explicitly gated examples or smoke-test suites.

Adapter-owning projects should add their own tests for option precedence and
response-field preservation when they depend on adapter-specific options. The
shared testkit is a floor, not proof that a governed adapter preserved every
downstream contract field.
