require "./monitoring/monitor"

module ServiceRunner
  def self.monitor(my service)
    Monitoring::Monitor.my service
  end
end
