require 'json'
require 'open-uri'
require 'net/http'

class ETengine
  API_BASE = "et-engine.com"

  attr_reader :scenario_id

  # poor mans singleton
  def self.instance
    @instance ||= ETengine.new
  end

  def initialize
    @scenario    = create_scenario
    @scenario_id = @scenario["id"]
  end

  def create_scenario
    http    = Net::HTTP.new(API_BASE)
    request = Net::HTTP::Post.new("/api/v3/scenarios/")
    request.set_form_data({
      "title"      => "API",
      "area_code"  => "nl",
      "start_year" => 2011,
      "end_year"   => 2030
    })
    response = http.request(request)
    JSON.parse(response.body)
  end

  # send inputs and result key
  # Example
  #
  #     ETengine.instance.calculate({households_insulation_level_old_houses: 2.0}, 'etflex_score')
  #     # => {"present" => 123, "future" => 234, "unit" => "#"}
  #     # "future" contains the number we are interested in.
  #
  def calculate(inputs, query)
    http    = Net::HTTP.new(API_BASE)
    request = Net::HTTP::Put.new("/api/v3/scenarios/#{scenario_id}")

    params = {"gqueries[]" => query, "autobalance" => "true", "reset" => "true"}
    inputs.each do |key, value|
      params["scenario[user_values][#{key}]"] = value
    end
    CONFIG["fixed"].each do |key,value|
      params["scenario[user_values][#{key}]"] = value
    end

    request.set_form_data(params)
    response = http.request(request)

    result = JSON.parse(response.body)
    if result["errors"]
      puts "Warning: #{result["errors"]}"
    elsif !result.has_key?("gqueries")

    end
    result["gqueries"][query]
  end

  # @param options cache. caches json response. it's unlikely to change.
  def fetch_input(key, opts = {})
    url = "#{ETENGINE_API_BASE}/inputs/#{key}"
    cache_filename = "cache/#{key}.json"

    if opts.fetch(:cache) && File.exists?(cache_filename)
      data = File.read(cache_filename)
    else
      data = open(url).read
    end

    if opts.fetch(:cache) && !File.exists?(cache_filename)
      File.open(cache_filename, 'w') { |f| f << data }
    end

    JSON.parse(data)
  end
end