require "sinatra/base"
require "extlib/string"

# BigBand is a collection of Sinatra extensions and offers better sinatra integration for common
# tools like Rake, YARD and Monk.
#
# == Usage
# 
# Using all BigBand features:
#
#   require "big_band"  
#   class Example < BigBand
#     # Yay, BigBand!
#   end
#
# Or for the lazy folks (read: you would don't subclass Sinatra::Base on your own):
#
#   require "sinatra"
#   require "big_band"
#   # Yay, BigBand!
# 
# Using just your favorite BigBand features:
#
#   require "big_band"
#   class Example < Sinatra::Base
#     register BigBand::SomeFeature
#     # Yay, BigBand::SomeFeature!
#   end
#
# Or, if you like a more handy syntax:
#
#   require "big_band"
#   class Example < BigBand :SomeFeature, MyStuff::Extension, :development => :DevelopmentOnlyFeature
#     # Yay, BigBand::SomeFeature!
#     # Yay, MyStuff::Extension!
#     # Yay, BigBand::DevelopmentOnlyFeature, if this is development mode!
#   end
#
# Loading all but one feature:
#
#   require "big_band"
#   class Example < BigBand :except => :SomeFeature
#     # Yay, all but BigBand::SomeFeature!
#   end
#
# Or just your favorite feature without you subclassing Sinatra::Base manually:
#
#   require "sinatra"
#   require "big_band/some_feature"
#   Sinatra::Application.register BigBand::SomeFeature
#   # Yay, BigBand::SomeFeature!
class BigBand < Sinatra::Base

  # Classes generated by BigBand.generate_class will be extended
  # with this class.
  module Generated
    
    attr_reader :big_band_extensions, :big_band_constructor

    # Adds extensions to subclass
    def inherited(klass)
      super
      BigBand.load_extensions(klass, *big_band_extensions)
    end

    # Use Generated#name for inspection.
    def inspect
      name
    end

    # Nice output for inspect and friends:
    #   foo = Class.new BigBand(:SomeExtension)
    #   foo.name # => BigBand(:SomeExtension)
    #   Foo = foo
    #   foo.name # => Foo
    def name
      real_name = super
      real_name.empty? ? big_band_constructor : real_name
    end

  end

  extend Generated

  # Extensions to load.
  def self.big_band_extensions
    default_extensions
  end

  # Generates a class for the given extensions. Note that this class is ment to be
  # subclassed rather than used directly. Given extensione will only be available for
  # subclasses.
  #
  #   class Foo < BigBand.generate_class(:except => :SomeExtension)
  #   end
  def self.generate_class(*options)
    @generated_classes ||= {[] => BigBand}
    @generated_classes[options] ||=  Class.new(Sinatra::Base) do
      extend BigBand::Generated
      @big_band_extensions = options
      @big_band_constructor = "BigBand(#{options.map { |o| o.inspect}.join ", "})"
    end
  end

  # Adds extensions to a Sinatra application:
  #
  #   class MyApp < Sinatra::Base
  #   end
  #
  #   BigBand.load_extensions MyApp, :SomeExtension, :development => :AnotherExtension
  def self.load_extensions(klass, *extensions)
    extensions = default_extensions if extensions.empty?
    extensions.flatten.each do |extension|
      if extension.respond_to? :each_pair
        extension.each_pair do |key, value|
          values = [value].flatten
          case key
          when :production, :test, :development
            klass.configure(key) { BigBand.load_extensions(klass, *values) }
          when :except
            exts = @nonenv_extensions.reject { |e| values.include? e }
            exts << @env_extensions.inject({}) do |accepted, (env, list)|
              accepted.merge env => list.reject { |e| values.include? e }
            end
            load_extensions(klass, *exts)
          else raise ArgumentError, "unknown key #{key.inspect}"
          end
        end
      else
        klass.register module_for(extension)
      end
    end
  end
  
  # Returns the module for a given extension identifier:
  #
  #   BigBand.module_for :BasicExtension # => BigBand::BasicExtension
  #   BigBand.module_for Array           # => Array
  #   BigBand.module_for "Foo::Bar"      # => BigBand::Foo::Bar or Foo::Bar or an exception
  def self.module_for(extension)
    case extension
    when Module then extension
    when String then extension.split("::").inject(self) { |klass, name| klass.const_get name }
    when Symbol then const_get(extension)
    end
  end

  # Default extensions that will be used whenever you subclass BigBand. You can also use this to create
  # your own extension collection:
  #
  #   class MyExtensions < BigBand(:except => :ExtensionIDontLike)
  #     default_extension FunkyExtension, :development => DevExtension
  #   end
  #
  # Note: If given a string or symbol, it will also try to setup an autoloader:
  #
  #   MyExtensions.default_extensions :Foo
  #
  # Will try to autoload MyExtensions::Foo from "my_extensions/foo" if necessary.
  def self.default_extensions(*extensions)
    return @default_extensions if @default_extensions and extensions.empty?
    @nonenv_extensions ||= []
    @env_extensions ||= {:development => []}
    autoload_list = []
    extensions.each do |extension|
      if extension.respond_to? :each_pair
        extension.each_pair do |env, exts|
          (@env_extensions[env] ||= []).push(*exts)
          autoload_list.push(*exts)
        end
      else
        @nonenv_extensions.push(*extension)
        autoload_list.push(*extension)
      end
    end
    autoload_list.each do |ext|
      next if ext.is_a? Module
      autoload ext, File.join(self.name.to_const_path, ext.to_s.to_const_path)
    end
    @default_extensions = [@nonenv_extensions, @env_extensions].flatten
  end

  default_extensions :AdvancedRoutes, :BasicExtensions, :Compass, :MoreServer, :Sass,
    :development => [:Reloader, :WebInspector]

end

# Shorthand for BigBand.generate_class
def BigBand(*options)
  BigBand.generate_class(*options)
end

module Sinatra
  module Delegator
    # Hooks into Sinatra to allow easy integration with "require 'sinatra'".
    def self.included(klass)
      BigBand.inherited(Sinatra::Application)
      Sinatra::Application.extensions.each do |ext|
        delegate(*ext.delegations) if ext.respond_to? :delegations
      end
    end
  end
end

# If require "sinatra" came before require "big_band" Sinatra::Delegator.included has not been called.
Sinatra::Delegator.included(self) if is_a? Sinatra::Delegator