class JobSpec
  include ActiveModel::Model
  include ActiveModel::Serialization

  attr_accessor :id, :name, :description, :expected_inputs, :execution, :expected_outputs

  def self.all
    Dir.glob(FileStorageService.spec_path('*')).map do |spec_dir|
      spec_file = File.join(spec_dir, 'spec.yml')
      next unless File.exist?(spec_file)
      
      from_yaml(File.read(spec_file), File.basename(spec_dir))
    end.compact
  end

  def self.find(spec_id)
    spec_file = FileStorageService.spec_path(spec_id).join('spec.yml')
    return nil unless File.exist?(spec_file)
    
    from_yaml(File.read(spec_file), spec_id)
  end

  def self.from_yaml(yaml_content, spec_id)
    data = YAML.safe_load(yaml_content, permitted_classes: [Symbol])
    new(
      id: spec_id,
      name: data['name'],
      description: data['description'],
      expected_inputs: data['expectedInputs'],
      execution: data['execution'],
      expected_outputs: data['expectedOutputs']
    )
  end

  def attributes
    {
      'id' => id,
      'name' => name,
      'description' => description,
      'expectedInputs' => expected_inputs,
      'execution' => execution,
      'expectedOutputs' => expected_outputs
    }
  end
end