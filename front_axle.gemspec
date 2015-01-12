$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "front_axle/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "front_axle"
  s.version     = FrontAxle::VERSION
  s.authors     = ["Simon Cozens"]
  s.email       = ["simon@simon-cozens.org"]
  s.homepage    = "https://github.com/simoncozens/front_axle"
  s.summary     = "Add a search engine to your data with ElasticSearch and tire."
  s.description = "Add a search engine to your data with ElasticSearch and tire."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.2.0"
  s.add_dependency "tire"

  s.add_development_dependency "sqlite3"
end
