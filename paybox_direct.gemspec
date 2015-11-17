# Copyright © 2015, Kévin Lesénéchal <kevin.lesenechal@gmail.com>.
#
# This library is licensed under the new BSD license. Checkout the license text
# in the LICENSE file or online at <http://opensource.org/licenses/BSD-3-Clause>.

require 'rake'

Gem::Specification.new do |s|
  s.name     = "paybox_direct"
  s.version  = "0.2.2"
  s.license  = "BSD-3-Clause"
  s.summary  = "An API to Paybox Direct and Paybox Direct Plus"
  s.author   = "Kévin Lesénéchal"
  s.email    = "kevin.lesenechal@gmail.com"
  s.homepage = "https://github.com/kevin-lesenechal/paybox_direct"
  s.files    = FileList["lib/**/*", "[A-Z]*", "spec/*"].to_a
  s.add_dependency "rake", "~> 10.0"
  s.add_development_dependency "rspec", "~> 3.0"
end
