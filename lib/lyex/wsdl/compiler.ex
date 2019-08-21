defmodule Lyex.Wsdl.Compiler do
  alias Lyex.Wsdl
  alias Lyex.Wsdl.Compiler.Structures

  def compile(assembled, context, prefix, http_options) when is_list(assembled) do
    Enum.map(assembled, &compile(&1, context, prefix, http_options))
  end

  def compile(
        %{service_name: service_name, port: port, port_type: port_type},
        context,
        prefix,
        http_options
      ) do
    name = :"#{context}.#{Macro.camelize(service_name)}"
    service_name = "#{prefix}.#{service_name}"

    functions =
      Enum.reduce(port_type.operations, [], fn operation, acc ->
        [generate_operation(operation, service_name, port.address, http_options) | acc]
      end)

    quote do
      defmodule unquote(name) do
        unquote(functions)
      end
    end
  end

  defp generate_operation(
         %Wsdl.PortType.Operation{} = operation,
         service_name,
         address,
         http_options
       ) do
    %{
      name: operation_name,
      input: input,
      output: output,
      output_type: output_type,
      request_template: request_template,
      request_headers: request_headers
    } = operation

    service_name = service_name |> Macro.camelize() |> String.to_atom()

    Structures.generate_structure(service_name, operation_name <> "Input", input)
    Structures.generate_structure(service_name, operation_name <> "Output", output)
    output_struct = service_name |> Module.concat(Macro.camelize(operation_name) <> "Output")

    function_name =
      to_string(operation_name)
      |> Macro.underscore()
      |> String.to_atom()

    input_type = generate_input_parameter(service_name, operation_name <> "Input")

    quote location: :keep, generated: true do
      def unquote(function_name)(unquote(input_type)) do
        import Lyex.Wsdl.Output, only: [read: 3]

        input = Keyword.get(binding(), :input)

        address = unquote(address)
        headers = unquote(request_headers)
        envelope = EEx.eval_string(unquote(request_template), assigns: [input: input])

        with {:ok, %{body: body}} <-
               HTTPoison.post(address, envelope, headers, unquote(http_options))
               |> IO.inspect(label: "response") do
          read(
            body,
            unquote(output_type),
            unquote(output_struct)
          )
        end
      end
    end
  end

  defp generate_input_parameter(service_name, input_name) do
    # I'm not this smart. This was generated in iex
    {:=, [],
     [
       {:%, [],
        [
          {:__aliases__, [alias: false],
           [service_name, String.to_atom(Macro.camelize(input_name))]},
          {:%{}, [], []}
        ]},
       Macro.var(:input, nil)
     ]}
  end
end
