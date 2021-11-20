require "../spec_helper"
require "../../src/service_runner/monitoring/config"

EXAMPLE = <<-YAML
check_http:
  - path: /index.html
    expected:
      body_file: /usr/share/doc/crystal/api/index.html
    frequency: 30
YAML

describe ServiceRunner::Monitoring::Config do
  it "parses the given text" do
    conf = ServiceRunner::Monitoring::Config.from_yaml EXAMPLE
    conf.check_http.size.should eq 1
    conf.check_http[0].path.should eq "/index.html"
  end
end
