defmodule ElixirLS.LanguageServer.Dialyzer.Utils do
  @epoch_gregorian_seconds 62_167_219_200

  @spec dialyzable?(module()) :: boolean()
  def dialyzable?(module) do
    file = get_beam_file(module)
    is_list(file) and match?({:ok, _}, :dialyzer_utils.get_core_from_beam(file))
  end

  @spec get_beam_file(module()) :: charlist() | :preloaded | :non_existing | :cover_compiled
  def get_beam_file(module) do
    case :code.which(module) do
      file when is_list(file) ->
        file

      other ->
        case :code.get_object_code(module) do
          {_module, _binary, beam_filename} -> beam_filename
          :error -> other
        end
    end
  end

  def pathname_to_module(path) do
    String.to_atom(Path.basename(path, ".beam"))
  end

  def expand_references(modules, exclude \\ MapSet.new(), result \\ MapSet.new())

  def expand_references([], _, result) do
    result
  end

  def expand_references([module | rest], exclude, result) do
    result =
      if module in result or module in exclude or not dialyzable?(module) do
        result
      else
        result = MapSet.put(result, module)
        expand_references(module_references(module), exclude, result)
      end

    expand_references(rest, exclude, result)
  end

  # Mix.Utils.last_modified/1 returns a posix time, so we normalize to a :calendar.universal_time()
  def normalize_timestamp(timestamp) when is_integer(timestamp),
    do: :calendar.gregorian_seconds_to_datetime(timestamp + @epoch_gregorian_seconds)

  defp module_references(mod) do
    try do
      for form <- read_forms(mod),
          {:call, _, {:remote, _, {:atom, _, module}, _}, _} <- form,
          uniq: true,
          do: module
    rescue
      _ -> []
    catch
      _ -> []
    end
  end

  # Read the Erlang abstract forms from the specified Module
  # compiled using the -debug_info compile option
  defp read_forms(module) do
    case :beam_lib.chunks(:code.which(module), [:abstract_code]) do
      {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, forms}}]}} ->
        forms

      {:ok, {:no_debug_info, _}} ->
        throw({:forms_not_found, module})

      {:error, :beam_lib, {:file_error, _, :enoent}} ->
        throw({:module_not_found, module})
    end
  end
end
