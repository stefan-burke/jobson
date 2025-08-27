class JobStderrChannel < JobOutputChannel
  private

  def output_type
    'stderr'
  end
end