$:.push File.expand_path("../lib", __FILE__)
require "knife-oktawave/version"

Gem::Specification.new do |s|
  s.name        = "knife-oktawave"
  s.version     = Knife::Oktawave::VERSION
  s.has_rdoc    = true
  s.authors     = ["Marek Siemdaj"]
  s.email       = ["marek.siemdaj@gmail.com"]
  s.homepage    = "https://github.com/oktawave-code/knife-oktawave"
  s.summary     = "Oktawave cloud support for Chef's Knife"
  s.description = "This plugin extends Knife with the ability to manage Oktawave Cloud Instances (OCI)."
  s.extra_rdoc_files = ["README.rdoc", "LICENSE"]
  s.files       = Dir["lib/**/*.rb"]
  s.add_dependency "chef", ">= 0.10.10"
  s.add_dependency "savon", "= 0.9.5"
  s.require_paths = ["lib"]
end
