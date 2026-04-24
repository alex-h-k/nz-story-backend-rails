class MatchingJob < ApplicationJob
  queue_as :default

  def perform
    MatchingService.run
  end
end
