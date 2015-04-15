require "addressable/uri"
require "net/http"
require "json"
require "uri"

require "sixpack/version"
require "sixpack/configuration"

module Sixpack

  class << self

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def generate_client_id
      SecureRandom.uuid
    end
  end


  class Session
    attr_reader :base_url
    attr_accessor :client_id, :ip_address, :user_agent

    def initialize(client_id=nil, options={}, params={})
      # options supplied directly will override the configured options
      options = Sixpack.configuration.to_hash.merge(options)

      @base_url = options[:base_url]

      default_params = {:ip_address => nil, :user_agent => :nil}
      params = default_params.merge(params)

      @ip_address = params[:ip_address]
      @user_agent = params[:user_agent]

      if client_id.nil?
        @client_id = Sixpack::generate_client_id()
      else
        @client_id = client_id
      end
    end

    def participate(experiment_name, alternatives, force=nil)
      if !(experiment_name =~ /^[a-z0-9][a-z0-9\-_ ]*$/)
        raise ArgumentError, "Bad experiment_name, must be lowercase, start with an alphanumeric and contain alphanumerics, dashes and underscores"
      end

      if alternatives.length < 2
        raise ArgumentError, "Must specify at least 2 alternatives"
      end

      alternatives.each { |alt|
        if !(alt =~ /^[a-z0-9][a-z0-9\-_ ]*$/)
          raise ArgumentError, "Bad alternative name: #{alt}, must be lowercase, start with an alphanumeric and contain alphanumerics, dashes and underscores"
        end
      }

      params = {
        :client_id => @client_id,
        :experiment => experiment_name,
        :alternatives => alternatives
      }
      if !force.nil? && alternatives.include?(force)
        return {"status" => "ok", "alternative" => {"name" => force}, "experiment" => {"version" => 0, "name" => experiment_name}, "client_id" => @client_id}
      end

      res = self.get_response("/participate", params)
      # On server failure use control
      if res["status"] == "failed"
        res["alternative"] = {"name" => alternatives[0]}
      end
      res
    end

    def convert(experiment_name)
      params = {
        :client_id => @client_id,
        :experiment => experiment_name
      }
      self.get_response("/convert", params)
    end

    def build_params(params)
      unless @ip_address.nil?
        params[:ip_address] = @ip_address
      end
      unless @user_agent.nil?
        params[:user_agent] = @user_agent
      end
      params
    end

    def get_response(endpoint, params)
      uri = URI.parse(@base_url)
      http = Net::HTTP.new(uri.host, uri.port)

      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      http.open_timeout = 0.25
      http.read_timeout = 0.25
      query = Addressable::URI.form_encode(self.build_params(params))

      begin
        res = http.start do |http|
          http.get(uri.path + endpoint + "?" + query)
        end
      rescue
        return {"status" => "failed", "error" => "http error"}
      end
      if res.code == "500"
        {"status" => "failed", "response" => res.body}
      else
        JSON.parse(res.body)
      end
    end
  end
end
