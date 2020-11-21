require "./spec_helper"

describe RateLimiter do
  describe "RateLimiter.new" do
    it "initializes a Limiter with a rate" do
      RateLimiter.new(rate: 0.33)
    end

    it "initializes a Limiter with an interval" do
      RateLimiter.new(interval: 0.5.seconds)
    end

    it "initializes a Limiter with max burst parameter" do
      RateLimiter.new(interval: 0.5.minutes, max_burst: 2)
      RateLimiter.new(rate: 0.5, max_burst: 5)
    end

    it "initializes a MultiLimiter combining the given Limiters" do
      rl_1 = RateLimiter.new(interval: 0.5.seconds)
      rl_2 = RateLimiter.new(rate: 0.5)
      multi = RateLimiter.new(rl_1, rl_2)
    end
  end

  describe RateLimiter::LimiterLike do
    it "raises a Timeout exception - without blocking - if no token is available on `#get!`" do
      interval = 0.4.seconds
      api_limiter = RateLimiter.new(interval: interval)
      api_limiter.get # empty bucket

      time {
        expect_raises(RateLimiter::Timeout) {
          api_limiter.get!
        }
      }.last.should be_close(0, 1e-2) # call should be non-blocking

      sleep interval * 1.5 # allow time for bucket to be refilled
      tkn, elapsed = time { api_limiter.get! }

      elapsed.should be_close(0, 1e-2)
      tkn.should be_a RateLimiter::Token
    end

    it "raises a Timeout exception if no token is available on `#get!`, after the specified max_wait duration" do
      interval = 0.4.seconds
      interval_fraction = interval / 3
      api_limiter = RateLimiter.new(interval: interval)
      api_limiter.get # empty bucket

      time {
        expect_raises(RateLimiter::Timeout) {
          api_limiter.get!(interval_fraction)
        }
      }.last.should be_close(interval_fraction.to_f, 1e-2)

      tkn, elapsed = time { api_limiter.get!(interval * 1.2) }
      elapsed.should be_close(2 * interval_fraction.to_f, 1e-2)
      tkn.should be_a RateLimiter::Token
    end

    it "returns nil if no token is available on `#get?`, without blocking" do
      interval = 0.4.seconds
      api_limiter = RateLimiter.new(interval: interval)
      api_limiter.get # empty bucket

      res, elapsed = time { api_limiter.get? }
      elapsed.should be_close(0, 1e-2)
      res.should be nil

      sleep interval * 1.5
      tkn, elapsed = time { api_limiter.get? }
      elapsed.should be_close(0, 1e-2)
      tkn.should be_a RateLimiter::Token
    end
  end

  describe RateLimiter::Limiter do
    it "returns a token on `#get`" do
      RateLimiter.new(0.5, 2).get
        .should be_a RateLimiter::Token
    end

    it "fills the bucket with the number of tokens set by max_burst from the onset" do
      api_limiter = RateLimiter.new(0.5, 2)
      time {
        2.times { api_limiter.get }
      }.last.should be_close(0, 1e-4) # no waiting, 2 tokens are already in the bucket
    end

    it "produces tokens at the given rate" do
      api_limiter = RateLimiter.new(0.5, 2)
      2.times { api_limiter.get } # empty bucket
      time { api_limiter.get }.last.should be_close(2, 1e-2)
      time { api_limiter.get }.last.should be_close(2, 1e-2)
    end

    it "produces a timeout if a token is not made available within the given interval" do
      api_limiter = RateLimiter.new(0.5, 2)
      2.times { api_limiter.get } # empty bucket

      err, elapsed = time { api_limiter.get(1.second) }
      elapsed.should be_close(1, 1e-2)
      err.should be_a RateLimiter::Timeout
      # if we now set 2 seconds as max waiting time, we'll actually retrieve the token
      # in approx 1 second, as one second of the current time interval has already gone
      # by with the previous `#.get` call
      tkn, elapsed = time { api_limiter.get(2.seconds) }
      elapsed.should be_close(1, 1e-2)
      tkn.should be_a RateLimiter::Token
    end
  end

  describe RateLimiter::MultiLimiter do
    api_burst = 6
    db_burst = api_burst // 2
    api_interval = 1.second
    db_interval = 0.1.seconds
    
    it "combines 2 or more rate limiters" do
      api_limiter = RateLimiter.new(interval: api_interval, max_burst: api_burst)
      db_limiter = RateLimiter.new(interval: db_interval, max_burst: db_burst)
      multi = RateLimiter.new(api_limiter, db_limiter)

      time { db_burst.times { # empty db bucket
          multi.get
        }
      }.last.should be_close(0, 1e-4)

      # we receive tokens with the db rate, while the api limiter still has burst tokens left
      time_to_empty_api_bucket = db_interval.to_f * (api_burst - db_burst)
      _, elapsed = time {
        (api_burst - db_burst).times { multi.get } # empty api bucket
      }
      elapsed.should be_close(time_to_empty_api_bucket, 1e-1)

      # then switch to the api rate, while accounting for time_to_empty_api_bucket
      time_to_next_api_token = api_interval.to_f - time_to_empty_api_bucket
      time { multi.get }.last.should be_close(time_to_next_api_token, 1e-2)

      # from this point on, multi's rate is bounded by the api rate
      iterations = rand(10)
      time {
        iterations.times { multi.get }
      }.last.should be_close(iterations * api_interval.to_f, 1e-1)

      err, elapsed = time { multi.get(api_interval / 10) }
      elapsed.should be_close(api_interval.to_f / 10, 1e-2)
      err.should be_a RateLimiter::Timeout
    end
  end
end
