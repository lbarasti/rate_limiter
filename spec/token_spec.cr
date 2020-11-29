require "./spec_helper"

describe RateLimiter::Token do
  expected_pattern = /RateLimiter::Token\(20\d{2}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\)/

  it "has a human-friendly string representation" do
    t = RateLimiter::Token.new
    t.to_s.should match expected_pattern
  end

  it "exposes a `created_at` field" do
    t = RateLimiter::Token.new
    t.created_at.should be_a Time
  end
end