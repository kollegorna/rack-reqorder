# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rack/reqorder/version'

Gem::Specification.new do |spec|
  spec.name          = "rack-reqorder"
  spec.version       = Rack::Reqorder::VERSION
  spec.authors       = ["Filippos Vasilakis", "Kollegorna"]
  spec.email         = ["vasilakisfil@gmail.com", "admin@kollegorna.se"]

  spec.summary       = %q{Request recorder and analyzer for rack apps}
  spec.description   = %q{Request recorder and analyzer for rack apps}
  spec.homepage      = "https://github.com/kollegorna/rack-reqorder"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mongoid"
  spec.add_dependency "activesupport"
  spec.add_dependency "rack-cors"
  spec.add_dependency "kaminari"
  spec.add_dependency "sinatra"

  spec.add_development_dependency "bundler", "~> 1.8"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "factory_girl", "~> 4.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "faker"
end
