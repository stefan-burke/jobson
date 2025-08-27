class JobStdoutChannel < JobOutputChannel
  private

  def output_type
    'stdout'
  end
end