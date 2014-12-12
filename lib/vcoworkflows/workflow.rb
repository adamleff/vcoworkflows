require_relative 'constants'
require_relative 'workflowservice'
require_relative 'workflowtoken'
require_relative 'workflowparameter'
require 'json'

module VcoWorkflows

  class Workflow

    attr_reader :id
    attr_reader :name
    attr_reader :version
    attr_reader :description
    attr_reader :input_parameters
    attr_reader :output_parameters
    attr_accessor :workflow_service
    attr_reader :source_json

    # @param [String] workflow_json
    # @param [VcoWorkflows::WorkflowService] workflow_service
    # @return [VcoWorkflows::Workflow]
    def initialize(workflow_json, workflow_service)

      workflow_data = JSON.parse(workflow_json)

      @workflow_service = workflow_service

      # Set up the attributes if they exist in the data json, otherwise nil them
      @id          = workflow_data.key?('id')          ? workflow_data['id']          : nil
      @name        = workflow_data.key?('name')        ? workflow_data['name']        : nil
      @version     = workflow_data.key?('version')     ? workflow_data['version']     : nil
      @description = workflow_data.key?('description') ? workflow_data['description'] : nil

      # Process the input parameters
      if workflow_data.key?('input-parameters')
        @input_parameters = Workflow.parse_parameters(workflow_data['input-parameters'])
      else
        @input_parameters = {}
      end

      # Process the output parameters
      if workflow_data.key?('output-parameters')
        @output_parameters = Workflow.parse_parameters(workflow_data['output-parameters'])
      else
        @output_parameters = {}
      end

      # Get the presentation data and set required flags on our parameters
      @presentation = workflow_service.get_presentation(self)

    end

    # Class
    # Parse json parameters and return a nice hash
    # @param [Object] parameter_data
    # @return [Hash]
    def self.parse_parameters(parameter_data)
      wfparams = {}
      parameter_data.each do |parameter|
        wfparam = VcoWorkflows::WorkflowParameter.new(type: parameter['type'], name: parameter['name'])
        if parameter['value']
          if wfparam.type.eql?('Array')
            value = []
            parameter['value'][wfparam.type.downcase]['elements'].each do |element|
              value << element[wfparam.subtype]['value']
            end
          else
            value = parameter['value'][wfparam.type.downcase]['value']
          end
          value = nil if value.eql?('null')
          wfparam.set(value)
        end
        wfparams[parameter['name']] = wfparam
      end
      return wfparams
    end

    # Public
    # Get an array of the names of all the required input parameters
    # @return [String[]]
    def get_required_parameter_names
      required = []
      @input_parameters.each_value {|v| required << v.name if v.required}
      return required
    end

    # Public
    # Get an array of the full set of input parameters
    # @return [String[]]
    def get_parameter_names
      @input_parameters.keys
    end

    # Public
    # Get the value of a specific input parameter
    # @param [String] parameter_name - Name of the parameter whose value to get
    # @return [VcoWorkflows::WorkflowParameter]
    def get_parameter(parameter_name)
      @input_parameters[parameter_name]
    end

    # Public
    # Set a parameter to a value
    # @param [String] parameter - name of the parameter to set
    # @param [Object] value - value to set
    def set_parameter(parameter, value)
      @input_parameters[parameter].set value
    end

    # Public
    # Verify that all mandatory input parameters have values
    def verify_parameters
      self.get_required_parameter_names.each do |name|
        param = @input_parameters[name]
        if param.required && (param.value.nil? || param.value.size == 0)
          fail(IOError, ERR[:param_verify_failed] << "#{name} required but not present.")
        end
      end
    end

    # Public
    # Execute this workflow
    # @param [VcoWorkflows::WorkflowService] workflow_service
    # @return [VcoWorkflows::WorkflowToken]
    def execute(workflow_service = nil)
      # If we're not given an explicit workflow service for this execution
      # request, use the one defined when we were created.
      workflow_service = @workflow_service if workflow_service.nil?
      # If we still have a nil workflow_service, go home.
      fail(IOError, ERR[:no_workflow_service_defined]) if workflow_service.nil?
      # Let's get this thing running!
      workflow_service.execute_workflow(@id, get_input_parameter_json)
    end

    # Public
    # @return [String]
    def to_s
      string =  "Workflow:    #{@name}\n"
      string << "ID:          #{@id}\n"
      string << "Description: #{@description}\n"
      string << "Version:     #{@version}\n"
      string << "\nInput Parameters:\n"
      @input_parameters.each_value { |wf_param| string << " #{wf_param}" } if @input_parameters.size > 0
      # string << "\n"
      # string << "REQUIRED Input Parameters: \n#{self.get_required_parameter_names.join(', ')}" << "\n"
      string << "\nOutput Parameters:" << "\n"
      @output_parameters.each_value { |wf_param| string << " #{wf_param}" } if @output_parameters.size > 0
      return string
    end

    # Public
    # Convert the input parameters to a JSON document
    # @return [String]
    def get_input_parameter_json
      tmp_params = []
      @input_parameters.each {|_k,v| tmp_params << v.as_struct}
      param_struct = {:parameters => tmp_params}
      param_struct.to_json
    end

  end

  class WorkflowPresentation

    attr_reader :source_json
    attr_reader :presentation_data

    # Public
    # @param [String] presentation_json
    # @param [VcoWorkflows::Workflow] workflow
    # @return [VcoWorkflows::WorkflowPresentation]
    def initialize(presentation_json, workflow)

      @source_json = presentation_json

      presentation_data = JSON.parse(presentation_json)

      # We're parsing this because we specifically want to know if any of
      # the input parameters are marked as required. This is very specifically
      # in the array of hashes in:
      # presentation_data[:steps][0][:step][:elements][0][:fields]
      fields = presentation_data['steps'][0]['step']['elements'][0]['fields']

      fields.each do |attribute|
        if attribute.key?('constraints')
          attribute['constraints'].each do |const|
            if const.key?('@type') && const['@type'].eql?('mandatory')
              workflow.input_parameters[attribute['id']].required = true
            end
          end
        end

      end

    end

    # Public
    # @return [String]
    def to_s
      return JSON.pretty_generate(JSON.parse(@source_json))
    end

    # Public
    # @return [String]
    def to_json
      @source_json
    end

  end

end
