# Why do I need a rate limiter?
# * We're calling an API that throttles us when we
#   call too frequently
# * we are exposing an API to customers and want to
#   ensure we don't get flooded with requests
# * Run ETL jobs with specified rate - e.g. query
#   a datastore with a rate limit
# * Run a database migration in production and we don't
#   want to affect the responsiveness of the service
#
# Token bucket algorithm
module Rate
  module LimiterLike
    abstract def get : Token
    abstract def get(max_wait : Time::Span) : Token | Timeout

    def get?
      get(max_wait: 0.seconds)
    end

    def get!
      case res = get(max_wait: 0.seconds)
      when Token
        res
      when Timeout
        raise res
      end
    end
  end

  class Timeout < Exception
  end

  class Token
    getter created_at : Time

    def initialize(@created_at = Time.utc)
    end
  end

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
      @rate_limiters.map { |rl|
        Channel(Token | Timeout).new(1).tap { |ch|
          spawn { ch.send rl.get(max_wait) }
        }
      }.reduce(Token.new) { |_, ch|
        case t = ch.receive
        in Timeout
          break t
        in Token
          t
        end
      }

      # _, remainder = @rate_limiters.map(&.bucket).reduce({Time.utc, max_wait}) { |(now, time_left), bucket|
      #   select
      #   when bucket.receive
      #     new_now = Time.utc
      #     elapsed = new_now - now
      #     {new_now, time_left - elapsed}
      #   when timeout(time_left)
      #     break {nil, nil}
      #   end
      # }
      # remainder.nil? ? Timeout.new : Token.new
    end
  end
end


# API
rl_1 = Rate::Limiter.new(rate: 10/60, max_burst: 6)
rl_2 = Rate::Limiter.new(rate: 2, max_burst: 2)
ml = Rate::MultiLimiter.new(rl_1, rl_2)

sleep 2.5
puts "#{Time.utc}: calls start now"
loop do
  case ml.get(1.second)
  when Rate::Token
    puts "#{Time.utc}: calling API"
  else
    puts "#{Time.utc}: timed out"
  end
end
