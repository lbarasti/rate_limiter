# Rate limiting functionality.
module RateLimiter
  VERSION = "1.0.1"
  # Creates a new `Limiter`.
  # `rate`: the rate of tokens being produced in tokens/second.
  # `max_burst`: maximum number of tokens that can be stored in the bucket.
  def self.new(rate : Float64, max_burst : Int32 = 1)
    Limiter.new(rate, max_burst)
  end

  # Creates a new `Limiter`.
  # `interval`: the interval at which new tokens are generated.
  # `max_burst`: maximum number of tokens that can be stored in the bucket.
  def self.new(interval : Time::Span, max_burst : Int32 = 1)
    rate = 1 / interval.total_seconds
    Limiter.new(rate, max_burst)
  end

  # Creates a `MultiLimiter`.
  # `limiters`: a set of rate limiters.
  def self.new(*limiters : Limiter)
    MultiLimiter.new(*limiters)
  end

  # Defines the API for a rate-limiter-like instance.
  module LimiterLike
    # Returns a `Token` as soon as available. Blocking.
    abstract def get : Token

    # Returns a `Token` if one is available within `max_wait` time,
    # otherwise it returns a `Timeout`. Blocking.
    abstract def get(max_wait : Time::Span) : Token | Timeout

    # Returns `nil` if no token is available at call time. Non-blocking.
    def get? : Token | Nil
      case t = get(max_wait: 0.seconds)
      in Token
        t
      in Timeout
        nil
      end
    end

    # Raises `RateLimiter::Timeout` if no token is available after the given
    # time span. Blocking for at most a `max_wait` duration.
    def get!(max_wait : Time::Span) : Token
      case res = get(max_wait: max_wait)
      in Token
        res
      in Timeout
        raise res
      end
    end

    # Raises `RateLimiter::Timeout` if no token is available at call time. Non-blocking.
    def get! : Token
      get!(max_wait: 0.seconds)
    end
  end

  # Returned or raised whenever a `Token` is not available within a given time constraint.
  class Timeout < Exception
  end

  # Represents the availability of capacity to perform operations in the current time bucket.
  class Token
    getter created_at : Time

    def initialize(@created_at = Time.utc)
    end


    def to_s(io)
      io << "#{ {{ @type }} }("
      @created_at.to_s(io)
      io << ")"
    end
  end

  # A rate limiter erogating tokens at the specified rate.
  # 
  # This is powered by the token bucket algorithm.
  class Limiter
    include LimiterLike
    getter rate, bucket

    def initialize(@rate : Float64, max_burst : Int32 = 1)
      interval = (1 / @rate).seconds
      @bucket = Channel(Nil).new(capacity: max_burst)
      max_burst.times { @bucket.send nil }

      spawn(name: "filler") {
        loop do
          sleep interval
          select
          when @bucket.send nil
          else
            # do nothing, the bucket is full
          end
        end
      }
    end

    def get : Token
      @bucket.receive
      Token.new
    end

    def get(max_wait : Time::Span) : Token | Timeout
      select
      when @bucket.receive
        Token.new
      when timeout(max_wait)
        Timeout.new
      end
    end
  end

  # A rate limiter combining multiple `Limiter`s.
  # 
  # A MultiLimter tries to acquire tokens from limiters producing at the lowest rate first.
  # This mitigates the scenario where tokens are acquired and then wasted due to a single rate limiter timing out. 
  class MultiLimiter
    include LimiterLike

    @rate_limiters : Array(Limiter)

    def initialize(*rate_limiters : Limiter)
      @rate_limiters = rate_limiters.to_a.sort_by(&.rate)
    end

    def get : Token
      @rate_limiters.each(&.get)
      Token.new
    end

    def get(max_wait : Time::Span) : Token | Timeout
      _, remainder = @rate_limiters
        .map(&.bucket)
        .reduce({Time.utc, max_wait}) { |(started_at, time_left), bucket|
          select
          when bucket.receive
            new_started_at = Time.utc
            elapsed = new_started_at - started_at
            {new_started_at, time_left - elapsed}
          when timeout(time_left)
            break {nil, nil}
          end
        }
      remainder.nil? ? Timeout.new : Token.new
    end
  end
end
