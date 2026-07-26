defmodule Inference.ResponseFormatTest do
  use ExUnit.Case, async: true

  alias Inference.{Error, Request, ResponseFormat}

  describe "normalize/1" do
    test "an unspecified format stays unspecified" do
      assert {:ok, nil} = ResponseFormat.normalize(nil)
    end

    test "text is an explicit member of the union" do
      assert {:ok, :text} = ResponseFormat.normalize(:text)
    end

    test "json object mode is an explicit member of the union" do
      assert {:ok, {:json, :object}} = ResponseFormat.normalize({:json, :object})
    end

    test "json schema normalizes strictness and keeps the declared schema" do
      schema = %{"type" => "object", "properties" => %{"answer" => %{"type" => "string"}}}

      assert {:ok, {:json_schema, normalized}} =
               ResponseFormat.normalize({:json_schema, %{name: "answer", schema: schema}})

      assert normalized == %{name: "answer", schema: schema, strict: true}
    end

    test "json schema keeps an explicit strict flag" do
      assert {:ok, {:json_schema, %{strict: false}}} =
               ResponseFormat.normalize(
                 {:json_schema, %{name: "answer", schema: %{"type" => "object"}, strict: false}}
               )
    end

    test "json schema accepts a keyword schema for schema-driven providers" do
      schema = [instruction: [type: :string, required: true]]

      assert {:ok, {:json_schema, %{schema: ^schema}}} =
               ResponseFormat.normalize({:json_schema, %{name: "instruction", schema: schema}})
    end

    test "the union is closed" do
      for value <- [
            :json,
            :object,
            {:json, :schema},
            {:json_schema, %{schema: %{"type" => "object"}}},
            {:json_schema, %{name: "", schema: %{"type" => "object"}}},
            {:json_schema, %{name: "answer", schema: %{}}},
            {:json_schema, %{name: "answer", schema: "not-a-schema"}},
            {:json_schema, %{name: "answer", schema: %{"type" => "object"}, strict: "yes"}},
            {:json_schema, %{name: "answer", schema: %{"type" => "object"}, extra: true}},
            [instruction: [type: :string]],
            %{type: "json_object"},
            "json"
          ] do
        assert {:error, %Error{category: :invalid, reason: :response_format}} =
                 ResponseFormat.normalize(value),
               "expected #{inspect(value)} to be rejected"
      end
    end
  end

  describe "requests" do
    test "a request normalizes its response format" do
      assert {:ok, %Request{response_format: {:json_schema, %{strict: true}}}} =
               Request.from_prompt("hello",
                 response_format: {:json_schema, %{name: "answer", schema: %{"type" => "object"}}}
               )
    end

    test "a request rejects a format outside the union before provider dispatch" do
      assert {:error, %Error{category: :invalid, reason: :response_format}} =
               Request.from_prompt("hello", response_format: :json)
    end
  end
end
