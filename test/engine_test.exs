defmodule Phoenix.LiveView.EngineTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.{Engine, Rendered}

  def safe(do: {:safe, _} = safe), do: safe
  def unsafe(do: {:safe, content}), do: content

  describe "rendering" do
    test "escapes HTML" do
      template = """
      <start> <%= "<escaped>" %>
      """

      assert render(template) == "<start> &lt;escaped&gt;\n"
    end

    test "escapes HTML from nested content" do
      template = """
      <%= Phoenix.LiveView.EngineTest.unsafe do %>
        <foo>
      <% end %>
      """

      assert render(template) == "\n  &lt;foo&gt;\n\n"
    end

    test "does not escape safe expressions" do
      assert render("Safe <%= {:safe, \"<value>\"} %>") == "Safe <value>"
    end

    test "nested content is always safe" do
      template = """
      <%= Phoenix.LiveView.EngineTest.safe do %>
        <foo>
      <% end %>
      """

      assert render(template) == "\n  <foo>\n\n"

      template = """
      <%= Phoenix.LiveView.EngineTest.safe do %>
        <%= "<foo>" %>
      <% end %>
      """

      assert render(template) == "\n  &lt;foo&gt;\n\n"
    end

    test "handles assigns" do
      assert render("<%= @foo %>", %{foo: "<hello>"}) == "&lt;hello&gt;"
    end

    test "supports non-output expressions" do
      template = """
      <% foo = @foo %>
      <%= foo %>
      """

      assert render(template, %{foo: "<hello>"}) == "\n&lt;hello&gt;\n"
    end

    test "raises ArgumentError for missing assigns" do
      assert_raise ArgumentError,
                   ~r/assign @foo not available in eex template.*Available assigns: \[:bar\]/s,
                   fn -> render("<%= @foo %>", %{bar: true}) end
    end
  end

  describe "rendered structure" do
    test "contains two static parts and one dynamic" do
      %{static: static, dynamic: dynamic} = eval("foo<%= 123 %>bar")
      assert dynamic == ["123"]
      assert static == ["foo", "bar"]
    end

    test "contains one static part at the beginning and one dynamic" do
      %{static: static, dynamic: dynamic} = eval("foo<%= 123 %>")
      assert dynamic == ["123"]
      assert static == ["foo", ""]
    end

    test "contains one static part at the end and one dynamic" do
      %{static: static, dynamic: dynamic} = eval("<%= 123 %>bar")
      assert dynamic == ["123"]
      assert static == ["", "bar"]
    end

    test "contains one dynamic only" do
      %{static: static, dynamic: dynamic} = eval("<%= 123 %>")
      assert dynamic == ["123"]
      assert static == ["", ""]
    end

    test "contains two dynamics only" do
      %{static: static, dynamic: dynamic} = eval("<%= 123 %><%= 456 %>")
      assert dynamic == ["123", "456"]
      assert static == ["", "", ""]
    end

    test "contains two static parts and two dynamics" do
      %{static: static, dynamic: dynamic} = eval("foo<%= 123 %><%= 456 %>bar")
      assert dynamic == ["123", "456"]
      assert static == ["foo", "", "bar"]
    end

    test "contains three static parts and two dynamics" do
      %{static: static, dynamic: dynamic} = eval("foo<%= 123 %>bar<%= 456 %>baz")
      assert dynamic == ["123", "456"]
      assert static == ["foo", "bar", "baz"]
    end
  end

  describe "change tracking" do
    test "does not render dynamic if it is unchanged" do
      template = "<%= @foo %>"
      assert changed(template, %{foo: 123}, nil) == ["123"]
      assert changed(template, %{foo: 123}, %{}) == ["123"]
      assert changed(template, %{foo: 123}, %{foo: true}) == [nil]
    end

    test "does not render dynamic without assigns" do
      template = "<%= 1 + 2 %>"
      assert changed(template, %{}, nil) == ["3"]
      assert changed(template, %{}, %{}) == [nil]
    end

    test "renders dynamic if it has a lexical form" do
      template = "<%= import List %><%= flatten(@foo) %>"
      assert changed(template, %{foo: '123'}, nil) == ["Elixir.List", '123']
      assert changed(template, %{foo: '123'}, %{}) == ["Elixir.List", '123']
      assert changed(template, %{foo: '123'}, %{foo: true}) == ["Elixir.List", nil]
    end

    test "renders dynamic if it has variables" do
      template = "<%= foo = @foo %><%= foo %>"
      assert changed(template, %{foo: 123}, nil) == ["123", "123"]
      assert changed(template, %{foo: 123}, %{}) == ["123", "123"]
      assert changed(template, %{foo: 123}, %{foo: true}) == ["123", "123"]
    end

    test "renders dynamic if it has variables regardless of assigns" do
      template = "<% bar = @bar %><%= @foo + bar %>"
      assert changed(template, %{foo: 123, bar: 456}, nil) == ["579"]
      assert changed(template, %{foo: 123, bar: 456}, %{}) == ["579"]
      assert changed(template, %{foo: 123, bar: 456}, %{foo: true, bar: true}) == ["579"]
    end
  end

  describe "fingerprints" do
    test "are 16 bytes long and independent of dynamic" do
      rendered1 = eval("foo<%= @bar %>baz", %{bar: 123})
      rendered2 = eval("foo<%= @bar %>baz", %{bar: 456})
      assert byte_size(rendered1.fingerprint) == 16
      assert rendered1.fingerprint == rendered2.fingerprint
    end

    test "are different on templates with same static but different dynamic" do
      rendered1 = eval("foo<%= @bar %>baz", %{bar: 123})
      rendered2 = eval("foobaz", %{bar: 123})
      assert rendered1.fingerprint != rendered2.fingerprint
    end
  end

  describe "integration" do
    defmodule View do
      use Phoenix.View, root: "test/fixtures/templates", path: ""
    end

    @assigns %{pre: "pre", inner: "inner", post: "post"}

    test "renders live engine to string" do
      assert Phoenix.View.render_to_string(View, "inner_live.html", @assigns) == "live: inner"
    end

    test "renders live engine as is" do
      assert %Rendered{static: ["live: ", ""], dynamic: ["inner"]} =
               Phoenix.View.render(View, "inner_live.html", @assigns)
    end

    test "renders live engine with nested live view" do
      assert %Rendered{
               static: ["pre: ", "\n", "post: ", ""],
               dynamic: [
                 "pre",
                 %Rendered{dynamic: ["inner"], static: ["live: ", ""]},
                 "post"
               ]
             } = Phoenix.View.render(View, "live_with_live.html", @assigns)
    end

    test "renders live engine with nested dead view" do
      assert %Rendered{
               static: ["pre: ", "\n", "post: ", ""],
               dynamic: ["pre", ["dead: ", "inner"], "post"]
             } = Phoenix.View.render(View, "live_with_dead.html", @assigns)
    end

    test "renders dead engine with nested live view" do
      assert Phoenix.View.render(View, "dead_with_live.html", @assigns) ==
               {:safe, ["pre: ", "pre", "\n", ["live: ", "inner", ""], "post: ", "post"]}
    end
  end

  defp eval(string, assigns \\ %{}) do
    EEx.eval_string(string, [assigns: assigns], file: __ENV__.file, engine: Engine)
  end

  defp changed(string, assigns, changed) do
    %{dynamic: dynamic} = eval(string, Map.put(assigns, :__changed__, changed))
    dynamic
  end

  defp render(string, assigns \\ %{}) do
    string
    |> eval(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end