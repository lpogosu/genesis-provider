# frozen_string_literal: true

require 'stringio'

# Запускает CLI внутри процесса и забирает его код выхода, stdout и stderr:
# так пример проверяет сообщения, не поднимая отдельный процесс Ruby.
module CliRunner
  Result = Struct.new(:status, :stdout, :stderr)

  def run_cli(*args)
    out = StringIO.new
    err = StringIO.new
    status = with_streams(out, err) { SpecGen::CLI.start(args) }
    Result.new(status, out.string, err.string)
  end

  private

  def with_streams(out, err)
    saved = [$stdout, $stderr]
    $stdout = out
    $stderr = err
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stdout, $stderr = saved
  end
end
