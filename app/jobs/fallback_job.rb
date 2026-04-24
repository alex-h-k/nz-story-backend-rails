class FallbackJob < ApplicationJob
  queue_as :default

  def perform
    MatchingService.run_fallback
  end
end
