require 'rubygems'
require 'pry'
require 'yaml'
require './api_wrapper'

ETENGINE_API_BASE = "http://et-engine.com/api/v3"
CONFIG        = YAML.load(File.read(ENV.fetch("CONFIG", "etlight.yml")))
POPULATION    = CONFIG['population']
MUTATION_RATE = CONFIG['mutation_rate']
BREED_MUTATE  = CONFIG['breed_mutate']

class Optimizer
  attr_accessor :populations

  def initialize(input_keys, count = POPULATION)
    inputs = input_keys.each_with_object({}) do |key, hsh|
      hsh[key] = nil
    end
    @count = count
    @populations = [Population.seed(inputs, count)]
  end

  # @param options :iterations, default: 1
  def evolve(opts = {})
    opts.fetch(:iterations, 1).times do |_|
      puts "-- New Population"

      population = populations.last
      population.calculate_fitness

      puts "-- Fittest #{population.genes_sorted_by_fitness.first.fitness.to_i} / #{population.genes.map(&:fitness).inject(&:+) / @count}"

      # Push a new (evolved) population to the stack.
      populations << population.evolve
    end
  end
end


# A population contains a set of genes.
# Evolving a population will create a new population
# and select the fittest and cross-breeds the gene_pool.
#
class Population
  attr_reader :inputs, :genes

  @@counter = 0

  def initialize(genes, count = 10)
    @count = count
    @genes = genes

    @id = @@counter += 1
  end

  def evolve
    genes_by_fitness = @genes.select(&:valid_fitness?)
      .sort_by(&:fitness)
      .reverse
      .map(&:dup)

    # take the two fittest genes
    fittest = genes_by_fitness[0...2]

    # initialize new gene_pool with the two fittest.
    gene_pool = fittest.dup

    # takes 40% fittest genes of the full population.
    # prioritize fitter genes.
    while gene_pool.length < (@count * 0.4)
      gene_pool << genes_by_fitness.select{ rand < 0.4 }.first
    end

    # Fill up gene pool with cross-breeding.
    (@count - gene_pool.length).times do
      fit_gene    = fittest.sample
      random_gene = @genes.sample.dup

      gene_pool << fit_gene.breed(random_gene)
    end

    gene_pool.each(&:mutate!)

    Population.new(gene_pool, @count)
  end

  def calculate_fitness
    @genes.each(&:calculate_fitness)
  end

  def seed
    @genes.each(&:seed)
  end

  def dup
    Population.new(genes.map(&:dup), @count)
  end

  # fittest genes first
  def genes_sorted_by_fitness
    @genes.sort_by(&:fitness).reverse
  end

  # -- Class methods ------------------------------------

  def self.seed(inputs, count = 10)
    genes = count.times.map { Gene.new(inputs).tap(&:seed) }
    Population.new(genes, count)
  end
end


# A gene holds settings for every input and represents the state
# of a single solution (every slider position).
#
# @example
#    g = Gene.new({"input-key" => 2.3, "input-key-2" => 4.0})
#    g.calculate_fitness # => 300
#    g.breed(other_gene)
#    # => a new Gene with settings from self and other
#    g.mutate! # randomly mutate's settings
#
class Gene
  attr_reader :properties, :fitness

  # Gene.new({ input_key : 23, input_key_2 : 0.2})
  def initialize(properties)
    @properties = properties.dup
  end

  def calculate_fitness
    unless @fitness
      result   = ETengine.instance.calculate(properties, CONFIG["fitness"])
      @fitness = result["future"]
    end
    puts("Fitness #{@fitness.to_i}: #{properties.values.join(", ")} ")
    @fitness
  rescue => e
    @fitness = -1
  end

  # create a child from two genes. randomly switches single chromosomes.
  def breed(other)
    klone = dup
    klone.breed!(other)
    klone
  end

  def breed!(other)
    properties.each do |key, value|
      self[key] = other[key] if rand < BREED_MUTATE
    end
  end

  # randomly mutates genomes.
  def mutate!
    properties.each do |key, value|
      self[key] = Input[key].random_value if rand < MUTATION_RATE
    end
  end

  # Creates gene fort first population with random settings
  def seed
    properties.each do |key, value|
      self[key] = Input[key].random_value
    end
  end

  # check that etengine returned a valid fitness
  # fitness below 100 are not possible and marked invalid.
  def valid_fitness?
    fitness && fitness > 100
  end

  def [](key)
    properties[key]
  end

  def []=(key, value)
    properties[key] = value
  end

  # creates a copy
  def dup
    Gene.new(@properties.dup)
  end

  def to_s
    "Fitness: #{fitness}, #{@properties.map(&:value)}"
  end
end

# Input represents a slider in the etmodel.
#
# @example
#     Input.load(["input-key", "input-key-2"])
#     Input["input-key"].random_value
#     => 3.0 (a random value within input min, max range)
#
class Input
  attr_reader   :id, :min, :max, :step, :value, :steps

  @@inputs = {}

  def initialize(attributes)
    @id    = attributes["code"]
    @min   = attributes["min"].to_f
    @max   = attributes["max"].to_f
    @step  = attributes["step"].to_f
    @steps = ((@max - @min) / @step).to_i
    Input[@id] = self
  end

  def random_value
    @min + (@step * rand(steps)).round(1)
  end

  # -- Class methods ------------------------------------

  def self.[](key)
    @@inputs[key]
  end

  def self.[]=(key, value)
    @@inputs[key] = value
  end

  def self.fetch(key, opts = {})
    Input.new(ETengine.instance.fetch_input(key, opts))
  end

  def self.load(keys)
    keys.each { |key| Input.fetch(key, cache: true) }
  end
end


Input.load(CONFIG["inputs"])
optimizer = Optimizer.new(CONFIG["inputs"])
optimizer.evolve(iterations: 20)
