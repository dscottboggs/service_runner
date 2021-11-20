module ServiceRunner::Monitoring
  module Check
    private class_property checks : Hash(String, Check) = {} of String => Check

    abstract def run(config) : Nil

    macro included
      checks[{{@type.stringify.snake_case}}] = self
      extend self
    end
  end
end

require "./check/**"
